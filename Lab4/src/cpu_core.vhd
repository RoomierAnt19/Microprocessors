--------------------------------------------------------------------------------
-- CENG 442 Lab 4                                                      cpu_core
--
-- Starting point for the top of your CPU.  The entity below is the published
-- interface.  Do not change it: the block design, the testbenches and the
-- board all depend on these names.
--
--   clk, rst          the clock, and the reset, synchronous and active high.
--                     rst goes straight to every unit, with no inverter.
--   DBGsel, DBGreg    the datapath's debug port, straight through
--   m_axi_*_i         the instruction port.  The fetch unit drives it.
--   m_axi_*_d         the data port.  It is tied off at the end of the
--                     architecture until Lab 5 connects the load/store unit.
--
-- Vivado infers clk, rst, m_axi_i and m_axi_d from the port names alone, so
-- a misspelled name makes an interface disappear from the block design.
--
-- The fetch unit and the tie-offs are done.  What is left is marked FILL IN:
-- your sequencer, your decoder and your datapath, and the wiring between
-- them.  Remember that Dlen, PCle and isBR act on a clock edge and must
-- reach the datapath in only one cycle of Execute.
--
-- Vivado reads the top file of a block design module as VHDL-93.  Keep this
-- file VHDL-93: no expressions in port maps, and no record ports.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.project_types.all;

entity cpu_core is
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;   -- synchronous, active high
    DBGsel : in  std_logic_vector(4 downto 0);
    DBGreg : out std_logic_vector(31 downto 0);

    -- AXI4 interfaces
    m_axi_awid_i,    m_axi_awid_d    : out std_logic_vector(0 downto 0);
    m_axi_awaddr_i,  m_axi_awaddr_d  : out std_logic_vector(31 downto 0);
    m_axi_awlen_i,   m_axi_awlen_d   : out std_logic_vector(7 downto 0);
    m_axi_awsize_i,  m_axi_awsize_d  : out std_logic_vector(2 downto 0);
    m_axi_awburst_i, m_axi_awburst_d : out std_logic_vector(1 downto 0);
    m_axi_awlock_i,  m_axi_awlock_d  : out std_logic;
    m_axi_awcache_i, m_axi_awcache_d : out std_logic_vector(3 downto 0);
    m_axi_awprot_i,  m_axi_awprot_d  : out std_logic_vector(2 downto 0);
    m_axi_awqos_i,   m_axi_awqos_d   : out std_logic_vector(3 downto 0);
    m_axi_awvalid_i, m_axi_awvalid_d : out std_logic;
    m_axi_awready_i, m_axi_awready_d : in  std_logic;
    m_axi_wdata_i,   m_axi_wdata_d   : out std_logic_vector(31 downto 0);
    m_axi_wstrb_i,   m_axi_wstrb_d   : out std_logic_vector(3 downto 0);
    m_axi_wlast_i,   m_axi_wlast_d   : out std_logic;
    m_axi_wvalid_i,  m_axi_wvalid_d  : out std_logic;
    m_axi_wready_i,  m_axi_wready_d  : in  std_logic;
    m_axi_bid_i,     m_axi_bid_d     : in  std_logic_vector(0 downto 0);
    m_axi_bresp_i,   m_axi_bresp_d   : in  std_logic_vector(1 downto 0);
    m_axi_bvalid_i,  m_axi_bvalid_d  : in  std_logic;
    m_axi_bready_i,  m_axi_bready_d  : out std_logic;
    m_axi_arid_i,    m_axi_arid_d    : out std_logic_vector(0 downto 0);
    m_axi_araddr_i,  m_axi_araddr_d  : out std_logic_vector(31 downto 0);
    m_axi_arlen_i,   m_axi_arlen_d   : out std_logic_vector(7 downto 0);
    m_axi_arsize_i,  m_axi_arsize_d  : out std_logic_vector(2 downto 0);
    m_axi_arburst_i, m_axi_arburst_d : out std_logic_vector(1 downto 0);
    m_axi_arlock_i,  m_axi_arlock_d  : out std_logic;
    m_axi_arcache_i, m_axi_arcache_d : out std_logic_vector(3 downto 0);
    m_axi_arprot_i,  m_axi_arprot_d  : out std_logic_vector(2 downto 0);
    m_axi_arqos_i,   m_axi_arqos_d   : out std_logic_vector(3 downto 0);
    m_axi_arvalid_i, m_axi_arvalid_d : out std_logic;
    m_axi_arready_i, m_axi_arready_d : in  std_logic;
    m_axi_rid_i,     m_axi_rid_d     : in  std_logic_vector(0 downto 0);
    m_axi_rdata_i,   m_axi_rdata_d   : in  std_logic_vector(31 downto 0);
    m_axi_rresp_i,   m_axi_rresp_d   : in  std_logic_vector(1 downto 0);
    m_axi_rlast_i,   m_axi_rlast_d   : in  std_logic;
    m_axi_rvalid_i,  m_axi_rvalid_d  : in  std_logic;
    m_axi_rready_i,  m_axi_rready_d  : out std_logic
    );
