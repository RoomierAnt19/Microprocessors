library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.Math_real.all;

entity alu is 
  generic(XLEN: positive := 32);
  Port (A : in std_logic_vector(XLEN-1 downto 0);
        B : in std_logic_vector(XLEN-1 downto 0);
        D : out std_logic_vector(XLEN-1 downto 0);
        func : in std_logic_vector(3 downto 0)
       );
end alu;

architecture Behavioral of alu is
  constant N_sel : integer := integer(ceil(log2(real(XLEN))));

  signal shout : STD_LOGIC_VECTOR(XLEN-1 downto 0);
  signal shco : std_logic;

  signal adout : STD_LOGIC_VECTOR(XLEN-1 downto 0);
  signal adco : std_logic;
  signal adovf : std_logic;

  signal sub : std_logic;
  signal slt : STD_LOGIC_VECTOR(0 downto 0);
  signal ult : STD_LOGIC_VECTOR(0 downto 0);
  signal cout : STD_LOGIC_VECTOR(XLEN-1 downto 0);

  signal andout : STD_LOGIC_VECTOR(XLEN-1 downto 0);
  signal xorout : STD_LOGIC_VECTOR(XLEN-1 downto 0);
  signal orout : STD_LOGIC_VECTOR(XLEN-1 downto 0);

  signal which : std_logic_vector(2 downto 0);

begin
  which <= func(2 downto 0);

  sub <= func(3) or func(1);
  adder : entity work.Adder_Subtractor(Behavioral)
    generic map (N => XLEN)
    Port map(
              a => A,
              b => B,
              add_sub => sub,
              r => adout,
              carry_out => adco,
              overflow => adovf
            );

  shifter : entity work.Barrel_Shifter(Behavioral)
    generic map (N => N_sel)
    port map(
              din => A,
              dout => shout,
              shamt => B(N_sel-1 downto 0),
              func => func(3 downto 2),
              co => shco
            );

  andout <= a and b;
  xorout <= a xor b;
  orout <= a or b;

  slt(0) <= adout(XLEN-1) xor adovf;
  ult(0) <= not adco;
  cout <= (XLEN-1 downto 1 => '0') & slt when func(0) = '0' else 
          (XLEN-1 downto 1 => '0') & ult;

  D <= adout when which ?= "000" else 
       shout when which ?= "-01" else
       cout when which ?= "01-" else
       xorout when which ?= "100" else
       orout when which ?= "110" else
       andout;

end architecture Behavioral;

