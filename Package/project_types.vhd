--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_arith.ALL;
use ieee.math_real.ALL;

package project_types is

  -- type slv_array_32 is array(natural range <>) of std_logic_vector(31 downto 0);

  -- Enumerated type for instruction categories
  type instruction_type_t is (AUIPC, -- Register <- PC + Immediate
                              LUI,   -- Register <- Immediate
                              JAL,   -- Jump And Link (PC relative: target addr
                                     -- is PC + Immediate)
                              JALR,  -- Jump And Link Register (target addr is
                                     -- in a Register)
                              BRANCH,-- PC relative conditional branch
                              LOAD,  -- 5 variants: LB, LBU, LH, LHU, LW
                              STORE, -- 3 variants: SB, SH, SW
                              RI,    -- Register <- Register op Immediate
                              RR,    -- Register <- Register op Register
                              FENCE, -- Wait for all writes to complete
                              ECALL, -- Software interrupt
                              ILLEGAL);  
                              
  -- a record type to for bundling the signals from the instruction decoder to the datapath 
  type control_word is record
    Asel    : std_logic_vector(4 downto 0);
    Bsel    : std_logic_vector(4 downto 0);
    Dsel    : std_logic_vector(4 downto 0);
    Dlen    : std_logic;
    PCAsel  : std_logic;
    IMMBsel : std_logic;
    PCDsel  : std_logic;
    PCie    : std_logic;  -- You may want to treat this separately.
    PCle    : std_logic;  -- You may want to treat this separately.
    isBR    : std_logic;
    BRcond  : std_logic_vector(2 downto 0);
    ALUFunc : std_logic_vector(3 downto 0);
    IMM     : std_logic_vector(31 downto 0);
  end record control_word;
                            
                              
  -- Function to convert boolean to std_logic
  function To_Std_Logic(L: BOOLEAN) return std_ulogic;

  -- Function to calculate the instruction category
  function get_i_type(instruction : std_logic_vector(31 downto 0)) 
    return instruction_type_t;

  -- Function to construct the immediate 
  function get_immediate_value(
    instruction : std_logic_vector(31 downto 0);
    i_type : instruction_type_t;
    is_shift_imm: boolean) return std_logic_vector;
    
  -- function to return the ceiling of log base 2 of x
  function clog2(X: integer) return integer;

end project_types;


package body project_types is

  -- Function to convert boolean to std_logic
  function To_Std_Logic(L: BOOLEAN) return std_ulogic is
    begin
      if L then
        return('1');
      else
        return('0');
      end if;
    end function To_Std_Logic;


  -- function to get the instruction type
  function get_i_type(instruction : std_logic_vector(31 downto 0))
    return instruction_type_t is
    variable return_value : instruction_type_t;
  begin
    case instruction(6 downto 0) is
      when "0010111" => return_value := AUIPC;
      when "0110111" => return_value := LUI;
      when "1101111" => return_value := JAL;
      when "1100111" => return_value := JALR;
      -- check branch condition to make sure instruction is legal
      when "1100011" => return_value := BRANCH; 
      
      when "0000011" =>
        case instruction(14 downto 12) is
          when "000" | "001" | "010" | "100" | "101" => return_value := LOAD;
          when others => return_value := illegal;
        end case;
      when "0100011" =>
        case instruction(14 downto 12) is
          when "000" | "001" | "010" => return_value := STORE;
          when others => return_value := illegal;
        end case;
      when "0010011" => return_value := RI;
      when "0110011" => return_value := RR;
      when "0001111" => return_value := FENCE;
      when "1110011" => return_value := ECALL;
      when  others => return_value := ILLEGAL;
    end case;
    return return_value;
  end function;

  -- Function to get the immediate value based on the instruction type
  -- and the instruction.
  function get_immediate_value(
    instruction : std_logic_vector(31 downto 0);
    i_type : instruction_type_t;
    is_shift_imm: boolean) return std_logic_vector is
    variable
      ui_imm, jal_imm, b_imm, imm_12, store_imm,
      return_value : std_logic_vector(31 downto 0);
    constant jal_adjust : integer := 4;
  begin
    -- immediate for LUI and AUIPC
    ui_imm  := instruction(31 downto 12) & "000000000000";
    -- immediate for JAL  (need to subtract 4)
    jal_imm := std_logic_vector(signed(SXT(instruction(31) &
                               instruction(19 downto 12) &
                               instruction(20) &
                               instruction(30 downto 21) &
                               "0",32)));
    -- immediate for JALR and RI instructions (shifts are special)
    if is_shift_imm then
      imm_12 := "000000000000000000000000000" & instruction(24 downto 20);
    else
      imm_12 :=  std_logic_vector(signed(SXT(instruction(31 downto 20),32)));
    end if; 

    -- immediate for store instructions
    store_imm := "00000000000000000000" &
                 instruction(31 downto 25) &
                 instruction(11 downto 7);
                 
      b_imm   := "0000000000000000000" &
                 instruction(31) &
                 instruction(7) &
                 instruction (30 downto 25) &
                 instruction(11 downto 8) &
                 "0";

    case i_type is
      when LUI|AUIPC =>
        return_value := ui_imm;
      when JAL =>
        return_value := jal_imm;
      when JALR|RI|LOAD =>
        return_value := imm_12; 
      when BRANCH =>
        return_value := b_imm;
      when STORE =>
        return_value := store_imm;
      when others =>
        return_value := (others=>'0');
    end case;
    return return_value;
  end function;

  -- function to return the ceiling of log base 2 of x
  function clog2(X: integer) return integer is
  begin
    return integer(ceil(log2(real(X))));
  end function clog2;

