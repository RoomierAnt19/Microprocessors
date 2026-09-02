library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.decoder.all;
use ieee.numeric_std.all;


entity register_file is
    generic(Nsel: integer := 2;
            Bits: integer := 8);
    Port ( clk, reset : in STD_LOGIC;
           den : in STD_LOGIC;
           dsel : in STD_LOGIC_VECTOR (Nsel-1 downto 0);
           din : in STD_LOGIC_VECTOR (Bits-1 downto 0);
           asel : in STD_LOGIC_VECTOR (Nsel-1 downto 0);
           bsel : in STD_LOGIC_VECTOR (Nsel-1 downto 0);
           a : out STD_LOGIC_vector(Bits-1 downto 0);
           b : out STD_LOGIC_vector(Bits-1 downto 0)
        );
end register_file;

architecture Behavioral of register_file is

type signal_array is array (2**Nsel-1 downto 0) of
    std_logic_vector(Bits-1 downto 0);
signal array_reg: signal_array;

signal decoded: std_logic_vector(2**Nsel-1 downto 0);
begin

decoded <= decode(dsel, den);

regs: for i in 0 to (2**Nsel-1) - 1 generate
    begin
        regsi: entity work.gen_reg (behavioral)
        generic map(N => Bits)
        port map(clk => clk,
                reset => reset,
                enable => decoded(i+1),
                d => din,
                q => array_reg(i+1));
        end generate;
      
array_reg(0) <= (others => '0');
a <= array_reg(to_integer(unsigned(asel)));
b <= array_reg(to_integer(unsigned(bsel)));


end Behavioral;
