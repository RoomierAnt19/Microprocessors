library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.stop; -- Standard VHDL-2008 simulation termination

entity register_file_tb is
end register_file_tb;

architecture Behavioral of register_file_tb is

  component register_file
    port(
      clk   : in  std_logic;
      reset : in  std_logic;
      den   : in  std_logic;
      dsel  : in  std_logic_vector(1 downto 0);
      asel  : in  std_logic_vector(1 downto 0);
--    bsel  : in  std_logic_vector(1 downto 0);
      din   : in  std_logic_vector(7 downto 0);
      a     : out std_logic_vector(7 downto 0)
--    b     : out std_logic_vector(7 downto 0)
    );
  end component;

  -- Inputs initialized to default state
  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';
  signal den   : std_logic := '1';
  signal dsel  : std_logic_vector(1 downto 0) := (others => '0');
  signal asel  : std_logic_vector(1 downto 0) := (others => '0');
  signal din   : std_logic_vector(7 downto 0) := (others => '0');
--signal bsel  : std_logic_vector(1 downto 0) := (others => '0');

  -- Outputs left uninitialized (driven strictly by UUT)
  signal a     : std_logic_vector(7 downto 0);
--signal b     : std_logic_vector(7 downto 0);

  constant clk_period : time := 20 ns;
  signal sim_finished : boolean := false;

begin

  uut: register_file port map(
    clk   => clk,
    reset => reset,
    den   => den,
    dsel  => dsel,
    asel  => asel,
--  bsel  => bsel,
    din   => din,
    a     => a
--  b     => b
  );

  -- Clock process with termination condition
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

  -- Stimulus process matching your exact signal timings
  stim_proc: process
  begin
    -- 0 ns: Initial state
    reset <= '1';
    den   <= '1';
    dsel  <= "00";
    asel  <= "00";
    din   <= (others => '0');

    -- 40 ns
    wait for 40 ns;
    reset <= '0';

    -- 80 ns
    wait for 40 ns;
    din   <= "00000011";

    -- 120 ns
    wait for 40 ns;
    din   <= "00001100";
    dsel  <= "01";
    asel  <= "01";

    -- 160 ns
    wait for 40 ns;
    din   <= "00110011";
    dsel  <= "10";
    asel  <= "10";

    -- 200 ns
    wait for 40 ns;
    din   <= "11111111";
    dsel  <= "11";
    asel  <= "11";

    -- 240 ns
    wait for 40 ns;
    din   <= "10000000";
    dsel  <= "00";
    asel  <= "00";

    -- 280 ns
    wait for 40 ns;
    den   <= '0';

    -- 300 ns
    wait for 20 ns;
    din   <= "00000000";
    dsel  <= "01";
    asel  <= "01";

    -- Allow final values to settle, then halt simulation
    wait for 100 ns;
    sim_finished <= true;
    stop;
    wait;
  end process;

end Behavioral;
