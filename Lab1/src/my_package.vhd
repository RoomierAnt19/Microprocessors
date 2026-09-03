library ieee;
use ieee.std_logic_1164.all;

package my_package is 
type control_word is record
  Asel  : std_logic_vector(4 downto 0);
  Bsel  : std_logic_vector(4 downto 0);
  Dsel  : std_logic_vector(4 downto 0);
  Dlen  : std_logic;
  PCAsel  : std_logic;
  IMMBsel : std_logic;
  PCDsel  : std_logic;
  PCie  : std_logic;
  isBR  : std_logic;
  BRcond  : std_logic_vector(2 downto 0);
  ALUFunc : std_logic_vector(3 downto 0);
  IMM : std_logic_vector(31 downto 0);
end record control_word;
end package my_package;
