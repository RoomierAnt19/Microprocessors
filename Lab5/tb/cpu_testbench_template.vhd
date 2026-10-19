--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- CENG 442 Lab 5                                        cpu_testbench_template
--
-- A harness for running the test programs against your core.  It
-- instantiates cpu_core, whose entity has not changed since Lab 4, with the
-- instruction port, m_axi_*_i, on a ROM at 00000000 holding the program and
-- the data port, m_axi_*_d, on a RAM at 10000000.  A watcher reads the
-- result out of the register file and prints one line saying whether the
-- program passed.  The signal names follow the convention that the
-- instruction side is i_ and the data side is d_.
--
-- One thing may need filling in, and it is marked FILL IN below: how the
-- data port reaches the read only data that t4_load reads from ROM.
--
-- How the test programs report
-- ----------------------------
-- Every program leaves its verdict in two registers and then parks in a
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
-- Run the Lab 4 programs first: t1_regs, t2_branch and t3_jump.  They do
-- not load or store, so a failure in one of them means the new wiring broke
-- something that used to work.  Then t4_load and t5_store.
--
-- Run the simulation from the directory that holds the .hex files, because
-- that is what the PROGRAM generic names.  Pass a different program with
-- -gPROGRAM=t2_branch.hex on the ghdl -r command line, or set it in Vivado's
-- simulation settings.
--
-- Start with MAX_STALL at 0 on both memories, so the memory answers as fast
-- as the bus allows.  Once the program passes, raise it to 3 and run again.
-- A core with a handshake bug often passes against instant memory and fails
-- against slow memory, and the DDR on the board in Lab 6 is very slow.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity cpu_testbench_template is
  generic (
    -- Which program to run.  Build it with make first.
    PROGRAM   : string  := "t4_load.hex";
    -- 0 makes the memories answer as fast as the bus allows.  Raise it
    -- once the program passes.
    MAX_STALL : integer := 0;
    -- Give up after this many clock cycles.
    TIMEOUT   : integer := 200000
    );
end cpu_testbench_template;

architecture behavioral of cpu_testbench_template is

  constant HALF_PERIOD : time := 5 ns;

  signal clk     : std_logic := '0';
  signal reset   : std_logic := '1';       -- active high, as the core wants
  signal aresetn : std_logic;              -- active low, as the memories want

  signal DBGsel : std_logic_vector(4 downto 0) := (others => '0');
  signal DBGreg : std_logic_vector(31 downto 0);

  -- Instruction side, from the fetch unit
  signal i_awid, i_bid, i_arid, i_rid       : std_logic_vector(0 downto 0);
  signal i_awaddr, i_araddr                 : std_logic_vector(31 downto 0);
  signal i_wdata, i_rdata                   : std_logic_vector(31 downto 0);
  signal i_awlen, i_arlen                   : std_logic_vector(7 downto 0);
  signal i_awsize, i_arsize                 : std_logic_vector(2 downto 0);
  signal i_awburst, i_arburst               : std_logic_vector(1 downto 0);
  signal i_bresp, i_rresp                   : std_logic_vector(1 downto 0);
  signal i_awcache, i_arcache, i_wstrb      : std_logic_vector(3 downto 0);
  signal i_awqos, i_arqos                   : std_logic_vector(3 downto 0);
  signal i_awprot, i_arprot                 : std_logic_vector(2 downto 0);
  signal i_awlock, i_arlock, i_wlast, i_rlast : std_logic;
  signal i_awvalid, i_awready, i_wvalid, i_wready : std_logic;
  signal i_bvalid, i_bready                 : std_logic;
  signal i_arvalid, i_arready, i_rvalid, i_rready : std_logic;

  -- Data side, from the load/store unit
  signal d_awid, d_bid, d_arid, d_rid       : std_logic_vector(0 downto 0);
  signal d_awaddr, d_araddr                 : std_logic_vector(31 downto 0);
  signal d_wdata, d_rdata                   : std_logic_vector(31 downto 0);
  signal d_awlen, d_arlen                   : std_logic_vector(7 downto 0);
  signal d_awsize, d_arsize                 : std_logic_vector(2 downto 0);
  signal d_awburst, d_arburst               : std_logic_vector(1 downto 0);
  signal d_bresp, d_rresp                   : std_logic_vector(1 downto 0);
  signal d_awcache, d_arcache, d_wstrb      : std_logic_vector(3 downto 0);
  signal d_awqos, d_arqos                   : std_logic_vector(3 downto 0);
  signal d_awprot, d_arprot                 : std_logic_vector(2 downto 0);
  signal d_awlock, d_arlock, d_wlast, d_rlast : std_logic;
  signal d_awvalid, d_awready, d_wvalid, d_wready : std_logic;
  signal d_bvalid, d_bready                 : std_logic;
  signal d_arvalid, d_arready, d_rvalid, d_rready : std_logic;

  signal done : boolean := false;

