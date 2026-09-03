-- ALU_testbench.vhdl
--
-- Self-checking testbench for the RV32 ALU described in
-- RV32_ALU_functions.pdf.
--
-- The unit under test must be an entity named alu with exactly this
-- interface:
--
--   entity alu is
--     generic (
--       XLEN : positive := 32
--     );
--     port (
--       A    : in  std_logic_vector(XLEN-1 downto 0);
--       B    : in  std_logic_vector(XLEN-1 downto 0);
--       func : in  std_logic_vector(3 downto 0);
--       D    : out std_logic_vector(XLEN-1 downto 0)
--     );
--   end entity alu;
--
-- The testbench instantiates that entity three times and runs three
-- phases against a reference model written directly from the function
-- table.  The reference model is independent of the ALU: it is written
-- with the numeric_std operators and shares no logic with any
-- implementation.
--
--   Phase 1   XLEN = 4    exhaustive, all 16 x 16 operand pairs
--                         against all 16 function codes.  4,096 vectors.
--
--   Phase 2   XLEN = 8    exhaustive, all 256 x 256 operand pairs
--                         against all 16 function codes.  1,048,576
--                         vectors.  This phase takes the longest.
--
--   Phase 3   XLEN = 32   directed corner cases crossed with each other,
--                         then random operands.  Exhaustive testing is
--                         impossible at this width, so the corner list
--                         carries the cases that break a careless SLT:
--                         the ends of the signed and unsigned ranges.
--
-- Widths of 4 and 8 are not decoration.  A 4-bit ALU is small enough to
-- test exhaustively, so a bug in SLT or in a shift fill has nowhere to
-- hide.  Anything that survives phases 1 and 2 is very unlikely to be
-- wrong at 32 bits, and anything that fails them is far easier to debug
-- with 4-bit operands than with 32-bit ones.
--
-- The shift amount is the low log2(XLEN) bits of B, so 2 bits at XLEN=4,
-- 3 bits at XLEN=8, and 5 bits at XLEN=32.  The remaining bits of B are
-- ignored by the shifts.
--
-- The six function codes that no RV32I instruction produces (1001, 1010,
-- 1011, 1100, 1110, 1111) are required to behave as their func(3)=0
-- counterparts, since func(3) is a don't-care for every operation except
-- ADD/SUB and SRL/SRA.  See the Notes on Implementation in the PDF.
--
-- To run under GHDL:
--   ghdl -a alu.vhdl ALU_testbench.vhdl
--   ghdl -e tb_alu
--   ghdl -r tb_alu
--
-- To run under Vivado's simulator:
--   xvhdl alu.vhdl ALU_testbench.vhdl
--   xelab tb_alu -s sim_alu
--   xsim sim_alu -R
--
-- The testbench prints a per-phase summary and ends with either
-- ALL TESTS PASSED or a failure assertion.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity alu_tb is
end entity alu_tb;

