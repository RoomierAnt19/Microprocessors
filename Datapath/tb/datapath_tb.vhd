--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- RISCV_datapath_testbench
--
-- Self-checking testbench for the Lab 1 datapath.  The instruction
-- decoder is not needed and is not instantiated.  Every control word
-- is built by hand and driven straight into the cw port, so the
-- datapath can be tested as soon as it is built.
--
-- The unit under test must be an entity named RISCV_datapath with an
-- architecture named behavioral and exactly this interface:
--
--   entity RISCV_datapath is
--     port (
--       cw     : in  control_word;                  -- see project_types
--       clk    : in  std_logic;
--       rst    : in  std_logic;                     -- synchronous, active high
--       DBGsel : in  std_logic_vector(4 downto 0);  -- register to examine
--       DBGreg : out std_logic_vector(31 downto 0); -- its contents
--       PCout  : out std_logic_vector(31 downto 0)  -- the program counter
--     );
--   end RISCV_datapath;
--
-- DBGsel and DBGreg are a debug read port on the register file: a
-- third read address, alongside the two the datapath already uses for
-- Asel and Bsel, with its own output.  It costs one more 32:1
-- multiplexer and it is what makes the datapath testable.  It is also
-- where a JTAG debug interface would attach in a real part, which is
-- why the port is worth having beyond this testbench: a debugger halts
-- the core and reads the register file through exactly this path.
--
--   DBGreg is combinational on DBGsel, so the testbench can read a
--   register without a clock edge, and 32 values of DBGsel read the
--   whole file between one clock edge and the next.
--
-- That is what this testbench does.  It keeps a shadow copy of all 32
-- registers, and after every single clock edge it compares the entire
-- register file against that copy.  A write that lands in the wrong
-- register, or a write that happens when Dlen is low, is reported by
-- name and cycle rather than having to be found in a waveform:
--
--   after ADD reg(5) <= reg(1) + reg(2): reg(7) is wrong,
--     expected 00000000, got 0000006B
--
-- The PC is checked after every clock edge in the same way.
--
-- Three properties of the datapath are worth stating up front, because
-- the expected values below only make sense once they are known:
--
--   cw.PCie increments the PC by 4, and it loses to a load: if PCie
--   is asserted in the same cycle as a load, from PCle or from a
--   taken branch, the PC takes the loaded value.  It originates in
--   the sequencer,
--   which feeds it to the decoder on a port of its own, and the
--   decoder passes it along in the control word, so the datapath sees
--   it like any other field.  This testbench asserts it only in the
--   tests that exercise it, so the PC holds still everywhere else and
--   the addresses in the branch tests stay easy to follow.
--
--   PCle is a control word field, not a port.  Inside the datapath it
--   is OR'd with the branch test unit's decision, and that OR is what
--   loads the PC.  So there are two independent ways to load it: the
--   decoder asserting cw.PCle for an unconditional jump, and a taken
--   branch.  The tests below exercise both, and check that each works
--   with the other one quiet.
--
--   With PCAsel high the A bus carries the PC, so every branch and
--   jump target is PC + IMM.  The A and B multiplexers have no ports
--   of their own, so they are checked through their results: IMMBsel
--   by every immediate operation below, and PCAsel by every branch
--   target landing where it should.
--
-- Every check is counted.  The run ends with one PASSED or FAILED
-- line, and a failing run ends with severity failure so that a
-- scripted simulation exits with an error.  After 25 failures the
-- individual reports stop, but the count in the summary line is
-- complete.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use work.project_types.ALL;  -- this should contain the definition for Control
                             -- Word above.

entity RISCV_datapath_testbench is
end RISCV_datapath_testbench;