end project_types;

--  type datapath_ctrl is (
--    -- signals to control muxes
--    dmarsel,-- select dbus into MAR rather than PC
--    memdsel,-- select memory as input to register file rather than the D bus
--    pcdsel, -- select program counter onto the D bus, instead of ALU output
--    pcasel, -- select program counter onto the A bus instead of register A
--    immbsel,-- select immediate onto the B bus instead of register B
--    -- signals to control latches
--    dlen,    -- latch into register file
--    pclen,   -- latch the program counter
--    pcien,   -- increment the program counter
--    mctrllen,-- latch the memory control register
--    maddrlen,-- latch the memory address register
--    mdatalen, -- latch the memory data register
--    -- signals to latch into the memory control register
--    memcen,
--    memoen,
--    memwen,
--    membyte,
--    memhalf,
--    sext
--    );

--  type datapath_ctrl_array is array(datapath_ctrl) of std_logic;
  
--  -- type control_word is record
--  --   i_type : instruction_type_t;
--  --   alu_op : alu_op_t;
--  --   immediate : std_logic_vector(31 downto 0);
--  --   ctrl: datapath_ctrl_array;
--  -- end record;

  
--  type instr_ctrl_array is array(instruction_type_t) of datapath_ctrl_array;

--  constant instr_ctrl_word : instr_ctrl_array :=
--    (
--      AUIPC     => "00011100110001110",
--      LUI       => "00001100110001110",
--      JAL       => "00111110110001110",
--      JALR      => "00001110110001110",
--      BRANCH    => "00011000110001110",
--      LW        => "11001101110001110",
--      LH        => "11001101110001101",
--      LB        => "11001101110001011",
--      LHU       => "11001101110001100",
--      LBU       => "11001101110001010",
--      SW        => "10001000111010110",
--      SH        => "10001000111010100",
--      SB        => "10001000111010010",
--      RI        => "00001100011001110",
--      RR        => "00000100011001110",
--      FENCE     => "00000000011001110",
--      EXCEPTION => "00000000011001110",
--      ILLEGAL   => "00000000011001110"
--      );        
      
--  constant skip_BRANCH_mask : datapath_ctrl_array := "11111101111111111";

--  -- When in reset, keep trying to deassert the control signals to
--  -- memory.
--  constant RESET_cw : datapath_ctrl_array := "00000000100111110";
--  -- When going from FETCHWAIT back to FETCHWAIT, make sure all control signals
--  -- going to memory are de-asserted.
--  constant FETCHWAIT_cw : datapath_ctrl_array := "00000000100111110";
--  -- When going from FETCHWAIT to FETCH, latch the PC into the MAR,
--  -- increment the PC, and start a memory word read operation
--  constant FETCHWAIT_proceed_cw : datapath_ctrl_array := "00100001110001110";
--  -- When going from FETCH1 to FETCH2, do nothing
--  constant FETCH1_cw : datapath_ctrl_array := "00100001111110010";
--  -- When going from FETCH back to FETCH, do nothing
--  constant FETCH2_cw : datapath_ctrl_array := "00000000000111110";
--  -- When going from FETCH to EXEC, latch the IR, and deassert all control
--  -- signals going to memory
--  constant FETCH2_proceed_cw : datapath_ctrl_array := "00000000100111110";

--  -- When we have a LD/ST instruction and memory is not ready, make sure
--  -- the control lines to memory are deasserted and stay in EXEC
--  constant EXEC_wait_cw : datapath_ctrl_array := "00000000100111110";
  
--  -- When staying in the LDST state, do nothing
--  constant LDST_cw : datapath_ctrl_array := "00000000000111110";
--  -- When proceeding from LDST to FETCHWAIT, deassert all control
--  -- lines to memory, and take remaining bits from the instruction
--  constant LDST_proceed_mask : datapath_ctrl_array := "00000000100111110";

--  type alu_op_t is (add_op, sub_op, xor_op, or_op, and_op,
--                    sll_op, srl_op, sra_op, pass_a_op, pass_b_op,
--                    slt_op, sltu_op, seq_op, sne_op, sge_op, sgeu_op,
--                    illegal_op);
