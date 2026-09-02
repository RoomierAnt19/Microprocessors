library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity Add_Sub_6bit is
generic ( N : integer := 8);
--  Port ( );
end Add_Sub_6bit;

architecture Behavioral of Add_Sub_6bit is
    signal ina, inb: unsigned (N-1 downto 0) := (others => '0');
    signal carry, over: std_logic;
    signal subtract: std_logic := '0';
    signal sum: std_logic_vector (N-1 downto 0) := (others => '0');
    

begin
    uut: entity work.Adder_Subtractor (adder_Nbit)
        generic map (N=>N)
        port map (a=>std_logic_vector(ina),b=>std_logic_vector(inb),r=>sum, add_sub=>subtract,carry_out=>carry,overflow=>over);
    
    ina <= ina+1 after 10 ns;
    inb <= inb+1 after 2**N*10 ns;
    subtract <= not subtract after 2**(N*2)*10 ns;       
    

end Behavioral;


