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
--       R    : out std_logic_vector(XLEN-1 downto 0)
--     );
--   end entity alu;
--
-- The testbench instantiates that entity three times and runs three
-- phases.  No reference model ships with it.
--
-- Phase 1 carries its 4,096 expected results outright, one hex
-- character each, so a 4-bit failure is reported with the operands that
-- caused it.  Phases 2 and 3 are checked with a rolling checksum over
-- the unit's own outputs, one per func code, so a failure there names
-- the operation but not the operands.  Four bits is where an arithmetic
-- bug is debuggable by hand anyway, and phase 1 is exhaustive there.
--
-- Regenerate the constants with tools/gen_alu_answers.py after any
-- change to the stimulus.  Each phase asserts its own vector count, so
-- drift between the two fails loudly rather than silently.
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
--   ghdl -a --std=08 -frelaxed project_types.vhdl generic_shifter.vhdl \
--        alu.vhdl ALU_testbench.vhdl
--   ghdl -e --std=08 ALU_testbench
--   ghdl -r --std=08 ALU_testbench
--
-- To run under Vivado's simulator:
--   xvhdl -2008 project_types.vhdl generic_shifter.vhdl \
--         alu.vhdl ALU_testbench.vhdl
--   xelab ALU_testbench -s sim_ALU_testbench
--   xsim sim_ALU_testbench -R
--
-- Measured on Vivado 2025.1 and GHDL 4.1.0, all three phases: 4 s under
-- xsim, 8 s under GHDL, 5 s under xsim with "log_wave -r /" in effect
-- and a 57 MB waveform database written.  A run that takes minutes or
-- stalls partway through phase 2 is neither the simulator's event rate
-- nor the waveform database.  The progress lines printed during phase 2
-- show whether a slow run is still advancing.
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
-- The testbench names no architecture, so the default binding selects
-- whichever architecture of alu was analyzed last.  With the file above
-- that is shared_adder.  Both architectures pass.
--
-- The testbench prints a per-phase summary and ends with either
-- ALL TESTS PASSED or a failure assertion.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity ALU_testbench is
end entity ALU_testbench;

