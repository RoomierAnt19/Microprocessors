--------------------------------------------------------------------------------
-- CENG 442 Lab 5                                              axi_write_channel
--
-- Starting point for the generic AXI4 write engine.  The entity below is
-- the published interface: the testbench binds to it by name, so do not
-- change any of it.  The architecture is empty.  Everything in it is
-- yours to write.
--
-- An AXI4 bus manager that owns only the write channels (AW, W and B).
-- It writes one DATA_WIDTH word to the address presented on addr each
-- time start is asserted, under the byte strobes presented on wstrb.
--
-- Client interface
-- ----------------
--   start  request a write of wdata to addr.  Taken on any rising edge
--          where ready is also high, ignored otherwise
--   addr   byte address to write.  Valid in the cycle where start is
--          taken, and captured then: the client may change it afterwards
--   wdata  the word to write, already in the correct byte lanes
--   wstrb  one bit per byte lane, high for the lanes to be written
--   ready  high when the engine is idle, so a new start will be taken
--          and the previous write has been answered.  It must go low on
--          the cycle after a start is taken
--
-- This is the read engine with one more channel and one more idea in it.
-- The write is not finished when the subordinate takes the data.  It is
-- finished when the subordinate answers on the response channel, and
-- that is what brings ready back up.  A design that calls the write done
-- when W is accepted will pass a casual look at a waveform and lose data
-- the first time it meets a memory that is slower than it is.
--
-- Single beat only.  AWLEN is zero, so there is one data beat and WLAST
-- is asserted on it.
--
-- BRESP does not have to be inspected.  This core has no way to raise an
-- exception, so a subordinate reporting SLVERR is treated like one
-- reporting OKAY.  Capturing BRESP into a register beside ready is where
-- a bus fault would attach when there is something to attach it to.
--------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;

entity axi_write_channel is
  generic (
    ADDR_WIDTH : integer := 32;   -- Width of the AXI address bus
    DATA_WIDTH : integer := 32;   -- Width of the AXI data bus
    ID_WIDTH   : integer := 1     -- Thread ID width
    );
  port (
    clk : in std_logic;
    rst : in std_logic;           -- synchronous, active high

    -- Client interface
    start : in  std_logic;
    addr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    wdata : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    wstrb : in  std_logic_vector(DATA_WIDTH/8-1 downto 0);
    ready : out std_logic;

    -- AXI4 Write Address Channel
    m_axi_awid    : out std_logic_vector(ID_WIDTH-1 downto 0);
    m_axi_awaddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    m_axi_awlen   : out std_logic_vector(7 downto 0);
    m_axi_awsize  : out std_logic_vector(2 downto 0);
    m_axi_awburst : out std_logic_vector(1 downto 0);
    m_axi_awlock  : out std_logic;
    m_axi_awcache : out std_logic_vector(3 downto 0);
    m_axi_awprot  : out std_logic_vector(2 downto 0);
    m_axi_awqos   : out std_logic_vector(3 downto 0);
    m_axi_awvalid : out std_logic;
    m_axi_awready : in  std_logic;

    -- AXI4 Write Data Channel
    m_axi_wdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);
    m_axi_wstrb  : out std_logic_vector(DATA_WIDTH/8-1 downto 0);
    m_axi_wlast  : out std_logic;
    m_axi_wvalid : out std_logic;
    m_axi_wready : in  std_logic;

    -- AXI4 Write Response Channel
    m_axi_bid    : in  std_logic_vector(ID_WIDTH-1 downto 0);
    m_axi_bresp  : in  std_logic_vector(1 downto 0);
    m_axi_bvalid : in  std_logic;
    m_axi_bready : out std_logic
    );
end axi_write_channel;

architecture behavioral of axi_write_channel is
  type WAC_state_t is (RESET, INIT, ACCEPT, WAITING);
  signal WAC_state,WAC_state_next, WAC_state_next_i: WAC_state_t;
  signal WAC_INIT_next, WAC_ACCEPT_next, WAC_WAITING_next: WAC_state_t;

  type WC_state_t is (RESET, INIT, ACCEPT, WAITING);
  signal WC_state,WC_state_next, WC_state_next_i: WC_state_t;
  signal WC_INIT_next, WC_ACCEPT_next, WC_WAITING_next: WC_state_t;

  type WRC_state_t is (RESET, WAITING, ACCEPT);
  signal WRC_state,WRC_state_next,WRC_state_next_i: WRC_state_t;
  signal WRC_WAITING_next: WRC_state_t;

  signal aw_latch_enable, w_latch_enable : std_logic;
  signal addr_i : Std_Logic_Vector(31 downto 0);

  -- Declare the state machines here.  Three of them, one per channel, is
  -- the arrangement that follows from Lab 3: the address and the data go
  -- out on channels that handshake independently and in either order, so
  -- neither can wait on the other, and the response machine waits on both.
  --
  -- Also declare the registers that hold AWADDR, WDATA and WSTRB, the
  -- signal that says all three machines are idle, and any boolean signal
  -- you find yourself writing more than once.

