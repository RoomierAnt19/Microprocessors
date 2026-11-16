--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- CENG 442 Lab 6                                                     CSR_regs
--
-- The machine-mode Control and Status Registers.  This is the CSR_regs.vhdl
-- handed out on D2L, finished so that it can be given to students ready to
-- use.  Changes from the D2L file:
--
--   * mie (304) and mip (344) exist.  Two interrupt sources are wired: the
--     machine timer (bit 7, MTIP/MTIE) and one external line (bit 11,
--     MEIP/MEIE).  The software interrupt (bit 3) reads zero.
--   * irq and irq_cause tell the sequencer that an interrupt should be
--     taken, and which one.  irq already includes mstatus.MIE.
--   * mtvec's base is writable.  MODE is hardwired to 1 (vectored) and
--     bits 6..2 read zero, so the base is 128-byte aligned.  That alignment
--     makes the vectored target base + 4*cause a concatenation, no adder:
--     trap_vector does exactly that.  The D2L file hardwired mtvec to
--     00000001, which put the exception slot on top of the reset vector.
--   * mepc is on its own port, for mret.  Bits 1..0 read zero (IALIGN=32).
--   * mepc and mcause have their own load enable, trap.  The D2L file
--     loaded mepc from clear_mie, which is still the case: clear_mie and
--     trap are the same pulse, and both names are kept so that the
--     sequencer reads naturally.
--   * qout is a selected assignment over the CSRs that exist, rather than a
--     4096 entry array indexed by qsel.  Unimplemented CSRs read zero.
--   * mcycle and minstret are generic_register instances.
--
-- Interrupt priority, highest first, as the privileged spec has it:
-- external (11), software (3, never pending here), timer (7).
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CSR_regs is
  port (
    clk, reset : in std_logic;
    dsel   : in std_logic_vector(11 downto 0); -- select register to write
    dlen   : in std_logic;                     -- write the register when 1
    din    : in std_logic_vector(31 downto 0); -- data to be written
    qsel   : in std_logic_vector(11 downto 0); -- select the output register
    qout   : out std_logic_vector(31 downto 0); -- data from selected register
    -- trap entry: mepc <= pc, mcause <= mcause_in
    mcause_in : in std_logic_vector(31 downto 0);
    mcause_le : in std_logic;
    clear_mie : in std_logic;  -- trap entry: mpie <= mie, mie <= 0, mepc <= pc
    restore_mie : in std_logic; -- mret: mie <= mpie, mpie <= 1
    mie : out std_logic;
    pc : in std_logic_vector(31 downto 0);
    exec : in std_logic;        -- one pulse per retired instruction
    -- interrupt sources
    mtip : in std_logic := '0';  -- machine timer, from the timer peripheral
    meip : in std_logic := '0';  -- machine external
    -- to the sequencer
    irq       : out std_logic;                    -- take an interrupt
    irq_cause : out std_logic_vector(4 downto 0); -- which one
    trap_base : out std_logic_vector(31 downto 0); -- mtvec base, for exceptions
    trap_vector : out std_logic_vector(31 downto 0); -- base + 4*irq_cause
    mepc_out  : out std_logic_vector(31 downto 0)
    );
end CSR_regs;