begin

  aresetn <= not reset;

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
  -- Your CPU.
  ------------------------------------------------------------------------------
  CPU : entity work.cpu_core
    port map (
      clk    => clk,
      rst    => reset,
      DBGsel => DBGsel,
      DBGreg => DBGreg,
      m_axi_awid_i    => i_awid,
      m_axi_awaddr_i  => i_awaddr,
      m_axi_awlen_i   => i_awlen,
      m_axi_awsize_i  => i_awsize,
      m_axi_awburst_i => i_awburst,
      m_axi_awlock_i  => i_awlock,
      m_axi_awcache_i => i_awcache,
      m_axi_awprot_i  => i_awprot,
      m_axi_awqos_i   => i_awqos,
      m_axi_awvalid_i => i_awvalid,
      m_axi_awready_i => i_awready,
      m_axi_wdata_i   => i_wdata,
      m_axi_wstrb_i   => i_wstrb,
      m_axi_wlast_i   => i_wlast,
      m_axi_wvalid_i  => i_wvalid,
      m_axi_wready_i  => i_wready,
      m_axi_bid_i     => i_bid,
      m_axi_bresp_i   => i_bresp,
      m_axi_bvalid_i  => i_bvalid,
      m_axi_bready_i  => i_bready,
      m_axi_arid_i    => i_arid,
      m_axi_araddr_i  => i_araddr,
      m_axi_arlen_i   => i_arlen,
      m_axi_arsize_i  => i_arsize,
      m_axi_arburst_i => i_arburst,
      m_axi_arlock_i  => i_arlock,
      m_axi_arcache_i => i_arcache,
      m_axi_arprot_i  => i_arprot,
      m_axi_arqos_i   => i_arqos,
      m_axi_arvalid_i => i_arvalid,
      m_axi_arready_i => i_arready,
      m_axi_rid_i     => i_rid,
      m_axi_rdata_i   => i_rdata,
      m_axi_rresp_i   => i_rresp,
      m_axi_rlast_i   => i_rlast,
      m_axi_rvalid_i  => i_rvalid,
      m_axi_rready_i  => i_rready,
      m_axi_awid_d    => d_awid,
      m_axi_awaddr_d  => d_awaddr,
      m_axi_awlen_d   => d_awlen,
      m_axi_awsize_d  => d_awsize,
      m_axi_awburst_d => d_awburst,
      m_axi_awlock_d  => d_awlock,
      m_axi_awcache_d => d_awcache,
      m_axi_awprot_d  => d_awprot,
      m_axi_awqos_d   => d_awqos,
      m_axi_awvalid_d => d_awvalid,
      m_axi_awready_d => d_awready,
      m_axi_wdata_d   => d_wdata,
      m_axi_wstrb_d   => d_wstrb,
      m_axi_wlast_d   => d_wlast,
      m_axi_wvalid_d  => d_wvalid,
      m_axi_wready_d  => d_wready,
      m_axi_bid_d     => d_bid,
      m_axi_bresp_d   => d_bresp,
      m_axi_bvalid_d  => d_bvalid,
      m_axi_bready_d  => d_bready,
      m_axi_arid_d    => d_arid,
      m_axi_araddr_d  => d_araddr,
      m_axi_arlen_d   => d_arlen,
      m_axi_arsize_d  => d_arsize,
      m_axi_arburst_d => d_arburst,
      m_axi_arlock_d  => d_arlock,
      m_axi_arcache_d => d_arcache,
      m_axi_arprot_d  => d_arprot,
      m_axi_arqos_d   => d_arqos,
      m_axi_arvalid_d => d_arvalid,
      m_axi_arready_d => d_arready,
      m_axi_rid_d     => d_rid,
      m_axi_rdata_d   => d_rdata,
      m_axi_rresp_d   => d_rresp,
      m_axi_rlast_d   => d_rlast,
      m_axi_rvalid_d  => d_rvalid,
      m_axi_rready_d  => d_rready);

  ------------------------------------------------------------------------------
  -- ROM at 00000000.  The program lives here, and so does any read only data
  -- it loads.  It is marked read only, so a core that stores into its own
  -- program says so instead of quietly corrupting itself.
  ------------------------------------------------------------------------------
  ROM : entity work.axi_memory(sim)
    generic map (MEM_SIZE_BYTES => 8192,
                 BASE_ADDR      => x"00000000",
                 INIT_FILE      => PROGRAM,
                 READ_ONLY      => true,
                 MAX_STALL      => MAX_STALL,
                 NAME           => "ROM")
    port map (
      clk => clk, aresetn => aresetn,
      s_axi_awid    => i_awid,    s_axi_awaddr  => i_awaddr,
      s_axi_awlen   => i_awlen,   s_axi_awsize  => i_awsize,
      s_axi_awburst => i_awburst, s_axi_awvalid => i_awvalid,
      s_axi_awready => i_awready,
      s_axi_wdata   => i_wdata,   s_axi_wstrb   => i_wstrb,
      s_axi_wlast   => i_wlast,   s_axi_wvalid  => i_wvalid,
      s_axi_wready  => i_wready,
      s_axi_bid     => i_bid,     s_axi_bresp   => i_bresp,
      s_axi_bvalid  => i_bvalid,  s_axi_bready  => i_bready,
      s_axi_arid    => i_arid,    s_axi_araddr  => i_araddr,
      s_axi_arlen   => i_arlen,   s_axi_arsize  => i_arsize,
      s_axi_arburst => i_arburst, s_axi_arvalid => i_arvalid,
      s_axi_arready => i_arready,
      s_axi_rid     => i_rid,     s_axi_rdata   => i_rdata,
      s_axi_rresp   => i_rresp,   s_axi_rlast   => i_rlast,
      s_axi_rvalid  => i_rvalid,  s_axi_rready  => i_rready);

  ------------------------------------------------------------------------------
  -- RAM at 10000000.  Uninitialised, which is why the test programs write
  -- before they read.
  ------------------------------------------------------------------------------
  RAM : entity work.axi_memory(sim)
    generic map (MEM_SIZE_BYTES => 8192,
                 BASE_ADDR      => x"10000000",
                 INIT_FILE      => "",
                 READ_ONLY      => false,
                 MAX_STALL      => MAX_STALL,
                 NAME           => "RAM")
    port map (
      clk => clk, aresetn => aresetn,
      s_axi_awid    => d_awid,    s_axi_awaddr  => d_awaddr,
      s_axi_awlen   => d_awlen,   s_axi_awsize  => d_awsize,
      s_axi_awburst => d_awburst, s_axi_awvalid => d_awvalid,
      s_axi_awready => d_awready,
      s_axi_wdata   => d_wdata,   s_axi_wstrb   => d_wstrb,
      s_axi_wlast   => d_wlast,   s_axi_wvalid  => d_wvalid,
      s_axi_wready  => d_wready,
      s_axi_bid     => d_bid,     s_axi_bresp   => d_bresp,
      s_axi_bvalid  => d_bvalid,  s_axi_bready  => d_bready,
      s_axi_arid    => d_arid,    s_axi_araddr  => d_araddr,
      s_axi_arlen   => d_arlen,   s_axi_arsize  => d_arsize,
      s_axi_arburst => d_arburst, s_axi_arvalid => d_arvalid,
      s_axi_arready => d_arready,
      s_axi_rid     => d_rid,     s_axi_rdata   => d_rdata,
      s_axi_rresp   => d_rresp,   s_axi_rlast   => d_rlast,
      s_axi_rvalid  => d_rvalid,  s_axi_rready  => d_rready);

  ------------------------------------------------------------------------------
  -- FILL IN, if your data memory is not reachable from the instruction
  -- side.  The test programs load from .rodata, which the linker puts in ROM,
  -- so t4_load reads from the ROM through the load/store unit.  On the FPGA
  -- in Lab 6 the SmartConnect gives both managers a path to both
  -- memories.  Here there is no interconnect, so if you want the data side
  -- to reach ROM as well you have a choice: link the test data into RAM and
  -- write it there first, or put a small address decoder between the data
  -- side and the two memories.  The simplest thing that works is to run
  -- t4_load with the data side wired to the ROM instead of the RAM, since
  -- that program never stores.
  ------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  -- The watcher.  Polls x4 through the debug port, and reports.
  ------------------------------------------------------------------------------
  watch : process is
    variable cycles : natural := 0;
    variable x4, x3 : std_logic_vector(31 downto 0);
  begin
    reset <= '1';
    for i in 1 to 8 loop
      wait until rising_edge(clk);
    end loop;
    reset <= '0';
    report "running " & PROGRAM severity note;

    DBGsel <= "00100";                    -- x4, the pass flag
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    if is_x(DBGreg) then
      done <= true;
      report "DBGreg is undriven.  Connect your datapath's DBGsel and " &
        "DBGreg to the ports of the same name in cpu_core: " &
        "this testbench reads the test program's result through them."
        severity failure;
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
