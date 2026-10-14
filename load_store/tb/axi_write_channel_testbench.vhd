--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- axi_write_channel_testbench
--
-- Self-checking testbench for the Lab 5 generic AXI write engine.  It
-- instantiates the engine as an AXI4 manager, plays the part of the
-- subordinate on the other end of the three write channels, and checks
-- both sides: that the engine puts the address, the data and the
-- strobes it was given on the bus unchanged, and that it obeys the AXI
-- handshake rules while doing it.
--
-- The unit under test must be an entity named axi_write_channel with an
-- architecture named behavioral and exactly the interface given in the
-- Lab 5 handout.  The testbench binds to that entity by name, so a
-- design whose ports differ will not simulate, no matter how correct
-- the logic inside it is.
--
-- There is no memory here.  The engine does not decide what a write
-- means, it only carries one: what it must get right is that AWADDR,
-- WDATA and WSTRB arrive at the subordinate exactly as the client
-- presented them, one beat, with the handshakes in order.  Whether the
-- bytes land in the right place is the load/store unit's problem, and
-- load_store_unit_testbench checks that against a real memory.
--
-- What is checked
-- ---------------
-- After every clock edge:
--
--   1. AWVALID and WVALID, once asserted, stay asserted until their
--      READY is seen.  A manager may not withdraw a write request.
--   2. AWADDR, AWLEN, AWSIZE and AWBURST hold still for as long as
--      AWVALID is high and AWREADY has not been seen, and WDATA, WSTRB
--      and WLAST do the same on their own channel.
--   3. AWLEN is 0, AWSIZE is 010 and AWBURST is 01 whenever AWVALID is
--      high: one beat, four bytes, INCR.
--   4. WLAST is high whenever WVALID is high.  There is one beat, so it
--      is always the last one.
--   5. No address, data beat or response is exchanged that was not
--      asked for, and the three counts agree at the end.
--   6. AWVALID and WVALID are low while rst is high and on the cycle
--      after it falls.
--
-- And for every write:
--
--   7. AWADDR is the address, WDATA the data and WSTRB the strobes that
--      the client presented when start was taken.
--   8. ready falls on the cycle after a start is taken.
--   9. ready does not come back up until the subordinate has answered on
--      the response channel.  Taking the data is not the end of a write.
--
-- The subordinate stalls at random and independently on all three
-- channels.  AWREADY and WREADY are each held low for a random spell
-- and withdrawn again while waiting, and the two are not synchronised,
-- so the address phase and the data phase land in either order and with
-- a different gap every time.  The response is then held back a further
-- random delay.  The client side stalls too: 0 to 3 idle cycles between
-- writes, so back to back writes and long gaps are both covered.  The
-- stalls come from three LFSRs with different seeds, so the run is
-- random but repeats exactly.
--
-- A directed phase at the end asserts start in the one cycle where it is
-- most likely to be taken by mistake, which is the cycle after the
-- response arrives, when two of the three machines are already idle.
--
-- Every check is counted.  The run ends with one PASSED or FAILED
-- line, and a failing run ends with severity failure so that a
-- scripted simulation exits with an error.  After 25 failures the
-- individual reports stop, but the count in the summary line is
-- complete.
--
-- Running it
-- ----------
--   ghdl -a --std=08 axi_write_channel.vhdl axi_write_channel_testbench.vhdl
--   ghdl -e --std=08 axi_write_channel_testbench
--   ghdl -r --std=08 axi_write_channel_testbench
--
-- Analyse anything the engine depends on, such as a register entity of
-- your own, ahead of axi_write_channel.vhdl on that first line.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity axi_write_channel_testbench is
end axi_write_channel_testbench;