architecture sim of ALU_testbench is

  -- Stop printing individual mismatches after this many, per phase.  A
  -- broken ALU can fail a million times, and the first few tell you
  -- everything the rest would.
  constant MAX_REPORTS : natural := 20;

  -- Random vectors per function code in phase 3.
  constant RANDOM_VECTORS : natural := 2000;

  -- Phase 2 sweeps 1,048,576 vectors, which is one simulation time step
  -- each.  GHDL does that in seconds.  Vivado's xsim is far slower and
  -- will appear to hang if it is also logging waveforms, so raise this
  -- to sample phase 2 instead of sweeping it while triaging a run.
  -- Must divide 256.  Leave it at 1 for a real test: a strided phase 2
  -- is not exhaustive and proves nothing about the codes it skips.
  constant STRIDE8 : positive := 1;

  ---------------------------------------------------------------------------
  -- Helpers
  ---------------------------------------------------------------------------

  -- Progress and summary go through textio rather than through report.
  -- xsim follows every report with a line naming the time, the process
  -- and the source file, which triples the length of the transcript for
  -- lines that are not diagnosing anything.  Mismatches stay on report,
  -- where that context is worth having.
  procedure print(s : string) is
    variable l : line;
  begin
    write(l, s);
    writeline(output, l);
  end procedure print;

  -- Name of the operation a function code selects, for the phase 2
  -- progress lines.  func(3) is a don't-care except for SUB and SRA.
  function mnemonic(f : std_logic_vector(3 downto 0)) return string is
  begin
    case f is
      when "0000" => return "ADD ";
      when "1000" => return "SUB ";
      when "0101" => return "SRL ";
      when "1101" => return "SRA ";
      when others =>
        case f(2 downto 0) is
          when "001"  => return "SLL ";
          when "010"  => return "SLT ";
          when "011"  => return "SLTU";
          when "100"  => return "XOR ";
          when "110"  => return "OR  ";
          when "111"  => return "AND ";
          when others => return "????";
        end case;
    end case;
  end function mnemonic;

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
  -- Expected results
  --
  -- No reference model ships with this testbench.  Phase 1 carries its
  -- 4,096 answers outright, one hex character each, in generation order,
  -- so a 4-bit failure is reported with the operands that caused it.
  -- Phases 2 and 3 are checked by a rolling checksum over the unit's own
  -- outputs, one per func code, so a failure there names the operation
  -- even though it cannot name the operands.
  --
  -- Regenerate all of it with tools/gen_alu_answers.py after any change
  -- to the stimulus.  Each phase asserts its own vector count, so drift
  -- between the two fails loudly rather than silently.
  ---------------------------------------------------------------------------
  -- Plain integers, not unsigned vectors: GHDL implements a vector
  -- operation as a loop over the elements with a temporary per call, and
  -- at eight million folded bits that is the difference between seconds
  -- and minutes.
  type hash_array is array (natural range <>) of natural;
  constant HASH_M    : natural := 67108859;   -- prime; 31*HASH_M+1 still fits
  constant HASH_INIT : natural := 1;

  function roll(h : natural; v : std_logic) return natural is
    variable b : natural := 0;
  begin
    if v = '1' then b := 1; end if;
    return (h * 31 + b) mod HASH_M;
  end function roll;

  constant PHASE1_ANSWERS : string(1 to 4096) :=
    "0123456789ABCDEF123456789ABCDEF023456789ABCDEF013456789ABCDEF012" &
    "456789ABCDEF012356789ABCDEF012346789ABCDEF012345789ABCDEF0123456" &
    "89ABCDEF012345679ABCDEF012345678ABCDEF0123456789BCDEF0123456789A" &
    "CDEF0123456789ABDEF0123456789ABCEF0123456789ABCDF0123456789ABCDE" &
    "00000000000000001248124812481248248024802480248036C836C836C836C8" &
    "48004800480048005A485A485A485A486C806C806C806C807EC87EC87EC87EC8" &
    "80008000800080009248924892489248A480A480A480A480B6C8B6C8B6C8B6C8" &
    "C800C800C800C800DA48DA48DA48DA48EC80EC80EC80EC80FEC8FEC8FEC8FEC8" &
    "0111111100000000001111110000000000011111000000000000111100000000" &
    "0000011100000000000000110000000000000001000000000000000000000000" &
    "1111111101111111111111110011111111111111000111111111111100001111" &
    "1111111100000111111111110000001111111111000000011111111100000000" &
    "0111111111111111001111111111111100011111111111110000111111111111" &
    "0000011111111111000000111111111100000001111111110000000011111111" &
    "0000000001111111000000000011111100000000000111110000000000001111" &
    "0000000000000111000000000000001100000000000000010000000000000000" &
    "0123456789ABCDEF1032547698BADCFE23016745AB89EFCD32107654BA98FEDC" &
    "45670123CDEF89AB54761032DCFE98BA67452301EFCDAB8976543210FEDCBA98" &
    "89ABCDEF0123456798BADCFE10325476AB89EFCD23016745BA98FEDC32107654" &
    "CDEF89AB45670123DCFE98BA54761032EFCDAB8967452301FEDCBA9876543210" &
    "0000000000000000100010001000100021002100210021003100310031003100" &
    "4210421042104210521052105210521063106310631063107310731073107310" &
    "84218421842184219421942194219421A521A521A521A521B521B521B521B521" &
    "C631C631C631C631D631D631D631D631E731E731E731E731F731F731F731F731" &
    "0123456789ABCDEF1133557799BBDDFF23236767ABABEFEF33337777BBBBFFFF" &
    "45674567CDEFCDEF55775577DDFFDDFF67676767EFEFEFEF77777777FFFFFFFF" &
    "89ABCDEF89ABCDEF99BBDDFF99BBDDFFABABEFEFABABEFEFBBBBFFFFBBBBFFFF" &
    "CDEFCDEFCDEFCDEFDDFFDDFFDDFFDDFFEFEFEFEFEFEFEFEFFFFFFFFFFFFFFFFF" &
    "0000000000000000010101010101010100220022002200220123012301230123" &
    "0000444400004444010145450101454500224466002244660123456701234567" &
    "000000008888888801010101898989890022002288AA88AA0123012389AB89AB" &
    "000044448888CCCC010145458989CDCD0022446688AACCEE0123456789ABCDEF" &
    "0FEDCBA98765432110FEDCBA98765432210FEDCBA98765433210FEDCBA987654" &
    "43210FEDCBA98765543210FEDCBA98766543210FEDCBA98776543210FEDCBA98" &
    "876543210FEDCBA99876543210FEDCBAA9876543210FEDCBBA9876543210FEDC" &
    "CBA9876543210FEDDCBA9876543210FEEDCBA9876543210FFEDCBA9876543210" &
    "00000000000000001248124812481248248024802480248036C836C836C836C8" &
    "48004800480048005A485A485A485A486C806C806C806C807EC87EC87EC87EC8" &
    "80008000800080009248924892489248A480A480A480A480B6C8B6C8B6C8B6C8" &
    "C800C800C800C800DA48DA48DA48DA48EC80EC80EC80EC80FEC8FEC8FEC8FEC8" &
    "0111111100000000001111110000000000011111000000000000111100000000" &
    "0000011100000000000000110000000000000001000000000000000000000000" &
    "1111111101111111111111110011111111111111000111111111111100001111" &
    "1111111100000111111111110000001111111111000000011111111100000000" &
    "0111111111111111001111111111111100011111111111110000111111111111" &
    "0000011111111111000000111111111100000001111111110000000011111111" &
    "0000000001111111000000000011111100000000000111110000000000001111" &
    "0000000000000111000000000000001100000000000000010000000000000000" &
    "0123456789ABCDEF1032547698BADCFE23016745AB89EFCD32107654BA98FEDC" &
    "45670123CDEF89AB54761032DCFE98BA67452301EFCDAB8976543210FEDCBA98" &
    "89ABCDEF0123456798BADCFE10325476AB89EFCD23016745BA98FEDC32107654" &
    "CDEF89AB45670123DCFE98BA54761032EFCDAB8967452301FEDCBA9876543210" &
    "0000000000000000100010001000100021002100210021003100310031003100" &
    "4210421042104210521052105210521063106310631063107310731073107310" &
    "8CEF8CEF8CEF8CEF9CEF9CEF9CEF9CEFADEFADEFADEFADEFBDEFBDEFBDEFBDEF" &
    "CEFFCEFFCEFFCEFFDEFFDEFFDEFFDEFFEFFFEFFFEFFFEFFFFFFFFFFFFFFFFFFF" &
    "0123456789ABCDEF1133557799BBDDFF23236767ABABEFEF33337777BBBBFFFF" &
    "45674567CDEFCDEF55775577DDFFDDFF67676767EFEFEFEF77777777FFFFFFFF" &
    "89ABCDEF89ABCDEF99BBDDFF99BBDDFFABABEFEFABABEFEFBBBBFFFFBBBBFFFF" &
    "CDEFCDEFCDEFCDEFDDFFDDFFDDFFDDFFEFEFEFEFEFEFEFEFFFFFFFFFFFFFFFFF" &
    "0000000000000000010101010101010100220022002200220123012301230123" &
    "0000444400004444010145450101454500224466002244660123456701234567" &
    "000000008888888801010101898989890022002288AA88AA0123012389AB89AB" &
    "000044448888CCCC010145458989CDCD0022446688AACCEE0123456789ABCDEF";

  constant PHASE2_SUMS : hash_array(0 to 15) := (
     0 => 36297972,   -- func 0000  ADD  65536 vectors
     1 =>  9996288,   -- func 0001  SLL  65536 vectors
     2 => 42992115,   -- func 0010  SLT  65536 vectors
     3 =>  1719378,   -- func 0011  SLTU 65536 vectors
     4 => 53422488,   -- func 0100  XOR  65536 vectors
     5 => 56342166,   -- func 0101  SRL  65536 vectors
     6 =>   934275,   -- func 0110  OR   65536 vectors
     7 => 35872708,   -- func 0111  AND  65536 vectors
     8 =>  5924920,   -- func 1000  SUB  65536 vectors
     9 =>  9996288,   -- func 1001  SLL  65536 vectors
    10 => 42992115,   -- func 1010  SLT  65536 vectors
    11 =>  1719378,   -- func 1011  SLTU 65536 vectors
    12 => 53422488,   -- func 1100  XOR  65536 vectors
    13 =>  7879255,   -- func 1101  SRA  65536 vectors
    14 =>   934275,   -- func 1110  OR   65536 vectors
    15 => 35872708);  -- func 1111  AND  65536 vectors

  constant PHASE3_SUMS : hash_array(0 to 15) := (
     0 => 50409552,   -- func 0000  ADD  2912 vectors
     1 => 40839815,   -- func 0001  SLL  2912 vectors
     2 => 13360638,   -- func 0010  SLT  2912 vectors
     3 => 35610617,   -- func 0011  SLTU 2912 vectors
     4 => 28880788,   -- func 0100  XOR  2912 vectors
     5 => 16566387,   -- func 0101  SRL  2912 vectors
     6 =>  4427806,   -- func 0110  OR   2912 vectors
     7 => 51701420,   -- func 0111  AND  2912 vectors
     8 => 55661177,   -- func 1000  SUB  2912 vectors
     9 => 31066483,   -- func 1001  SLL  2912 vectors
    10 => 32159309,   -- func 1010  SLT  2912 vectors
    11 => 24095001,   -- func 1011  SLTU 2912 vectors
    12 =>  4391426,   -- func 1100  XOR  2912 vectors
    13 =>  1534802,   -- func 1101  SRA  2912 vectors
    14 => 39639120,   -- func 1110  OR   2912 vectors
    15 => 53842206);  -- func 1111  AND  2912 vectors

  function answer_nibble(idx : natural) return std_logic_vector is
    constant DIGITS : string(1 to 16) := "0123456789ABCDEF";
    variable ch  : character;
    variable nib : natural := 0;
  begin
    ch := PHASE1_ANSWERS(idx + 1);
    for k in 1 to 16 loop
      if DIGITS(k) = ch then nib := k - 1; end if;
    end loop;
    return std_logic_vector(to_unsigned(nib, 4));
  end function answer_nibble;



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
  -- UUT connections
  ---------------------------------------------------------------------------
  signal func : std_logic_vector(3 downto 0) := (others => '0');

  signal a4, b4, r4    : std_logic_vector(3 downto 0)  := (others => '0');
  signal a8, b8, r8    : std_logic_vector(7 downto 0)  := (others => '0');
  signal a32, b32, r32 : std_logic_vector(31 downto 0) := (others => '0');