architecture sim of alu_tb is

  -- Stop printing individual mismatches after this many, per phase.  A
  -- broken ALU can fail a million times, and the first few tell you
  -- everything the rest would.
  constant MAX_REPORTS : natural := 20;

  -- Random vectors per function code in phase 3.
  constant RANDOM_VECTORS : natural := 2000;

  ---------------------------------------------------------------------------
  -- Helpers
  ---------------------------------------------------------------------------

  function clog2(n : positive) return natural is
    variable bits  : natural  := 0;
    variable count : positive := 1;
  begin
    while count < n loop
      count := count * 2;
      bits  := bits + 1;
    end loop;
    return bits;
  end function clog2;

  function is_01(v : std_logic_vector) return boolean is
    variable ok : boolean := true;
  begin
    for i in v'range loop
      if v(i) /= '0' and v(i) /= '1' then
        ok := false;
      end if;
    end loop;
    return ok;
  end function is_01;

  -- Hex string for reporting.  Returns a row of question marks if the
  -- value contains anything other than '0' or '1', which is what an
  -- undriven or contended ALU output looks like.
  function to_hex(v : std_logic_vector) return string is
    constant DIGITS : string(1 to 16) := "0123456789ABCDEF";
    constant NDIG   : natural := (v'length + 3) / 4;
    variable padded : std_logic_vector(NDIG*4-1 downto 0) := (others => '0');
    variable result : string(1 to NDIG);
    variable nibble : natural;
    variable top    : natural;
  begin
    if not is_01(v) then
      return (1 to NDIG => '?');
    end if;
    padded(v'length-1 downto 0) := v;
    for i in 1 to NDIG loop
      top    := padded'left - (i-1)*4;
      nibble := to_integer(unsigned(padded(top downto top-3)));
      result(i) := DIGITS(nibble + 1);
    end loop;
    return result;
  end function to_hex;

  function to_bin(v : std_logic_vector) return string is
    variable result : string(1 to v'length);
    variable index  : positive := 1;
  begin
    for i in v'range loop
      case v(i) is
        when '0'    => result(index) := '0';
        when '1'    => result(index) := '1';
        when others => result(index) := 'X';
      end case;
      index := index + 1;
    end loop;
    return result;
  end function to_bin;

  ---------------------------------------------------------------------------
  -- Reference model
  --
  -- Written straight from the function table, with no shared structure
  -- with any ALU implementation.  Width comes from the operands, so the
  -- same model checks all three instances.
  ---------------------------------------------------------------------------
  function alu_model(a, b : std_logic_vector;
                     func : std_logic_vector(3 downto 0))
    return std_logic_vector
  is
    constant W     : natural := a'length;
    constant SW    : natural := clog2(W);
    variable av    : std_logic_vector(W-1 downto 0) := a;
    variable bv    : std_logic_vector(W-1 downto 0) := b;
    variable res   : std_logic_vector(W-1 downto 0) := (others => '0');
    variable shamt : natural;
    variable op    : std_logic_vector(3 downto 0);
  begin
    -- func(3) is a don't-care except for SUB and SRA, so the six unused
    -- codes collapse onto their func(3)=0 counterparts.
    if func = "1000" or func = "1101" then
      op := func;
    else
      op := '0' & func(2 downto 0);
    end if;

    shamt := to_integer(unsigned(bv(SW-1 downto 0)));

    case op is
      when "0000" =>                       -- ADD
        res := std_logic_vector(unsigned(av) + unsigned(bv));
      when "1000" =>                       -- SUB
        res := std_logic_vector(unsigned(av) - unsigned(bv));
      when "0001" =>                       -- SLL
        res := std_logic_vector(shift_left(unsigned(av), shamt));
      when "0101" =>                       -- SRL
        res := std_logic_vector(shift_right(unsigned(av), shamt));
      when "1101" =>                       -- SRA
        res := std_logic_vector(shift_right(signed(av), shamt));
      when "0100" =>                       -- XOR
        res := av xor bv;
      when "0110" =>                       -- OR
        res := av or bv;
      when "0111" =>                       -- AND
        res := av and bv;
      when "0010" =>                       -- SLT
        if signed(av) < signed(bv) then
          res(0) := '1';
        end if;
      when "0011" =>                       -- SLTU
        if unsigned(av) < unsigned(bv) then
          res(0) := '1';
        end if;
      when others =>
        res := (others => '0');
    end case;

    return res;
  end function alu_model;

  ---------------------------------------------------------------------------
  -- Corner operands for the 32-bit phase.  The first six are the values
  -- that separate a correct SLT from one built on the sign bit of a
  -- 32-bit difference.
  ---------------------------------------------------------------------------
  type corner_array is array (natural range <>) of std_logic_vector(31 downto 0);
  constant CORNERS : corner_array(0 to 11) := (
    x"80000000",    -- most negative
    x"80000001",
    x"7FFFFFFF",    -- most positive
    x"FFFFFFFF",    -- -1, or the largest unsigned value
    x"FFFFFFFE",
    x"00000001",
    x"00000000",
    x"00000002",
    x"55555555",
    x"AAAAAAAA",
    x"0000001F",    -- shift amount 31
    x"00000020");   -- low five bits are zero, so a shift by 0

  ---------------------------------------------------------------------------
  -- DUT connections
  ---------------------------------------------------------------------------
  signal func : std_logic_vector(3 downto 0) := (others => '0');

  signal a4, b4, d4    : std_logic_vector(3 downto 0)  := (others => '0');
  signal a8, b8, d8    : std_logic_vector(7 downto 0)  := (others => '0');
  signal a32, b32, d32 : std_logic_vector(31 downto 0) := (others => '0');

begin

  dut4 : entity work.alu
    generic map (XLEN => 4)
    port map (A => a4, B => b4, func => func, D => d4);

  dut8 : entity work.alu
    generic map (XLEN => 8)
    port map (A => a8, B => b8, func => func, D => d8);

  dut32 : entity work.alu
    generic map (XLEN => 32)
    port map (A => a32, B => b32, func => func, D => d32);

  stimulus : process

    variable total_errors : natural := 0;
    variable phase_errors : natural := 0;
    variable phase_count  : natural := 0;
    variable reports      : natural := 0;

    variable seed1 : positive := 12345;
    variable seed2 : positive := 6789;
    variable rand  : real;

    procedure start_phase(name : string) is
    begin
      phase_errors := 0;
      phase_count  := 0;
      reports      := 0;
      report "=== " & name & " ===" severity note;
    end procedure start_phase;

    procedure end_phase(name : string) is
    begin
      total_errors := total_errors + phase_errors;
      report name & ": " & integer'image(phase_count) & " vectors, " &
             integer'image(phase_errors) & " errors" severity note;
    end procedure end_phase;

    -- Compare one result against the model.  Call this after the inputs
    -- have been applied and time has advanced.
    procedure check(a, b, f, got : std_logic_vector; name : string) is
      variable expected : std_logic_vector(got'range);
    begin
      expected    := alu_model(a, b, f);
      phase_count := phase_count + 1;
      if got /= expected then
        phase_errors := phase_errors + 1;
        if reports < MAX_REPORTS then
          reports := reports + 1;
          report name & " MISMATCH func=" & to_bin(f) &
                 " A=" & to_hex(a) & " B=" & to_hex(b) &
                 " expected=" & to_hex(expected) &
                 " got=" & to_hex(got) severity warning;
          if reports = MAX_REPORTS then
            report name & ": further mismatches will not be printed"
              severity warning;
          end if;
        end if;
      end if;
    end procedure check;

    -- One uniformly distributed bit per position.
    procedure random_slv(result : out std_logic_vector) is
      variable value : std_logic_vector(result'range);
    begin
      for i in value'range loop
        uniform(seed1, seed2, rand);
        if rand < 0.5 then
          value(i) := '0';
        else
          value(i) := '1';
        end if;
      end loop;
      result := value;
    end procedure random_slv;

    variable rand32 : std_logic_vector(31 downto 0);

  begin

    -------------------------------------------------------------------------
    -- Phase 1: XLEN = 4, exhaustive
    -------------------------------------------------------------------------
    start_phase("Phase 1: XLEN=4, exhaustive");
    for f in 0 to 15 loop
      func <= std_logic_vector(to_unsigned(f, 4));
      for i in 0 to 15 loop
        a4 <= std_logic_vector(to_unsigned(i, 4));
        for j in 0 to 15 loop
          b4 <= std_logic_vector(to_unsigned(j, 4));
          wait for 1 ns;
          check(a4, b4, func, d4, "XLEN=4");
        end loop;
      end loop;
    end loop;
    end_phase("Phase 1: XLEN=4, exhaustive");

    -------------------------------------------------------------------------
    -- Phase 2: XLEN = 8, exhaustive
    -------------------------------------------------------------------------
    start_phase("Phase 2: XLEN=8, exhaustive");
    for f in 0 to 15 loop
      func <= std_logic_vector(to_unsigned(f, 4));
      report "  XLEN=8: function code " & to_bin(std_logic_vector(to_unsigned(f, 4)))
        severity note;
      for i in 0 to 255 loop
        a8 <= std_logic_vector(to_unsigned(i, 8));
        for j in 0 to 255 loop
          b8 <= std_logic_vector(to_unsigned(j, 8));
          wait for 1 ns;
          check(a8, b8, func, d8, "XLEN=8");
        end loop;
      end loop;
    end loop;
    end_phase("Phase 2: XLEN=8, exhaustive");

    -------------------------------------------------------------------------
    -- Phase 3: XLEN = 32, corner cases then random
    -------------------------------------------------------------------------
    start_phase("Phase 3: XLEN=32, corner and random");

    for f in 0 to 15 loop
      func <= std_logic_vector(to_unsigned(f, 4));
      for i in CORNERS'range loop
        a32 <= CORNERS(i);
        for j in CORNERS'range loop
          b32 <= CORNERS(j);
          wait for 1 ns;
          check(a32, b32, func, d32, "XLEN=32 corner");
        end loop;
      end loop;
    end loop;

    for f in 0 to 15 loop
      func <= std_logic_vector(to_unsigned(f, 4));
      for n in 1 to RANDOM_VECTORS loop
        random_slv(rand32);
        a32 <= rand32;
        random_slv(rand32);
        b32 <= rand32;
        wait for 1 ns;
        check(a32, b32, func, d32, "XLEN=32 random");
      end loop;
    end loop;

    -- Random operands rarely land on a corner, so cross the corner list
    -- against random values as well.
    for f in 0 to 15 loop
      func <= std_logic_vector(to_unsigned(f, 4));
      for i in CORNERS'range loop
        a32 <= CORNERS(i);
        for n in 1 to 64 loop
          random_slv(rand32);
          b32 <= rand32;
          wait for 1 ns;
          check(a32, b32, func, d32, "XLEN=32 mixed");
        end loop;
      end loop;
    end loop;

    end_phase("Phase 3: XLEN=32, corner and random");

    -------------------------------------------------------------------------
    -- Summary
    -------------------------------------------------------------------------
    report "=== Summary ===" severity note;
    if total_errors = 0 then
      report "ALL TESTS PASSED" severity note;
    else
      report integer'image(total_errors) & " total errors" severity warning;
    end if;

    assert total_errors = 0
      report "ALU TESTBENCH FAILED" severity failure;

    wait;
  end process stimulus;

end architecture sim;