architecture behavioral of axi_write_channel_testbench is

  constant ADDR_WIDTH : integer := 32;
  constant DATA_WIDTH : integer := 32;
  constant ID_WIDTH   : integer := 1;
  constant STRB_WIDTH : integer := DATA_WIDTH/8;

  constant NUM_WRITES : natural := 200;
  constant TIMEOUT    : natural := 100;

  constant HALF_PERIOD : time := 10 ns;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Client interface
  signal start : std_logic := '0';
  signal addr  : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
  signal wdata : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal wstrb : std_logic_vector(STRB_WIDTH-1 downto 0) := (others => '0');
  signal ready : std_logic;

  -- AXI4 Write Address Channel
  signal awid    : std_logic_vector(ID_WIDTH-1 downto 0);
  signal awaddr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal awlen   : std_logic_vector(7 downto 0);
  signal awsize  : std_logic_vector(2 downto 0);
  signal awburst : std_logic_vector(1 downto 0);
  signal awlock  : std_logic;
  signal awcache : std_logic_vector(3 downto 0);
  signal awprot  : std_logic_vector(2 downto 0);
  signal awqos   : std_logic_vector(3 downto 0);
  signal awvalid : std_logic;
  signal awready : std_logic := '0';

  -- AXI4 Write Data Channel
  signal wwdata : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal wwstrb : std_logic_vector(STRB_WIDTH-1 downto 0);
  signal wlast  : std_logic;
  signal wvalid : std_logic;
  signal wready : std_logic := '0';

  -- AXI4 Write Response Channel
  signal bid    : std_logic_vector(ID_WIDTH-1 downto 0) := (others => '0');
  signal bresp  : std_logic_vector(1 downto 0) := "00";
  signal bvalid : std_logic := '0';
  signal bready : std_logic;

  signal done : boolean := false;

  -- Raised by the address and data subordinates when their half of a
  -- transaction has been taken.  The response subordinate waits for both.
  signal aw_taken : natural := 0;
  signal w_taken  : natural := 0;

  function hex(v : std_logic_vector) return string is
    constant digits : string := "0123456789ABCDEF";
    variable u : unsigned(v'length-1 downto 0) := unsigned(v);
    variable r : string(1 to (v'length+3)/4);
    variable n : integer;
    variable hi, lo : integer;
  begin
    for i in 0 to (v'length+3)/4 - 1 loop
      hi := v'length-1-4*i;
      lo := hi - 3;
      if lo < 0 then
        lo := 0;
      end if;
      n := to_integer(u(hi downto lo));
      r(i+1) := digits(n+1);
    end loop;
    return r;
  end function;

  -- One step of a maximal length 32 bit LFSR, taps 32, 22, 2 and 1.
  -- Used instead of ieee.math_real so that every run is identical.
  procedure next_rand(s : inout unsigned(31 downto 0)) is
  begin
    s := s(30 downto 0) & (s(31) xor s(21) xor s(1) xor s(0));
  end procedure;

begin

  ------------------------------------------------------------------------------
  -- Clock
  ------------------------------------------------------------------------------
  clock : process is
  begin
    while not done loop
      clk <= '0';
      wait for HALF_PERIOD;
      clk <= '1';
      wait for HALF_PERIOD;
    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- Unit under test
  ------------------------------------------------------------------------------
  uut : entity work.axi_write_channel(behavioral)
    generic map (
      ADDR_WIDTH => ADDR_WIDTH,
      DATA_WIDTH => DATA_WIDTH,
      ID_WIDTH   => ID_WIDTH
      )
    port map (
      clk => clk,
      rst => rst,

      start => start,
      addr  => addr,
      wdata => wdata,
      wstrb => wstrb,
      ready => ready,

      m_axi_awid    => awid,
      m_axi_awaddr  => awaddr,
      m_axi_awlen   => awlen,
      m_axi_awsize  => awsize,
      m_axi_awburst => awburst,
      m_axi_awlock  => awlock,
      m_axi_awcache => awcache,
      m_axi_awprot  => awprot,
      m_axi_awqos   => awqos,
      m_axi_awvalid => awvalid,
      m_axi_awready => awready,

      m_axi_wdata  => wwdata,
      m_axi_wstrb  => wwstrb,
      m_axi_wlast  => wlast,
      m_axi_wvalid => wvalid,
      m_axi_wready => wready,

      m_axi_bid    => bid,
      m_axi_bresp  => bresp,
      m_axi_bvalid => bvalid,
      m_axi_bready => bready
      );

  ------------------------------------------------------------------------------
  -- Subordinate, write address channel.  Takes an address when it feels
  -- like it, independently of the data channel.
  ------------------------------------------------------------------------------
  aw_slave : process is
    variable seed  : unsigned(31 downto 0) := x"13579BDF";
    variable stall : natural;
    variable hold  : natural;
    variable got   : boolean;
  begin
    awready <= '0';
    wait until rising_edge(clk) and rst = '0';

    while not done loop
      got := false;
      while not got loop
        next_rand(seed);
        stall := to_integer(seed(1 downto 0));          -- 0 to 3
        awready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;

        awready <= '1';
        hold := 1 + to_integer(seed(3 downto 2));       -- 1 to 4
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if awvalid = '1' then
            got := true;
          end if;
          exit when got;
        end loop;
      end loop;
      awready  <= '0';
      aw_taken <= aw_taken + 1;
    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- Subordinate, write data channel.  A different seed, so the data is
  -- taken before the address about as often as after it.
  ------------------------------------------------------------------------------
  w_slave : process is
    variable seed  : unsigned(31 downto 0) := x"0F1E2D3C";
    variable stall : natural;
    variable hold  : natural;
    variable got   : boolean;
  begin
    wready <= '0';
    wait until rising_edge(clk) and rst = '0';

    while not done loop
      got := false;
      while not got loop
        next_rand(seed);
        stall := to_integer(seed(2 downto 0));          -- 0 to 7
        if stall > 4 then
          stall := stall - 4;
        end if;
        wready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;

        wready <= '1';
        hold := 1 + to_integer(seed(4 downto 3));       -- 1 to 4
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if wvalid = '1' then
            got := true;
          end if;
          exit when got;
        end loop;
      end loop;
      wready  <= '0';
      w_taken <= w_taken + 1;
    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- Subordinate, write response channel.  A write is not finished until
  -- this answers, and it does not answer until both the address and the
  -- data have been taken.
  ------------------------------------------------------------------------------
  b_slave : process is
    variable seed  : unsigned(31 downto 0) := x"2468ACE0";
    variable stall : natural;
    variable n     : natural := 0;
  begin
    bvalid <= '0';
    bresp  <= "00";
    wait until rising_edge(clk) and rst = '0';

    while not done loop
      n := n + 1;
      while aw_taken < n or w_taken < n loop
        wait until rising_edge(clk);
      end loop;

      next_rand(seed);
      stall := to_integer(seed(2 downto 0));            -- 0 to 7
      if stall > 4 then
        stall := stall - 4;
      end if;
      for i in 1 to stall loop
        wait until rising_edge(clk);
      end loop;

      bresp  <= "00";
      bid    <= (others => '0');
      bvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when bready = '1';
      end loop;
      bvalid <= '0';
    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- Client and checker.  Drives start, addr, wdata and wstrb, and after
  -- every clock edge checks the three write channels against the AXI
  -- handshake rules.
  ------------------------------------------------------------------------------
  test : process is
    variable checks : natural := 0;
    variable errors : natural := 0;
    variable seed   : unsigned(31 downto 0) := x"5A5A1234";

    -- What the channels carried during the previous cycle.
    variable p_awvalid, p_awready : std_logic := '0';
    variable p_awaddr  : std_logic_vector(ADDR_WIDTH-1 downto 0)
      := (others => '0');
    variable p_awlen   : std_logic_vector(7 downto 0) := (others => '0');
    variable p_awsize  : std_logic_vector(2 downto 0) := (others => '0');
    variable p_awburst : std_logic_vector(1 downto 0) := (others => '0');
    variable p_wvalid, p_wready, p_wlast : std_logic := '0';
    variable p_wdata   : std_logic_vector(DATA_WIDTH-1 downto 0)
      := (others => '0');
    variable p_wstrb   : std_logic_vector(STRB_WIDTH-1 downto 0)
      := (others => '0');
    variable have_prev : boolean := false;

    -- Transaction bookkeeping.
    variable starts_taken : natural := 0;
    variable addrs_sent   : natural := 0;
    variable beats_sent   : natural := 0;
    variable resps_taken  : natural := 0;
    variable expect_addr  : std_logic_vector(ADDR_WIDTH-1 downto 0)
      := (others => '0');
    variable expect_data  : std_logic_vector(DATA_WIDTH-1 downto 0)
      := (others => '0');
    variable expect_strb  : std_logic_vector(STRB_WIDTH-1 downto 0)
      := (others => '0');
    variable saw_addr, saw_beat : boolean := false;

    variable cycles   : natural;
    variable gap      : natural;
    variable resps_at : natural;
    variable a : std_logic_vector(ADDR_WIDTH-1 downto 0);
    variable d : std_logic_vector(DATA_WIDTH-1 downto 0);
    variable t : std_logic_vector(STRB_WIDTH-1 downto 0);

    -- Count every check.  Report the first 25 failures and then stop
    -- reporting, so that one broken signal does not bury the rest of
    -- the run.  The summary count stays complete.
    procedure check(cond : in boolean; msg : in string) is
    begin
      checks := checks + 1;
      if not cond then
        errors := errors + 1;
        if errors <= 25 then
          report msg severity error;
        end if;
        if errors = 25 then
          report "further failures will not be reported individually"
            severity note;
        end if;
      end if;
    end procedure;

    -- Advance one clock cycle and check everything that can be checked
    -- from the outside of the engine.  The signal values read here are
    -- the ones that were on the wires during the cycle that just ended,
    -- which is what the edge sampled.
    procedure step is
    begin
      wait until rising_edge(clk);

      -- Write address channel
      if have_prev and p_awvalid = '1' and p_awready = '0' then
        check(awvalid = '1',
              "AWVALID was withdrawn before AWREADY was seen, for address " &
              hex(p_awaddr));
        check(awaddr = p_awaddr,
              "AWADDR changed while AWVALID was high and AWREADY low: was " &
              hex(p_awaddr) & ", now " & hex(awaddr));
        check(awlen = p_awlen and awsize = p_awsize and awburst = p_awburst,
              "AWLEN, AWSIZE or AWBURST changed while AWVALID was high " &
              "and AWREADY low");
      end if;

      if awvalid = '1' then
        check(awlen = x"00",
              "AWLEN is " & hex(awlen) & ", must be 00 for a single beat");
        check(awsize = "010",
              "AWSIZE is not 010, so the beat is not four bytes wide");
        check(awburst = "01",
              "AWBURST is not 01 (INCR)");
      end if;

      -- Write data channel
      if have_prev and p_wvalid = '1' and p_wready = '0' then
        check(wvalid = '1',
              "WVALID was withdrawn before WREADY was seen, for data " &
              hex(p_wdata));
        check(wwdata = p_wdata,
              "WDATA changed while WVALID was high and WREADY low: was " &
              hex(p_wdata) & ", now " & hex(wwdata));
        check(wwstrb = p_wstrb,
              "WSTRB changed while WVALID was high and WREADY low: was " &
              hex(p_wstrb) & ", now " & hex(wwstrb));
        check(wlast = p_wlast,
              "WLAST changed while WVALID was high and WREADY low");
      end if;

      if wvalid = '1' then
        check(wlast = '1',
              "WLAST is low on the only beat of the burst");
      end if;

      -- An address handshake.
      if awvalid = '1' and awready = '1' then
        addrs_sent := addrs_sent + 1;
        check(addrs_sent <= starts_taken,
              "the engine put address " & hex(awaddr) &
              " on the bus without being asked for it");
        check(awaddr = expect_addr,
              "AWADDR is " & hex(awaddr) & ", expected " & hex(expect_addr));
        saw_addr := true;
      end if;

      -- A data handshake.
      if wvalid = '1' and wready = '1' then
        beats_sent := beats_sent + 1;
        check(beats_sent <= starts_taken,
              "the engine put a data beat on the bus without being asked");
        check(wwdata = expect_data,
              "WDATA is " & hex(wwdata) & ", expected " & hex(expect_data));
        check(wwstrb = expect_strb,
              "WSTRB is " & hex(wwstrb) & ", expected " & hex(expect_strb));
        saw_beat := true;
      end if;

      -- A response handshake.
      if bvalid = '1' and bready = '1' then
        resps_taken := resps_taken + 1;
        check(resps_taken <= addrs_sent and resps_taken <= beats_sent,
              "a write response was accepted before the write was sent");
      end if;

      p_awvalid := awvalid;
      p_awready := awready;
      p_awaddr  := awaddr;
      p_awlen   := awlen;
      p_awsize  := awsize;
      p_awburst := awburst;
      p_wvalid  := wvalid;
      p_wready  := wready;
      p_wdata   := wwdata;
      p_wstrb   := wwstrb;
      p_wlast   := wlast;
      have_prev := true;
    end procedure;

    -- Present a request and let the engine take it.
    procedure issue(ia : in std_logic_vector(ADDR_WIDTH-1 downto 0);
                    id : in std_logic_vector(DATA_WIDTH-1 downto 0);
                    it : in std_logic_vector(STRB_WIDTH-1 downto 0)) is
    begin
      addr        <= ia;
      wdata       <= id;
      wstrb       <= it;
      start       <= '1';
      expect_addr := ia;
      expect_data := id;
      expect_strb := it;
      saw_addr    := false;
      saw_beat    := false;
      step;
      start        <= '0';
      starts_taken := starts_taken + 1;

      -- The request has been taken, so the client is free to move on.
      -- The engine must have captured all three: AXI requires each
      -- payload to be stable for as long as its VALID is asserted, and
      -- both may still be asserted for many cycles after this one.
      addr  <= std_logic_vector(unsigned(ia) + 4);
      wdata <= not id;
      wstrb <= not it;
    end procedure;

  begin
    rst   <= '1';
    start <= '0';
    addr  <= (others => '0');
    wdata <= (others => '0');
    wstrb <= (others => '0');

    for i in 1 to 4 loop
      wait until rising_edge(clk);
      check(awvalid = '0', "AWVALID is not low while rst is high");
      check(wvalid  = '0', "WVALID is not low while rst is high");
    end loop;

    rst <= '0';
    step;
    check(awvalid = '0',
          "AWVALID is not low on the first cycle after reset, " &
          "with no request made");
    check(wvalid = '0',
          "WVALID is not low on the first cycle after reset, " &
          "with no request made");

    for trial in 1 to NUM_WRITES loop

      -- An idle gap of 0 to 3 cycles, so that back to back writes and
      -- long pauses are both covered.
      next_rand(seed);
      gap := to_integer(seed(1 downto 0));
      for i in 1 to gap loop
        step;
      end loop;

      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "ready never came up before write " & integer'image(trial));
      exit when cycles >= TIMEOUT;

      -- A word aligned address, a data word, and a strobe pattern that
      -- is sometimes a full word and sometimes a single byte or a half.
      next_rand(seed);
      a := std_logic_vector(seed(29 downto 0)) & "00";
      next_rand(seed);
      d := std_logic_vector(seed);
      next_rand(seed);
      case to_integer(seed(1 downto 0)) is
        when 0      => t := "1111";
        when 1      => t := "0011";
        when 2      => t := "1100";
        when others => t := "0001";
      end case;

      resps_at := resps_taken;
      issue(a, d, t);

      step;
      check(ready = '0',
            "ready stayed high after a start was taken, on write " &
            integer'image(trial));

      -- Wait for the write to finish.  It is not finished when the data
      -- has been taken.  It is finished when the response arrives.
      cycles := 0;
      while (ready /= '1' or not saw_addr or not saw_beat)
        and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "write " & integer'image(trial) & " of address " & hex(a) &
            " never finished");
      exit when cycles >= TIMEOUT;

      check(resps_taken > resps_at,
            "ready came back up on write " & integer'image(trial) &
            " without a response on the B channel");

    end loop;

    ------------------------------------------------------------------------
    -- Directed: start asserted in the one cycle where it is most likely
    -- to be taken by mistake.
    --
    -- The three machines do not reach the idle state together.  The
    -- address and data machines get there on the edge that takes the
    -- response, one full cycle before the response machine follows them.
    -- In that cycle ready is low, because the client has not been told
    -- the write is finished, but an engine that gates start on the
    -- address machine alone will take a start anyway and put a write on
    -- the bus that nobody asked for.
    ------------------------------------------------------------------------
    for trial in 1 to 5 loop

      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;

      next_rand(seed);
      a := std_logic_vector(seed(29 downto 0)) & "00";
      next_rand(seed);
      d := std_logic_vector(seed);
      t := "1111";

      issue(a, d, t);

      -- Run to the edge that takes the response.
      resps_at := resps_taken;
      cycles   := 0;
      while resps_taken = resps_at and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "directed write " & integer'image(trial) &
            " never got its response");
      exit when cycles >= TIMEOUT;

      -- The next edge is the one in question.  Poke it.
      start <= '1';
      step;
      start <= '0';
      check(ready = '0',
            "ready was high in the cycle after the response, on directed " &
            "write " & integer'image(trial));

      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "directed write " & integer'image(trial) & " never finished");
      exit when cycles >= TIMEOUT;

    end loop;

    check(addrs_sent = starts_taken,
          "the engine sent " & integer'image(addrs_sent) &
          " addresses for " & integer'image(starts_taken) & " requests");
    check(beats_sent = starts_taken,
          "the engine sent " & integer'image(beats_sent) &
          " data beats for " & integer'image(starts_taken) & " requests");
    check(resps_taken = starts_taken,
          "the engine took " & integer'image(resps_taken) &
          " responses for " & integer'image(starts_taken) & " requests");

    done <= true;

    if errors = 0 then
      report "axi_write_channel testbench PASSED: all " &
        integer'image(checks) & " checks passed, over " &
        integer'image(starts_taken) & " writes." severity note;
    else
      report "axi_write_channel testbench FAILED: " & integer'image(errors) &
        " of " & integer'image(checks) & " checks failed." severity failure;
    end if;
    wait;
  end process;

end behavioral;
