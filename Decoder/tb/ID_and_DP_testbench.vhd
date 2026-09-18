--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use work.project_types.ALL;

entity ID_and_DP_testbench is
end ID_and_DP_testbench;

architecture Behavioral of ID_and_DP_testbench is
  signal instruction : STD_LOGIC_VECTOR (31 downto 0);
  signal pcie : std_logic := '0';
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal DBGsel : std_logic_vector(4 downto 0);
  signal DBGreg, PCout : std_logic_vector(31 downto 0);
  
  procedure clk_pulse(signal clk : inout std_logic) is 
  begin
    wait for 10 ns;
    clk <= '1';
    wait for 10 ns;
    clk <= '0';
  end procedure;
  
begin

UUT: entity work.ID_and_DP (rtl)
  port map(
    instruction => instruction,
    pcie => pcie,
    clk => clk,
    rst => rst,
    DBGsel =>  DBGsel,
    DBGreg => DBGreg, 
    PCout => PCout
 );


test: process is
  variable checks : natural := 0;
  variable errors : natural := 0;

  -- Count every check.  Report only the ones that fail, using the same
  -- message text the old assert statements used.
  procedure check(cond : in boolean; msg : in string) is
  begin
    checks := checks + 1;
    if not cond then
      errors := errors + 1;
      report msg severity error;
    end if;
  end procedure;

