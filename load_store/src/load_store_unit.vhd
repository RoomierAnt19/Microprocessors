--------------------------------------------------------------------------------
-- CENG 442 Lab 5                                                load_store_unit
--
-- Starting point for the load/store unit.  The entity below is the
-- published interface: the testbench binds to it by name, so do not
-- change any of it.  The architecture is empty.
--
-- One AXI4 manager port, driven by two engines that never contend: your
-- axi_read_channel on the AR and R channels, and your axi_write_channel
-- on AW, W and B.  A load starts one, a store starts the other, and the
-- unit is ready when both are.
--
-- Everything the engines do not know about lives here, and all of it is
-- byte lanes.  RV32I addresses individual bytes, the bus carries words,
-- and this is where the two are reconciled.
--
--   Addresses.  Hand both engines addr with the low two bits cleared, so
--   that every transaction on the bus is a naturally aligned four byte
--   access.  The low two bits never go on the bus.  They select a lane
--   in here.
--
--   Stores.  Replicate the data across the word and let WSTRB pick the
--   lanes that are really written.  Replicating costs nothing and saves
--   a shifter.
--
--   Loads.  The whole word comes back.  Select the lane here, from the
--   low address bits of the request, then extend it.
--
-- funct3 comes straight from the instruction, so nothing has to be
-- recoded between the decoder and here:
--
--   000  LB / SB   byte, sign extended on a load
--   001  LH / SH   halfword, sign extended on a load
--   010  LW / SW   word
--   100  LBU       byte, zero extended
--   101  LHU       halfword, zero extended
--
-- so funct3(1 downto 0) is the size and funct3(2) means unsigned.
--
-- Misaligned accesses are not handled.  RV32I allows a core to trap on
-- them, this one has no way to trap yet, and a halfword that straddles a
-- word boundary would need two bus transactions.  Assume the address is
-- naturally aligned for its size.
--
-- One thing is easy to miss.  The client is free to move on as soon as
-- the request is accepted, and a load's word does not come back for
-- several cycles, so the byte offset and funct3 of the request have to
-- be held here.  The read engine's raddr cannot serve: it holds the
-- aligned address that went on the bus, with the two bits you need
-- cleared.
--------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use work.decoder.all;

