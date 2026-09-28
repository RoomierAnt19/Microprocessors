library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fetch_unit is
	generic (
		C_M_AXI_BURST_LEN  : integer	:= 16;    -- Burst Length. Supports 1, 2, 4, 8, 16, 32, 64, 128, 256 burst lengths
		C_M_AXI_ID_WIDTH   : integer	:= 1;     -- Thread ID Width
		C_M_AXI_ADDR_WIDTH : integer	:= 32;    -- Width of Address Bus
		C_M_AXI_DATA_WIDTH : integer	:= 32     -- Width of Data Bus
	);
	port (
		-- Users to add ports here
        PC : in std_logic_vector(31 downto 0);
        instruction : out std_logic_vector(31 downto 0);
        address : out std_logic_vector(31 downto 0);
        ready : out std_logic;   -- signals that the current instruction is valid
        fetch : in std_logic;  -- tells the fetch unit to fetch the next instruction
            -- User ports ends
		-- Do not modify the ports beyond this line

		M_AXI_ACLK	  : in std_logic;      -- Global Clock Signal.
		M_AXI_ARESETN	: in std_logic;    -- Global Reset Singal. This Signal is Active Low
		
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
end fetch_unit;

architecture implementation of fetch_unit is

begin

end implementation;
