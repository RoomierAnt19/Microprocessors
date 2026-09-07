-- BTU_testbench.vhdl
--
-- Self-checking testbench for the RV32 Branch Test Unit described in
-- RV32_BTU_functions.pdf.
--
-- The unit under test must be an entity named branch_test_unit with
-- exactly this interface:
--
--   entity branch_test_unit is
--     generic (
--       XLEN : integer := 32
--     );
--     port (
--       RS1         : in  std_logic_vector(XLEN-1 downto 0);
--       RS2         : in  std_logic_vector(XLEN-1 downto 0);
--       cond        : in  std_logic_vector(2 downto 0);
--       enable      : in  std_logic;
--       take_branch : out std_logic
--     );
--   end entity branch_test_unit;
--
-- The testbench instantiates that entity three times and runs three
-- phases against a reference model written directly from the condition
-- table.  That model is independent of the BTU: it is written with the
-- numeric_std operators and shares no logic with any implementation.
-- It lives in the separate package btu_reference, which supplies
--
--   function btu_model(a, b : std_logic_vector;
--                      c    : std_logic_vector(2 downto 0);
--                      en   : std_logic) return std_logic;
--
--   Phase 1   XLEN = 4    exhaustive, all 16 x 16 operand pairs against
--                         all 8 condition codes and both values of
--                         enable.  4,096 vectors.
--
--   Phase 2   XLEN = 8    exhaustive, all 256 x 256 operand pairs
--                         against all 8 condition codes and both values
--                         of enable.  1,048,576 vectors.  This phase
--                         takes the longest.
--
--   Phase 3   XLEN = 32   directed corner cases crossed with each other,
--                         random operands, random equal pairs, and the
--                         corners crossed with random values.
--                         Exhaustive testing is impossible at this
--                         width, so the corner list carries the cases
--                         that break a careless BLT: the ends of the
--                         signed and unsigned ranges.
--
-- Widths of 4 and 8 are not decoration.  A 4-bit BTU is small enough to
-- test exhaustively, so a signed comparison built on the sign bit of a
-- difference has nowhere to hide.  At 4 bits that bug is reported at
-- RS1 = 0 and RS2 = 8, which is -8: the correct answer for BLT is 0 and
-- the broken unit says 1.  Anything that survives phases 1 and 2 is
-- very unlikely to be wrong at 32 bits, and anything that fails them is
-- far easier to debug with 4-bit operands than with 32-bit ones.
--
-- Random 32-bit operands essentially never compare equal, so random
-- vectors alone never test BEQ in the taken direction.  Phase 3 drives
-- the corner list against itself and drives a run of random pairs with
-- RS2 forced equal to RS1 for that reason.
--
-- The two condition codes that no RV32I instruction produces (010 and
-- 011) are required to leave take_branch at 0, as is every code when
-- enable is 0.  Leaving them undefined infers a latch.  See the Notes
-- on Implementation in the PDF.
--
-- To run under GHDL:
--   ghdl -a --std=08 -frelaxed project_types.vhdl btu_reference.vhdl \
--        branch_test_unit.vhdl BTU_testbench.vhdl
--   ghdl -e --std=08 tb_btu
--   ghdl -r --std=08 tb_btu
--
-- To run under Vivado's simulator:
--   xvhdl -2008 project_types.vhdl btu_reference.vhdl \
--         branch_test_unit.vhdl BTU_testbench.vhdl
--   xelab tb_btu -s sim_btu
--   xsim sim_btu -R
--
-- project_types is needed only because branch_test_unit uses
-- To_Std_Logic from it.  The testbench itself depends on nothing but
-- the IEEE libraries and btu_reference.
--
-- Measured on Vivado 2025.1 and GHDL 4.1.0, all three phases: 3 s under
-- either simulator.  A run that takes minutes or stalls partway through
-- phase 2 is not the simulator's event rate.  The progress lines printed
-- during phase 2 show whether a slow run is still advancing.
--
-- Running it from the Vivado GUI is what hangs.  The generated
-- <top>.tcl contains "add_wave /", which puts every top-level object in
-- the wave window.  The simulator handles the million time steps of
-- phase 2 without trouble, but the wave viewer does not, and the GUI
-- stops responding partway through that phase.  Replace the generated
-- script with one that adds nothing to the wave window:
--
--   printf 'run -all\nquit\n' > no_wave.tcl
--   set_property -name {xsim.simulate.custom_tcl} \
--     -value {/full/path/no_wave.tcl} -objects [get_filesets sim_1]
--
-- With that set, the project's own simulate.sh runs the whole testbench
-- in the same few seconds the command line takes.
--
-- The testbench prints a per-phase summary and ends with either
-- ALL TESTS PASSED or a failure assertion.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- The reference model lives in its own file, btu_reference.vhdl, and is
-- not part of the lab distribution.  Analyze it before this file.
use work.btu_reference.all;

entity btu_tb is
end entity btu_tb;

