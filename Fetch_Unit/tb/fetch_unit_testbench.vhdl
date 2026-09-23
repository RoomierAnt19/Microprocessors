
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity fetch_unit_testbench is
end fetch_unit_testbench;

architecture Behavioral of fetch_unit_testbench is
  signal fetch, reset, sys_clock, ready: std_logic := '0';
  signal PC, instruction, address : STD_LOGIC_VECTOR ( 31 downto 0 ) := (others => '0');
begin


  uut: entity work.design_1_wrapper (STRUCTURE) 
    port map(
      PC => PC,
      address => address,
      fetch => fetch,
      instruction => instruction,
      ready => ready,
      reset => reset,
      sys_clock => sys_clock
      );
  
  sys_clock <= not sys_clock after 5 ns;
  reset <= '1' after 20 ns;

  process
  begin
    wait for 1500 ns;

    wait for 10 ns;
    PC <= x"00000000";
    fetch <= '1';
    wait for 10 ns;
    fetch <= '0';
    wait for 15 ns;
    wait until ready = '1';   

    wait for 10 ns;
    PC <= x"00000004";
    fetch <= '1';
    wait for 10 ns;
    fetch <= '0';
    wait for 15 ns;
    wait until ready = '1';   
    
    wait for 10 ns;
    PC <= x"00000008";
    fetch <= '1';
    wait for 10 ns;
    fetch <= '0';
    wait for 15 ns;
    wait until ready = '1';   
  end process;

end Behavioral;
