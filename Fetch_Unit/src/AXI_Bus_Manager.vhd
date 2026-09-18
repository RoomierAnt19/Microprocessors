library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity entity_name is
	generic (
		-- Users can add generic parameters here

		-- User parameters ends
		C_M_TARGET_SLAVE_BASE_ADDR : std_logic_vector	:= x"00000000"; -- Base address of targeted slave
		C_M_AXI_BURST_LEN	     : integer	:= 1; -- Burst Length. Supports 1, 2, 4, 8, 16, 32, 64, 128, 256 burst lengths
		C_M_AXI_ID_WIDTH	     : integer	:= 1; -- Thread ID Width
		C_M_AXI_ADDR_WIDTH	   : integer	:= 32; -- Width of Address Bus
		C_M_AXI_DATA_WIDTH	   : integer	:= 32; -- Width of Data Bus
		C_M_AXI_AWUSER_WIDTH   : integer	:= 0; -- Width of User Write Address Bus
		C_M_AXI_ARUSER_WIDTH   : integer	:= 0; -- Width of User Read Address Bus
		C_M_AXI_WUSER_WIDTH	   : integer	:= 0; -- Width of User Write Data Bus
		C_M_AXI_RUSER_WIDTH	   : integer	:= 0; -- Width of User Read Data Bus
		C_M_AXI_BUSER_WIDTH	   : integer	:= 0  -- Width of User Response Bus
    );
	port (
		-- Users can add ports here. These are SUGGESTED user ports.
		Start_read	 : in std_logic;  -- Initiate AXI read transaction
    Read_address : in std_logic_vector(C_M_AXI_ADDR_WIDTH-1 downto 0); -- address to read from
 		Read_Done	: out std_logic; -- Asserts when transaction is complete
    Read_Data : out std_logic_vector(0 to C_M_AXI_DATA_WIDTH*C_M_AXI_BURST_LEN - 1); -- Data that was read (modify as needed)
		Error	: out std_logic; -- Asserts when ERROR is detected
		-- User ports ends
    -- Global AXI ports
		M_AXI_ACLK	: in std_logic;    -- Global Clock Signal.
		M_AXI_ARESETN	: in std_logic;  -- Global Reset Singal. This Signal is Active Low
    -- AXI Write Address Channel
		M_AXI_AWID	: out std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0); -- Master Interface Write Address ID
		M_AXI_AWADDR	: out std_logic_vector(C_M_AXI_ADDR_WIDTH-1 downto 0); -- Master Interface Write Address
		M_AXI_AWLEN	: out std_logic_vector(7 downto 0); -- Burst length. The burst length gives the exact number of transfers in a burst
		M_AXI_AWSIZE	: out std_logic_vector(2 downto 0); -- Burst size. This signal indicates the size of each transfer in the burst
		M_AXI_AWBURST	: out std_logic_vector(1 downto 0); -- Burst type. The burst type and the size information, determine how the address for each transfer within the burst is calculated.
		M_AXI_AWLOCK	: out std_logic; -- Lock type. Provides additional information about the atomic characteristics of the transfer. 
		M_AXI_AWCACHE	: out std_logic_vector(3 downto 0); -- Memory type. This signal indicates how transactions are required to progress through a system.
		M_AXI_AWPROT	: out std_logic_vector(2 downto 0); -- Protection type. This signal indicates the privilege and security level of the transaction, and whether the transaction is a data access or an instruction access.
		M_AXI_AWQOS	: out std_logic_vector(3 downto 0); -- Quality of Service, QoS identifier sent for each write transaction.
		M_AXI_AWUSER	: out std_logic_vector(C_M_AXI_AWUSER_WIDTH-1 downto 0); -- Optional User-defined signal in the write address channel.
		M_AXI_AWVALID	: out std_logic; -- Write address valid. This signal indicates that the channel is signaling valid write address and control information.
		M_AXI_AWREADY	: in std_logic; -- Write address ready. This signal indicates that the slave is ready to accept an address and associated control signals
    -- AXI Write Data Channel
		M_AXI_WDATA	: out std_logic_vector(C_M_AXI_DATA_WIDTH-1 downto 0); -- Master Interface Write Data.
		M_AXI_WSTRB	: out std_logic_vector(C_M_AXI_DATA_WIDTH/8-1 downto 0); -- Write strobes. This signal indicates which byte lanes hold valid data. There is one write strobe bit for each eight bits of the write data bus.
		M_AXI_WLAST	: out std_logic; -- Write last. This signal indicates the last transfer in a write burst.
		M_AXI_WUSER	: out std_logic_vector(C_M_AXI_WUSER_WIDTH-1 downto 0); -- Optional User-defined signal in the write data channel.
		M_AXI_WVALID	: out std_logic; -- Write valid. This signal indicates that valid write data and strobes are available
		M_AXI_WREADY	: in std_logic; -- Write ready. This signal indicates that the slave can accept the write data.
    -- AXI Write Response Channel
		M_AXI_BID	: in std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0); -- Master Interface Write Response.
		M_AXI_BRESP	: in std_logic_vector(1 downto 0); -- Write response. This signal indicates the status of the write transaction.
		M_AXI_BUSER	: in std_logic_vector(C_M_AXI_BUSER_WIDTH-1 downto 0); -- Optional User-defined signal in the write response channel
		M_AXI_BVALID	: in std_logic; -- Write response valid. This signal indicates that the  channel is signaling a valid write response.
		M_AXI_BREADY	: out std_logic; -- Response ready. This signal indicates that the master can accept a write response.
    -- AXI Read Address Channel
		M_AXI_ARID	: out std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0); -- Master Interface Read Address.
		M_AXI_ARADDR	: out std_logic_vector(C_M_AXI_ADDR_WIDTH-1 downto 0); -- Read address. This signal indicates the initial address of a read burst transaction.
		M_AXI_ARLEN	: out std_logic_vector(7 downto 0); -- Burst length. The burst length gives the exact number of transfers in a burst
		M_AXI_ARSIZE	: out std_logic_vector(2 downto 0); -- Burst size. This signal indicates the size of each transfer in the burst
		M_AXI_ARBURST	: out std_logic_vector(1 downto 0); -- Burst type. The burst type and the size information, determine how the address for each transfer within the burst is calculated.
		M_AXI_ARLOCK	: out std_logic; -- Lock type. Provides additional information about the atomic characteristics of the transfer.
		M_AXI_ARCACHE	: out std_logic_vector(3 downto 0); -- Memory type. This signal indicates how transactions are required to progress through a system.
		M_AXI_ARPROT	: out std_logic_vector(2 downto 0); -- Protection type. This signal indicates the privilege and security level of the transaction, and whether the transaction is a data access or an instruction access.
		M_AXI_ARQOS	: out std_logic_vector(3 downto 0); -- Quality of Service, QoS identifier sent for each read transaction
		M_AXI_ARUSER	: out std_logic_vector(C_M_AXI_ARUSER_WIDTH-1 downto 0); -- Optional User-defined signal in the read address channel.
		M_AXI_ARVALID	: out std_logic; -- Write address valid. This signal indicates that the channel is signaling valid read address and control information
		M_AXI_ARREADY	: in std_logic; -- Read address ready. This signal indicates that the slave is ready to accept an address and associated control signals
    -- AXI Read Data Channel
		M_AXI_RID	: in std_logic_vector(C_M_AXI_ID_WIDTH-1 downto 0); -- Read ID tag. This signal is the identification tag for the read data group of signals generated by the slave.
		M_AXI_RDATA	: in std_logic_vector(C_M_AXI_DATA_WIDTH-1 downto 0); -- Master Read Data
		M_AXI_RRESP	: in std_logic_vector(1 downto 0); -- Read response. This signal indicates the status of the read transfer
		M_AXI_RLAST	: in std_logic; -- Read last. This signal indicates the last transfer in a read burst
		M_AXI_RUSER	: in std_logic_vector(C_M_AXI_RUSER_WIDTH-1 downto 0); -- Optional User-defined signal in the read address channel.
		M_AXI_RVALID	: in std_logic; -- Read valid. This signal indicates that the channel is signaling the required read data.
		M_AXI_RREADY	: out std_logic -- Read ready. This signal indicates that the master can accept the read data and response information.
    );
end entity_name;

architecture implementation of entity_name is



begin
  
  
	------------------------------
	-- Read Address Channel
	------------------------------

	-- The purpose of the read address channel is to set up the
	-- address and command information for the entire transaction.  It
	-- is a single beat of information.


  

	----------------------------------
	--Read Data Channel
	----------------------------------


  

	----------------------
	--Write Address Channel
	----------------------

	-- The purpose of the write address channel is to request the
	-- address and command information for the entire transaction.  It
	-- is a single beat of information.



	----------------------
	-- Write Data Channel
	----------------------

	-- The write data will continually try to push write data across the
	-- interface.  The amount of data accepted will depend on the AXI
	-- slave and the AXI Interconnect settings, such as if there are
	-- FIFOs enabled in interconnect.  Note that there is no explicit
	-- timing relationship to the write address channel.  The write
	-- channel has its own throttling flag, separate from the AW
	-- channel.  Synchronization between the channels must be determined
	-- by the user.

	-- The simpliest but lowest performance would be to only issue one
	-- address write and write data burst at a time.


	----------------------
	--Write Response Channel
	----------------------




end implementation;