architecture sim of btu_tb is

  -- Stop printing individual mismatches after this many, per phase.  A
  -- broken BTU can fail a million times, and the first few tell you
  -- everything the rest would.
  constant MAX_REPORTS : natural := 20;

  -- Random vectors per control combination in phase 3.
  constant RANDOM_VECTORS : natural := 2000;

  -- Indexed by the enable loop counter, so that every phase sweeps
  -- enable as well as cond.
  constant EN_VALS : std_logic_vector(0 to 1) := "01";

  -- Phase 2 sweeps 1,048,576 vectors, which is one simulation time step
  -- each.  GHDL does that in seconds.  Vivado's xsim is far slower and
  -- will appear to hang if it is also logging waveforms, so raise this
  -- to sample phase 2 instead of sweeping it while triaging a run.
  -- Must divide 256.  Leave it at 1 for a real test: a strided phase 2
  -- is not exhaustive and proves nothing about the operand pairs it
  -- skips.
  constant STRIDE8 : positive := 1;

  -- Print a progress line every this many values of RS1 in phase 2, so
  -- that a stalled run can be told from a slow one.
  constant PROGRESS8 : positive := 32;

  ---------------------------------------------------------------------------
  -- Helpers
  ---------------------------------------------------------------------------

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
  -- undriven or contended input looks like.
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

  -- One character for a single bit, so that a take_branch of 'U' or 'X'
  -- is reported as itself rather than silently compared as not-'1'.
  function to_char(b : std_logic) return string is
  begin
    case b is
      when '0'    => return "0";
      when '1'    => return "1";
      when 'U'    => return "U";
      when 'X'    => return "X";
      when 'Z'    => return "Z";
      when others => return "?";
    end case;
  end function to_char;

  -- Mnemonic for the control combination, so a failure report names the
  -- instruction rather than only its encoding.
  function mnemonic(c : std_logic_vector(2 downto 0); en : std_logic)
    return string
  is
  begin
    if en /= '1' then
      return "disabled";
    end if;
    case c is
      when "000"  => return "BEQ ";
      when "001"  => return "BNE ";
      when "100"  => return "BLT ";
      when "101"  => return "BGE ";
      when "110"  => return "BLTU";
      when "111"  => return "BGEU";
      when others => return "----";
    end case;
  end function mnemonic;

  ---------------------------------------------------------------------------
  -- Corner operands for the 32-bit phase.  These are the values that
  -- separate a correct signed comparison from one built on the sign bit
  -- of a 32-bit difference, and a correct unsigned comparison from a
  -- signed one.
  ---------------------------------------------------------------------------
  type corner_array is array (natural range <>) of std_logic_vector(31 downto 0);
  constant CORNERS : corner_array(0 to 11) := (
    x"80000000",    -- most negative signed, and 2**31 unsigned
    x"80000001",
    x"7FFFFFFF",    -- most positive signed
    x"7FFFFFFE",
    x"FFFFFFFF",    -- -1 signed, largest unsigned
    x"FFFFFFFE",
    x"00000000",
    x"00000001",
    x"00000002",
    x"55555555",
    x"AAAAAAAA",
    x"0000000F");

  ---------------------------------------------------------------------------
  -- UUT connections
  ---------------------------------------------------------------------------
  signal cond   : std_logic_vector(2 downto 0) := (others => '0');
  signal enable : std_logic                    := '0';

  signal a4, b4    : std_logic_vector(3 downto 0)  := (others => '0');
  signal a8, b8    : std_logic_vector(7 downto 0)  := (others => '0');
  signal a32, b32  : std_logic_vector(31 downto 0) := (others => '0');

  signal take_branch4  : std_logic;
  signal take_branch8  : std_logic;
  signal take_branch32 : std_logic;