architecture behavioral of CSR_regs is
  function decode ( signal en: std_logic; signal sel : std_logic_vector) return std_logic_vector is
    variable value: std_logic_vector((2**sel'length-1) downto 0) := (others=>'0');
  begin
    if en = '1' then
      value(to_integer(unsigned(sel))) := '1';
    end if;
    return value;
  end function;

  signal dsel_decoded : std_logic_vector(2**12-1 downto 0);

  signal misa_q, mvendorid_q, marchid_q, mimpid_q, mhartid_q, mconfigptr_q,
    mtvec_q, mie_q, mip_q, mscratch_q, mepc_q, mcause_q
    : std_logic_vector(31 downto 0);
  signal mcause_d, mepc_d : std_logic_vector(31 downto 0);
  signal mcause_le_i, mepc_le_i : std_logic;
  signal status_register_out: std_logic_vector(63 downto 0);
  -- din in both halves, for status_register (VHDL-93 wants a signal there)
  signal din2 : std_logic_vector(63 downto 0);

  signal mcycle_q, mcycle_d, mcycle_inc : std_logic_vector(63 downto 0);
  signal minstret_q, minstret_d, minstret_inc : std_logic_vector(63 downto 0);
  signal mcycle_sel : std_logic_vector(1 downto 0);
  signal minstret_sel : std_logic_vector(2 downto 0);

  -- interrupt bits, pending and enabled
  signal mstatus_mie : std_logic;
  signal mei, mti : std_logic;
  signal irq_sel : std_logic_vector(1 downto 0);
  -- irq_cause, readable here (VHDL-93 cannot read an out port)
  signal irq_cause_i : std_logic_vector(4 downto 0);
begin

  dsel_decoded <= decode(dlen,dsel);

  -- misa  (WARL)  301
  misa: entity work.generic_CSR (behavioral)
    generic map(
      WARL_bits => (others => '1'),
      Default_bits =>  x"40000100" -- RV32I with only machine mode
      )
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#301#),
              d => din, q => misa_q);

  -- mvendorid (RO) F11
  mvendorid: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => (others => '1'), Default_bits => x"00001000")
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#F11#),
              d => din, q => mvendorid_q);

  -- marchid (RO) F12
  marchid: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => (others => '1'), Default_bits => x"00011000")
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#F12#),
              d => din, q => marchid_q);

  -- mimpid (RO) F13
  mimpid: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => (others => '1'), Default_bits => x"00111000")
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#F13#),
              d => din, q => mimpid_q);

  -- mhartid (RO) F14
  mhartid: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => (others => '1'), Default_bits => x"00000000")
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#F14#),
              d => din, q => mhartid_q);

  -- mconfigptr (RO) F15
  mconfigptr: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => (others => '1'), Default_bits => x"00000000")
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#F15#),
              d => din, q => mconfigptr_q);

  -- mstatus (300) and mstatush (310)
  mstatus: entity work.status_register(behavioral)
    port map (
      clk => clk,
      reset => reset,
      clear_mie => clear_mie,
      restore_mie => restore_mie,
      mie_out => mstatus_mie,
      wen_lower => dsel_decoded(16#300#),
      wen_upper => dsel_decoded(16#310#),
      d => din2,
      q => status_register_out);
  din2 <= din & din;
  mie <= mstatus_mie;

  -- mtvec (305).  Bits 6..0 are fixed: MODE = 01 (vectored), and the base
  -- is 128-byte aligned.  Bits 31..7 are the writable base.  Out of reset
  -- the base is zero, which is the reset vector, so the startup code must
  -- write mtvec before it enables any interrupt.
  mtvec: entity work.generic_CSR (behavioral)
    generic map(
      WARL_bits => x"0000007F",
      Default_bits =>  x"00000001"
      )
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#305#),
              d => din, q => mtvec_q);

  -- Exceptions go to the base.  Interrupt cause n goes to base + 4n, and
  -- because the base is 128-byte aligned and n < 32, that is the base's
  -- upper 25 bits with n in bits 6..2.
  trap_base   <= mtvec_q(31 downto 7) & "0000000";
  trap_vector <= mtvec_q(31 downto 7) & irq_cause_i & "00";

  -- mie (304).  Only MEIE (11) and MTIE (7) are writable.
  mie_reg: entity work.generic_CSR (behavioral)
    generic map(
      WARL_bits => x"FFFFF77F",
      Default_bits =>  x"00000000"
      )
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#304#),
              d => din, q => mie_q);

  -- mip (344).  Read only: the pending bits come straight from the
  -- sources, which are level sensitive.  Software clears MTIP by writing a
  -- later time to mtimecmp, not by writing mip.
  mip_q <= (11 => meip, 7 => mtip, others => '0');

  -- An interrupt is taken when it is pending, enabled in mie, and
  -- mstatus.MIE is set.
  mei <= meip and mie_q(11);
  mti <= mtip and mie_q(7);
  irq <= (mei or mti) and mstatus_mie;
  irq_sel <= mei & mti;
  with irq_sel select irq_cause_i <=
    "01011" when "10" | "11",   -- external wins
    "00111" when "01",
    "00000" when others;
  irq_cause <= irq_cause_i;

  -- mcycle/mcycleh (B00/B80), 64 bits, counting every clock.  A write to
  -- either half replaces that half and skips the increment that cycle.
  mcycle_reg: entity work.gen_reg (behavioral)
    generic map(N => 64)
    port map(d => mcycle_d, q => mcycle_q, clk => clk, enable => '1', reset => reset);
  mcycle_inc <= std_logic_vector(unsigned(mcycle_q) + 1);
  mcycle_sel <= dsel_decoded(16#B80#) & dsel_decoded(16#B00#);
  with mcycle_sel select mcycle_d <=
    mcycle_q(63 downto 32) & din when "01",
    din & mcycle_q(31 downto 0) when "10",
    mcycle_inc when others;

  -- minstret/minstreth (B02/B82), counting retired instructions.
  minstret_reg: entity work.gen_reg (behavioral)
    generic map(N => 64)
    port map(d => minstret_d, q => minstret_q, clk => clk, enable => '1', reset => reset);
  minstret_inc <= std_logic_vector(unsigned(minstret_q) + 1);
  minstret_sel <= dsel_decoded(16#B82#) & dsel_decoded(16#B02#) & exec;
  with minstret_sel select minstret_d <=
    minstret_q(63 downto 32) & din when "010" | "011",
    din & minstret_q(31 downto 0) when "100" | "101",
    minstret_inc when "001",
    minstret_q when others;

  -- mscratch (340)
  mscratch: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => x"00000000", Default_bits => x"00000000")
    port map (clk => clk, reset => reset, wen => dsel_decoded(16#340#),
              d => din, q => mscratch_q);

  -- mepc (341).  Loaded from pc on trap entry, or written by csrw.  Bits
  -- 1..0 are fixed at zero.
  mepc_d <= pc when clear_mie = '1' else din;
  mepc_le_i <= dsel_decoded(16#341#) or clear_mie;
  mepc: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => x"00000003", Default_bits => x"00000000")
    port map (clk => clk, reset => reset, wen => mepc_le_i,
              d => mepc_d, q => mepc_q);
  mepc_out <= mepc_q;

  -- mcause (342).  Loaded from mcause_in on trap entry, or written by csrw.
  mcause_d <= mcause_in when mcause_le = '1' else din;
  mcause_le_i <= mcause_le or dsel_decoded(16#342#);
  mcause: entity work.generic_CSR (behavioral)
    generic map(WARL_bits => x"00000000", Default_bits => x"00000000")
    port map (clk => clk, reset => reset, wen => mcause_le_i,
              d => mcause_d, q => mcause_q);

  -- mtval (343), mhpmcounter3..31, mhpmevent3..31 and mcountinhibit all
  -- read zero, which the others clause below provides.
  with qsel select qout <=
    status_register_out(31 downto 0)  when x"300",
    misa_q                            when x"301",
    mie_q                             when x"304",
    mtvec_q                           when x"305",
    status_register_out(63 downto 32) when x"310",
    mscratch_q                        when x"340",
    mepc_q                            when x"341",
    mcause_q                          when x"342",
    mip_q                             when x"344",
    mcycle_q(31 downto 0)             when x"B00",
    minstret_q(31 downto 0)           when x"B02",
    mcycle_q(63 downto 32)            when x"B80",
    minstret_q(63 downto 32)          when x"B82",
    mvendorid_q                       when x"F11",
    marchid_q                         when x"F12",
    mimpid_q                          when x"F13",
    mhartid_q                         when x"F14",
    mconfigptr_q                      when x"F15",
    (others => '0')                   when others;

end behavioral;
