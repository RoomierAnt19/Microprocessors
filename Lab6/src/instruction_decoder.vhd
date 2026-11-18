library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.project_types.all;

entity instruction_decoder is
  port (
         instruction: in std_logic_vector(31 downto 0);
         cw: out control_word;
         is_store: out std_logic;
         mem_op: out std_logic;
         CSR_sel: out Std_Logic_Vector(31 downto 20);
         is_CSR: out Std_Logic;
         is_mret: out Std_Logic;
         is_trap: out Std_Logic;
         mcause: out Std_Logic_Vector(4 downto 0);
         PCie: in std_logic
       );
end entity instruction_decoder;

architecture rtl of instruction_decoder is
  signal instruction_type : instruction_type_t;
  signal is_shift_imm, is_RI : BOOLEAN;
  signal top_ALU_func, is_csr_dlen : std_logic;
  signal mcause_i : Std_Logic_Vector(4 downto 0);
begin

  instruction_type <= get_i_type(instruction);

  cw.Bsel <= instruction(24 downto 20);
  cw.Dsel <= instruction(11 downto 7);
  cw.BRcond <= instruction(14 downto 12);

  with instruction_type select
    cw.Asel <= (others => '0') when LUI,
               instruction(19 downto 15) when others;

  with instruction(14 downto 12) select
    is_csr_dlen <= '0' when "000" | "100",
                    '1' when others;

  with instruction_type select
    cw.Dlen <= '0' when STORE,
               '0' when BRANCH,
               '0' when FENCE,
               is_csr_dlen when ECALL,
               '0' when ILLEGAL,
               '1' when others;

  with instruction_type select
    cw.PCasel <= '1' when AUIPC,
                 '1' when JAL,
                 '1' when BRANCH,
                 '0' when others;

  with instruction_type select
    cw.IMMBsel <= '0' when RR,
                  instruction(14) when ECALL,
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

  with instruction(14 downto 12) select
    is_shift_imm <= TRUE when "001" | "101",
                    FALSE when others;


  with instruction_type select
    is_RI <= TRUE when RI,
             FALSE when others;

  top_ALU_func <= instruction(30) when is_shift_imm
                  else '0';

  with instruction_type select
    cw.ALUfunc <= instruction(30) & instruction(14 downto 12) when RR,
                  top_ALU_func & instruction(14 downto 12) when RI,
                  top_ALU_func & instruction(14 downto 12) when ECALL, --Maybe get rid of
                  "0000" when others;
  
  cw.IMM <= get_immediate_value(instruction, instruction_type, is_shift_imm and is_RI);

  cw.PCie <= PCie;

  is_store <= '1' when instruction_type = STORE else '0';

  mem_op <= '1' when instruction_type = STORE or instruction_type = LOAD else '0';

  ------------------------------------------------------------------------------
  -- CSR instructions 
  ------------------------------------------------------------------------------
  CSR_sel <= instruction(31 downto 20);

  with instruction_type select
    is_CSR <= is_csr_dlen when ECALL,
              '0' when others;

  is_mret <= '1' when (instruction_type = ECALL and instruction(14 downto 12) = "000" and instruction(31 downto 20) = x"302") else
             '0';

  is_trap <= '1' when instruction_type = ILLEGAL else
             mcause_i(0) when instruction(14 downto 12) = "000" else
             '0';

  mcause_i <= "01011" when (instruction_type = ECALL and instruction(31 downto 20) = x"000") else
              "00011" when (instruction_type = ECALL and instruction(31 downto 20) = x"001") else
              "00010";

  mcause <= mcause_i;

end architecture rtl;