begin

  uut4 : entity work.btu
    generic map (XLEN => 4)
    port map (RS1 => a4, RS2 => b4, cond => cond,
              enable => enable, take_branch => take_branch4);

  uut8 : entity work.btu
    generic map (XLEN => 8)
    port map (RS1 => a8, RS2 => b8, cond => cond,
              enable => enable, take_branch => take_branch8);

  uut32 : entity work.btu
    generic map (XLEN => 32)
    port map (RS1 => a32, RS2 => b32, cond => cond,
              enable => enable, take_branch => take_branch32);

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
    procedure check(a, b : std_logic_vector;
                    c    : std_logic_vector(2 downto 0);
                    en   : std_logic;
                    got  : std_logic;
                    name : string) is
      variable expected : std_logic;
    begin
      expected    := btu_model(a, b, c, en);
      phase_count := phase_count + 1;
      if got /= expected then
        phase_errors := phase_errors + 1;
        if reports < MAX_REPORTS then
          reports := reports + 1;
          report name & " MISMATCH " & mnemonic(c, en) &
                 " enable=" & to_char(en) & " cond=" & to_bin(c) &
                 " RS1=" & to_hex(a) & " RS2=" & to_hex(b) &
                 " expected=" & to_char(expected) &
                 " got=" & to_char(got) severity warning;
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
    for e in 0 to 1 loop
      enable <= EN_VALS(e);
      for c in 0 to 7 loop
        cond <= std_logic_vector(to_unsigned(c, 3));
        for i in 0 to 15 loop
          a4 <= std_logic_vector(to_unsigned(i, 4));
          for j in 0 to 15 loop
            b4 <= std_logic_vector(to_unsigned(j, 4));
            wait for 1 ns;
            check(a4, b4, cond, enable, take_branch4, "XLEN=4");
          end loop;
        end loop;
      end loop;
    end loop;
    end_phase("Phase 1: XLEN=4, exhaustive");

    -------------------------------------------------------------------------
    -- Phase 2: XLEN = 8, exhaustive
    -------------------------------------------------------------------------
    start_phase("Phase 2: XLEN=8, exhaustive");
    for e in 0 to 1 loop
      enable <= EN_VALS(e);
      for c in 0 to 7 loop
        cond <= std_logic_vector(to_unsigned(c, 3));
        wait for 1 ns;
        report "  XLEN=8: enable=" & to_char(enable) &
               " cond=" & to_bin(cond) & " " & mnemonic(cond, enable)
          severity note;
        for i in 0 to (256 / STRIDE8) - 1 loop
          if (i mod PROGRESS8) = 0 then
            report "    RS1=" & to_hex(std_logic_vector(to_unsigned(i * STRIDE8, 8))) &
                   " vectors=" & integer'image(phase_count) &
                   " at " & time'image(now) severity note;
          end if;
          a8 <= std_logic_vector(to_unsigned(i * STRIDE8, 8));
          for j in 0 to (256 / STRIDE8) - 1 loop
            b8 <= std_logic_vector(to_unsigned(j * STRIDE8, 8));
            wait for 1 ns;
            check(a8, b8, cond, enable, take_branch8, "XLEN=8");
          end loop;
        end loop;
      end loop;
    end loop;
    end_phase("Phase 2: XLEN=8, exhaustive");

    -------------------------------------------------------------------------
    -- Phase 3: XLEN = 32, corner cases, random, and equal pairs
    -------------------------------------------------------------------------
    start_phase("Phase 3: XLEN=32, corner and random");

    -- Corners against corners.  This is where a signed comparison built
    -- on the sign bit of a 32-bit difference fails, and it is also the
    -- only part of this phase that reliably drives RS1 = RS2.
    for e in 0 to 1 loop
      enable <= EN_VALS(e);
      for c in 0 to 7 loop
        cond <= std_logic_vector(to_unsigned(c, 3));
        for i in CORNERS'range loop
          a32 <= CORNERS(i);
          for j in CORNERS'range loop
            b32 <= CORNERS(j);
            wait for 1 ns;
            check(a32, b32, cond, enable, take_branch32, "XLEN=32 corner");
          end loop;
        end loop;
      end loop;
    end loop;

    -- Independent random operands.
    for e in 0 to 1 loop
      enable <= EN_VALS(e);
      for c in 0 to 7 loop
        cond <= std_logic_vector(to_unsigned(c, 3));
        for n in 1 to RANDOM_VECTORS loop
          random_slv(rand32);
          a32 <= rand32;
          random_slv(rand32);
          b32 <= rand32;
          wait for 1 ns;
          check(a32, b32, cond, enable, take_branch32, "XLEN=32 random");
        end loop;
      end loop;
    end loop;

    -- Random equal pairs.  Two independent random 32-bit values collide
    -- about once in 2**32, so without this loop BEQ is never taken on a
    -- random vector and BNE is never not taken.
    for e in 0 to 1 loop
      enable <= EN_VALS(e);
      for c in 0 to 7 loop
        cond <= std_logic_vector(to_unsigned(c, 3));
        for n in 1 to 256 loop
          random_slv(rand32);
          a32 <= rand32;
          b32 <= rand32;
          wait for 1 ns;
          check(a32, b32, cond, enable, take_branch32, "XLEN=32 equal");
        end loop;
      end loop;
    end loop;

    -- Corners against random values, in both operand positions, since a
    -- comparison can be broken in one direction only.
    for e in 0 to 1 loop
      enable <= EN_VALS(e);
      for c in 0 to 7 loop
        cond <= std_logic_vector(to_unsigned(c, 3));
        for i in CORNERS'range loop
          for n in 1 to 64 loop
            random_slv(rand32);
            a32 <= CORNERS(i);
            b32 <= rand32;
            wait for 1 ns;
            check(a32, b32, cond, enable, take_branch32, "XLEN=32 mixed");
            a32 <= rand32;
            b32 <= CORNERS(i);
            wait for 1 ns;
            check(a32, b32, cond, enable, take_branch32, "XLEN=32 mixed");
          end loop;
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
      report "BTU TESTBENCH FAILED" severity failure;

    wait;
  end process stimulus;

end architecture sim;
