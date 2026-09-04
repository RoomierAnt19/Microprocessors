library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_test_tb is
end entity branch_test_tb;

architecture sim of branch_test_tb is

    constant N : positive := 32;

    -- UUT Signals
    signal tb_a      : std_logic_vector(N - 1 downto 0) := (others => '0');
    signal tb_b      : std_logic_vector(N - 1 downto 0) := (others => '0');
    signal tb_op     : std_logic_vector(2 downto 0)      := (others => '0');
    signal tb_enable : std_logic                         := '0';
    signal tb_branch : std_logic;

    -- Helper procedure for applying tests and asserting output
    procedure check_branch(
        constant a_val       : in std_logic_vector(N - 1 downto 0);
        constant b_val       : in std_logic_vector(N - 1 downto 0);
        constant op_val      : in std_logic_vector(2 downto 0);
        constant en_val      : in std_logic;
        constant expected    : in std_logic;
        constant description : in string;
        signal sig_a         : out std_logic_vector(N - 1 downto 0);
        signal sig_b         : out std_logic_vector(N - 1 downto 0);
        signal sig_op        : out std_logic_vector(2 downto 0);
        signal sig_en        : out std_logic;
        signal sig_out       : in  std_logic
    ) is
    begin
        sig_a  <= a_val;
        sig_b  <= b_val;
        sig_op <= op_val;
        sig_en <= en_val;
        wait for 10 ns;

        assert sig_out = expected
            report "TEST FAILED: " & description & 
                   " | Expected: " & std_logic'image(expected) & 
                   ", Got: " & std_logic'image(sig_out)
            severity error;
    end procedure;

begin

    -- Instantiate Unit Under Test (UUT)
    uut: entity work.branch_test
        generic map (
            N => N
        )
        port map (
            A      => tb_a,
            B      => tb_b,
            op     => tb_op,
            enable => tb_enable,
            branch => tb_branch
        );

    stim_proc: process
        -- Test patterns
        constant VAL_ZERO : std_logic_vector(31 downto 0) := x"00000000";
        constant VAL_POS5 : std_logic_vector(31 downto 0) := x"00000005";
        constant VAL_POS8 : std_logic_vector(31 downto 0) := x"00000008";
        constant VAL_NEG3 : std_logic_vector(31 downto 0) := x"FFFFFFFD"; -- -3 signed, 4294967293 unsigned
    begin

        -- =========================================================
        -- 1. Check Enable gating (when enable = '0', branch must be '0')
        -- =========================================================
        check_branch(VAL_POS5, VAL_POS5, "000", '0', '0', "Enable is low (BEQ should not fire)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);

        -- =========================================================
        -- 2. Op: 000 (EQ)
        -- =========================================================
        check_branch(VAL_POS5, VAL_POS5, "000", '1', '1', "EQ: 5 == 5 (True)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_POS5, VAL_POS8, "000", '1', '0', "EQ: 5 == 8 (False)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);

        -- =========================================================
        -- 3. Op: 001 (NEQ)
        -- =========================================================
        check_branch(VAL_POS5, VAL_POS8, "001", '1', '1', "NEQ: 5 /= 8 (True)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_POS5, VAL_POS5, "001", '1', '0', "NEQ: 5 /= 5 (False)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);

        -- =========================================================
        -- 4. Op: 100 (LT - Signed Less Than)
        -- =========================================================
        check_branch(VAL_POS5, VAL_POS8, "100", '1', '1', "LT: +5 < +8 (True)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_NEG3, VAL_POS5, "100", '1', '1', "LT: -3 < +5 (True, signed)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_POS5, VAL_NEG3, "100", '1', '0', "LT: +5 < -3 (False, signed)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_POS5, VAL_POS5, "100", '1', '0', "LT: +5 < +5 (False)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);

        -- =========================================================
        -- 5. Op: 101 (GE - Signed Greater or Equal)
        -- =========================================================
        check_branch(VAL_POS8, VAL_POS5, "101", '1', '1', "GE: +8 >= +5 (True)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_POS5, VAL_POS5, "101", '1', '1', "GE: +5 >= +5 (True)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_NEG3, VAL_POS5, "101", '1', '0', "GE: -3 >= +5 (False, signed)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);

        -- =========================================================
        -- 6. Op: 110 (LTU - Unsigned Less Than)
        -- =========================================================
        check_branch(VAL_POS5, VAL_POS8, "110", '1', '1', "LTU: 5 < 8 (True)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        -- In unsigned terms, 0xFFFFFFFD is ~4.29 billion, so 5 < ~4.29B is True
        check_branch(VAL_POS5, VAL_NEG3, "110", '1', '1', "LTU: 5 < 0xFFFFFFFD (True, unsigned)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_NEG3, VAL_POS5, "110", '1', '0', "LTU: 0xFFFFFFFD < 5 (False, unsigned)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);

        -- =========================================================
        -- 7. Op: 111 (GEU - Unsigned Greater or Equal)
        -- =========================================================
        check_branch(VAL_NEG3, VAL_POS5, "111", '1', '1', "GEU: 0xFFFFFFFD >= 5 (True, unsigned)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_POS5, VAL_POS5, "111", '1', '1', "GEU: 5 >= 5 (True)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);
        check_branch(VAL_POS5, VAL_NEG3, "111", '1', '0', "GEU: 5 >= 0xFFFFFFFD (False, unsigned)", 
                     tb_a, tb_b, tb_op, tb_enable, tb_branch);

        report "--- ALL BRANCH TESTS COMPLETED SUCCESSFULLY ---" severity note;
        wait;
    end process;

end architecture sim;
