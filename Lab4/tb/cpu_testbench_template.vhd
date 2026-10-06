--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- CENG 442 Lab 4                                        cpu_testbench_template
--
-- A harness for running the test programs against your core in GHDL, before
-- you build the block design.  Nothing needs filling in: it instantiates
-- cpu_core, whose entity is published in the skeleton, and it has the clock,
-- the reset, a ROM at 00000000 holding the program, and a watcher that reads
-- the result out of the register file and prints one line saying whether the
-- program passed.
--
-- The instruction port, m_axi_*_i, goes to the ROM.  The data port,
-- m_axi_*_d, is tied off inside the Lab 4 core, so its outputs are left open
-- here and its inputs are held at zero.  None of the programs load or store,
-- so one memory is all the core needs.
--
-- How the test programs report
-- ----------------------------
-- Every test program leaves its verdict in two registers and then parks in a
-- one instruction loop:
--
--     x4 = 1              the program passed
--     x4 = 0, x3 = n      check n failed
--     x4 = 0, x3 = 0      the core never reached the end
--
-- This testbench polls x4 through the debug port and stops as soon as it
-- turns 1, so a passing run finishes quickly.  A failing run times out and
-- prints x3, which names the check.  The number is in a comment beside that
-- check in the .S file.
--
-- Run them in order: t1_regs, t2_branch, t3_jump.  Pass a different program
-- with -gPROGRAM=t2_branch.hex on the ghdl -r command line, or set it in
-- Vivado's simulation settings.  Run the simulation from the directory that
-- holds the .hex files, because that is what the PROGRAM generic names.
--
-- The Cylon eye
-- -------------
-- cylon_sim.hex does not report a verdict.  It never stops.  Run it with
-- -gCYLON=true and the watcher instead reads a0 and checks that it walks one
-- bit left from 00000001 to 00008000 and back again, one position at a time.
-- That is what the LEDs will do on the board.
--
-- Start with MAX_STALL at 0, so the memory answers as fast as the bus
-- allows.  Once the program passes, raise it to 3 and run again.  A core with
-- a handshake bug often passes against instant memory and fails against slow
-- memory.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity cpu_testbench_template is
  generic (
    -- Which program to run.  Build it with make first.
    PROGRAM   : string  := "t1_regs.hex";
    -- true for cylon_sim.hex: check the sweep instead of x3 and x4.
    CYLON     : boolean := false;
    -- 0 makes the memory answer as fast as the bus allows.  Raise it once
    -- the program passes.
    MAX_STALL : integer := 0;
    -- Give up after this many clock cycles.
    TIMEOUT   : integer := 200000
    );
end cpu_testbench_template;

architecture behavioral of cpu_testbench_template is

  constant HALF_PERIOD : time := 5 ns;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';        -- active high, as the core wants
  signal resetn : std_logic;               -- active low, as the memory wants

  signal DBGsel : std_logic_vector(4 downto 0) := (others => '0');
  signal DBGreg : std_logic_vector(31 downto 0);

  -- The instruction port, from the fetch unit
  signal awid, bid, arid, rid       : std_logic_vector(0 downto 0);
  signal awaddr, araddr             : std_logic_vector(31 downto 0);
  signal wdata, rdata               : std_logic_vector(31 downto 0);
  signal awlen, arlen               : std_logic_vector(7 downto 0);
  signal awsize, arsize             : std_logic_vector(2 downto 0);
  signal awburst, arburst           : std_logic_vector(1 downto 0);
  signal bresp, rresp               : std_logic_vector(1 downto 0);
  signal awcache, arcache, wstrb    : std_logic_vector(3 downto 0);
  signal awqos, arqos               : std_logic_vector(3 downto 0);
  signal awprot, arprot             : std_logic_vector(2 downto 0);
  signal awlock, arlock, wlast, rlast : std_logic;
  signal awvalid, awready, wvalid, wready : std_logic;
  signal bvalid, bready             : std_logic;
  signal arvalid, arready, rvalid, rready : std_logic;

  signal done : boolean := false;