end cpu_core;

architecture structural of cpu_core is

  -- The fetch unit's user ports.
  signal PC, instruction, instruction_address : std_logic_vector(31 downto 0);
  signal ready, fetch, PCie, execute : std_logic;
  signal instruction_cw, data_cw : control_word;

  -- FILL IN: the signals your sequencer, decoder and datapath need, for
  -- example the control word from the decoder and the one that reaches the
  -- datapath.

begin

  ------------------------------------------------------------------------------
  -- FILL IN: your sequencer.  It drives fetch and PCie, and watches ready.
  ------------------------------------------------------------------------------
sequencer : entity work.sequencer
  port map (
    clk => clk,
    rst => rst,
    ready => ready,
    fetch => fetch,
    PCie => PCie,
    execute => execute
  );
  ------------------------------------------------------------------------------
  -- FILL IN: your decoder.  Its input is instruction.
  ------------------------------------------------------------------------------
decoder : entity work.instruction_decoder
  port map (
    instruction => instruction,
    cw => instruction_cw,
    PCie => PCie
  );
  ------------------------------------------------------------------------------
  -- FILL IN: whatever lets Dlen, PCle and isBR through in one cycle only.
  ------------------------------------------------------------------------------
  data_cw.Asel <= instruction_cw.Asel;
  data_cw.Bsel <= instruction_cw.Bsel;
  data_cw.Dsel <= instruction_cw.Dsel;
  data_cw.PCAsel <=  instruction_cw.PCAsel;
  data_cw.IMMBsel <= instruction_cw.IMMBsel;
  data_cw.PCDsel <= instruction_cw.PCDsel;
  data_cw.PCie <= instruction_cw.PCie;
  data_cw.BRcond <= instruction_cw.BRcond;
  data_cw.ALUFunc <= instruction_cw.ALUFunc;
  data_cw.IMM <= instruction_cw.IMM;
  data_cw.Dlen <= instruction_cw.Dlen and execute;
  data_cw.PCle <= instruction_cw.PCle and execute;
  data_cw.isBR <= instruction_cw.isBR and execute;
  ------------------------------------------------------------------------------
  -- FILL IN: your datapath.  Its address input is instruction_address, its
  -- PCout drives PC, and DBGsel and DBGreg go straight through to the ports
  -- of the same name.  Until it is here, DBGreg is undriven.
  ------------------------------------------------------------------------------
