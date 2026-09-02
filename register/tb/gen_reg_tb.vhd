library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.env.stop; -- Standard VHDL-2008 simulation stop

entity gen_reg_tb is
end entity gen_reg_tb;

architecture Behavioral of gen_reg_tb is
  component gen_reg 
    port(
      clk    : in  std_logic;
      reset  : in  std_logic;
      d      : in  std_logic_vector(7 downto 0);
      q      : out std_logic_vector(7 downto 0);
      enable : in  std_logic
    );
  end component;

  signal clk    : std_logic := '0';
  signal reset  : std_logic := '1';
  signal d      : std_logic_vector(7 downto 0) := (others => '0');
  signal q      : std_logic_vector(7 downto 0); -- Do not pre-assign output signals
  signal enable : std_logic := '1';

  constant clk_period : time := 20 ns;
  signal sim_finished : boolean := false;

begin

  utt: gen_reg port map(
    clk    => clk,
    reset  => reset,
    d      => d,
    q      => q,
    enable => enable
  );

  -- Clock process with termination check
  clk_proc: process
  begin
    while not sim_finished loop
      clk <= '0';
      wait for clk_period / 2;
      clk <= '1';
      wait for clk_period / 2;
    end loop;
    wait;
  end process;

  -- Stimulus process
  stim_proc: process
  begin
    -- Initial Reset
    reset <= '1';
    wait for 40 ns;
    reset <= '0';

    -- Apply Stimulus
    wait for 40 ns; -- 80 ns total
    d <= "00000011";

    wait for 40 ns; -- 120 ns total
    d <= "00001100";

    wait for 40 ns; -- 160 ns total
    d <= "00110011";

    wait for 80 ns; -- 240 ns total
    d <= "10000000";

    wait for 40 ns; -- 280 ns total
    enable <= '0';

    wait for 20 ns; -- 300 ns total
    d <= "00000000";

    -- End of test
    wait for 100 ns;
    sim_finished <= true;
    stop; -- Terminates simulation cleanly
    wait;
  end process;

end architecture Behavioral;
