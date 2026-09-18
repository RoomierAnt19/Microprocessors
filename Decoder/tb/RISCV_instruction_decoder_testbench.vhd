----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/09/2024 11:37:32 AM
-- Design Name: 
-- Module Name: RISCV_instruction_decoder_testbench - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use work.project_types.all;

entity RISCV_Inst_Dec_tb is
end RISCV_Inst_Dec_tb;

architecture Behavioral of RISCV_Inst_Dec_tb is
signal cw:control_word;

signal instruction : std_logic_vector(31 downto 0);   
--signal cw.Dsel : std_logic_vector(4 downto 0);
--signal cw.Asel : std_logic_vector(4 downto 0);
--signal cw.bsel : std_logic_vector(4 downto 0);
--signal imm : std_logic_vector(31 downto 0);
--signal func : std_logic_vector(3 downto 0);

begin



uut: entity work.instruction_decoder(rtl)
port map
(
    instruction => instruction,
    cw => cw,
    PCie => '0'
 );

test: process
begin
instruction <= X"00247CB7";
wait for 5 ns;
assert unsigned(cw.Dsel) = 25 and signed(cw.imm) = 2387968 and unsigned(cw.Asel) = 0 and cw.ALUfunc = "0000" report "LUI #1 not working" severity warning;

instruction <= X"008107B7";
wait for 5 ns;
assert unsigned(cw.Dsel) = 15 and signed(cw.imm) = 8454144 and unsigned(cw.Asel) = 0 and cw.ALUfunc = "0000" report "LUI #2 not working" severity warning;

instruction <= X"0BED0BB7";
wait for 5 ns;
assert unsigned(cw.Dsel) = 23 and signed(cw.imm) = 200081408 and unsigned(cw.Asel) = 0 and cw.ALUfunc = "0000" report "LUI #3 not working" severity warning;


instruction <= X"142CAEB7";
wait for 5 ns;
assert unsigned(cw.Dsel) = 29 and signed(cw.imm) = 338468864 and unsigned(cw.Asel) = 0 and cw.ALUfunc = "0000" report "LUI #4 not working" severity warning;


instruction <= X"095E5C37";
wait for 5 ns;
assert unsigned(cw.Dsel) = 24 and signed(cw.imm) = 157175808 and unsigned(cw.Asel) = 0 and cw.ALUfunc = "0000" report "LUI #5 not working" severity warning;

instruction <= X"01511A17";
wait for 5 ns;
assert unsigned(cw.Dsel) = 20 and signed(cw.imm) = 22089728 and cw.ALUfunc = "0000" report "AUIPC #1 not working" severity warning;

instruction <= X"000C8B97";
wait for 5 ns;
assert unsigned(cw.Dsel) = 23 and signed(cw.imm) = 819200 and cw.ALUfunc = "0000" report "AUIPC #2 not working" severity warning;

instruction <= X"FE5FF06F";
wait for 5 ns;
assert unsigned(cw.Dsel) = 0 and signed(cw.imm) = -28 and cw.ALUfunc = "0000" report "JAL #1 not working" severity warning;

instruction <= X"018002EF";
wait for 5 ns;
assert unsigned(cw.Dsel) = 5 and signed(cw.imm) = 24 and cw.ALUfunc = "0000" report "JAL #2 not working" severity warning;

instruction <= X"FEC08067";
wait for 5 ns;
assert unsigned(cw.Dsel) = 0 and unsigned(cw.Asel) = 1 and signed(cw.IMM) = -20 and cw.ALUfunc = "0000" report "JALR #1 not working" severity warning;

instruction <= X"12C10067";
wait for 5 ns;
assert unsigned(cw.Dsel) = 0 and unsigned(cw.Asel) = 2 and signed(cw.IMM) = 300 and cw.ALUfunc = "0000" report "JALR #2 not working" severity warning;

instruction <= X"00000663";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 0 and unsigned(cw.bsel) = 0 and signed(cw.IMM) = 12 and cw.ALUfunc = "0000" report "BRANCH #1 not working" severity warning;

instruction <= X"00209463";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 1 and unsigned(cw.bsel) = 2 and signed(cw.IMM) = 8 and cw.ALUfunc = "0000" report "BRANCH #2 not working" severity warning;

instruction <= X"0041C263";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 3 and unsigned(cw.bsel) = 4 and signed(cw.IMM) = 4 and cw.ALUfunc = "0000" report "BRANCH #3 not working" severity warning;

instruction <= X"00525063";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 4 and unsigned(cw.bsel) = 5 and signed(cw.IMM) = 0 and cw.ALUfunc = "0000" report "BRANCH #4 not working" severity warning;

instruction <= X"FE736EE3";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 6 and unsigned(cw.bsel) = 7 and signed(cw.IMM) = -4 and cw.ALUfunc = "0000" report "BRANCH #5 not working" severity warning;