entity load_store_unit is
  generic (
    -- C_M_AXI_BURST_LEN is not read.  Every transaction is a single beat.
    -- It stays in the list so that older code which passes it still
    -- elaborates.
            C_M_AXI_BURST_LEN  : integer	:= 16;
            C_M_AXI_ID_WIDTH   : integer	:= 1;     -- Thread ID Width
            C_M_AXI_ADDR_WIDTH : integer	:= 32;    -- Width of Address Bus
            C_M_AXI_DATA_WIDTH : integer	:= 32     -- Width of Data Bus
          );
  port (
    -- Users to add ports here
         start  : in  std_logic;                      -- begin an access
         store  : in  std_logic;                      -- 1 = store, 0 = load
         addr   : in  std_logic_vector(31 downto 0);  -- byte address
         funct3 : in  std_logic_vector(2 downto 0);   -- size and signedness
         wdata  : in  std_logic_vector(31 downto 0);  -- data for a store
         rdata  : out std_logic_vector(31 downto 0);  -- result of a load
         ready  : out std_logic;                      -- idle, result valid
                                                      -- User ports ends
                                                      -- Do not modify the ports beyond this line

         clk           : in std_logic;   -- the core clock
         rst           : in std_logic;   -- synchronous, active high

         M_AXI_AWID	  : out std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0);   -- Master Interface Write Address ID
         M_AXI_AWADDR  : out std_logic_vector(C_M_AXI_ADDR_WIDTH-1 downto 0); -- Master Interface Write Address
         M_AXI_AWLEN	  : out std_logic_vector(7 downto 0); -- Burst length. The burst length gives the exact number of transfers in a burst
         M_AXI_AWSIZE  : out std_logic_vector(2 downto 0); -- Burst size. This signal indicates the size of each transfer in the burst
         M_AXI_AWBURST	: out std_logic_vector(1 downto 0); -- Burst type. The burst type, and the size information, determine how 
                                                           -- the address for each transfer within the burst is calculated.
         M_AXI_AWLOCK	: out std_logic;                    -- Lock type provides additional information about the atomic characteristics of the transfer.
         M_AXI_AWCACHE	: out std_logic_vector(3 downto 0); -- Memory type. This signal indicates how transactions are required to progress through a system.
         M_AXI_AWPROT	: out std_logic_vector(2 downto 0); -- Protection type. This signal indicates the privilege and security level of the 
                                                          -- transaction, and whether the transaction is a data access or an instruction access.
         M_AXI_AWQOS	  : out std_logic_vector(3 downto 0); -- Quality of Service, QoS identifier sent for each write transaction.
         M_AXI_AWVALID	: out std_logic;                    -- Write address valid. This signal indicates that the channel is signaling valid
                                                           -- write address and control information.
         M_AXI_AWREADY	: in std_logic;                     -- Write address ready.  This signal indicates that the slave is ready to accept an address
                                                           -- and associated control signals
         M_AXI_WDATA	  : out std_logic_vector(C_M_AXI_DATA_WIDTH-1 downto 0);   -- Master Interface Write Data.
         M_AXI_WSTRB	  : out std_logic_vector(C_M_AXI_DATA_WIDTH/8-1 downto 0); -- Write strobes. This signal indicates which byte lanes hold valid data.
                                                                                -- There is one write strobe bit for each eight bits of the write data bus.
         M_AXI_WLAST	  : out std_logic;                    -- Write last. This signal indicates the last transfer in a write burst.
         M_AXI_WVALID	: out std_logic;                    -- Write valid. This signal indicates that valid write data and strobes are available
         M_AXI_WREADY	: in std_logic;                     -- Write ready. This signal indicates that the slave can accept the write data.
         M_AXI_BID	    : in std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0);      -- Master Interface Write Response.
         M_AXI_BRESP	  : in std_logic_vector(1 downto 0);  -- Write response. This signal indicates the status of the write transaction.
         M_AXI_BVALID	: in std_logic;                     -- Write response valid. This signal indicates that the channel is signaling a valid write response.
         M_AXI_BREADY	: out std_logic;                    -- Response ready. This signal indicates that the master can accept a write response.

         M_AXI_ARID	  : out std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0);     -- Master Interface Read Address.
         M_AXI_ARADDR	: out std_logic_vector(C_M_AXI_ADDR_WIDTH-1 downto 0); -- Read address. This signal indicates the initial address of a
                                                                             -- read burst transaction.
         M_AXI_ARLEN	  : out std_logic_vector(7 downto 0); -- Burst length. The burst length gives the exact number of transfers in a burst
         M_AXI_ARSIZE	: out std_logic_vector(2 downto 0); -- Burst size. This signal indicates the size of each transfer in the burst
         M_AXI_ARBURST	: out std_logic_vector(1 downto 0); -- Burst type. The burst type and the size information, determine how the address for each
                                                           -- transfer within the burst is calculated.
         M_AXI_ARLOCK	: out std_logic;                    -- Lock type. Provides additional information about the atomic characteristics of the transfer.
         M_AXI_ARCACHE	: out std_logic_vector(3 downto 0); -- Memory type. This signal indicates how transactions are required to progress through a system.
         M_AXI_ARPROT	: out std_logic_vector(2 downto 0); -- Protection type. This signal indicates the privilege and security level of the transaction,
                                                          -- and whether the transaction is a data access or an instruction access.
         M_AXI_ARQOS	  : out std_logic_vector(3 downto 0); -- Quality of Service, QoS identifier sent for each read transaction
         M_AXI_ARVALID	: out std_logic;                    -- Read address valid. This signal indicates that the channel is signaling valid read
                                                           -- address and control information
         M_AXI_ARREADY	: in std_logic;                     -- Read address ready. This signal indicates that the slave is ready to accept an address
                                                           -- and associated control signals
         M_AXI_RID	    : in std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0);    -- Read ID tag. This signal is the identification tag for the read data group
                                                                              -- of signals generated by the slave.
         M_AXI_RDATA	  : in std_logic_vector(C_M_AXI_DATA_WIDTH-1 downto 0);  -- Master Read Data
         M_AXI_RRESP	  : in std_logic_vector(1 downto 0);  -- Read response. This signal indicates the status of the read transfer
         M_AXI_RLAST	  : in std_logic;                     -- Read last. This signal indicates the last transfer in a read burst
         M_AXI_RVALID	: in std_logic;                     -- Read valid. This signal indicates that the channel is signaling the required read data.
         M_AXI_RREADY	: out std_logic                     -- Read ready. This signal indicates that the master can accept the read data and response information.
       );
