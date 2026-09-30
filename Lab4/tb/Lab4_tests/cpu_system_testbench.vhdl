--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- CENG 442 Lab 4                                          cpu_system_testbench
--
-- Runs a test program on your block design: the clocking wizard, the reset
-- block, your CPU, the SmartConnect, the AXI BRAM controller and the block
-- memory, exactly as they go onto the board.  Nothing here needs filling in,
-- provided the block design follows the handout:
--
--   the block design is named cpu_system, so its wrapper is
--   cpu_system_wrapper, and it has exactly four external ports:
--
--     sys_clock  in   the board's 100 MHz clock, into the clocking wizard
--     reset      in   the CPU RESET button, active low
--     DBGsel     in   5 bits, straight through to the datapath
--     DBGreg     out  16 bits, the low half of the datapath's DBGreg
--
-- Connection automation names sys_clock and reset for you.  Vivado names the
-- other two after the pin they came from, with _0 on the end.  Rename them
-- in the block design, or this will not elaborate.
--
-- The clocking wizard takes some microseconds to lock, and the reset block
-- holds the core in reset until it does, so nothing happens for the first
-- few thousand clock cycles.  That is normal.
--
-- The program is whatever the block memory was initialised with.  There is
-- no file to name here: to run a different program, point the Block Memory
-- Generator at a different .coe, regenerate the output products, and run
-- again.  PROGRAM is only the name this testbench prints.
--
-- It must run in Vivado's simulator.  The BRAM controller and the block
-- memory are Xilinx IP, and GHDL cannot simulate them.  Use the GHDL
-- template, cpu_testbench_template, for quick turnarounds while the core
-- is still being debugged.
--
-- How the test programs report
-- ----------------------------
--     x4 = 1              the program passed
--     x4 = 0, x3 = n      check n failed
--     x4 = 0, x3 = 0      the core never reached the end
--
-- The Cylon eye
-- -------------
-- Initialise the block memory from cylon_sim.coe, not cylon.coe, and set
-- CYLON to true.  The watcher then reads a0 and checks that it walks one bit
-- left from 0001 to 8000 and back again.  cylon.coe has a delay long
-- enough to see by eye, which is tens of millions of clock cycles per
-- sweep: that one is for the board.
--
-- Cycle counts in the report are cycles of sys_clock, at 100 MHz.  The core
-- runs at 50 MHz, so it has had half as many.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity cpu_system_testbench is
  generic (
    -- The program the block memory holds.  Only used in the report.
    PROGRAM   : string  := "t1_regs";
    -- true for cylon_sim.coe: check the sweep instead of x3 and x4.
    CYLON     : boolean := false;
    -- Give up after this many cycles of sys_clock.
    TIMEOUT   : integer := 400000
    );
end cpu_system_testbench;

architecture behavioral of cpu_system_testbench is

  constant HALF_PERIOD : time := 5 ns;    -- 100 MHz, the board's clock

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';        -- the CPU RESET button, active low

  signal DBGsel : std_logic_vector(4 downto 0) := (others => '0');
  signal DBGreg : std_logic_vector(15 downto 0);

  signal done : boolean := false;

