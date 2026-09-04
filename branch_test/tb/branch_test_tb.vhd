library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_test_tb is
end entity branch_test_tb;

architecture sim of branch_test_tb is

    constant N : positive := 32;

    -- UUT Signals
    signal tb_a      : std_logic_vector(N - 1 downto 0) := (others => '0');
    signal tb_b      : std_logic_vector(N - 1 downto 0) := (others => '0');
    signal tb_op     : std_logic_vector(2 downto 0)      := (others => '0');
    signal tb_enable : std_logic                         := '0';
    signal tb_branch : std_logic;
begin

    -- Instantiate Unit Under Test (UUT)
    uut: entity work.branch_test
        generic map (
            N => N
        )
        port map (
            A      => tb_a,
            B      => tb_b,
            op     => tb_op,
            enable => tb_enable,
            branch => tb_branch
        );

    stim_proc: process
        -- Test patterns
        constant VAL_ZERO : std_logic_vector(31 downto 0) := x"00000000";
        constant VAL_POS5 : std_logic_vector(31 downto 0) := x"00000005";
        constant VAL_POS8 : std_logic_vector(31 downto 0) := x"00000008";
        constant VAL_NEG3 : std_logic_vector(31 downto 0) := x"FFFFFFFD"; -- -3 signed, 4294967293 unsigned
    begin


        wait;
    end process;

end architecture sim;