begin

  ------------------------------------------------------------------------------
  -- Write Address Channel state machine
  ------------------------------------------------------------------------------
  WAC_state <= WAC_state_next when rising_edge(clk);
  WAC_state_next <= RESET when rst = '1' else WAC_state_next_i;

  with WAC_state select WAC_state_next_i <= 
        WAC_INIT_next when INIT,
        WAC_ACCEPT_next when ACCEPT,
        WAITING when RESET,
        WAC_WAITING_next when others;

  WAC_INIT_next <= ACCEPT when M_AXI_AWREADY = '1' else INIT;
  WAC_ACCEPT_next <= WAITING when m_axi_bvalid = '1' else ACCEPT;
  WAC_WAITING_next <= INIT when start = '1' and WC_state = WAITING
                      else WAITING;
  -- Mealy outputs for WAC state machine 
  aw_latch_enable <= '1' when WAC_state = WAITING and start = '1'
                     else '0';
  -- Moore outputs for WAC state machine
  M_AXI_AWVALID <= '1' when WAC_state = INIT else '0';
  ------------------------------------------------------------------------------
  -- Write Data Channel state machine
  ------------------------------------------------------------------------------
  WC_state <= WC_state_next when rising_edge(clk);
  WC_state_next <= RESET when rst = '1' else WC_state_next_i;

  with WC_state select WC_state_next_i <= 
        WC_INIT_next when INIT,
        WC_ACCEPT_next when ACCEPT,
        WAITING when RESET,
        WC_WAITING_next when others;

  WC_INIT_next <= ACCEPT when M_AXI_WREADY = '1' else INIT;
  WC_ACCEPT_next <= WAITING when m_axi_bvalid = '1' else ACCEPT;
  WC_WAITING_next <= INIT when start = '1' and WC_state = WAITING
                      else WAITING;
  -- Mealy outputs for WAC state machine 
  -- Moore outputs for WAC state machine
  M_AXI_WVALID <= '1' when WAC_state = INIT else '0';
  ------------------------------------------------------------------------------
  -- Write Response Channel state machine
  ------------------------------------------------------------------------------
  WRC_state <= WRC_state_next when rising_edge(clk);
  WRC_state_next <= RESET when rst = '1' else WRC_state_next_i;

  with WRC_state select WRC_state_next_i <= 
  WRC_WAITING_next when WAITING,
  WAITING when others;

  WRC_WAITING_next <= ACCEPT when M_AXI_BVALID = '1' else
                     WAITING;
  -- Mealy outputs for RC state machine
  w_latch_enable <= '1' when WRC_state_next_i = ACCEPT else '0';
  -- Moore outputs for RC state machine
  M_AXI_BREADY <= '1' when WRC_state = WAITING else '0';
  ------------------------------------------------------------------------------
  -- State decodes
  --
  -- ready is all three machines being idle, and a start is taken only
  -- when that is true.  Gating a start on one machine alone is a bug:
  -- the three do not reach the idle state on the same edge, and a start
  -- taken in the gap puts a write on the bus that nobody asked for.
  ------------------------------------------------------------------------------


  ------------------------------------------------------------------------------
  -- Address, data and strobe registers
  --
  -- Loaded on the edge that starts the transaction, and on that edge
  -- only, so each payload is stable for as long as its VALID is asserted.
  ------------------------------------------------------------------------------


  ------------------------------------------------------------------------------
  -- AXI Write Address Channel outputs
  ------------------------------------------------------------------------------


  ------------------------------------------------------------------------------
  -- AXI Write Data Channel outputs
  ------------------------------------------------------------------------------


  ------------------------------------------------------------------------------
  -- AXI Write Response Channel outputs
  ------------------------------------------------------------------------------


  ------------------------------------------------------------------------------
  -- Client interface outputs
  ------------------------------------------------------------------------------


end behavioral;