instruction <= X"FE83FCE3";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 7 and unsigned(cw.bsel) = 8 and signed(cw.IMM) = -8 and cw.ALUfunc = "0000" report "BRANCH #6 not working" severity warning;

instruction <= X"4E550483";
wait for 5 ns;
assert unsigned(cw.Dsel) = 9 and unsigned(cw.Asel) = 10 and signed(cw.IMM) = 1253 and cw.ALUfunc = "0000" report "LOAD #1 not working" severity warning;

instruction <= X"DCD61583";
wait for 5 ns;
assert unsigned(cw.Dsel) = 11 and unsigned(cw.Asel) = 12 and signed(cw.IMM) = -563 and cw.ALUfunc = "0000" report "LOAD #2 not working" severity warning;

instruction <= X"19372683";
wait for 5 ns;
assert unsigned(cw.Dsel) = 13 and unsigned(cw.Asel) = 14 and signed(cw.IMM) = 403 and cw.ALUfunc = "0000" report "LOAD #3 not working" severity warning;

instruction <= X"18284783";
wait for 5 ns;
assert unsigned(cw.Dsel) = 15 and unsigned(cw.Asel) = 16 and signed(cw.IMM) = 386 and cw.ALUfunc = "0000" report "LOAD #4 not working" severity warning;

instruction <= X"12F95883";
wait for 5 ns;
assert unsigned(cw.Dsel) = 17 and unsigned(cw.Asel) = 18 and signed(cw.IMM) = 303 and cw.ALUfunc = "0000" report "LOAD #5 not working" severity warning;

instruction <= X"153A0E23";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 20 and unsigned(cw.bsel) = 19 and signed(cw.IMM) = 348 and cw.ALUfunc = "0000" report "STORE #1 not working" severity warning;

instruction <= X"355B11A3";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 22 and unsigned(cw.bsel) = 21 and signed(cw.IMM) = 835 and cw.ALUfunc = "0000" report "STORE #2 not working" severity warning;

instruction <= X"3B7C2423";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 24 and unsigned(cw.bsel) = 23 and signed(cw.IMM) = 936 and cw.ALUfunc = "0000" report "STORE #3 not working" severity warning;

instruction <= X"3C8D0C93";
wait for 5 ns;
assert unsigned(cw.Dsel) = 25 and unsigned(cw.Asel) = 26 and signed(cw.IMM) = 968 and cw.ALUfunc = "0000" report "ADDI #1 not working" severity warning;

instruction <= X"ED5E0D93";
wait for 5 ns;
assert unsigned(cw.Dsel) = 27 and unsigned(cw.Asel) = 28 and signed(cw.IMM) = -299 and cw.ALUfunc = "0000" report "ADDI #2 not working" severity warning;

instruction <= X"FFF00F13";
wait for 5 ns;
assert unsigned(cw.Dsel) = 30 and unsigned(cw.Asel) = 0 and signed(cw.IMM) = -1 and cw.ALUfunc = "0000" report "ADDI #3 not working" severity warning;

instruction <= X"7FF08E13";
wait for 5 ns;
assert unsigned(cw.Dsel) = 28 and unsigned(cw.Asel) = 1 and signed(cw.IMM) = 2047 and cw.ALUfunc = "0000" report "ADDI #4 not working" severity warning;

instruction <= X"E0C8A793";
wait for 5 ns;
assert unsigned(cw.Dsel) = 15 and unsigned(cw.Asel) = 17 and signed(cw.IMM) = -500 and cw.ALUfunc = "0010" report "SLTI not working" severity warning;

instruction <= X"EDC93393";
wait for 5 ns;
assert unsigned(cw.Dsel) = 7 and unsigned(cw.Asel) = 18 and signed(cw.IMM) = -292 and cw.ALUfunc = "0011" report "SLTIU not working" severity warning;

instruction <= X"F9C14093";
wait for 5 ns;
assert unsigned(cw.Dsel) = 1 and unsigned(cw.Asel) = 2 and signed(cw.IMM) = -100 and cw.ALUfunc = "0100" report "XORI not working" severity warning;

instruction <= X"1F426193";
wait for 5 ns;
assert unsigned(cw.Dsel) = 3 and unsigned(cw.Asel) = 4 and signed(cw.IMM) = 500 and cw.ALUfunc = "0110" report "ORI not working" severity warning;

instruction <= X"EBF37293";
wait for 5 ns;
assert unsigned(cw.Dsel) = 5 and unsigned(cw.Asel) = 6 and signed(cw.IMM) = -321 and cw.ALUfunc = "0111" report "ANDI not working" severity warning;

instruction <= X"00141393";
wait for 5 ns;
assert unsigned(cw.Dsel) = 7 and unsigned(cw.Asel) = 8 and signed(cw.IMM) = 1 and cw.ALUfunc = "0001" report "SLLI #1 not working" severity warning;

