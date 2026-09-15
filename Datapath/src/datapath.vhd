library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.project_types.all;


entity data_path is 
  Port (
         cw: in control_word;
         clk: in std_logic;
         rst: in std_logic;
         Dbugsel: in Std_Logic_Vector(4 downto 0);
         Dbug: out Std_Logic_Vector(31 downto 0);
         PC_out: out Std_Logic_Vector(31 downto 0)
       );
end data_path;

architecture arch of data_path is
  signal take_branch, branch : std_logic;
  signal a,b, d_bus, a_bus, b_bus, alu_d, pc_q: std_logic_vector(31 downto 0);

begin

  reg_file : entity work.register_file
  generic map (
                Nsel => 5,
                Bits => 32
              )
  port map (
             clk => clk,
             reset => rst,
             den => cw.dlen,
             dsel => cw.dsel,
             din => d_bus,
             asel => cw.asel,
             bsel => cw.bsel,
             a => a,
             b => b,
             dbugsel => Dbugsel,
             dbug => Dbug
           );

  alu : entity work.alu
  generic map (
                XLEN => 32
              )
  port map (
             A => a_bus,
             B => b_bus,
             D => alu_d,
             func => cw.ALUFunc
           );

  btu : entity work.btu
  generic map (
                XLEN => 32
              )
  port map (
             RS1 => a,
             RS2 => b,
             cond => cw.BRcond,
             enable => cw.isBr,
             take_branch => take_branch 
           );

  pc : entity work.pc
  port map (
             clk => clk,
             d => alu_d,
             q => pc_q,
             count => cw.PCie,
             reset => rst,
             load => branch
           );

  with cw.PCDsel select 
    d_bus <= pc_q when '1',
             alu_d when others;

  with cw.PCAsel select 
    a_bus <= a when '0',
             pc_q when others;

  with cw.IMMBsel select 
    b_bus <= b when '0',
             cw.IMM when others;

  branch <= take_branch or cw.PCle;

  PC_out <= pc_q;


end architecture arch;


