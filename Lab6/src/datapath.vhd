library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.project_types.all;


entity data_path is
  Port (
         cw: in control_word;
         clk: in std_logic;
         rst: in std_logic;
         load: in std_logic;
         is_CSR: in std_logic;
         Dbugsel: in Std_Logic_Vector(4 downto 0);
         Dbug: out Std_Logic_Vector(31 downto 0);
         wdata: out Std_Logic_Vector(31 downto 0);
         instruction_address: in Std_Logic_Vector(31 downto 0);
         rdata: in Std_Logic_Vector(31 downto 0);
         PC_out: out Std_Logic_Vector(31 downto 0);
         address: out Std_Logic_Vector(31 downto 0);
         CSR_q: in Std_Logic_Vector(31 downto 0);
         CSR_d: out Std_Logic_Vector(31 downto 0);
         CSR_address: in Std_Logic_Vector(31 downto 0);
         take_CSR: in std_logic;
         CSR_en: out std_logic
       );
end data_path;

architecture arch of data_path is
  signal take_branch, branch : std_logic;
  signal d_bus_sel : Std_Logic_Vector(2 downto 0);
  signal a,b, d_bus, a_bus, b_bus, alu_d, pc_bus, pc_q, set, clear, CSR_a: std_logic_vector(31 downto 0);

begin
  ------------------------------------------------------------------------------
  -- REGISTER FILE
  ------------------------------------------------------------------------------
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

  ------------------------------------------------------------------------------
  -- ALU
  ------------------------------------------------------------------------------
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

  ------------------------------------------------------------------------------
  -- BRANCH TEST UNTI
  ------------------------------------------------------------------------------
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

  ------------------------------------------------------------------------------
  -- PROGRAM COUNTER
  ------------------------------------------------------------------------------
  pc_bus <= CSR_address when take_CSR else
            alu_d;
  pc : entity work.pc
  port map (
             clk => clk,
             d => alu_d,
             q => pc_q,
             count => cw.PCie,
             reset => rst,
             load => branch
           );

  ------------------------------------------------------------------------------
  -- DATA PATH BUS LINES
  ------------------------------------------------------------------------------
  d_bus_sel <= cw.PCDsel & load & is_CSR;

  with d_bus_sel select?
    d_bus <= pc_q when "1--",
             rdata when "-1-",
             CSR_q when "--1",
             alu_d when others;

  with cw.PCAsel select
    a_bus <= a when '0',
             instruction_address when others;

  with cw.IMMBsel select
    b_bus <= b when '0',
             cw.IMM when others;

  branch <= take_branch or cw.PCle or take_CSR;

  PC_out <= pc_q;

  address <= alu_d;
  wdata <= b;
  ------------------------------------------------------------------------------
  -- Set Clear Logic
  ------------------------------------------------------------------------------
  with cw.IMMBsel select
    CSR_a <= a when '0',
             cw.IMM when others;

  set <= CSR_q or CSR_a;
  clear <= CSR_q and (not CSR_a);

  with cw.ALUFunc(1 downto 0) select
    CSR_d <= CSR_a when "01",
             set when "10",
             clear when others;

  CSR_en <= '1' when (cw.ALUFunc(1 downto 0) = "01" or cw.Asel /= "00000") else '0';
end architecture arch;


