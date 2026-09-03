library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library work;
use work.my_package.all;


entity data_path is 
  Port (
    input: in control_word;
    clk: in std_logic
       );
end data_path;

architecture arch of data_path is

begin
  reg_file : entity work.register_file(behavioral)
    generic map (Nsel : )
    Port map (

             )

  alu : entity work.alu(behavioral)
    generic map (xlen => 32)
    Port map (
             )



end architecture arch;


