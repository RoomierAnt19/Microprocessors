library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

package decoder is

function decode(selected: std_logic_vector; enable:std_logic)
    return std_logic_vector;

end decoder;

package body decoder is

function decode(selected: std_logic_vector; enable:std_logic)
    return std_logic_vector is
        variable decoded: std_logic_vector((2**selected'length)-1 downto 0);
        begin
        
        decoded := (others => '0');
        
        decoded(TO_INTEGER(unsigned(selected))) := enable;
        
        return decoded;
        end function;

end decoder;
