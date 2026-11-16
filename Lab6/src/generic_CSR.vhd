library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
-- use IEEE.NUMERIC_STD.ALL;

-- This file defines a generic Control and Status Register (CSR).  A
-- CSR may be Read Only (RO), Read/Write (RW), Write Any Read Legal
-- (WARL), or may be divided into fields, each with their own
-- attributes.

-- The "RObits" generic specifies which bits of the register are read
-- only.  Any attemp to write to bits marked as read only will be
-- ignored.

-- The "Default" generic allows us to define the contents of each RO
-- bit in the register, as well as the default content of the register
-- when it comes out of reset.

entity generic_CSR is
  generic(
    WARL_bits  : std_logic_vector(31 downto 0) := (others => '0');
    PASS_bits  : std_logic_vector(31 downto 0) := (others => '0');
    Default_bits : std_logic_vector(31 downto 0) := (others => '0')
    );
  port (
    clk, reset, wen: in std_logic;
    d :  in std_logic_vector(31 downto 0);
    q : out std_logic_vector(31 downto 0);
    passthrough :  in std_logic_vector(31 downto 0) := (others => '0')
    );
end generic_CSR;

architecture Behavioral of generic_CSR is
  signal data : std_logic_vector(31 downto 0) := Default_bits;
  signal next_data : std_logic_vector(31 downto 0);
begin

  next_data <= Default_bits when reset = '1' else
               (Default_bits and WARL_bits) or (d and (not WARL_bits)) when wen = '1' else
               data;

  bits: for I in 31 downto 0 generate
    bitI: if WARL_bits(I) = '1' generate
      data(I) <= Default_bits(I);
    elsif PASS_bits(I) = '1' generate
      data(I) <= passthrough(I);
    else generate
      data(I) <= next_data(I) when rising_edge(clk);
    end generate;
  end generate;
  
  q <= data;

end Behavioral;
