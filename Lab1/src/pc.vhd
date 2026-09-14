library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity pc is
  port (
    clk: STD_logic;
    d: in std_logic_vector (31 downto 0);
    q: out std_logic_vector(31 downto 0);
    count: in STD_logic;
    load: in STD_logic;
    reset: in std_logic
  );
end entity pc;

architecture Behavioral of pc is

  signal q_i, q_next, q_count: std_logic_vector(29 downto 0);
  signal ctrl: std_logic_vector(2 downto 0);

begin
  ctrl <= reset & load & count;

  q_count <= Std_Logic_Vector(unsigned(q_i) + 1);

  q_i <= q_next when rising_edge(clk);

  q <= q_i & "00";

  with ctrl select? 
  q_next <=
    q_count when "001",
    q_i when "000",
    (others => '0') when "1---",
    d when others;
end architecture Behavioral;

