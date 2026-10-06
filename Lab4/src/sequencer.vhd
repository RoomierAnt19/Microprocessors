library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


entity sequencer is
  port (
         clk : in std_logic;
         rst : in std_logic;
         ready : in std_logic;
         fetch : out std_logic;
         PCie : out std_logic;
         execute : out std_logic
       );
end entity sequencer;

architecture rtl of sequencer is
  type Seq_state_t is (RESET, START, WAITING);
  signal Seq_state, Seq_state_next, Seq_state_i: Seq_state_t;
  signal Start_next, Waiting_next: Seq_state_t;
begin
  ------------------------------------------------------------------------- 
  --Storage for Sequencer
  Seq_state <= Seq_state_next when rising_edge(clk);
  Seq_state_next <= RESET when rst = '1' else Seq_state_i;

  with Seq_state select Seq_state_i <=
  START when RESET,
  start_next when START,
  Waiting_next when others;

  Start_next <= START when ready = '0' else WAITING;
  Waiting_next <= WAITING when ready = '0' else START;
  -- Mealy outputs for RAC state machine
  PCie <= '1' when Seq_state = START and ready = '1'
                     else '0';

  execute <= '1' when Seq_state = WAITING and ready = '1'
                     else '0';
  -- Moore outputs for RAC state machine
  fetch <= '1' when Seq_state = START else '0';
end architecture rtl;



