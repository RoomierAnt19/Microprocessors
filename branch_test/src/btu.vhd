library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity btu is
  generic( N: positive := 32);
  port (
    RS1 : in std_logic_vector(N-1 downto 0);
    RS2 : in std_logic_vector(N-1 downto 0);
    cond : in std_logic_vector(2 downto 0);
    enable : in std_logic;
    take_branch : out std_logic
  );
end entity btu;

architecture rtl of btu is
  signal adout: std_logic_vector(N-1 downto 0);
  signal co, ovf, lt, ltu, eq, output: std_logic;
  signal outcode: std_logic_vector(1 downto 0);


begin
  compare : entity work.Adder_Subtractor(Behavioral)
    generic map (N => N)
    Port map(
              a => RS1,
              b => RS2S2,
              add_sub => '1',
              r => adout,
              carry_out => co,
              overflow => ovf
            );

  lt <= adout(N-1) xor ovf;
  ltu <= not co;
  eq <= '1' when unsigned(adout) = 0 else '0';

  outcode <= cond(2 downto 1);
  output <= lt when outcode = "10" else
            ltu when outcode = "11" else
            eq when outcode = "00" else
            '0';

  take_branch <= (cond(0) xor output) and enable;
end architecture rtl;