begin
    clk_pulse(clk);
    clk_pulse(clk);
    rst <= '0';
    clk_pulse(clk);

    -- addi t2, x0, -1      // t2 becomes -1
    DBGsel <= "00111";
    instruction <= X"FFF00393";
    clk_pulse(clk);
    check(signed(DBGreg) = -1, "addi t2, x0, -1 is not working");
  
    -- addi t3, x0, 1
    DBGsel <= std_logic_vector(to_unsigned(28,5));
    instruction <= X"00100E13";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "addi t3, x0, 1 is not working");
  
    -- addi t4, x0, 2047
    DBGsel <= std_logic_vector(to_unsigned(29,5));
    instruction <= X"7FF00E93";
    clk_pulse(clk);
    check(signed(DBGreg) = 2047, "addi t4, x0, 2047 is not working");
  
    -- addi t5, x0, 0x7CE
    DBGsel <= std_logic_vector(to_unsigned(30,5));
    instruction <= X"7CE00F13";
    clk_pulse(clk);
    check(DBGreg = x"000007CE", "addi t5, x0, 0x7CE is not working");

    -- li  t0, 2       # t0 =  2
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"00200293";
    clk_pulse(clk);
    check(signed(DBGreg) = 2, "li  t0, 2 is not working");
  
    -- li  t1, 46      # t1 = 46
    DBGsel <= std_logic_vector(to_unsigned(6,5));
    instruction <= X"02E00313";
    clk_pulse(clk);
    check(signed(DBGreg) = 46, "li  t1, 46 is not working");
  
    -- li  t2, 10      # t2 = 10
    DBGsel <= std_logic_vector(to_unsigned(7,5));
    instruction <= X"00A00393";
    clk_pulse(clk);
    check(signed(DBGreg) = 10, "li  t2, 10 is not working");
  
    -- add t3, t0, t0  # t3 =  2 +  2 =  4
    DBGsel <= std_logic_vector(to_unsigned(28,5));
    instruction <= X"00528E33";
    clk_pulse(clk);
    check(signed(DBGreg) = 4, " add t3, t0, t0 is not working");
    
    -- add t4, t0, t1  # t4 =  2 + 46 = 48
    DBGsel <= std_logic_vector(to_unsigned(29,5));
    instruction <= X"00628EB3";
    clk_pulse(clk);
    check(signed(DBGreg) = 48, "add t4, t0, t1 is not working");
  
    -- add t4, t4, t2  # t4 = 48 + 10 = 58
    DBGsel <= std_logic_vector(to_unsigned(29,5));
    instruction <= X"007E8EB3";
    clk_pulse(clk);
    check(signed(DBGreg) = 58, "add t4, t4, t2 is not working");
  
    -- mv   t0, t1     # t0 = t1
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"00030293";
    clk_pulse(clk);
    check(signed(DBGreg) = 46, "mv   t0, t1 is not working");
  
    -- li  t0, 2       # t0 =  2
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"00200293";
    clk_pulse(clk);
    check(signed(DBGreg) = 2, "li  t0, 2 is not working");

    -- li  t1, 46      # t1 = 46
    DBGsel <= std_logic_vector(to_unsigned(6,5));
    instruction <= X"02E00313";
    clk_pulse(clk);
    check(signed(DBGreg) = 46, "li  t1, 46 is not working");
    
    -- li  t2, 10      # t2 = 10
    DBGsel <= std_logic_vector(to_unsigned(7,5));
    instruction <= X"00A00393";
    clk_pulse(clk);
    check(signed(DBGreg) = 10, "li  t2, 10 is not working");
  
    -- sub t3, t1, t0  # t3 = 46 -  2 = 44
    DBGsel <= std_logic_vector(to_unsigned(28,5));
    instruction <= X"40530E33";
    clk_pulse(clk);
    check(signed(DBGreg) = 44, "sub t3, t1, t0 is not working");
  
    -- sub t4, t0, t2  # t4 =  2 - 10 = -8
    DBGsel <= std_logic_vector(to_unsigned(29,5));
    instruction <= X"40728EB3";
    clk_pulse(clk);
    check(signed(DBGreg) = -8, "sub t4, t0, t2 is not working");
  
    -- neg t5, t0      # t5 = -2
    DBGsel <= std_logic_vector(to_unsigned(30,5));
    instruction <= X"40500F33";
    clk_pulse(clk);
    check(signed(DBGreg) = -2, "neg t5, t0 is not working");
  
    -- sub t6, x0, t0  # t6 = 0 - 2 = -2  ; The x0 register is always zero
    DBGsel <= std_logic_vector(to_unsigned(31,5));
    instruction <= X"40500FB3";
    clk_pulse(clk);
    check(signed(DBGreg) = -2, "sub t6, x0, t0 is not working");
  
    -- lui t0, 1       # t0 = 1 << 12 = 0x1000 = 4096
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"000012B7";
    clk_pulse(clk);
    check(signed(DBGreg) = 4096, "lui t0, 1 is not working");
  
    -- lui t1, 3       # t1 = 3 << 12 = 0x3000 = 12288
    DBGsel <= std_logic_vector(to_unsigned(6,5));
    instruction <= X"00003337";
    clk_pulse(clk);
    check(signed(DBGreg) = 12288, "lui t1, 3 is not working");
    
    -- lui t2, 0x100   # t2 = 0x100 << 12 = 0x100000 = 1048576
    DBGsel <= std_logic_vector(to_unsigned(7,5));
    instruction <= X"001003B7";
    clk_pulse(clk);
    check(signed(DBGreg) = 1048576, "lui t2, 0x100 is not working");
  
    -- add tests for shift, branch, and jump instructions

    -- Tim's tests
    -- addi t0, zero, 1 -- t0 = 1
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"00100293";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "addi t0, zero, 1 is not working");
    
    -- add t1, t0, t0 // t1 = 2
    DBGsel <= std_logic_vector(to_unsigned(6,5));
    instruction <= X"00528333";
    clk_pulse(clk);
    check(signed(DBGreg) = 2, "add t1, t0, t0 is not working");
    
    -- sll t2, t1, t0 // t2 = 4
    DBGsel <= std_logic_vector(to_unsigned(7,5));
    instruction <= X"005313B3";
    clk_pulse(clk);
    check(signed(DBGreg) = 4, "sll t2, t1, t0 is not working");
    
    -- sub t3, t2, t0 // t3 = 3
    DBGsel <= std_logic_vector(to_unsigned(28,5));
    instruction <= X"40538E33";
    clk_pulse(clk);
    check(signed(DBGreg) = 3, "sub t3, t2, t0 is not working");
    
    -- sub t4, zero, t0 // t4 = -1
    DBGsel <= std_logic_vector(to_unsigned(29,5));
    instruction <= X"40500EB3";
    clk_pulse(clk);
    check(signed(DBGreg) = -1, "sub t4, zero, t0 is not working");
    
    -- slt t5, zero, t4 // t5 = 0
    DBGsel <= std_logic_vector(to_unsigned(30,5));
    instruction <= X"01D02F33";
    clk_pulse(clk);
    check(signed(DBGreg) = 0, "slt t5, zero, t4 is not working");
    
    -- sltu t6, zero, t4 // t6 = 1
    DBGsel <= std_logic_vector(to_unsigned(31,5));
    instruction <= X"01D03FB3";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "sltu t6, zero, t4 is not working");
    
    -- slt s5, t0, t1 // s5 = 1
    DBGsel <= std_logic_vector(to_unsigned(21,5));
    instruction <= X"0062AAB3";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "slt s5, t0, t1 is not working");
    
    -- sltu s6, zero, zero // s6 = 0
    DBGsel <= std_logic_vector(to_unsigned(22,5));
    instruction <= X"00003B33";
    clk_pulse(clk);
    check(signed(DBGreg) = 0, "sltu s6, zero, zero is not working");
    
    -- xor s0, t4, t3 // s0 = FFFFFFFC
    DBGsel <= std_logic_vector(to_unsigned(8,5));
    instruction <= X"01CEC433";
    clk_pulse(clk);
    check(DBGreg = X"FFFFFFFC", "xor s0, t4, t3 is not working");
    
    -- sra s1, s0, t0 // s1 = FFFFFFFE
    DBGsel <= std_logic_vector(to_unsigned(9,5));
    instruction <= X"405454B3";
    clk_pulse(clk);
    check(DBGreg = X"FFFFFFFE", "sra s1, s0, t0 is not working");
    
    -- srl s2, s0, t0 // s2 = 7FFFFFFE
    DBGsel <= std_logic_vector(to_unsigned(18,5));
    instruction <= X"00545933";
    clk_pulse(clk);
    check(signed(DBGreg) = X"7FFFFFFE", "srl s2, s0, t0 is not working");
    
    -- or s3, t2, t0 // s3 = 5
    DBGsel <= std_logic_vector(to_unsigned(19,5));
    instruction <= X"0053E9B3";
    clk_pulse(clk);
    check(signed(DBGreg) = 5, "or s3, t2, t0 is not working");
    
    -- and s4, s3, t2 // s4 = 4
    DBGsel <= std_logic_vector(to_unsigned(20,5));
    instruction <= X"0079FA33";
    clk_pulse(clk);
    check(signed(DBGreg) = 4, "and s4, s3, t2 is not working");
    
    -- beq t0, t1, 8 // PCout = 0
    instruction <= X"00628463";
    clk_pulse(clk);
    check(signed(PCout) = 0, "beq t0, t1, 8 is not working");
    
    -- beq t0, t6, 8 // PCout = 8
    instruction <= X"01F28463";
    clk_pulse(clk);
    check(signed(PCout) = 8, "beq t0, t6, 8 is not working");
    
    -- bne t0, t6, 8 // PCout = 8
    instruction <= X"01F29463";
    clk_pulse(clk);
    check(signed(PCout) = 8, "bne t0, t6, 8 is not working");
    
    -- bne t0, t1, 8 // PCout = 16
    instruction <= X"00629463";
    clk_pulse(clk);
    check(signed(PCout) = 16, "bne t0, t1, 8 is not working");
    
    --  blt zero, zero, 8 // PCout = 16
    instruction <= X"00004463";
    clk_pulse(clk);
    check(signed(PCout) = 16, "blt zero, zero, 8 is not working");
    
    -- blt t4, t0, 8 // PCout = 24
    instruction <= X"005EC463";
    clk_pulse(clk);
    check(signed(PCout) = 24, "blt t4, t0, 8 is not working");
    
    -- bge t4, t0, 8 // PCout = 24
    instruction <= X"005ED463";
    clk_pulse(clk);
    check(signed(PCout) = 24, "bge t4, t0, 8 is not working");
    
    -- bge zero, zero, 8 // PCout = 32
    instruction <= X"00005463";
    clk_pulse(clk);
    check(signed(PCout) = 32, "bge zero, zero, 8 is not working");
    
    -- bltu t4, t0, 8 // PCout = 32
    instruction <= X"005EE463";
    clk_pulse(clk);
    check(signed(PCout) = 32, "bltu t4, t0, 8 is not working");
    
    -- bltu t0, t4, 8 // PCout = 40
    instruction <= X"01D2E463";
    clk_pulse(clk);
    check(signed(PCout) = 40, "bltu t0, t4, 8 is not working");
    
    -- bgeu t0, t4, 8 // PCout = 40
    instruction <= X"01D2F463";
    clk_pulse(clk);
    check(signed(PCout) = 40, "bgeu t0, t4, 8 is not working");
    
    -- bgeu t4, t0,8 // PCout = 48
    instruction <= X"005EF463";
    clk_pulse(clk);
    check(signed(PCout) = 48, "bgeu t4, t0,8 is not working");
    
    -- slti s2, zero, -1 // s2 = 0
    DBGsel <= std_logic_vector(to_unsigned(18,5));
    instruction <= X"FFF02913";
    clk_pulse(clk);
    check(signed(DBGreg) = 0, "slti s2, zero, -1 is not working");
    
    -- lui s4, 300 // s4 = 1228800
    DBGsel <= std_logic_vector(to_unsigned(20,5));
    instruction <= X"0012CA37";
    clk_pulse(clk);
    check(signed(DBGreg) = 1228800, "lui s4, 300 is not working");
    
    -- sltiu s3, s4, -1 // s3 = 1
    DBGsel <= std_logic_vector(to_unsigned(19,5));
    instruction <= X"FFFA3993";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "sltiu s3, s4, -1 is not working");
    
    -- xori s5, s3, 3 // s5 = 2
    DBGsel <= std_logic_vector(to_unsigned(21,5));
    instruction <= X"0039CA93";
    clk_pulse(clk);
    check(signed(DBGreg) = 2, "xori s5, s3, 3 is not working");
    
    -- ori s6, s5, 4 // s6 = 6
    DBGsel <= std_logic_vector(to_unsigned(22,5));
    instruction <= X"004AEB13";
    clk_pulse(clk);
    check(signed(DBGreg) = 6, "ori s6, s5, 4 is not working");
    
    -- andi s7, s6, 4 // s7 = 4
    DBGsel <= std_logic_vector(to_unsigned(23,5));
    instruction <= X"004B7B93";
    clk_pulse(clk);
    check(signed(DBGreg) = 4, "andi s7, s6, 4 is not working");
    
    -- slli s8, s7, 2 // s8 = 16
    DBGsel <= std_logic_vector(to_unsigned(24,5));
    instruction <= X"002B9C13";
    clk_pulse(clk);
    check(signed(DBGreg) = 16, "slli s8, s7, 2 is not working");
    
    -- addi s9, x0, -4 // s9 = -4
    DBGsel <= std_logic_vector(to_unsigned(25,5));
    instruction <= X"FFC00C93";
    clk_pulse(clk);
    check(signed(DBGreg) = -4, "addi s9, x0, -4 is not working");
    
    -- srli s10, s9, 1 // s10 = 7FFFFFFFE
    DBGsel <= std_logic_vector(to_unsigned(26,5));
    instruction <= X"001CDD13";
    clk_pulse(clk);
    check(DBGreg = X"7FFFFFFE", "srli s10, s9, 1 is not working");
    
    -- srai s11, s9, 1 // s10 = -2
    DBGsel <= std_logic_vector(to_unsigned(27,5));
    instruction <= X"401CDD93";
    clk_pulse(clk);
    check(signed(DBGreg) = -2, "srai s11, s9, 1 is not working");
    
    -- jal, x1, 8 // x1 = 48, pcout = 56
    DBGsel <= std_logic_vector(to_unsigned(1,5));
    instruction <= X"008000EF";
    clk_pulse(clk);
    check(signed(DBGreg) = 48 and signed(pcout) = 56, "jal, x1, 8 is not working");

    -- jalr x2, 16(s9) // x2 = 56, pcout = 12
    DBGsel <= std_logic_vector(to_unsigned(2,5));
    instruction <= X"010C8167";
    clk_pulse(clk);
    check(signed(DBGreg) = 56 and signed(pcout) = 12, "jalr x2, 16(s9) is not working");