end load_store_unit;

architecture behavioral of load_store_unit is

  -- Declare the aligned address, the two engines' start and ready
  -- signals, the word the read engine brings back, the replicated store
  -- data and its strobes, the register that holds the request, and the
  -- lane selection and extension signals.
  signal read_ready, write_ready : std_logic;
  signal address_fix, read_data, shifted_read_data, rdata_latched: Std_Logic_Vector(31 downto 0);
  --write data
  signal wdata_byte, wdata_half, write_data: Std_Logic_Vector(31 downto 0);

  signal extend_byte : Std_Logic_Vector(31 downto 8);
  signal extend_half : Std_Logic_Vector(31 downto 16);
  signal wstrb_byte, wstrb, wstrb_half  : std_logic_vector(3 downto 0);
  signal funct : std_logic_vector(2 downto 0);
  signal lower_add, lower_add_latched : std_logic_vector(1 downto 0);

begin
  ------------------------------------------------------------------------------
  -- Both Engine Signals
  ------------------------------------------------------------------------------
  ready <= write_ready and read_ready;
  address_fix <= addr(C_M_AXI_ADDR_WIDTH-1 downto 2) & "00";
  lower_add <= addr(1 downto 0);
------------------------------------------------------------------------------
-- Read engine: the AR and R channels
------------------------------------------------------------------------------
  read_channel : entity work.axi_read_channel
  generic map (
                ID_WIDTH => C_M_AXI_ID_WIDTH,
                ADDR_WIDTH => C_M_AXI_ADDR_WIDTH,
                DATA_WIDTH => C_M_AXI_DATA_WIDTH
              )
  port map (
             clk => clk,
             rst => rst,
             start => start and not store,
             addr => address_fix,
             rdata => rdata_latched,
             raddr => open,
             ready => read_ready,
             M_AXI_ARID => M_AXI_ARID,
             M_AXI_ARADDR => M_AXI_ARADDR,
             M_AXI_ARLEN => M_AXI_ARLEN,
             M_AXI_ARSIZE => M_AXI_ARSIZE,
             M_AXI_ARBURST => M_AXI_ARBURST,
             M_AXI_ARLOCK => M_AXI_ARLOCK,
             M_AXI_ARCACHE => M_AXI_ARCACHE,
             M_AXI_ARPROT => M_AXI_ARPROT,
             M_AXI_ARQOS => M_AXI_ARQOS,
             M_AXI_ARVALID => M_AXI_ARVALID,
             M_AXI_ARREADY => M_AXI_ARREADY,
             M_AXI_RID => M_AXI_RID,
             M_AXI_RDATA => M_AXI_RDATA,
             M_AXI_RRESP => M_AXI_RRESP,
             M_AXI_RLAST => M_AXI_RLAST,
             M_AXI_RVALID => M_AXI_RVALID,
             M_AXI_RREADY => M_AXI_RREADY
           );