architecture Behavioral of RISCV_datapath_testbench is

  -- ALU function codes, from RV32_ALU_functions.  func(3) is
  -- inst(30) and func(2 downto 0) is funct3.
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

  -- Branch conditions, from RV32_BTU_functions.  These are funct3.
  constant C_EQ  : std_logic_vector(2 downto 0) := "000";
  constant C_NE  : std_logic_vector(2 downto 0) := "001";
  constant C_LT  : std_logic_vector(2 downto 0) := "100";
  constant C_GE  : std_logic_vector(2 downto 0) := "101";
  constant C_LTU : std_logic_vector(2 downto 0) := "110";
  constant C_GEU : std_logic_vector(2 downto 0) := "111";

  type reg_file_t is array(0 to 31) of std_logic_vector(31 downto 0);

  function to5(n : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(n, 5));
  end function;

  function to32(i : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_signed(i, 32));
  end function;

  function hex(v : std_logic_vector(31 downto 0)) return string is
    constant digits : string := "0123456789ABCDEF";
    variable r : string(1 to 8);
    variable n : integer;
  begin
    for i in 0 to 7 loop
      n := to_integer(unsigned(v(31-4*i downto 28-4*i)));
      r(i+1) := digits(n+1);
    end loop;
    return r;
  end function;

  -- Idle control word: no register write, no branch, no increment.
  constant CW_NOP : control_word := (
    Asel    => "00000",
    Bsel    => "00000",
    Dsel    => "00000",
    Dlen    => '0',
    PCAsel  => '0',
    IMMBsel => '0',
    PCDsel  => '0',
    PCie    => '0',
    PCle    => '0',
    isBR    => '0',
    BRcond  => "000",
    ALUFunc => F_ADD,
    IMM     => (others => '0'));

  signal cw     : control_word := CW_NOP;
  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal DBGsel : std_logic_vector(4 downto 0) := (others => '0');
  signal DBGreg : std_logic_vector(31 downto 0);
  signal PCout  : std_logic_vector(31 downto 0);

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

  -- if reg(a) cond reg(b) then PC <= PC + offset
  function br(cond : std_logic_vector(2 downto 0);
              a, b : natural; offset : integer) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.isBR    := '1';
    c.BRcond  := cond;
    c.Asel    := to5(a);
    c.Bsel    := to5(b);
    c.PCAsel  := '1';           -- A bus = PC
    c.IMMBsel := '1';           -- B bus = IMM
    c.ALUFunc := F_ADD;         -- so the ALU computes the target
    c.IMM     := to32(offset);
    return c;
  end function;

  -- PC <= PC + offset, with the decoder asking for the load directly.
  function jal(offset : integer) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.PCle    := '1';
    c.PCAsel  := '1';           -- A bus = PC
    c.IMMBsel := '1';           -- B bus = IMM
    c.ALUFunc := F_ADD;         -- so the ALU computes the target
    c.IMM     := to32(offset);
    return c;
  end function;

  -- PC <= reg(a) + offset, and reg(d) <= PC
  function jalr(a : natural; offset : integer; d : natural) return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.PCle    := '1';
    c.Asel    := to5(a);        -- A bus = reg(a), not the PC
    c.IMMBsel := '1';
    c.ALUFunc := F_ADD;
    c.IMM     := to32(offset);
    c.Dsel    := to5(d);
    c.Dlen    := '1';
    c.PCDsel  := '1';
    return c;
  end function;

  -- PC <= PC + offset, and reg(d) <= PC
  function jal(offset : integer; d : natural) return control_word is
    variable c : control_word := jal(offset);
  begin
    c.Dsel   := to5(d);
    c.Dlen   := '1';
    c.PCDsel := '1';            -- D bus = PC
    return c;
  end function;

  -- Same control word with the register write turned off.
  function no_write(c : control_word) return control_word is
    variable r : control_word := c;
  begin
    r.Dlen := '0';
    return r;
  end function;

  -- Increment the PC by four.
  function inc_pc return control_word is
    variable c : control_word := CW_NOP;
  begin
    c.PCie := '1';
    return c;
  end function;

  -- Same control word with the increment enable also asserted.
  function also_inc(c : control_word) return control_word is
    variable r : control_word := c;
  begin
    r.PCie := '1';
    return r;
  end function;

  -- Same control word with the branch unit enabled on a condition that
  -- is false, to prove the two PC load paths are independent.
  function with_false_branch(c : control_word) return control_word is
    variable r : control_word := c;
  begin
    r.isBR   := '1';
    r.BRcond := C_NE;
    r.Asel   := to5(0);
    r.Bsel   := to5(0);         -- x0 /= x0 is false
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

  ----------------------------------------------------------------
  -- Your datapath should have this port structure, and the cw
  -- port should look like the cw structure shown above.
  ----------------------------------------------------------------
UUT: entity work.data_path (arch)
  port map(
    cw     => cw,
    clk    => clk,
    rst    => rst,
    Dbugsel => DBGsel,
    Dbug => DBGreg,
    PC_out  => PCout
    );