begin

  uut4 : entity work.alu
    generic map (XLEN => 4)
    port map (A => a4, B => b4, func => func, d => r4);

  uut8 : entity work.alu
    generic map (XLEN => 8)
    port map (A => a8, B => b8, func => func, d => r8);

  uut32 : entity work.alu
    generic map (XLEN => 32)
    port map (A => a32, B => b32, func => func, d => r32);

  stimulus : process

    variable total_errors : natural := 0;
    variable phase_errors : natural := 0;
    variable phase_count  : natural := 0;
    variable reports      : natural := 0;

    -- Deterministic pseudo-random source.  xorshift32 rather than
    -- ieee.math_real.UNIFORM, because the phase 2 and 3 checksums are
    -- constants and every simulator has to walk the identical sequence
    -- to reproduce them.  tools/gen_alu_answers.py carries the same
    -- three lines.
    variable rng : unsigned(31 downto 0) := x"12345678";

    -- One running checksum per func code, so a phase 2 or 3 failure
    -- names the operation.
    variable hsum  : hash_array(0 to 15) := (others => HASH_INIT);
    variable p1idx : natural := 0;

    procedure start_phase(name : string) is
    begin
      phase_errors := 0;
      phase_count  := 0;
      reports      := 0;
      hsum         := (others => HASH_INIT);
      print("=== " & name & " ===");
    end procedure start_phase;

    procedure end_phase(name : string; expect_count : natural) is
    begin
      total_errors := total_errors + phase_errors;
      print(name & ": " & integer'image(phase_count) & " vectors, " &
            integer'image(phase_errors) & " errors");
      assert phase_count = expect_count
        report name & " ran " & integer'image(phase_count) & " vectors, but " &
               "the stored answers were generated for " &
               integer'image(expect_count) & ".  The stimulus and " &
               "tools/gen_alu_answers.py have diverged; regenerate."
        severity failure;
    end procedure end_phase;

    -- Phase 1 only.  The answers are carried outright, so a mismatch is
    -- reported with the operands that caused it.
    procedure check_p1(a, b, f, got : std_logic_vector) is
      variable expected : std_logic_vector(3 downto 0);
    begin
      expected    := answer_nibble(p1idx);
      p1idx       := p1idx + 1;
      phase_count := phase_count + 1;
      if got /= expected then
        phase_errors := phase_errors + 1;
        if reports < MAX_REPORTS then
          reports := reports + 1;
          report "XLEN=4 MISMATCH " & mnemonic(f) & " func=" & to_bin(f) &
                 " A=" & to_hex(a) & " B=" & to_hex(b) &
                 " expected=" & to_hex(expected) &
                 " got=" & to_hex(got) severity warning;
          if reports = MAX_REPORTS then
            report "XLEN=4: further mismatches will not be printed"
              severity warning;
          end if;
        end if;
      end if;
    end procedure check_p1;

    -- Phases 2 and 3.  Folded into the checksum for this func code, most
    -- significant bit first.
    procedure absorb(fi : natural; got : std_logic_vector) is
      variable h  : natural := hsum(fi);
      variable ok : boolean := true;
    begin
      for k in got'range loop
        if got(k) /= '0' and got(k) /= '1' then
          ok := false;
        end if;
        h := roll(h, got(k));
      end loop;
      hsum(fi)    := h;
      phase_count := phase_count + 1;
      -- A checksum folds 'U' or 'X' in as if it were 0, so metavalues
      -- have to be caught here rather than left to the comparison.
      if not ok then
        phase_errors := phase_errors + 1;
        if reports < MAX_REPORTS then
          reports := reports + 1;
          report "R = " & to_bin(got) & " is not all 0 or 1, on func=" &
                 to_bin(std_logic_vector(to_unsigned(fi, 4))) severity warning;
        end if;
      end if;
    end procedure absorb;

    procedure verify_sums(expect : hash_array; name : string) is
      variable fv : std_logic_vector(3 downto 0);
    begin
      for fi in 0 to 15 loop
        if hsum(fi) /= expect(fi) then
          fv := std_logic_vector(to_unsigned(fi, 4));
          phase_errors := phase_errors + 1;
          report name & " CHECKSUM MISMATCH for func=" & to_bin(fv) & " " &
                 mnemonic(fv) & ": expected " & integer'image(expect(fi)) &
                 ", got " & integer'image(hsum(fi)) &
                 ".  Phase 1 reports this class of bug with operands."
            severity warning;
        end if;
      end loop;
    end procedure verify_sums;

    procedure random_slv(result : out std_logic_vector) is
    begin
      rng := rng xor shift_left(rng, 13);
      rng := rng xor shift_right(rng, 17);
      rng := rng xor shift_left(rng, 5);
      result := std_logic_vector(resize(rng, result'length));
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
          check_p1(a4, b4, func, r4);
        end loop;
      end loop;
    end loop;
    end_phase("Phase 1: XLEN=4, exhaustive", 4096);

    -------------------------------------------------------------------------
    -- Phase 2: XLEN = 8, exhaustive
    -------------------------------------------------------------------------
    start_phase("Phase 2: XLEN=8, exhaustive");
    for f in 0 to 15 loop
      func <= std_logic_vector(to_unsigned(f, 4));
      print("  func " & to_bin(std_logic_vector(to_unsigned(f, 4))) & " " &
            mnemonic(std_logic_vector(to_unsigned(f, 4))));
      for i in 0 to (256 / STRIDE8) - 1 loop
        a8 <= std_logic_vector(to_unsigned(i * STRIDE8, 8));
        for j in 0 to (256 / STRIDE8) - 1 loop
          b8 <= std_logic_vector(to_unsigned(j * STRIDE8, 8));
          wait for 1 ns;
          absorb(f, r8);
        end loop;
      end loop;
    end loop;
    verify_sums(PHASE2_SUMS, "Phase 2");
    end_phase("Phase 2: XLEN=8, exhaustive", 1048576);

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
          absorb(f, r32);
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
        absorb(f, r32);
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
          absorb(f, r32);
        end loop;
      end loop;
    end loop;

    verify_sums(PHASE3_SUMS, "Phase 3");
    end_phase("Phase 3: XLEN=32, corner and random", 46592);

    -------------------------------------------------------------------------
    -- Summary
    -------------------------------------------------------------------------
    print("=== Summary ===");
    if total_errors = 0 then
      print("ALL TESTS PASSED");
    else
      report integer'image(total_errors) & " total errors" severity warning;
    end if;

    assert total_errors = 0
      report "ALU TESTBENCH FAILED" severity failure;

    wait;
  end process stimulus;

end architecture sim;