datapath : entity work.data_path
  port map (
    cw => data_cw,
    clk => clk,
    rst => rst,
    Dbugsel => DBGsel,
    Dbug => DBGreg,
    instruction_address => instruction_address,
    PC_out => PC
  );

  ------------------------------------------------------------------------------
  -- FILL IN: your Fetch_unit.  It fetchs the instruction
  ------------------------------------------------------------------------------
  FETCH_UNIT : entity work.fetch_unit (implementation)
    generic map(
      C_M_AXI_ID_WIDTH   => 1,
      C_M_AXI_ADDR_WIDTH => 32,
      C_M_AXI_DATA_WIDTH => 32
      )
    port map(
      PC                  => PC,
      instruction         => instruction,
      address =>  instruction_address,  -- to the datapath's address input
      ready               => ready,
      fetch               => fetch,

      M_AXI_ACLK => clk,

      M_AXI_ARESETN => rst,

      M_AXI_AWID    => m_axi_awid_i,
      M_AXI_AWADDR  => m_axi_awaddr_i,
      M_AXI_AWLEN   => m_axi_awlen_i,
      M_AXI_AWSIZE  => m_axi_awsize_i,
      M_AXI_AWBURST => m_axi_awburst_i,
      M_AXI_AWLOCK  => m_axi_awlock_i,
      M_AXI_AWCACHE => m_axi_awcache_i,
      M_AXI_AWPROT  => m_axi_awprot_i,
      M_AXI_AWQOS   => m_axi_awqos_i,
      M_AXI_AWVALID => m_axi_awvalid_i,
      M_AXI_AWREADY => m_axi_awready_i,
      M_AXI_WDATA   => m_axi_wdata_i,
      M_AXI_WSTRB   => m_axi_wstrb_i,
      M_AXI_WLAST   => m_axi_wlast_i,
      M_AXI_WVALID  => m_axi_wvalid_i,
      M_AXI_WREADY  => m_axi_wready_i,
      M_AXI_BID     => m_axi_bid_i,
      M_AXI_BRESP   => m_axi_bresp_i,
      M_AXI_BVALID  => m_axi_bvalid_i,
      M_AXI_BREADY  => m_axi_bready_i,
      M_AXI_ARID    => m_axi_arid_i,
      M_AXI_ARADDR  => m_axi_araddr_i,
      M_AXI_ARLEN   => m_axi_arlen_i,
      M_AXI_ARSIZE  => m_axi_arsize_i,
      M_AXI_ARBURST => m_axi_arburst_i,
      M_AXI_ARLOCK  => m_axi_arlock_i,
      M_AXI_ARCACHE => m_axi_arcache_i,
      M_AXI_ARPROT  => m_axi_arprot_i,
      M_AXI_ARQOS   => m_axi_arqos_i,
      M_AXI_ARVALID => m_axi_arvalid_i,
      M_AXI_ARREADY => m_axi_arready_i,
      M_AXI_RID     => m_axi_rid_i,
      M_AXI_RDATA   => m_axi_rdata_i,
      M_AXI_RRESP   => m_axi_rresp_i,
      M_AXI_RLAST   => m_axi_rlast_i,
      M_AXI_RVALID  => m_axi_rvalid_i,
      M_AXI_RREADY  => m_axi_rready_i
      );

  ------------------------------------------------------------------------------
  -- The data port is disabled until Lab 5 connects the load/store unit.
  -- No VALID is ever raised and no READY is ever given, so no transaction
  -- can start on it.  The other outputs are constants, as in the fetch unit.
  ------------------------------------------------------------------------------
  m_axi_awvalid_d <= '0';
  m_axi_wvalid_d  <= '0';
  m_axi_bready_d  <= '0';
  m_axi_arvalid_d <= '0';
  m_axi_rready_d  <= '0';

  m_axi_awid_d    <= (others => '0');
  m_axi_awaddr_d  <= (others => '0');
  m_axi_awlen_d   <= (others => '0');
  m_axi_awsize_d  <= "010";
  m_axi_awburst_d <= "01";
  m_axi_awlock_d  <= '0';
  m_axi_awcache_d <= "0010";
  m_axi_awprot_d  <= "000";
  m_axi_awqos_d   <= x"0";

  m_axi_wdata_d   <= (others => '0');
  m_axi_wstrb_d   <= (others => '0');
  m_axi_wlast_d   <= '0';

  m_axi_arid_d    <= (others => '0');
  m_axi_araddr_d  <= (others => '0');
  m_axi_arlen_d   <= (others => '0');
  m_axi_arsize_d  <= "010";
  m_axi_arburst_d <= "01";
  m_axi_arlock_d  <= '0';
  m_axi_arcache_d <= "0010";
  m_axi_arprot_d  <= "000";
  m_axi_arqos_d   <= x"0";

end structural;