test: process is
  variable checks  : natural := 0;
  variable errors  : natural := 0;
  variable shadow  : reg_file_t := (others => (others => '0'));
  variable pc_exp  : integer := 0;

  -- Count every check.  Report the first 25 failures and then stop
  -- reporting, so that one broken register does not bury the rest of
  -- the run.  The summary count stays complete.
  procedure check(cond : in boolean; msg : in string) is
  begin
    checks := checks + 1;
    if not cond then
      errors := errors + 1;
      if errors <= 25 then
        report msg severity error;
      end if;
      if errors = 25 then
        report "further failures will not be reported individually"
          severity note;
      end if;
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

  -- Read the whole register file through the debug port and compare it
  -- against the shadow copy.  DBGreg is combinational on DBGsel, so
  -- this costs no clock cycles, and it leaves the control word under
  -- test untouched.
  procedure check_regs(msg : string) is
  begin
    for i in 0 to 31 loop
      DBGsel <= to5(i);
      wait for 1 ns;
      check(DBGreg = shadow(i),
            msg & ": reg(" & integer'image(i) & ") is wrong, expected " &
            hex(shadow(i)) & ", got " & hex(DBGreg));
    end loop;
  end procedure;

  -- Clock the applied control word in, then check the PC and every
  -- register.  d is the register the operation should write, or -1 if
  -- it should write none.  A write to register 0 must be discarded, so
  -- d = 0 updates nothing.  Set pc_exp before calling if the operation
  -- is supposed to move the PC.
  procedure run(msg : string; d : integer := -1; value : integer := 0) is
  begin
    step;
    if d > 0 then
      shadow(d) := to32(value);
    end if;
    check(PCout = to32(pc_exp),
          msg & ": the PC is wrong, expected " & hex(to32(pc_exp)) &
          ", got " & hex(PCout));
    check_regs(msg);
  end procedure;

