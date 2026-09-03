
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity Adder_Subtractor is
    generic ( N : integer := 6);
    
    Port ( a : in std_logic_vector (N-1 downto 0);
           b : in std_logic_vector (N-1 downto 0);
           add_sub : in STD_LOGIC;
           r : out STD_LOGIC_VECTOR (N-1 downto 0);
           carry_out : out STD_LOGIC;
           overflow : out STD_LOGIC
           );
end Adder_Subtractor;

architecture behavioral of Adder_Subtractor is
    signal sub: unsigned (N downto 0);
    signal topbits: unsigned (2 downto 0);
    signal subtract, modB: std_logic_vector (N-1 downto 0);
    


begin
    subtract <= (others => add_sub);
    modB <= b xor subtract;
    sub <= unsigned('0' & modB( N-2 downto 0) & add_sub) + unsigned('0' & a( N-2 downto 0) & add_sub);
    topbits <= unsigned('0' & modB(N-1 downto N-1) & sub(N)) + unsigned('0' & a(N-1 downto N-1) & sub(N));
    overflow <= sub(N) xor topbits(2);
    carry_out <= topbits(2);
    r <= std_logic_vector(topbits(1) & sub(N-1 downto 1));
    
end behavioral;
