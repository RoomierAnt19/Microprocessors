library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity left is
--  Port ( );
end left;

architecture Behavioral of left is
    signal di, do: std_logic_vector (7 downto 0) := (others => '0');
    signal sht: unsigned  (2 downto 0) := (others => '0');
    signal fu: unsigned (1 downto 0) := (others => '0');
    signal co: std_logic;
    

begin
    uut: entity work.Barrel_Shifter (Behavioral)
        generic map (N=>3)
        port map( din => di,
                  dout => do,
                  shamt => std_logic_vector(sht),
                  func => std_logic_vector(fu),
                  co => co
                  );
    di <= "10010000";
    fu <= "11";
    sht <= sht+1 after 10 ns;
end Behavioral;
