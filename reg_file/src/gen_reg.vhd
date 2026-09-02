library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity gen_reg is
  generic( N: integer := 8);
  port (
    clk: STD_logic;
    d: in std_logic_vector (N-1 downto 0);
    q: out std_logic_vector(N-1 downto 0);
    reset: in STD_logic;
    enable: in STD_logic
  );
end entity gen_reg;

architecture Behavioral of gen_reg is

  signal q_i, q_next: std_logic_vector(N-1 downto 0);
  signal ctrl: std_logic_vector(1 downto 0);

begin

  q_i <= q_next when rising_edge(clk);
  ctrl <= reset & enable;
  q <= q_i;

  with ctrl select q_next <=
    q_i when "00",
    d when "01",
    (others => '0') when others;

end architecture Behavioral;