instruction <= X"01D51493";
wait for 5 ns;
assert unsigned(cw.Dsel) = 9 and unsigned(cw.Asel) = 10 and signed(cw.IMM) = 29 and cw.ALUfunc = "0001" report "SLLI #2 not working" severity warning;

instruction <= X"00265593";
wait for 5 ns;
assert unsigned(cw.Dsel) = 11 and unsigned(cw.Asel) = 12 and signed(cw.IMM) = 2 and cw.ALUfunc = "0101" report "SRLI #1 not working" severity warning;

instruction <= X"01F75693";
wait for 5 ns;
assert unsigned(cw.Dsel) = 13 and unsigned(cw.Asel) = 14 and signed(cw.IMM) = 31 and cw.ALUfunc = "0101" report "SRLI #2 not working" severity warning;

instruction <= X"40385793";
wait for 5 ns;
assert unsigned(cw.Dsel) = 15 and unsigned(cw.Asel) = 16 and unsigned(cw.IMM(4 downto 0)) = 3 and cw.ALUfunc = "1101" report "SRAI #1 not working" severity warning;

instruction <= X"41E95893";
wait for 5 ns;
assert unsigned(cw.Dsel) = 17 and unsigned(cw.Asel) = 18 and unsigned(cw.IMM(4 downto 0)) = 30 and cw.ALUfunc = "1101" report "SRAI #2 not working" severity warning;

instruction <= X"00208033";
wait for 5 ns;
assert unsigned(cw.Dsel) = 0 and unsigned(cw.Asel) = 1 and unsigned(cw.bsel) = 2 and cw.ALUfunc = "0000" report "ADD not working" severity warning;

instruction <= X"40418133";
wait for 5 ns;
assert unsigned(cw.Dsel) = 2 and unsigned(cw.Asel) = 3 and unsigned(cw.bsel) = 4 and cw.ALUfunc = "1000" report "SUB not working" severity warning;

instruction <= X"007312B3";
wait for 5 ns;
assert unsigned(cw.Dsel) = 5 and unsigned(cw.Asel) = 6 and unsigned(cw.bsel) = 7 and cw.ALUfunc = "0001" report "SLL not working" severity warning;

instruction <= X"00A42433";
wait for 5 ns;
assert unsigned(cw.Dsel) = 8 and unsigned(cw.Asel) = 8 and unsigned(cw.bsel) = 10 and cw.ALUfunc = "0010" report "SLT not working" severity warning;

instruction <= X"00B534B3";
wait for 5 ns;
assert unsigned(cw.Dsel) = 9 and unsigned(cw.Asel) = 10 and unsigned(cw.bsel) = 11 and cw.ALUfunc = "0011" report "SLTU not working" severity warning;

instruction <= X"00D645B3";
wait for 5 ns;
assert unsigned(cw.Dsel) = 11 and unsigned(cw.Asel) = 12 and unsigned(cw.bsel) = 13 and cw.ALUfunc = "0100" report "XOR not working" severity warning;

instruction <= X"0107D733";
wait for 5 ns;
assert unsigned(cw.Dsel) = 14 and unsigned(cw.Asel) = 15 and unsigned(cw.bsel) = 16 and cw.ALUfunc = "0101" report "SRL not working" severity warning;

instruction <= X"413958B3";
wait for 5 ns;
assert unsigned(cw.Dsel) = 17 and unsigned(cw.Asel) = 18 and unsigned(cw.bsel) = 19 and cw.ALUfunc = "1101" report "SRA not working" severity warning;

instruction <= X"016AEA33";
wait for 5 ns;
assert unsigned(cw.Dsel) = 20 and unsigned(cw.Asel) = 21 and unsigned(cw.bsel) = 22 and cw.ALUfunc = "0110" report "OR not working" severity warning;

instruction <= X"01AC7BB3";
wait for 5 ns;
assert unsigned(cw.Dsel) = 23 and unsigned(cw.Asel) = 24 and unsigned(cw.bsel) = 26 and cw.ALUfunc = "0111" report "AND not working" severity warning;

instruction <= X"F60008E3";
wait for 5 ns;
assert cw.Dlen = '0' and unsigned(cw.Asel) = 0 and unsigned(cw.bsel) = 0 and signed(cw.IMM) = -144 and cw.ALUfunc = "0000" report "BRANCH #7 not working" severity warning;

instruction <= X"FB9FF06F";
wait for 5 ns;
assert unsigned(cw.Dsel) = 0 and cw.ALUfunc = "0000" and signed(cw.IMM) = -72 report "JAL #3 not working" severity warning;

instruction <= X"40010093";
wait for 5 ns;
assert unsigned(cw.Dsel) = 1 and unsigned(cw.Asel) = 2 and signed(cw.IMM) = 1024 and cw.ALUfunc = "0000" report "ADDI #5 not working" severity warning;
wait;
end process;

end Behavioral;

