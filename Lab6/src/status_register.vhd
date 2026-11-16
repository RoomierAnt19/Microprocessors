----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/15/2024 03:19:34 PM
-- Design Name: 
-- Module Name: status_register - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- Lab 6: mret now sets MPIE to 1 (privileged spec 3.1.6.1).
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity status_register is
  Port (
  clk, reset, wen_lower, wen_upper: in std_logic;
  d: in std_logic_vector(63 downto 0);
  q: out std_logic_vector(63 downto 0);
  -- we want a dedicated way to clear mie from the sequencer.
  -- this should do the following: mpie = mie, mie = 0
  clear_mie: in std_logic;
  -- this should restore the mie (i.e. mie = mpie). this should
  -- be done when mret is executed.
  restore_mie: in std_logic;
  -- send mie out on its own port so everyone can see it
  mie_out : out std_logic
  );
end status_register;

architecture Behavioral of status_register is
constant SD_POS: integer := 31;
constant TSR_POS: integer := 22;
constant TW_POS: integer := 21;
constant TVM_POS: integer := 20;
constant MXR_POS: integer := 19;
constant SUM_POS: integer := 18;
constant MPRV_POS: integer := 17;
constant XS_POS: integer := 15;
constant FS_POS: integer := 13;
constant MPP_POS: integer := 11;
constant VS_POS: integer := 9;
constant SPP_POS: integer := 8;
constant MPIE_POS: integer := 7;
constant UBE_POS: integer := 6;
constant SPIE_POS: integer := 5;
constant MIE_POS: integer := 3;
constant SIE_POS: integer := 1;
constant SBE_POS: integer := 36;
constant MBE_POS: integer := 37;
signal sd, tsr, tw, tvm, mxr, sum, mprv, spp, mpie, mpie_next, ube, spie, mie, mie_next, sie, mbe, sbe: std_logic;
signal xs, fs, mpp, vs: std_logic_vector(1 downto 0);
signal output_vector: std_logic_vector(63 downto 0);

begin

-- define where all of the signals are present in the 64-bit status register
-- (mstatus)
output_vector(SD_POS) <= sd;
output_vector(30 downto 23) <= (others => '0');
output_vector(TSR_POS) <= tsr;
output_vector(TW_POS) <= tw;
output_vector(TVM_POS) <= tvm;
output_vector(MXR_POS) <= mxr;
output_vector(SUM_POS) <= sum;
output_vector(MPRV_POS) <= mprv;
output_vector(XS_POS + 1 downto XS_POS) <= xs;
output_vector(FS_POS + 1 downto FS_POS) <= fs;
output_vector(MPP_POS + 1 downto MPP_POS) <= mpp;
output_vector(VS_POS + 1 downto VS_POS) <= vs;
output_vector(SPP_POS) <= spp;
output_vector(MPIE_POS) <= mpie;
output_vector(UBE_POS) <= ube;
output_vector(SPIE_POS) <= spie;
output_vector(4) <= '0';
output_vector(MIE_POS) <= mie;
output_vector(2) <= '0';
output_vector(SIE_POS) <= sie;
output_vector(0) <= '0';
-- (mstatush)
output_vector(35 downto 32) <= (others => '0');
output_vector(SBE_POS) <= sbe;
output_vector(MBE_POS) <= mbe;
output_vector(63 downto 38) <= (others => '0');

q <= output_vector;

-- mie (machine interrupt enable, remember mie = mpie when we want to restore mie)
mie_next <= '0' when reset = '1' or clear_mie = '1' else mpie when restore_mie = '1' else d(MIE_POS) when wen_lower = '1' else mie;
mie <= mie_next when rising_edge(clk);
mie_out <= mie;

-- sie (supervisor interrupt enable, for now set to 0)
sie <= '0';

-- mpie (machine previous interrupt enable, we want to store mie when clear_mie is triggered)
-- Lab 6: mret sets mpie to 1, as the privileged spec requires.
mpie_next <= '0' when reset = '1' else mie when clear_mie = '1' else '1' when restore_mie = '1' else d(MPIE_POS) when wen_lower = '1' else mpie;
mpie <= mpie_next when rising_edge(clk);

-- spie (supervisor previous interrupt enable, for now set to 0)
spie <= '0';

-- mpp (machine previous privilege mode, in this case we'll set it to "11" since we'll always be in machine mode)
mpp <= "11";

-- spp (supervisor previous privilege mode, for now set to 0)
spp <= '0';

-- mprv (mprv is read-only 0 if U mode is not supported)
mprv <= '0';

-- mxr (mxr is read-only 0 if S mode is not supported)
mxr <= '0';

-- sum (supervisor user memory access, for now set to 0)
sum <= '0';

-- sbe, ube, mbe (supervisor/user/machine bit endianness, we are only supporting little endian => 0)
sbe <= '0';
ube <= '0';
mbe <= '0';

-- tvm (tvm is read-only 0 if S mode is not supported)
tvm <= '0';

-- tw (tw is read-only 0 when there are no modes less priviledged than M)
tw <= '0';

-- tsr (tsr is read-only 0 when S mode is not supported)
tsr <= '0';

-- fs (fs is read-only 0 if neither the f extension nor s-mode is implemented. come back to this if you want floating point support!)
fs <= "00";

-- vs (vs is read-only 0 if neither the v registers nor s mode are implemented)
vs <= "00";

-- xs (xs is read-only 0 for systems without additional user extensions)
xs <= "00";

-- sd (sd is always 0 when xs, vs, and fs are all read-only zero)
sd <= '0';


end Behavioral;
