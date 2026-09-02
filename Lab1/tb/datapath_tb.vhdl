library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.my_package.all;

entity datapath_testbench is
end datapath_testbench;

architecture arch of datapath_testbench is
  signal  imm    : std_logic_vector(15 downto 0):="0000000010101010";
  signal  asel   : std_logic_vector(2 downto 0):="000";
  signal  bsel   : std_logic_vector(2 downto 0):="000";
  signal  ALUfunc: std_logic_vector(3 downto 0):="0000";
  signal  dsel   : std_logic_vector(2 downto 0):="000";
  signal  Memin    : std_logic_vector(15 downto 0):="0000000000000000";
  signal  clk    : std_logic:='0';
  signal  rst    : std_logic:='1';
  signal  Memout   : std_logic_vector(15 downto 0);
  signal  Addr   : std_logic_vector(15 downto 0);
  signal  flags  : flag_array;
  signal  cw     : control_t_array;
begin

  uut: entity work.data_path(arch)
    port map(
      cw => cw    ,
      imm    => imm    ,
      asel   => asel   ,
      bsel   => bsel   ,
      ALUfunc=> ALUfunc,
      dsel   => dsel   ,
      Memin    => Memin    ,
      clk    => clk    ,
      rst    => rst    ,
      Memout   => Memout   ,
      Addr   => Addr   ,
      flags  => flags  
      );

  process
  begin
    loop
      wait for 5 ns;
      clk <= not clk;
    end loop;
  end process;

  process
  begin
    cw(Irle) <= '1';
    cw(Memsel) <= '0'; 
    cw(immBsel) <= '0';
    cw(pcDsel) <= '0';
    cw(pcAsel) <= '0';
    cw(pcle) <= '1';
    cw(pcie) <= '1';
    cw(dle) <= '1';
    cw(fle) <= '1';
    cw(aoe) <= '1';
    cw(memen) <= '1';
    cw(memrd) <= '1';
    cw(memwr) <= '1';
    cw(clken) <= '1';
      
    rst <=  '0';
    wait for 5 ns;
    rst <=  '1';
    wait for 1 ns;
    Memin <= "1010101010101010";
    cw(Memsel) <= '1'; 
    dsel <= "000";
    cw(dle) <= '0';
    wait for 10 ns;
    cw(dle) <= '1';
    cw(pcie) <= '1';
    wait for 100 ns;
    cw(pcie) <= '0';
    cw(pcDsel) <= '1';
    cw(aoe) <='0';
    wait for 10 ns;
    cw(aoe) <='1';
    wait;
  end process;
  

end arch;
