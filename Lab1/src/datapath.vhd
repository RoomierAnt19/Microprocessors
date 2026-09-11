library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.my_package.all;


entity data_path is 
  Port (
         input: in control_word;
         clk: in std_logic
       );
end data_path;

architecture arch of data_path is
  signal branch : std_logic;
  signal a,b, d_bus, a_bus, b_bus, alu_d, pc_q: std_logic_vector(31 downto 0);

begin

  reg_file : entity work.register_file
  generic map (
                Nsel => 5,
                Bits => 32
              )
  port map (
             clk => clk,
             reset => '0',
             den => input.dlen,
             dsel => input.dsel,
             din => d_bus,
             asel => input.asel,
             bsel => input.bsel,
             a => a,
             b => b
           );

  alu : entity work.alu
  generic map (
                XLEN => 32
              )
  port map (
             A => a_bus,
             B => b_bus,
             D => alu_d,
             func => input.ALUFunc
           );

  btu : entity work.btu
  generic map (
                XLEN => 32
              )
  port map (
             RS1 => a,
             RS2 => b,
             cond => input.BRcond,
             enable => input.isBr,
             take_branch => branch 
           );

  pc : entity work.pc
  port map (
             clk => clk,
             d => alu_d,
             q => pc_q,
             count => input.PCie,
             load => branch
           );

  with input.PCDsel select 
    d_bus <= pc_q when '0',
             alu_d when others;

  with input.PCAsel select 
    a_bus <= a when '0',
             pc_q when others;

  with input.IMMBsel select 
    b_bus <= b when '0',
             input.IMM when others;


end architecture arch;