begin

  resetn <= not rst;

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
  -- Your CPU.  The data port's outputs are open and its inputs are zero.
  ------------------------------------------------------------------------------
  CPU : entity work.cpu_core
    port map (
      clk    => clk,
      rst    => rst,
      DBGsel => DBGsel,
      DBGreg => DBGreg,
      m_axi_awid_i    => awid,    m_axi_awaddr_i  => awaddr,
      m_axi_awlen_i   => awlen,   m_axi_awsize_i  => awsize,
      m_axi_awburst_i => awburst, m_axi_awlock_i  => awlock,
      m_axi_awcache_i => awcache, m_axi_awprot_i  => awprot,
      m_axi_awqos_i   => awqos,   m_axi_awvalid_i => awvalid,
      m_axi_awready_i => awready,
      m_axi_wdata_i   => wdata,   m_axi_wstrb_i   => wstrb,
      m_axi_wlast_i   => wlast,   m_axi_wvalid_i  => wvalid,
      m_axi_wready_i  => wready,
      m_axi_bid_i     => bid,     m_axi_bresp_i   => bresp,
      m_axi_bvalid_i  => bvalid,  m_axi_bready_i  => bready,
      m_axi_arid_i    => arid,    m_axi_araddr_i  => araddr,
      m_axi_arlen_i   => arlen,   m_axi_arsize_i  => arsize,
      m_axi_arburst_i => arburst, m_axi_arlock_i  => arlock,
      m_axi_arcache_i => arcache, m_axi_arprot_i  => arprot,
      m_axi_arqos_i   => arqos,   m_axi_arvalid_i => arvalid,
      m_axi_arready_i => arready,
      m_axi_rid_i     => rid,     m_axi_rdata_i   => rdata,
      m_axi_rresp_i   => rresp,   m_axi_rlast_i   => rlast,
      m_axi_rvalid_i  => rvalid,  m_axi_rready_i  => rready,
      m_axi_awid_d    => open,    m_axi_awaddr_d  => open,
      m_axi_awlen_d   => open,    m_axi_awsize_d  => open,
      m_axi_awburst_d => open,    m_axi_awlock_d  => open,
      m_axi_awcache_d => open,    m_axi_awprot_d  => open,
      m_axi_awqos_d   => open,    m_axi_awvalid_d => open,
      m_axi_awready_d => '0',
      m_axi_wdata_d   => open,    m_axi_wstrb_d   => open,
      m_axi_wlast_d   => open,    m_axi_wvalid_d  => open,
      m_axi_wready_d  => '0',
      m_axi_bid_d     => "0",     m_axi_bresp_d   => "00",
      m_axi_bvalid_d  => '0',     m_axi_bready_d  => open,
      m_axi_arid_d    => open,    m_axi_araddr_d  => open,
      m_axi_arlen_d   => open,    m_axi_arsize_d  => open,
      m_axi_arburst_d => open,    m_axi_arlock_d  => open,
      m_axi_arcache_d => open,    m_axi_arprot_d  => open,
      m_axi_arqos_d   => open,    m_axi_arvalid_d => open,
      m_axi_arready_d => '0',
      m_axi_rid_d     => "0",     m_axi_rdata_d   => (others => '0'),
      m_axi_rresp_d   => "00",    m_axi_rlast_d   => '0',
      m_axi_rvalid_d  => '0',     m_axi_rready_d  => open);

  ------------------------------------------------------------------------------
  -- ROM at 00000000, holding the program.  It is marked read only, so a core
  -- that writes to its own program says so instead of quietly corrupting
  -- itself.  The Lab 4 core has no way to write at all, so a complaint here
  -- means the fetch unit's write side is not tied off.
  ------------------------------------------------------------------------------
  ROM : entity work.axi_memory(sim)
    generic map (MEM_SIZE_BYTES => 8192,
                 BASE_ADDR      => x"00000000",
                 INIT_FILE      => PROGRAM,
                 READ_ONLY      => true,
                 MAX_STALL      => MAX_STALL,
                 NAME           => "ROM")
    port map (
      clk => clk, aresetn => resetn,
      s_axi_awid    => awid,    s_axi_awaddr  => awaddr,
      s_axi_awlen   => awlen,   s_axi_awsize  => awsize,
      s_axi_awburst => awburst, s_axi_awvalid => awvalid,
      s_axi_awready => awready,
      s_axi_wdata   => wdata,   s_axi_wstrb   => wstrb,
      s_axi_wlast   => wlast,   s_axi_wvalid  => wvalid,
      s_axi_wready  => wready,
      s_axi_bid     => bid,     s_axi_bresp   => bresp,
      s_axi_bvalid  => bvalid,  s_axi_bready  => bready,
      s_axi_arid    => arid,    s_axi_araddr  => araddr,
      s_axi_arlen   => arlen,   s_axi_arsize  => arsize,
      s_axi_arburst => arburst, s_axi_arvalid => arvalid,
      s_axi_arready => arready,
      s_axi_rid     => rid,     s_axi_rdata   => rdata,
      s_axi_rresp   => rresp,   s_axi_rlast   => rlast,
      s_axi_rvalid  => rvalid,  s_axi_rready  => rready);

  ------------------------------------------------------------------------------
  -- The watcher.  Reads the register file through the debug port, and
  -- reports.
  ------------------------------------------------------------------------------
  watch : process is
    variable cycles : natural := 0;
    variable x4, x3 : std_logic_vector(31 downto 0);
    variable a0     : std_logic_vector(31 downto 0);
    variable expect : std_logic_vector(31 downto 0);
    variable moves  : natural := 0;
    variable going_left : boolean := true;
    variable bad    : boolean := false;
  begin
    rst <= '1';
    for i in 1 to 20 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    report "running " & PROGRAM severity note;

    if CYLON then
      DBGsel <= "01010";                  -- x10, which is a0
    else
      DBGsel <= "00100";                  -- x4, the pass flag
    end if;
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    if is_x(DBGreg) then
      done <= true;
      report "DBGreg is undriven.  Connect your datapath's DBGsel and " &
        "DBGreg to the ports of the same name in cpu_core: this " &
        "testbench reads the program's result through them."
        severity failure;
    end if;

    if CYLON then
      -- Wait for a0 to become 1, then follow it.  Every change must be one
      -- position in the current direction.  Pass after a full sweep out to
      -- 00008000 and back to 00000001: thirty moves.
      loop
        wait until rising_edge(clk);
        cycles := cycles + 1;
        exit when DBGreg = x"00000001" or cycles >= TIMEOUT;
      end loop;
      a0 := DBGreg;
      while moves < 30 and cycles < TIMEOUT and not bad loop
        wait until rising_edge(clk);
        cycles := cycles + 1;
        if DBGreg /= a0 then
          if going_left then
            expect := a0(30 downto 0) & '0';
          else
            expect := '0' & a0(31 downto 1);
          end if;
          if DBGreg = expect then
            a0 := DBGreg;
            moves := moves + 1;
            if a0 = x"00008000" then
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
          " of 30 moves in " & integer'image(cycles) & " cycles.  Build " &
          "cylon_sim, not cylon, or raise TIMEOUT"
          severity failure;
      end if;
      wait;
    end if;

    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when DBGreg = x"00000001" or cycles >= TIMEOUT;
    end loop;
    x4 := DBGreg;

    DBGsel <= "00011";                    -- x3, the check number
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    x3 := DBGreg;

    done <= true;
    if x4 = x"00000001" then
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
