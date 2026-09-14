--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- RISCV_datapath_testbench
--
-- Self-checking testbench for RISCV_datapath by itself.  The
-- instruction decoder is not needed and is not instantiated.  This
-- testbench builds each control word by hand and drives it straight
-- into the cw port, so the datapath can be tested as soon as it is
-- built, before any work is done on the decoder.
--
-- The unit under test must be an entity named RISCV_datapath with an
-- architecture named behavioral and exactly this interface:
--
--   cw      : in  control_word                     (see project_types)
--   address : in  std_logic_vector(31 downto 0)    address of the
--                                                  current instruction
--   clk     : in  std_logic
--   rst     : in  std_logic                        synchronous, active high
--   exec    : in  std_logic                        gates all state changes
--   PCie    : in  std_logic                        increment the PC by 4
--   DBGsel  : in  std_logic_vector(4 downto 0)     register to watch
--   DBGreg  : out std_logic_vector(31 downto 0)    contents of that register
--   PCout   : out std_logic_vector(31 downto 0)    contents of the PC
--   data_out: out std_logic_vector(31 downto 0)    the D bus
--
-- Everything is observed through DBGreg, PCout, and data_out, so the
-- internal names inside the datapath do not matter.
--
-- The control word is built by the small set of functions below rather
-- than field by field, so each test reads like the instruction it
-- stands for.  Three rules of the datapath are worth stating up front,
-- because the expected values only make sense once they are known:
--
--   exec gates everything.  A register write happens only when
--   cw.Dlen and exec are both high, and the PC loads only when
--   (cw.PClen or take_branch) and exec are both high.
--
--   The PC is not incremented by this testbench unless PCie is high.
--   In the real machine the fetch unit raises PCie during fetch, so by
--   the time an instruction executes the PC already points at the next
--   one.  Here PCie is low except in the test that exercises it, so
--   the value linked into rd by a jump is the un-incremented PC.
--
--   The A bus takes the address input, not the PC, when cw.PCAsel is
--   high.  That input is the address of the instruction being
--   executed, which is what AUIPC, JAL, and the branches add their
--   immediate to.  This testbench holds it at ADDR_BASE.
--
-- Every check is counted.  The run ends with one PASSED or FAILED
-- line, and a failing run ends with severity failure so that a
-- scripted simulation exits with an error.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use work.project_types.ALL;

entity RISCV_datapath_testbench is
end RISCV_datapath_testbench;

