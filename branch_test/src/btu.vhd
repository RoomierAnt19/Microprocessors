library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity btu is
  generic( XLEN: positive := 32);
  port (
    RS1 : in std_logic_vector(XLEN-1 downto 0);
    RS2 : in std_logic_vector(XLEN-1 downto 0);
    cond : in std_logic_vector(2 downto 0);
    enable : in std_logic;
    take_branch : out std_logic
  );
end entity btu;

architecture rtl of btu is
  signal adout: std_logic_vector(XLEN-1 downto 0);
  signal co, ovf, lt, ltu, eq: std_logic;
  signal outcode: std_logic_vector(3 downto 0);


begin
  compare : entity work.Adder_Subtractor(Behavioral)
    generic map (N => XLEN)
    Port map(
              a => RS1,
              b => RS2,
              add_sub => '1',
              r => adout,
              carry_out => co,
              overflow => ovf
            );

  lt <= adout(XLEN-1) xor ovf;
  ltu <= not co;
  eq <= '1' when unsigned(adout) = 0 else '0';

  outcode <= enable & cond;
  with outcode select
    take_branch <= lt when "1100",
                   not lt when "1101",
                   ltu when "1110",
                   not ltu when "1111",
                   eq when "1000",
                   not eq when "1001",
                   '0' when others;
end architecture rtl;
