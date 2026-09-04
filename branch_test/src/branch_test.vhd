library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity branch_test is
  generic( N: positive := 32);
  port (
    A : in std_logic_vector(N-1 downto 0);
    B : in std_logic_vector(N-1 downto 0);
    op : in std_logic_vector(2 downto 0);
    enable : in std_logic;
    branch : out std_logic
  );
end entity branch_test;

architecture rtl of branch_test is
  signal adout: std_logic_vector(N-1 downto 0);
  signal co, ovf, lt, ltu, eq, output: std_logic;
  signal outcode: std_logic_vector(1 downto 0);


begin
  compare : entity work.Adder_Subtractor(Behavioral)
    generic map (N => N)
    Port map(
              a => A,
              b => B,
              add_sub => '1',
              r => adout,
              carry_out => co,
              overflow => ovf
            );

  lt <= adout(N-1) xor ovf;
  ltu <= not co;
  eq <= '1' when unsigned(adout) = 0 else '0';

  outcode <= op(2 downto 1);
  output <= lt when outcode = "10" else
            ltu when outcode = "11" else
            eq when outcode = "00" else
            '0';

  branch <= (op(0) xor output) and enable;
end architecture rtl;