begin

  clock : process is
  begin
    while not done loop
      clk <= '0';
      wait for HALF_PERIOD;
      clk <= '1';
      wait for HALF_PERIOD;
    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- The block design.
  ------------------------------------------------------------------------------
  SYSTEM : entity work.cpu_system_wrapper
    port map (
      sys_clock => clk,
      reset     => resetn,
      DBGsel    => DBGsel,
      DBGreg    => DBGreg);

  ------------------------------------------------------------------------------
  -- The watcher.  Reads the register file through the debug port, and
  -- reports.
  ------------------------------------------------------------------------------
  watch : process is
    variable cycles : natural := 0;
    variable x4, x3 : std_logic_vector(15 downto 0);
    variable a0     : std_logic_vector(15 downto 0);
    variable expect : std_logic_vector(15 downto 0);
    variable moves  : natural := 0;
    variable going_left : boolean := true;
    variable bad    : boolean := false;
  begin
    resetn <= '0';
    for i in 1 to 20 loop
      wait until rising_edge(clk);
    end loop;
    resetn <= '1';
    report "running " & PROGRAM severity note;

    if CYLON then
      DBGsel <= "01010";                  -- x10, which is a0
    else
      DBGsel <= "00100";                  -- x4, the pass flag
    end if;
    -- Wait for the clocking wizard to lock and the reset block to let the
    -- core go.  Until then the register file may not be driven at all.
    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when not is_x(DBGreg) or cycles >= TIMEOUT;
    end loop;
    if is_x(DBGreg) then
      done <= true;
      report "DBGreg is undriven.  Check that DBGsel and DBGreg are " &
        "external ports of the block design, wired straight through to " &
        "the datapath: this testbench reads the program's result " &
        "through them."
        severity failure;
    end if;

    if CYLON then
      -- Wait for a0 to become 1, then follow it.  Every change must be one
      -- position in the current direction.  Pass after a full sweep out to
      -- 8000 and back to 0001: thirty moves.
      loop
        wait until rising_edge(clk);
        cycles := cycles + 1;
        exit when DBGreg = x"0001" or cycles >= TIMEOUT;
      end loop;
      a0 := DBGreg;
      while moves < 30 and cycles < TIMEOUT and not bad loop
        wait until rising_edge(clk);
        cycles := cycles + 1;
        if DBGreg /= a0 then
          if going_left then
            expect := a0(14 downto 0) & '0';
          else
            expect := '0' & a0(15 downto 1);
          end if;
          if DBGreg = expect then
            a0 := DBGreg;
            moves := moves + 1;
            if a0 = x"8000" then
              going_left := false;
            end if;
          else
            bad := true;
            report "a0 went from " & to_hstring(a0) & " to " &
              to_hstring(DBGreg) & ", expected " & to_hstring(expect)
              severity error;
          end if;
        end if;
      end loop;
      done <= true;
      if moves = 30 then
        report PROGRAM & " swept out and back correctly in " &
          integer'image(cycles) & " clock cycles" severity note;
      elsif bad then
        report PROGRAM & " FAILED: a0 did not move one LED at a time"
          severity failure;
      else
        report PROGRAM & " FAILED: a0 made only " & integer'image(moves) &
          " of 30 moves in " & integer'image(cycles) & " cycles.  Initialise " &
          "the block memory from cylon_sim.coe, not cylon.coe, or raise TIMEOUT"
          severity failure;
      end if;
      wait;
    end if;

    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when DBGreg = x"0001" or cycles >= TIMEOUT;
    end loop;
    x4 := DBGreg;

    DBGsel <= "00011";                    -- x3, the check number
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    x3 := DBGreg;

    done <= true;
    if x4 = x"0001" then
      report PROGRAM & " PASSED after " & integer'image(cycles) &
        " clock cycles" severity note;
    elsif is_x(x3) or is_x(x4) then
      report PROGRAM & " left x3 or x4 undefined.  Something in the core " &
        "is driving the register file with metavalues" severity failure;
    elsif to_integer(unsigned(x3)) /= 0 then
      report PROGRAM & " FAILED at check " &
        integer'image(to_integer(unsigned(x3))) &
        ".  The check number is in a comment in the .S file."
        severity failure;
    else
      report PROGRAM & " never finished: x3 and x4 are both zero after " &
        integer'image(cycles) & " cycles.  The core is stuck.  Look at the " &
        "fetch unit's ready and the address it is fetching from: a core " &
        "that is stuck is almost always waiting on a handshake that never " &
        "completes, or fetching from the wrong address after reset."
        severity failure;
    end if;
    wait;
  end process;

end behavioral;
