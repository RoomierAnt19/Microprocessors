library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.project_types.ALL;


entity ID_and_DP is
  port(
        instruction : in STD_LOGIC_VECTOR(31 downto 0);
        clk : in std_logic;
        rst : in std_logic;
        PCie : in std_logic;
        DBGsel :  in STD_LOGIC_VECTOR(4 downto 0);
        DBGreg : out STD_LOGIC_VECTOR(31 downto 0);
        PCout : out STD_LOGIC_VECTOR(31 downto 0)
      );

end entity ID_and_DP;

architecture rtl of ID_and_DP is
  signal cw : control_word;

begin

  instruction_decoder : entity work.instruction_decoder
  port map (
             instruction => instruction,
             cw => cw,
             PCie => PCie
           );

  data_path : entity work.data_path
  port map (
             cw => cw,
             clk => clk,
             rst => rst,
             Dbugsel => DBGsel,
             Dbug => DBGreg,
             PC_out => PCout
             );
end architecture rtl;