architecture Behavioral of RISCV_datapath_testbench is

  -- ALU function codes.  Bit 3 is instruction bit 30 and bits 2 downto 0
  -- are funct3, so these are the codes the decoder will eventually
  -- produce.
  constant F_ADD  : std_logic_vector(3 downto 0) := "0000";
  constant F_SUB  : std_logic_vector(3 downto 0) := "1000";
  constant F_SLL  : std_logic_vector(3 downto 0) := "0001";
  constant F_SLT  : std_logic_vector(3 downto 0) := "0010";
  constant F_SLTU : std_logic_vector(3 downto 0) := "0011";
  constant F_XOR  : std_logic_vector(3 downto 0) := "0100";
  constant F_SRL  : std_logic_vector(3 downto 0) := "0101";
  constant F_SRA  : std_logic_vector(3 downto 0) := "1101";
  constant F_OR   : std_logic_vector(3 downto 0) := "0110";
  constant F_AND  : std_logic_vector(3 downto 0) := "0111";

  -- Branch conditions.  These are funct3 from the branch instructions.
  constant C_EQ  : std_logic_vector(2 downto 0) := "000";
  constant C_NE  : std_logic_vector(2 downto 0) := "001";
  constant C_LT  : std_logic_vector(2 downto 0) := "100";
  constant C_GE  : std_logic_vector(2 downto 0) := "101";
  constant C_LTU : std_logic_vector(2 downto 0) := "110";
  constant C_GEU : std_logic_vector(2 downto 0) := "111";

  -- The address input is held here for the whole run, so every jump
  -- and branch target is ADDR_BASE plus the offset in the test.
  constant ADDR_BASE : natural := 16#1000#;

  function to5(n : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(n, 5));
  end function;

  function to32(i : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_signed(i, 32));
  end function;

  -- Idle control word: no register write, no PC load, no branch.
  constant CW_NOP : control_word := (
    Asel    => "00000",
    Bsel    => "00000",
    Dsel    => "00000",
    Dlen    => '0',
    PCAsel  => '0',
    IMMBsel => '0',
    PCDsel  => '0',
    PClen   => '0',
    isBR    => '0',
    BRcond  => "000",
    ALUFunc => F_ADD,
    IMM     => (others => '0'));

  signal cw       : control_word := CW_NOP;
  signal address  : std_logic_vector(31 downto 0)
                    := std_logic_vector(to_unsigned(ADDR_BASE, 32));
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal exec     : std_logic := '0';
  signal PCie     : std_logic := '0';
  signal DBGsel   : std_logic_vector(4 downto 0) := (others => '0');
  signal DBGreg   : std_logic_vector(31 downto 0);
  signal PCout    : std_logic_vector(31 downto 0);
  signal data_out : std_logic_vector(31 downto 0);

  -- reg(d) <= reg(a) func reg(b)
  function rr(func : std_logic_vector(3 downto 0);
              a, b, d : natural) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.ALUFunc := func;
    c.Asel    := to5(a);
    c.Bsel    := to5(b);
    c.Dsel    := to5(d);
    c.Dlen    := '1';
    return c;
  end function;

  -- reg(d) <= reg(a) func imm
  function ri(func : std_logic_vector(3 downto 0);
              a : natural; imm : integer; d : natural) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.ALUFunc := func;
    c.Asel    := to5(a);
    c.Dsel    := to5(d);
    c.Dlen    := '1';
    c.IMMBsel := '1';
    c.IMM     := to32(imm);
    return c;
  end function;

  -- reg(d) <= imm
  function li(d : natural; imm : integer) return control_word is
  begin
    return ri(F_ADD, 0, imm, d);
  end function;

  -- reg(d) <= address + imm    (the AUIPC path: A bus from the address
  -- input rather than from the register file)
  function addr_imm(imm : integer; d : natural) return control_word is
    variable c : control_word := ri(F_ADD, 0, imm, d);
  begin
    c.PCAsel := '1';
    return c;
  end function;

  -- reg(d) <= PC, with no jump
  function link(d : natural) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.Dsel   := to5(d);
    c.Dlen   := '1';
    c.PCDsel := '1';
    return c;
  end function;

  -- PC <= address + offset
  function jal(offset : integer) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.ALUFunc := F_ADD;
    c.PCAsel  := '1';
    c.IMMBsel := '1';
    c.IMM     := to32(offset);
    c.PClen   := '1';
    return c;
  end function;

  -- PC <= address + offset, reg(d) <= PC
  function jal(offset : integer; d : natural) return control_word is
    variable c : control_word := jal(offset);
  begin
    c.Dsel   := to5(d);
    c.Dlen   := '1';
    c.PCDsel := '1';
    return c;
  end function;

  -- PC <= reg(a) + offset, reg(d) <= PC
  function jalr(a : natural; offset : integer; d : natural) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.ALUFunc := F_ADD;
    c.Asel    := to5(a);
    c.IMMBsel := '1';
    c.IMM     := to32(offset);
    c.PClen   := '1';
    c.Dsel    := to5(d);
    c.Dlen    := '1';
    c.PCDsel  := '1';
    return c;
  end function;

  -- if reg(a) cond reg(b) then PC <= address + offset
  function br(cond : std_logic_vector(2 downto 0);
              a, b : natural; offset : integer) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.isBR    := '1';
    c.BRcond  := cond;
    c.Asel    := to5(a);
    c.Bsel    := to5(b);
    c.PCAsel  := '1';
    c.IMMBsel := '1';
    c.ALUFunc := F_ADD;
    c.IMM     := to32(offset);
    return c;
  end function;

  -- Same control word with the register write turned off.
  function no_write(c : control_word) return control_word is
    variable r : control_word := c;
  begin
    r.Dlen := '0';
    return r;
  end function;

  -- Same control word with the branch unit disabled.
  function no_br(c : control_word) return control_word is
    variable r : control_word := c;
  begin
    r.isBR := '0';
    return r;
  end function;

begin

UUT: entity work.RISCV_datapath (behavioral)
  port map(
    cw       => cw,
    address  => address,
    clk      => clk,
    rst      => rst,
    exec     => exec,
    PCie     => PCie,
    DBGsel   => DBGsel,
    DBGreg   => DBGreg,
    PCout    => PCout,
    data_out => data_out
    );

test: process is
  variable checks : natural := 0;
  variable errors : natural := 0;

  -- Count every check.  Report only the ones that fail.
  procedure check(cond : in boolean; msg : in string) is
  begin
    checks := checks + 1;
    if not cond then
      errors := errors + 1;
      report msg & " is not working" severity error;
    end if;
  end procedure;

  -- One clock pulse.  The control word must already be applied.
  procedure step is
  begin
    wait for 10 ns;
    clk <= '1';
    wait for 10 ns;
    clk <= '0';
  end procedure;

  procedure check_reg(r : natural; expected : std_logic_vector(31 downto 0);
                      msg : string) is
  begin
    DBGsel <= to5(r);
    wait for 1 ns;
    check(DBGreg = expected, msg);
  end procedure;

  procedure check_reg(r : natural; expected : integer; msg : string) is
  begin
    check_reg(r, to32(expected), msg);
  end procedure;

  procedure check_pc(expected : integer; msg : string) is
  begin
    check(PCout = to32(expected), msg);
  end procedure;