-- Trevor's tests
    
    -- addi x2, x0, 32        x2 = 32
    DBGsel <= std_logic_vector(to_unsigned(2,5));
    instruction <= X"02000113";
    clk_pulse(clk);
    check(signed(DBGreg) = 32, "addi x2, x0, 32 is not working");
    
    -- addi x3, x0, 3        x3 = 3
    DBGsel <= std_logic_vector(to_unsigned(3,5));
    instruction <= X"00300193";
    clk_pulse(clk);
    check(signed(DBGreg) = 3, "addi x3, x0, 3 is not working");
    
    -- sll x5, x2, x3   
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"003112b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 256, "sll x5, x2, x3 is not working");
    
    -- srl x5, x2, x3   
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"003152b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 4, "srl x5, x2, x3 is not working");
    
    -- addi x3, x0, 826        x3 = 826
    DBGsel <= std_logic_vector(to_unsigned(3,5));
    instruction <= X"33a00193";
    clk_pulse(clk);
    check(signed(DBGreg) = 826, "addi x3, x0, 826 is not working");
    
    -- addi x2, x0, 861        x2 = 861
    DBGsel <= std_logic_vector(to_unsigned(2,5));
    instruction <= X"35d00113";
    clk_pulse(clk);
    check(signed(DBGreg) = 861, "addi x2, x0, 861 is not working");
    
    -- and x5, x2, x3       861 and 826 = 792 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"003172b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 792, "srl x5, x2, x3 is not working");
    
    -- or x5, x2, x3       861 or 826 = 895 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"003162b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 895, "or x5, x2, x3 is not working");
    
    -- xor x5, x2, x3       861 xor 826 = 103 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"003142b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 103, "xor x5, x2, x3 is not working");
    
    -- slt x5, x2, x3       861 < 826 = 0 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"003122b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 0, "slt x5, x2, x3 is not working");
    
    -- slt x5, x3, x2       861 > 826 = 1 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"0021a2b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "slt x5, x3, x2 is not working");
    
    -- addi x3, x0, -900   x3 = -900 
    DBGsel <= std_logic_vector(to_unsigned(3,5));
    instruction <= X"c7c00193";
    clk_pulse(clk);
    check(signed(DBGreg) = -900, "addi x3, x0, -900 is not working");
    
    -- sltu x5, x2, x3       826 < unsigned(-900) = 1 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"003132b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "sltu x5, x2, x3 is not working");
    
    -- sltu x5, x3, x2       861 > unsigned(-900) = 0 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"0021b2b3";
    clk_pulse(clk);
    check(signed(DBGreg) = 0, "sltu x5, x3, x2 is not working");
    
    
    -- slli x5, x2, 3       861 slli 3 = 6888 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"00311293";
    clk_pulse(clk);
    check(signed(DBGreg) = 6888, "slli x5, x2, 3 is not working");
    
    -- slti x5, x2, 3       861 < 3 = 0 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"00312293";
    clk_pulse(clk);
    check(signed(DBGreg) = 0, "slti x5, x2, 3 is not working");
    
    -- sltiu x5, x2, -1       861 < unsigned(-1) = 1 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"fff13293";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "sltiu x5, x2, -1 is not working");
    
    -- srli x5, x2, 2       861 srli 2 = 215 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"00215293";
    clk_pulse(clk);
    check(signed(DBGreg) = 215, "srli x5, x2, 2 is not working");
    
    -- ori x5, x2, 35       861 ori 35 = 895 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"37f16293";
    clk_pulse(clk);
    check(signed(DBGreg) = 895, "ori x5, x2, 35 is not working");
    
    -- andi x5, x2, 35       861 andi 35 = 1 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"02317293";
    clk_pulse(clk);
    check(signed(DBGreg) = 1, "andi x5, x2, 35 is not working");
    
    -- xori x5, x2, 35       861 xori 35 = 894 
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"02314293";
    clk_pulse(clk);
    check(signed(DBGreg) = 894, "xori x5, x2, 35 is not working");

   -- auipc x1, 1000 // x1 = 4096012
    DBGsel <= std_logic_vector(to_unsigned(1,5));
    instruction <= X"003E8097";
    clk_pulse(clk);
    check(signed(DBGreg) = 4096012, "auipc x1, 1000 is not working");



    -- More jal tests.  pcie is tied low in this testbench, so the PC never
    -- self-increments and the value linked into rd is the un-incremented PC.
    -- The auipc test above leaves the PC at 12.

    -- jal x5, -12 // x5 = 12, PCout = 0   (backward jump)
    DBGsel <= std_logic_vector(to_unsigned(5,5));
    instruction <= X"FF5FF2EF";
    clk_pulse(clk);
    check(signed(DBGreg) = 12 and signed(PCout) = 0, "jal x5, -12 is not working");

    -- jal x6, 2044 // x6 = 0, PCout = 2044   (large positive offset)
    DBGsel <= std_logic_vector(to_unsigned(6,5));
    instruction <= X"7FC0036F";
    clk_pulse(clk);
    check(signed(DBGreg) = 0 and signed(PCout) = 2044, "jal x6, 2044 is not working");

    -- jal x0, 8 // x0 stays 0, PCout = 2052   (link into x0 must be discarded)
    DBGsel <= std_logic_vector(to_unsigned(0,5));
    instruction <= X"0080006F";
    clk_pulse(clk);
    check(signed(DBGreg) = 0 and signed(PCout) = 2052, "jal x0, 8 is not working");

    -- Summary of the whole run
    if errors = 0 then
      report "ID_and_DP testbench PASSED: all " & integer'image(checks) &
        " checks passed." severity note;
    else
      report "ID_and_DP testbench FAILED: " & integer'image(errors) &
        " of " & integer'image(checks) & " checks failed." severity failure;
    end if;

    wait;    
end process;

end Behavioral;
