library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity Barrel_Shifter is
    generic(N: natural := 3);
    Port ( din : in STD_LOGIC_VECTOR (2**N-1 downto 0);
           dout : out STD_LOGIC_VECTOR ((2**N)-1 downto 0);
           shamt : in STD_LOGIC_VECTOR (N-1 downto 0);
           func : in STD_LOGIC_VECTOR (1 downto 0);
           co : out STD_LOGIC
           );
end Barrel_Shifter;

architecture Behavioral of Barrel_Shifter is
    type stage_array is array (0 to N) of std_logic_vector(din'range);
    signal stage: stage_array;
    signal zero: std_logic_vector (2**(N-1) downto 0) := (others => '0');
    signal one: std_logic_vector (2**(N-1) downto 0) := (others => '1');
begin

co <= 
    '0' when TO_INTEGER(unsigned(shamt)) = 0 or func= "00" else
    din(2**N-TO_INTEGER(unsigned(shamt))) when func= "01" else
    din(TO_INTEGER(unsigned(shamt))-1);

stage(0) <= din;
Shift: for I in N downto 1 generate
    sI: stage(I) <= 
        --No shift
        stage(I-1) when shamt(I-1) = '0' else
    
        --Shift left
        stage(I-1)(2**N-2**(I-1)-1 downto 0) & zero(2**(I-1)-1 downto 0) when func?="-0" else
        
        --Shift arithmetic right
        one(2**(I-1)-1 downto 0) & stage(I-1)(2**N-1 downto 2**(I-1)) when func="11" and stage(I-1)((2**N)-1 downto (2**N)-1) = "1" else
        
        zero(2**(I-1)-1 downto 0) & stage(I-1)(2**N-1 downto 2**(I-1));
end generate Shift;
dout <= stage(N);

end Behavioral;