begin

  ------------------------------------------------------------------
  -- Reset.  The PC and every register must come up at zero.
  ------------------------------------------------------------------
  cw   <= CW_NOP;
  rst  <= '1';
  exec <= '0';
  PCie <= '0';
  step;
  step;
  check_pc(0, "reset of the PC");
  check_reg(1, 0, "reset of register 1");
  check_reg(31, 0, "reset of register 31");
  rst <= '0';

  exec <= '1';

  ------------------------------------------------------------------
  -- Immediates onto the B bus, and the ALU functions.
  ------------------------------------------------------------------
  cw <= li(1, 100);
  step;
  check_reg(1, 100, "reg(1) <= 100");

  cw <= li(2, 7);
  step;
  check_reg(2, 7, "reg(2) <= 7");

  cw <= li(3, -1);
  step;
  check_reg(3, -1, "reg(3) <= -1");

  cw <= li(4, 100);
  step;
  check_reg(4, 100, "reg(4) <= 100");

  cw <= rr(F_ADD, 1, 2, 5);
  step;
  check_reg(5, 107, "ADD reg(5) <= reg(1) + reg(2)");

  cw <= rr(F_SUB, 1, 2, 6);
  step;
  check_reg(6, 93, "SUB reg(6) <= reg(1) - reg(2)");

  cw <= rr(F_AND, 1, 2, 7);
  step;
  check_reg(7, 4, "AND reg(7) <= reg(1) and reg(2)");

  cw <= rr(F_OR, 1, 2, 8);
  step;
  check_reg(8, 103, "OR reg(8) <= reg(1) or reg(2)");

  cw <= rr(F_XOR, 1, 2, 9);
  step;
  check_reg(9, 99, "XOR reg(9) <= reg(1) xor reg(2)");

  cw <= ri(F_SLL, 1, 3, 10);
  step;
  check_reg(10, 800, "SLL reg(10) <= reg(1) sll 3");

  cw <= ri(F_SRL, 3, 1, 11);
  step;
  check_reg(11, X"7FFFFFFF", "SRL reg(11) <= reg(3) srl 1");

  cw <= ri(F_SRA, 3, 1, 12);
  step;
  check_reg(12, -1, "SRA reg(12) <= reg(3) sra 1");

  cw <= rr(F_SLT, 3, 2, 13);
  step;
  check_reg(13, 1, "SLT with a negative first operand");

  cw <= rr(F_SLT, 2, 3, 14);
  step;
  check_reg(14, 0, "SLT with a negative second operand");

  cw <= rr(F_SLTU, 3, 2, 15);
  step;
  check_reg(15, 0, "SLTU with the larger operand first");

  cw <= rr(F_SLTU, 2, 3, 16);
  step;
  check_reg(16, 1, "SLTU with the smaller operand first");

  ------------------------------------------------------------------
  -- The three rules about writing the register file.
  ------------------------------------------------------------------
  cw <= no_write(li(1, 999));
  step;
  check_reg(1, 100, "Dlen low must not write the register file");

  exec <= '0';
  cw <= li(1, 999);
  step;
  check_reg(1, 100, "exec low must not write the register file");
  exec <= '1';

  cw <= li(0, 42);
  step;
  check_reg(0, 0, "a write to register 0 must be discarded");

  ------------------------------------------------------------------
  -- The A bus mux, and the D bus.
  ------------------------------------------------------------------
  cw <= addr_imm(16#20#, 17);
  step;
  check_reg(17, ADDR_BASE + 16#20#, "A bus from the address input");

  cw <= rr(F_ADD, 1, 2, 18);
  wait for 1 ns;
  check(data_out = to32(107), "data_out carries the ALU result");
  step;

  ------------------------------------------------------------------
  -- The PC: increment, load, and which one wins.
  ------------------------------------------------------------------
  exec <= '0';
  cw   <= CW_NOP;
  PCie <= '1';
  step;
  check_pc(4, "PCie increments the PC");
  step;
  check_pc(8, "PCie increments the PC again");
  PCie <= '0';
  step;
  check_pc(8, "the PC holds when PCie is low");

  exec <= '1';
  cw <= jal(16#10#);
  step;
  check_pc(ADDR_BASE + 16#10#, "PClen loads the PC from the ALU");

  -- A load and an increment at the same time: the load must win.
  PCie <= '1';
  cw   <= jal(16#20#);
  step;
  check_pc(ADDR_BASE + 16#20#, "a PC load takes priority over an increment");
  PCie <= '0';

  -- Jump through a register, and link.  The linked value is the PC as
  -- it stood before the jump, because PCie is low in this testbench.
  cw <= jalr(1, 8, 20);
  step;
  check_pc(108, "JALR loads the PC from reg(1) + 8");
  check_reg(20, ADDR_BASE + 16#20#, "JALR links the old PC into reg(20)");

  -- The link path on its own, with no jump.
  cw <= link(21);
  wait for 1 ns;
  check(data_out = to32(108), "data_out carries the PC when PCDsel is high");
  step;
  check_reg(21, 108, "reg(21) <= PC");
  check_pc(108, "the PC does not move when only PCDsel is set");

  exec <= '0';
  cw <= jal(16#40#);
  step;
  check_pc(108, "exec low must not load the PC");
  exec <= '1';

  ------------------------------------------------------------------
  -- Branches.  reg(1) = reg(4) = 100, reg(2) = 7, reg(3) = -1.
  -- Every target is ADDR_BASE plus the offset.
  ------------------------------------------------------------------
  cw <= br(C_EQ, 1, 4, 16#10#);
  step;
  check_pc(ADDR_BASE + 16#10#, "BEQ taken");

  cw <= br(C_EQ, 1, 2, 16#20#);
  step;
  check_pc(ADDR_BASE + 16#10#, "BEQ not taken");

  cw <= br(C_NE, 1, 2, 16#30#);
  step;
  check_pc(ADDR_BASE + 16#30#, "BNE taken");

  cw <= br(C_NE, 1, 4, 16#40#);
  step;
  check_pc(ADDR_BASE + 16#30#, "BNE not taken");

  cw <= br(C_LT, 2, 1, 16#50#);
  step;
  check_pc(ADDR_BASE + 16#50#, "BLT taken");

  cw <= br(C_LT, 1, 2, 16#60#);
  step;
  check_pc(ADDR_BASE + 16#50#, "BLT not taken");

  cw <= br(C_GE, 1, 2, 16#70#);
  step;
  check_pc(ADDR_BASE + 16#70#, "BGE taken");

  cw <= br(C_GE, 2, 1, 16#80#);
  step;
  check_pc(ADDR_BASE + 16#70#, "BGE not taken");

  -- reg(3) is -1, which is the largest unsigned value, so the signed
  -- and unsigned answers differ here.
  cw <= br(C_LTU, 2, 3, 16#90#);
  step;
  check_pc(ADDR_BASE + 16#90#, "BLTU taken");

  cw <= br(C_LTU, 3, 2, 16#A0#);
  step;
  check_pc(ADDR_BASE + 16#90#, "BLTU not taken");

  cw <= br(C_GEU, 3, 2, 16#B0#);
  step;
  check_pc(ADDR_BASE + 16#B0#, "BGEU taken");

  cw <= br(C_GEU, 2, 3, 16#C0#);
  step;
  check_pc(ADDR_BASE + 16#B0#, "BGEU not taken");

  cw <= br(C_LT, 3, 2, 16#D0#);
  step;
  check_pc(ADDR_BASE + 16#D0#, "BLT taken with a negative operand");

  -- A backward branch.
  cw <= br(C_EQ, 1, 4, -16);
  step;
  check_pc(ADDR_BASE - 16, "a branch to a negative offset");

  -- The condition is true, but the branch unit is disabled.
  cw <= no_br(br(C_EQ, 1, 4, 16#10#));
  step;
  check_pc(ADDR_BASE - 16, "isBR low must not let the branch happen");

  -- The condition is true and the branch unit is enabled, but the
  -- datapath is not executing.
  exec <= '0';
  cw <= br(C_EQ, 1, 4, 16#10#);
  step;
  check_pc(ADDR_BASE - 16, "exec low must not let the branch happen");
  exec <= '1';

  -- A branch must not write the register file.
  check_reg(1, 100, "a branch must leave the registers alone");

  ------------------------------------------------------------------
  -- Reset again, from a state where nothing is zero.
  ------------------------------------------------------------------
  cw  <= CW_NOP;
  rst <= '1';
  step;
  check_pc(0, "reset returns the PC to zero");
  check_reg(1, 0, "reset clears register 1");
  check_reg(21, 0, "reset clears register 21");
  rst <= '0';

  ------------------------------------------------------------------
  -- Summary of the whole run
  ------------------------------------------------------------------
  if errors = 0 then
    report "RISCV_datapath testbench PASSED: all " & integer'image(checks) &
      " checks passed." severity note;
  else
    report "RISCV_datapath testbench FAILED: " & integer'image(errors) &
      " of " & integer'image(checks) & " checks failed." severity failure;
  end if;

  wait;
end process;

end Behavioral;
