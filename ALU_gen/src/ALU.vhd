library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity alu_gen is 
  generic(N: integer := 8);
  Port (a : in std_logic_vector(N-1 downto 0);
        b : in std_logic_vector(N-1 downto 0);
        r : out std_logic_vector(N-1 downto 0);
        op : in std_logic_vector(3 downto 0)
       );
end alu_gen;