------------------------------------------------------------------------------
-- Write engine: the AW, W and B channels
------------------------------------------------------------------------------
  write_channel : entity work.axi_write_channel
  generic map (
                ADDR_WIDTH => C_M_AXI_ADDR_WIDTH,
                DATA_WIDTH => C_M_AXI_DATA_WIDTH,
                ID_WIDTH => C_M_AXI_ID_WIDTH
              )
  port map (
             clk => clk,
             rst => rst,
             start => start and store,
             addr => address_fix,
             wdata => write_data,
             wstrb => wstrb,
             ready => write_ready,

             m_axi_awid => M_AXI_AWID,
             m_axi_awaddr => M_AXI_AWADDR,
             m_axi_awlen => M_AXI_AWLEN,
             m_axi_awsize => M_AXI_AWSIZE,
             m_axi_awburst => M_AXI_AWBURST,
             m_axi_awlock => M_AXI_AWLOCK,
             m_axi_awcache => M_AXI_AWCACHE,
             m_axi_awprot => M_AXI_AWPROT,
             m_axi_awqos => M_AXI_AWQOS,
             m_axi_awvalid => M_AXI_AWVALID,
             m_axi_awready => M_AXI_AWREADY,
             m_axi_wdata => M_AXI_WDATA,
             m_axi_wstrb => M_AXI_WSTRB,
             m_axi_wlast => M_AXI_WLAST,
             m_axi_wvalid => M_AXI_WVALID,
             m_axi_wready => M_AXI_WREADY,
             m_axi_bid => M_AXI_BID,
             m_axi_bresp => M_AXI_BRESP,
             m_axi_bvalid => M_AXI_BVALID,
             m_axi_bready => M_AXI_BREADY
           );

  ------------------------------------------------------------------------------
  -- Store data: replicate across the word
  ------------------------------------------------------------------------------
  wdata_byte <= wdata(7 downto 0) & wdata(7 downto 0) & wdata(7 downto 0) & wdata(7 downto 0);
  wdata_half <= wdata(15 downto 0) & wdata(15 downto 0);
  with funct3(1 downto 0) select
    write_data <= wdata_byte when "00",
                  wdata_half when "01",
                  wdata when others;
  ------------------------------------------------------------------------------
  -- Store strobes: pick the lanes that are really written
  ------------------------------------------------------------------------------
  wstrb_byte <= decode(lower_add, '1');
  wstrb_half <= "1100" when lower_add(1) = '1' else "0011";
  with funct3(1 downto 0) select
    wstrb <= wstrb_byte when "00",
                  wstrb_half when "01",
                  "1111" when others;
  ------------------------------------------------------------------------------
  -- The request, held until the word comes back
  ------------------------------------------------------------------------------
  func : entity work.gen_reg
  generic map (
  N => 3
  )
  port map (
             clk => clk,
             d => funct3,
             q => funct,
             reset => rst,
             enable => start
             );

  offset : entity work.gen_reg
  generic map (
  N => 2
  )
  port map (
             clk => clk,
             d => lower_add,
             q => lower_add_latched,
             reset => rst,
             enable => start and ready
             );
  ------------------------------------------------------------------------------
  -- Load data: select the lane, then extend it
  ------------------------------------------------------------------------------
  read_data <= M_AXI_RDATA when M_AXI_RVALID = '1' else rdata_latched;
  with lower_add_latched select
  shifted_read_data <=
    x"00"     & read_data(31 downto 8)  when "01",
    x"0000"   & read_data(31 downto 16) when "10",
    x"000000" & read_data(31 downto 24) when "11",
    read_data                           when others;

  extend_byte <= (others => shifted_read_data(7) and not funct(2));
  extend_half <= (others => shifted_read_data(15) and not funct(2));

  with funct(1 downto 0) select
    rdata <= extend_byte & shifted_read_data(7 downto 0) when "00",
                  extend_half & shifted_read_data(15 downto 0) when "01",
                  read_data when others;
end behavioral;