begin

  ------------------------------------------------------------------
  -- Reset.  The PC and every register must come up at zero.
  ------------------------------------------------------------------
  cw  <= CW_NOP;
  rst <= '1';
  step;
  run("after reset");
  rst <= '0';

  ------------------------------------------------------------------
  -- Immediates onto the B bus, and the ALU functions.
  ------------------------------------------------------------------
  cw <= li(1, 100);
  run("reg(1) <= 100", 1, 100);

  cw <= li(2, 7);
  run("reg(2) <= 7", 2, 7);

  cw <= li(3, -1);
  run("reg(3) <= -1", 3, -1);

  cw <= li(4, 100);
  run("reg(4) <= 100", 4, 100);

  cw <= rr(F_ADD, 1, 2, 5);
  run("ADD reg(5) <= reg(1) + reg(2)", 5, 107);

  cw <= rr(F_SUB, 1, 2, 6);
  run("SUB reg(6) <= reg(1) - reg(2)", 6, 93);

  cw <= rr(F_AND, 1, 2, 7);
  run("AND reg(7) <= reg(1) and reg(2)", 7, 4);

  cw <= rr(F_OR, 1, 2, 8);
  run("OR reg(8) <= reg(1) or reg(2)", 8, 103);

  cw <= rr(F_XOR, 1, 2, 9);
  run("XOR reg(9) <= reg(1) xor reg(2)", 9, 99);

  cw <= ri(F_SLL, 1, 3, 10);
  run("SLL reg(10) <= reg(1) sll 3", 10, 800);

  cw <= ri(F_SRL, 3, 1, 11);
  run("SRL reg(11) <= reg(3) srl 1", 11, 2147483647);

  cw <= ri(F_SRA, 3, 1, 12);
  run("SRA reg(12) <= reg(3) sra 1", 12, -1);

  cw <= rr(F_SLT, 3, 2, 13);
  run("SLT with a negative first operand", 13, 1);

  cw <= rr(F_SLT, 2, 3, 14);
  run("SLT with a negative second operand", 14, 0);

  cw <= rr(F_SLTU, 3, 2, 15);
  run("SLTU with the larger operand first", 15, 0);

  cw <= rr(F_SLTU, 2, 3, 16);
  run("SLTU with the smaller operand first", 16, 1);

  ------------------------------------------------------------------
  -- The two rules about writing the register file.
  ------------------------------------------------------------------
  cw <= no_write(li(1, 999));
  run("Dlen low must not write the register file");

  cw <= li(0, 42);
  run("a write to register 0 must be discarded", 0);

  ------------------------------------------------------------------
  -- The program counter.
  ------------------------------------------------------------------
  cw     <= inc_pc;
  pc_exp := pc_exp + 4;
  run("PCie increments the PC");

  cw     <= inc_pc;
  pc_exp := pc_exp + 4;
  run("PCie increments the PC again");

  cw <= CW_NOP;
  run("the PC holds when PCie is low");

  -- A load and an increment in the same cycle: the load must win, on
  -- both of the paths that can load the PC.  If the increment won, a
  -- jump landing in the same cycle as an increment would be dropped
  -- and the machine would run straight through it.
  cw     <= also_inc(jal(32));
  pc_exp := pc_exp + 32;
  run("PCle takes priority over PCie");

  cw     <= also_inc(br(C_EQ, 1, 4, 64));
  pc_exp := pc_exp + 64;
  run("a taken branch takes priority over PCie");

  ------------------------------------------------------------------
  -- Branches.  reg(1) = reg(4) = 100, reg(2) = 7, reg(3) = -1.
  -- Every target is the current PC plus the offset.
  ------------------------------------------------------------------
  cw     <= br(C_EQ, 1, 4, 16);
  pc_exp := pc_exp + 16;
  run("BEQ taken");

  cw <= br(C_EQ, 1, 2, 32);
  run("BEQ not taken");

  cw     <= br(C_NE, 1, 2, 48);
  pc_exp := pc_exp + 48;
  run("BNE taken");

  cw <= br(C_NE, 1, 4, 64);
  run("BNE not taken");

  cw     <= br(C_LT, 2, 1, 80);
  pc_exp := pc_exp + 80;
  run("BLT taken");

  cw <= br(C_LT, 1, 2, 96);
  run("BLT not taken");

  cw     <= br(C_GE, 1, 2, 112);
  pc_exp := pc_exp + 112;
  run("BGE taken");

  cw <= br(C_GE, 2, 1, 128);
  run("BGE not taken");

  -- reg(3) is -1, which is the largest unsigned value, so the signed
  -- and unsigned answers differ here.
  cw     <= br(C_LTU, 2, 3, 144);
  pc_exp := pc_exp + 144;
  run("BLTU taken");

  cw <= br(C_LTU, 3, 2, 160);
  run("BLTU not taken");

  cw     <= br(C_GEU, 3, 2, 176);
  pc_exp := pc_exp + 176;
  run("BGEU taken");

  cw <= br(C_GEU, 2, 3, 192);
  run("BGEU not taken");

  cw     <= br(C_LT, 3, 2, 208);
  pc_exp := pc_exp + 208;
  run("BLT taken with a negative operand");

  cw     <= br(C_EQ, 1, 4, -16);
  pc_exp := pc_exp - 16;
  run("a branch to a negative offset");

  -- The condition is true, but the branch unit is disabled.
  cw <= no_br(br(C_EQ, 1, 4, 16));
  run("isBR low must not let the branch happen");

  ------------------------------------------------------------------
  -- Jumps.  cw.PCle loads the PC with no help from the branch test
  -- unit, which stays disabled throughout this group.  The linked
  -- value is the PC as it stood before the jump.
  ------------------------------------------------------------------
  cw     <= jal(64, 20);
  shadow(20) := to32(pc_exp);     -- the link value is the old PC
  pc_exp := pc_exp + 64;
  run("JAL links the old PC into reg(20)");

  cw     <= jal(-32);
  pc_exp := pc_exp - 32;
  run("a jump with no link");

  cw     <= jalr(1, 8, 21);
  shadow(21) := to32(pc_exp);
  pc_exp := 100 + 8;              -- reg(1) is 100, and PCAsel is low
  run("JALR loads the PC from reg(1) + 8 and links");

  -- PCle must not depend on the branch unit.  Here the branch
  -- condition is false, and the jump must happen anyway.
  cw     <= with_false_branch(jal(48));
  pc_exp := pc_exp + 48;
  run("PCle loads the PC even when the branch condition is false");

  -- And the converse: a taken branch with PCle low still loads.
  cw     <= br(C_EQ, 1, 4, 16);
  pc_exp := pc_exp + 16;
  run("a taken branch loads the PC with PCle low");

  ------------------------------------------------------------------
  -- Reset again, from a state where nothing is zero.
  ------------------------------------------------------------------
  cw     <= CW_NOP;
  rst    <= '1';
  shadow := (others => (others => '0'));
  pc_exp := 0;
  run("after a second reset");
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
