library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;


entity reg_test is
end reg_test;

architecture Behavioral of reg_test is

    component register_file
    
    port(
    clk : in std_logic;
    reset: in std_logic;
    den: in std_logic;
    dsel: in std_logic_vector(1 downto 0);
    asel: in std_logic_vector(1 downto 0);
--    bsel: in std_logic_vector(1 downto 0);
    din: in std_logic_vector(7 downto 0);
    a: out std_logic_vector(7 downto 0)
--    b: out std_logic_vector(7 downto 0)
    );
end component;

signal clk : std_logic := '0';
signal reset: std_logic := '1';
signal dsel: std_logic_vector(1 downto 0) := (others => '0');
signal din: std_logic_vector(7 downto 0) := (others => '0');
signal asel: std_logic_vector(1 downto 0) := (others => '0');
signal a: std_logic_vector(7 downto 0) := (others => '0');
signal bsel: std_logic_vector(1 downto 0) := (others => '0');
signal b: std_logic_vector(7 downto 0) := (others => '0');
signal den: std_logic := '1';

constant clk_period : time := 20 ns;
begin

uut: register_file port map(
    clk  => clk,
    reset => reset,
    den => den,
    dsel => dsel,
    asel => asel,
--    bsel => bsel,
    din => din,
    a => a
--    b => b
    );
    
clk <= not clk after clk_period/2;

reset <= '0' after 40ns;

din <= "00000011" after 80 ns,
     "00001100" after 120 ns,
     "00110011" after 160 ns,
     "11111111" after 200 ns,
     "10000000" after 240 ns,
     "00000000" after 300 ns;
     
dsel <= "01" after 120 ns,
        "10" after 160 ns,
        "11" after 200 ns,
        "00" after 240 ns,
        "01" after 300 ns; 
        
asel <= "01" after 120 ns,
        "10" after 160 ns,
        "11" after 200 ns,
        "00" after 240 ns,
        "01" after 300 ns; 

--bsel <= "01" after 120 ns,
--        "10" after 160 ns,
--        "11" after 200 ns,
--        "00" after 240 ns,
--        "01" after 300 ns; 


den <= '0' after 280 ns;
   
end Behavioral;