library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.project_types.all;

entity instruction_decoder is
  port (
         instruction: in std_logic_vector(31 downto 0);   
         cw: out control_word;
         PCie: in std_logic
       );
end entity instruction_decoder;

architecture rtl of instruction_decoder is
  signal instruction_type : instruction_type_t;
  signal is_shift_imm : BOOLEAN;
  signal is_RI : BOOLEAN;
  signal top_ALU_func : std_logic;
begin

  instruction_type <= get_i_type(instruction);

  cw.Bsel <= instruction(24 downto 20);
  cw.Dsel <= instruction(11 downto 7);

  with instruction_type select
    cw.Asel <= (others => '0') when LUI,
               instruction(19 downto 15) when others;

  with instruction_type select
    cw.Dlen <= '0' when STORE,
               '0' when BRANCH,
               '0' when FENCE,
               '0' when ECALL,
               '0' when ILLEGAL,
               '1' when others;

  with instruction_type select
    cw.PCasel <= '1' when AUIPC,
                 '1' when JAL,
                 '1' when BRANCH,
                 '0' when others;

  with instruction_type select
    cw.IMMBsel <= '0' when RR,
                  '1' when others;

  with instruction_type select
    cw.PCDsel <= '1' when JAL,
                 '1' when JALR,
                 '0' when others;

  with instruction_type select
    cw.PCle <= '1' when JAL,
               '1' when JALR,
               '0' when others;

  with instruction_type select
    cw.isBR <= '1' when BRANCH,
               '0' when others;

  cw.BRcond <= instruction(14 downto 12);

  with instruction(14 downto 12) select
    is_shift_imm <= TRUE when "001" or "101",
                    FALSE when others;

  with instruction_type select
    is_RI <= TRUE when RI,
             FALSE when others;

  top_ALU_func <= instruction(30) when is_shift_imm and is_RI
                  else '0';

  with instruction_type select
    cw.ALUfunc <= instruction(30) & instruction(14 downto 12) when RR,
                  top_ALU_func & instruction(14 downto 12) when RI,
                  "0000" when others;
  
  cw.IMM <= get_immediate_value(instruction, instruction_type, is_shift_imm and is_RI);

  cw.PCie <= PCie;

end architecture rtl;
