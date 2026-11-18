--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- CENG 442 Lab 6                                                machine_timer
--
-- The RISC-V machine timer, mtime and mtimecmp, as an AXI4-Lite subordinate.
--
--   offset 0   mtime, low word
--   offset 4   mtime, high word
--   offset 8   mtimecmp, low word
--   offset C   mtimecmp, high word
--
-- mtime counts up by one every clock.  mtimecmp resets to all ones, so
-- nothing is pending out of reset.  mtip is high whenever mtime >= mtimecmp,
-- compared as unsigned 64-bit numbers, and stays high until software writes
-- a later time to mtimecmp.  It is registered, so it rises one clock after
-- the comparison becomes true.
--
-- A write replaces the whole word: WSTRB is ignored, because the core only
-- ever stores words here.  Writing one half of mtime leaves the other half
-- alone for that cycle, so a carry out of the low half is lost if it
-- happens on the same edge.  Software that cares writes the low half to
-- zero first.
--
-- Reading mtime takes two loads, and the low half can wrap between them.
-- The usual fix is in software: read high, low, high, and retry if the two
-- highs differ.  The test programs only ever compare against a time a few
-- thousand cycles away, so they read the low word alone.
--
-- Write side: AW and W are taken independently, in either order, because
-- an AXI4 manager may present them in either order (the Lab 5 write engine
-- raises both at once, but takes their handshakes separately).  The
-- registers are written on the edge that takes the response, when both
-- address and data are known to be held.
--
--   W_IDLE     AWREADY and WREADY high.
--              both taken                                   -> W_RESP
--              only AW taken                                -> W_GOT_AW
--              only W taken                                 -> W_GOT_W
--   W_GOT_AW   WREADY high.  W taken                        -> W_RESP
--   W_GOT_W    AWREADY high.  AW taken                      -> W_RESP
--   W_RESP     BVALID high.  BREADY = '1' / write           -> W_IDLE
--
-- Read side:
--
--   R_IDLE     ARREADY high.  AR taken / capture RDATA      -> R_DATA
--   R_DATA     RVALID high.  RREADY = '1'                   -> R_IDLE
--
-- Design rules: no process statements; registers are generic_register
-- instances; each state machine follows the state_q / state_next /
-- state_next_i template with per-state next-state signals.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity machine_timer is
  generic (
    ADDR_WIDTH : integer := 12
    );
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;   -- synchronous, active high
    mtip : out std_logic;   -- machine timer interrupt pending

    s_axi_awaddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    s_axi_awprot  : in  std_logic_vector(2 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    s_axi_arprot  : in  std_logic_vector(2 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic
    );

  -- Tell the block design that rst is an active-high reset.  Without
  -- this, Vivado assumes active low and draws rst with a bubble.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO of rst : signal is "xilinx.com:signal:reset:1.0 rst RST";
  attribute X_INTERFACE_PARAMETER of rst : signal is "POLARITY ACTIVE_HIGH";
end machine_timer;

architecture behavioral of machine_timer is
  type wstate_t is (W_IDLE, W_GOT_AW, W_GOT_W, W_RESP);
  type rstate_t is (R_IDLE, R_DATA);
  constant W_INIT : wstate_t := W_IDLE;
  constant R_INIT : rstate_t := R_IDLE;

  signal wstate_q, wstate_next, wstate_next_i : wstate_t;
  signal W_IDLE_next, W_GOT_AW_next, W_GOT_W_next, W_RESP_next : wstate_t;
  signal rstate_q, rstate_next, rstate_next_i : rstate_t;
  signal R_IDLE_next, R_DATA_next : rstate_t;

  signal in_W_IDLE, in_W_GOT_AW, in_W_GOT_W, in_W_RESP : std_logic;
  signal in_R_IDLE, in_R_DATA : std_logic;

  signal awready_i, wready_i, aw_take, w_take, ar_take : std_logic;
  signal w_idle_sel : std_logic_vector(1 downto 0);
  signal do_write : std_logic;

  signal awaddr_q, araddr_word : std_logic_vector(1 downto 0);
  signal wdata_q : std_logic_vector(31 downto 0);
  signal rdata_d : std_logic_vector(31 downto 0);

  signal mtime_lo, mtime_hi, mtime_lo_d, mtime_hi_d : std_logic_vector(31 downto 0);
  signal mtime_inc : std_logic_vector(63 downto 0);
  signal cmp_lo, cmp_hi, cmp_lo_d, cmp_hi_d : std_logic_vector(31 downto 0);
  signal cmp_lo_en, cmp_hi_en : std_logic;
  signal wr_sel : std_logic_vector(2 downto 0);
  signal mtip_d, mtip_q : std_logic_vector(0 downto 0);
begin

  ------------------------------------------------------------------------------
  -- Write side state machine
  ------------------------------------------------------------------------------
  wstate_q <= wstate_next when rising_edge(clk);
  wstate_next <= W_INIT when rst = '1' else wstate_next_i;

  with wstate_q select wstate_next_i <=
    W_IDLE_next   when W_IDLE,
    W_GOT_AW_next when W_GOT_AW,
    W_GOT_W_next  when W_GOT_W,
    W_RESP_next   when W_RESP;

  w_idle_sel <= aw_take & w_take;
  with w_idle_sel select W_IDLE_next <=
    W_RESP   when "11",
    W_GOT_AW when "10",
    W_GOT_W  when "01",
    wstate_q when others;
  W_GOT_AW_next <= W_RESP when w_take = '1' else wstate_q;
  W_GOT_W_next  <= W_RESP when aw_take = '1' else wstate_q;
  W_RESP_next   <= W_IDLE when s_axi_bready = '1' else wstate_q;

  in_W_IDLE   <= '1' when wstate_q = W_IDLE   else '0';
  in_W_GOT_AW <= '1' when wstate_q = W_GOT_AW else '0';
  in_W_GOT_W  <= '1' when wstate_q = W_GOT_W  else '0';
  in_W_RESP   <= '1' when wstate_q = W_RESP   else '0';

  awready_i <= in_W_IDLE or in_W_GOT_W;
  wready_i  <= in_W_IDLE or in_W_GOT_AW;
  aw_take   <= s_axi_awvalid and awready_i;
  w_take    <= s_axi_wvalid and wready_i;
  do_write  <= in_W_RESP and s_axi_bready;

  s_axi_awready <= awready_i;
  s_axi_wready  <= wready_i;
  s_axi_bvalid  <= in_W_RESP;
  s_axi_bresp   <= "00";

  awaddr_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 2)
    port map(d => s_axi_awaddr(3 downto 2), q => awaddr_q,
             clk => clk, en => aw_take, rst => rst);

  wdata_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 32)
    port map(d => s_axi_wdata, q => wdata_q,
             clk => clk, en => w_take, rst => rst);

  ------------------------------------------------------------------------------
  -- Read side state machine
  ------------------------------------------------------------------------------
  rstate_q <= rstate_next when rising_edge(clk);
  rstate_next <= R_INIT when rst = '1' else rstate_next_i;

  with rstate_q select rstate_next_i <=
    R_IDLE_next when R_IDLE,
    R_DATA_next when R_DATA;

  R_IDLE_next <= R_DATA when s_axi_arvalid = '1' else rstate_q;
  R_DATA_next <= R_IDLE when s_axi_rready = '1' else rstate_q;

  in_R_IDLE <= '1' when rstate_q = R_IDLE else '0';
  in_R_DATA <= '1' when rstate_q = R_DATA else '0';

  ar_take <= s_axi_arvalid and in_R_IDLE;

  s_axi_arready <= in_R_IDLE;
  s_axi_rvalid  <= in_R_DATA;
  s_axi_rresp   <= "00";

  -- RDATA is captured on the edge that takes the address, so it holds still
  -- for as long as RVALID is up.
  rdata_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 32)
    port map(d => rdata_d, q => s_axi_rdata,
             clk => clk, en => ar_take, rst => rst);
  araddr_word <= s_axi_araddr(3 downto 2);
  with araddr_word select rdata_d <=
    mtime_lo when "00",
    mtime_hi when "01",
    cmp_lo   when "10",
    cmp_hi   when others;

  ------------------------------------------------------------------------------
  -- mtime: counts every clock, unless software is writing a half of it.
  ------------------------------------------------------------------------------
  wr_sel <= do_write & awaddr_q;

  mtime_lo_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 32)
    port map(d => mtime_lo_d, q => mtime_lo, clk => clk, en => '1', rst => rst);
  mtime_inc <= std_logic_vector(unsigned(mtime_hi & mtime_lo) + 1);
  with wr_sel select mtime_lo_d <=
    wdata_q                 when "100",
    mtime_inc(31 downto 0)  when others;

  mtime_hi_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 32)
    port map(d => mtime_hi_d, q => mtime_hi, clk => clk, en => '1', rst => rst);
  with wr_sel select mtime_hi_d <=
    wdata_q                 when "101",
    mtime_inc(63 downto 32) when others;

  ------------------------------------------------------------------------------
  -- mtimecmp: resets to all ones.  generic_register's own reset clears to
  -- zero, so these registers are loaded with ones while rst is high
  -- instead, and their rst inputs are tied low.
  ------------------------------------------------------------------------------
  cmp_lo_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 32)
    port map(d => cmp_lo_d, q => cmp_lo, clk => clk, en => cmp_lo_en, rst => '0');
  cmp_lo_en <= '1' when rst = '1' or wr_sel = "110" else '0';
  cmp_lo_d  <= (others => '1') when rst = '1' else wdata_q;

  cmp_hi_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 32)
    port map(d => cmp_hi_d, q => cmp_hi, clk => clk, en => cmp_hi_en, rst => '0');
  cmp_hi_en <= '1' when rst = '1' or wr_sel = "111" else '0';
  cmp_hi_d  <= (others => '1') when rst = '1' else wdata_q;

  ------------------------------------------------------------------------------
  -- mtip
  ------------------------------------------------------------------------------
  mtip_reg: entity work.generic_register(behavioral)
    generic map(XLEN => 1)
    port map(d => mtip_d, q => mtip_q, clk => clk, en => '1', rst => rst);
  mtip_d(0) <= '1' when unsigned(mtime_hi & mtime_lo) >= unsigned(cmp_hi & cmp_lo)
               else '0';
  mtip <= mtip_q(0);

end behavioral;
