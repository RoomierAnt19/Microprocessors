--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- axi_read_channel_testbench
--
-- Self-checking testbench for the Lab 3 generic AXI read engine.  It
-- instantiates the engine as an AXI4 manager, plays the part of the
-- subordinate on the other end of the two read channels, and checks
-- both sides: that the engine returns the right word for every address
-- it is asked for, and that it obeys the AXI handshake rules while
-- doing it.
--
-- The unit under test must be an entity named axi_read_channel with an
-- architecture named behavioral and exactly the interface given in the
-- Lab 3 handout.  The testbench binds to that entity by name, so a
-- design whose ports differ will not simulate, no matter how correct
-- the logic inside it is.
--
-- The memory
-- ----------
-- There is no memory array.  The subordinate answers every read with
--
--   mem_word(a) = a xor A5A5A5A5
--
-- so the testbench knows what every address in the 32 bit space holds
-- without storing anything, every address holds a different word, and
-- no address holds its own value.  An engine that returns the address
-- instead of the data it was given fails on the first read.
--
-- What is checked
-- ---------------
-- After every clock edge:
--
--   1. ARVALID, once asserted, stays asserted until ARREADY is seen.
--      A manager may not withdraw a read request.
--   2. ARADDR, ARLEN, ARSIZE and ARBURST hold still for as long as
--      ARVALID is high and ARREADY has not been seen.
--   3. ARLEN is 0, ARSIZE is 010 and ARBURST is 01 whenever ARVALID is
--      high: one beat, four bytes, INCR.
--   4. No read data beat arrives that was not asked for, and no
--      address is put on the bus that the client did not request.
--   5. ARVALID is low while rst is high and on the cycle after it falls.
--   6. rdata and raddr hold still while ready is high and no new read
--      has been started.
--
-- And for every read:
--
--   7. The address the engine puts on ARADDR is the address the client
--      put on addr when start was taken.
--   8. ready falls on the cycle after a start is taken, so the client
--      can tell that the engine is busy.
--   9. When ready comes back up, rdata holds mem_word of the requested
--      address and raddr holds the requested address.
--
-- The subordinate stalls at random.  It holds ARREADY low for 0 to 3
-- cycles before accepting an address, and waits a further 0 to 4
-- cycles before putting the data on the bus, so the address phase and
-- the data phase are pulled apart by a different amount on every read.
-- The client side stalls too: 0 to 3 idle cycles between one read
-- completing and the next being started, so back to back reads and
-- long gaps are both covered.  The stalls come from two LFSRs with
-- different seeds, so the run is random but repeats exactly.
--
-- Every check is counted.  The run ends with one PASSED or FAILED
-- line, and a failing run ends with severity failure so that a
-- scripted simulation exits with an error.  After 25 failures the
-- individual reports stop, but the count in the summary line is
-- complete.
--
-- Running it
-- ----------
--   ghdl -a --std=08 axi_read_channel.vhdl axi_read_channel_testbench.vhdl
--   ghdl -e --std=08 axi_read_channel_testbench
--   ghdl -r --std=08 axi_read_channel_testbench
--
-- Analyse anything the engine depends on, such as a register entity of
-- your own, ahead of axi_read_channel.vhdl on that first line.
--
-- In Vivado, add the two files to a simulation set and make
-- axi_read_channel_testbench the top.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity axi_read_channel_testbench is
end axi_read_channel_testbench;

architecture behavioral of axi_read_channel_testbench is

  constant ADDR_WIDTH : integer := 32;
  constant DATA_WIDTH : integer := 32;
  constant ID_WIDTH   : integer := 1;

  -- Number of reads performed.
  constant NUM_READS : natural := 200;

  -- Cycles to wait for a read to finish before giving up on it.
  constant TIMEOUT : natural := 100;

  constant HALF_PERIOD : time := 10 ns;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Client interface
  signal start : std_logic := '0';
  signal addr  : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
  signal rdata : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal raddr : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal ready : std_logic;

  -- AXI4 Read Address Channel
  signal arid    : std_logic_vector(ID_WIDTH-1 downto 0);
  signal araddr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal arlen   : std_logic_vector(7 downto 0);
  signal arsize  : std_logic_vector(2 downto 0);
  signal arburst : std_logic_vector(1 downto 0);
  signal arlock  : std_logic;
  signal arcache : std_logic_vector(3 downto 0);
  signal arprot  : std_logic_vector(2 downto 0);
  signal arqos   : std_logic_vector(3 downto 0);
  signal arvalid : std_logic;
  signal arready : std_logic := '0';

  -- AXI4 Read Data Channel
  signal rid    : std_logic_vector(ID_WIDTH-1 downto 0) := (others => '0');
  signal rrdata : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal rresp  : std_logic_vector(1 downto 0) := "00";
  signal rlast  : std_logic := '0';
  signal rvalid : std_logic := '0';
  signal rready : std_logic;

  -- Raised when the last read has been checked, to stop the clock.
  signal done : boolean := false;

  -- The contents of memory.  See the comment at the top.
  function mem_word(a : std_logic_vector(ADDR_WIDTH-1 downto 0))
    return std_logic_vector is
  begin
    return a xor x"A5A5A5A5";
  end function;

  function hex(v : std_logic_vector) return string is
    constant digits : string := "0123456789ABCDEF";
    variable u : unsigned(v'length-1 downto 0) := unsigned(v);
    variable r : string(1 to v'length/4);
    variable n : integer;
  begin
    for i in 0 to v'length/4 - 1 loop
      n := to_integer(u(v'length-1-4*i downto v'length-4-4*i));
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
  uut : entity work.axi_read_channel(rtl)
    generic map (
      C_M_AXI_ADDR_WIDTH => ADDR_WIDTH,
      C_M_AXI_DATA_WIDTH => DATA_WIDTH,
      C_M_AXI_ID_WIDTH   => ID_WIDTH
      )
    port map (
      clk => clk,
      rst => rst,

      start => start,
      addr  => addr,
      rdata => rdata,
      raddr => raddr,
      ready => ready,

      m_axi_arid    => arid,
      m_axi_araddr  => araddr,
      m_axi_arlen   => arlen,
      m_axi_arsize  => arsize,
      m_axi_arburst => arburst,
      m_axi_arlock  => arlock,
      m_axi_arcache => arcache,
      m_axi_arprot  => arprot,
      m_axi_arqos   => arqos,
      m_axi_arvalid => arvalid,
      m_axi_arready => arready,

      m_axi_rid    => rid,
      m_axi_rdata  => rrdata,
      m_axi_rresp  => rresp,
      m_axi_rlast  => rlast,
      m_axi_rvalid => rvalid,
      m_axi_rready => rready
      );

  ------------------------------------------------------------------------------
  -- AXI4 subordinate.  Accepts one address at a time, after a random
  -- stall, and answers it with one beat, after a second random stall.
  -- It never has more than one transaction in hand, which is all the
  -- engine can issue.
  ------------------------------------------------------------------------------
  subordinate : process is
    variable seed  : unsigned(31 downto 0) := x"13579BDF";
    variable stall : natural;
    variable hold  : natural;
    variable got   : boolean;
    variable a     : std_logic_vector(ADDR_WIDTH-1 downto 0);
    variable id    : std_logic_vector(ID_WIDTH-1 downto 0);
  begin
    arready <= '0';
    rvalid  <= '0';
    rlast   <= '0';
    rresp   <= "00";
    rrdata  <= x"BAD1BAD1";

    wait until rising_edge(clk) and rst = '0';

    while not done loop

      -- Take an address, but not eagerly.  ARREADY goes low for 0 to 3
      -- cycles, then high for 1 to 4, and repeats until an address is
      -- actually handed over.  A subordinate is allowed to withdraw
      -- ARREADY at any time, and this one does, so the engine is made
      -- to hold ARVALID and ARADDR steady across cycles in which the
      -- address is not being taken.
      got := false;
      while not got loop
        next_rand(seed);
        stall := to_integer(seed(1 downto 0));          -- 0 to 3
        arready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;

        -- Reading a signal just after the edge gives its value during
        -- the cycle that ended, which is the value the handshake was
        -- made on.
        arready <= '1';
        hold := 1 + to_integer(seed(3 downto 2));       -- 1 to 4
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if arvalid = '1' then
            a   := araddr;
            id  := arid;
            got := true;
          end if;
          exit when got;
        end loop;
      end loop;
      arready <= '0';

      -- Sit on the data for a while, so the data phase separates from
      -- the address phase by a different amount on every read.
      next_rand(seed);
      stall := to_integer(seed(4 downto 2));          -- 0 to 7
      if stall > 4 then
        stall := stall - 4;
      end if;
      for i in 1 to stall loop
        wait until rising_edge(clk);
      end loop;

      -- One beat, so it is also the last beat.
      rrdata <= mem_word(a);
      rid    <= id;
      rresp  <= "00";
      rlast  <= '1';
      rvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when rready = '1';
      end loop;
      rvalid <= '0';
      rlast  <= '0';
      -- RDATA means nothing while RVALID is low, so it is filled with
      -- something recognisable.  An engine that passes RDATA through
      -- instead of capturing it hands this to its client.
      rrdata <= x"BAD1BAD1";

    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- Client and checker.  Drives start and addr, and after every clock
  -- edge checks the read address channel against the AXI handshake
  -- rules.
  ------------------------------------------------------------------------------
  test : process is
    variable checks : natural := 0;
    variable errors : natural := 0;
    variable seed   : unsigned(31 downto 0) := x"2468ACE0";

    -- What the read address channel carried during the previous cycle.
    variable p_arvalid : std_logic := '0';
    variable p_arready : std_logic := '0';
    variable p_araddr  : std_logic_vector(ADDR_WIDTH-1 downto 0)
      := (others => '0');
    variable p_arlen   : std_logic_vector(7 downto 0) := (others => '0');
    variable p_arsize  : std_logic_vector(2 downto 0) := (others => '0');
    variable p_arburst : std_logic_vector(1 downto 0) := (others => '0');
    variable have_prev : boolean := false;

    -- Transaction bookkeeping.
    variable starts_taken  : natural := 0;
    variable addrs_issued  : natural := 0;
    variable beats_seen    : natural := 0;
    variable expect_addr   : std_logic_vector(ADDR_WIDTH-1 downto 0)
      := (others => '0');
    variable saw_address   : boolean := false;

    -- What rdata and raddr must hold while the engine is idle.
    variable hold_valid : boolean := false;
    variable hold_data  : std_logic_vector(DATA_WIDTH-1 downto 0)
      := (others => '0');
    variable hold_addr  : std_logic_vector(ADDR_WIDTH-1 downto 0)
      := (others => '0');

    variable cycles   : natural;
    variable gap      : natural;
    variable hangover : natural;
    variable beats_at : natural;
    variable a      : std_logic_vector(ADDR_WIDTH-1 downto 0);

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
    -- the ones that were on the wires during the cycle that just
    -- ended, which is what the edge sampled.
    procedure step is
    begin
      wait until rising_edge(clk);

      if have_prev and p_arvalid = '1' and p_arready = '0' then
        check(arvalid = '1',
              "ARVALID was withdrawn before ARREADY was seen, for address " &
              hex(p_araddr));
        check(araddr = p_araddr,
              "ARADDR changed while ARVALID was high and ARREADY low: was " &
              hex(p_araddr) & ", now " & hex(araddr));
        check(arlen = p_arlen and arsize = p_arsize and arburst = p_arburst,
              "ARLEN, ARSIZE or ARBURST changed while ARVALID was high " &
              "and ARREADY low");
      end if;

      if arvalid = '1' then
        check(arlen = x"00",
              "ARLEN is " & hex(arlen) & ", must be 00 for a single beat");
        check(arsize = "010",
              "ARSIZE is not 010, so the beat is not four bytes wide");
        check(arburst = "01",
              "ARBURST is not 01 (INCR)");
      end if;

      -- An address handshake.  It must be the address the client asked
      -- for, and the client must have asked for one.
      if arvalid = '1' and arready = '1' then
        addrs_issued := addrs_issued + 1;
        check(addrs_issued <= starts_taken,
              "the engine put address " & hex(araddr) &
              " on the bus without being asked for it");
        check(araddr = expect_addr,
              "ARADDR is " & hex(araddr) & ", expected " & hex(expect_addr));
        saw_address := true;
      end if;

      -- A data handshake.  It must belong to an address that was sent.
      if rvalid = '1' and rready = '1' then
        beats_seen := beats_seen + 1;
        check(beats_seen <= addrs_issued,
              "a read data beat was accepted before any address was sent");
      end if;

      -- Nothing may move while the engine is idle.
      if hold_valid and ready = '1' then
        check(rdata = hold_data,
              "rdata changed while the engine was idle: was " &
              hex(hold_data) & ", now " & hex(rdata));
        check(raddr = hold_addr,
              "raddr changed while the engine was idle: was " &
              hex(hold_addr) & ", now " & hex(raddr));
      end if;

      p_arvalid := arvalid;
      p_arready := arready;
      p_araddr  := araddr;
      p_arlen   := arlen;
      p_arsize  := arsize;
      p_arburst := arburst;
      have_prev := true;
    end procedure;

  begin
    rst   <= '1';
    start <= '0';
    addr  <= (others => '0');

    for i in 1 to 4 loop
      wait until rising_edge(clk);
      check(arvalid = '0', "ARVALID is not low while rst is high");
    end loop;

    rst <= '0';
    step;
    check(arvalid = '0',
          "ARVALID is not low on the first cycle after reset, " &
          "with no request made");

    for trial in 1 to NUM_READS loop

      -- An idle gap of 0 to 3 cycles, so that back to back reads and
      -- long pauses are both covered.
      next_rand(seed);
      gap := to_integer(seed(1 downto 0));
      for i in 1 to gap loop
        step;
      end loop;

      -- Wait for the engine to be ready to take a request.
      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "ready never came up before read " & integer'image(trial));
      exit when cycles >= TIMEOUT;

      -- Pick an address.  Word aligned, which is what a fetch unit or
      -- a load/store unit will ask for.
      next_rand(seed);
      a := std_logic_vector(seed(29 downto 0)) & "00";

      addr        <= a;
      start       <= '1';
      expect_addr := a;
      saw_address := false;
      hold_valid  := false;
      step;
      starts_taken := starts_taken + 1;

      -- The request has been taken, so the client is free to move addr on,
      -- exactly as a program counter does.  The engine must have captured
      -- the address: AXI requires ARADDR to be stable for as long as
      -- ARVALID is asserted, and it may still be asserted for many cycles.
      addr <= std_logic_vector(unsigned(a) + 4);

      -- Some clients are sloppy and leave start asserted for a cycle or
      -- two after it has been taken.  The engine must ignore it: ready is
      -- low, so as far as the client has been told nothing has finished,
      -- and a second transaction here was never requested.  The minimum
      -- read takes longer than this, so ready cannot legitimately return
      -- while start is still high.
      next_rand(seed);
      hangover := to_integer(seed(6 downto 5));        -- 0 to 3
      if hangover > 2 then
        hangover := 2;
      end if;
      for i in 1 to hangover loop
        step;
        check(ready = '0',
              "ready came back up while start was still asserted, on read " &
              integer'image(trial));
      end loop;
      start <= '0';

      -- The engine has taken the request, so it must say it is busy.
      if hangover = 0 then
        step;
      end if;
      check(ready = '0',
            "ready stayed high after a start was taken, on read " &
            integer'image(trial));

      -- Wait for the read to finish.
      cycles := 0;
      while (ready /= '1' or not saw_address) and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "read " & integer'image(trial) & " of address " & hex(a) &
            " never finished");
      exit when cycles >= TIMEOUT;

      check(rdata = mem_word(a),
            "read of address " & hex(a) & ": rdata is " & hex(rdata) &
            ", expected " & hex(mem_word(a)));
      check(raddr = a,
            "read of address " & hex(a) & ": raddr is " & hex(raddr));

      -- Hold these, and check that they do not move until the next read.
      hold_data  := rdata;
      hold_addr  := raddr;
      hold_valid := true;

    end loop;

    ------------------------------------------------------------------------
    -- Directed: start asserted in the one cycle where it is most likely to
    -- be taken by mistake.
    --
    -- The two machines do not reach the idle state together.  The address
    -- machine gets there on the edge that captures the data word, one full
    -- cycle before the data machine follows it.  In that cycle ready is
    -- low, because the client has not been told the read is finished, but
    -- an engine that gates start on its address machine alone will take a
    -- start anyway and put an address on the bus that nobody asked for.
    ------------------------------------------------------------------------
    for trial in 1 to 5 loop

      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;

      next_rand(seed);
      a := std_logic_vector(seed(29 downto 0)) & "00";

      addr        <= a;
      start       <= '1';
      expect_addr := a;
      saw_address := false;
      hold_valid  := false;
      step;
      start        <= '0';
      starts_taken := starts_taken + 1;
      addr <= std_logic_vector(unsigned(a) + 4);

      -- Run to the edge that hands over the data word.
      beats_at := beats_seen;
      cycles   := 0;
      while beats_seen = beats_at and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "directed read " & integer'image(trial) & " never got its data");
      exit when cycles >= TIMEOUT;

      -- The next edge is the one in question.  Poke it.
      start <= '1';
      step;
      start <= '0';
      check(ready = '0',
            "ready was high in the cycle after the data beat, on directed " &
            "read " & integer'image(trial));

      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "directed read " & integer'image(trial) & " never finished");
      exit when cycles >= TIMEOUT;

      check(rdata = mem_word(a),
            "directed read of " & hex(a) & ": rdata is " & hex(rdata) &
            ", expected " & hex(mem_word(a)));
      check(raddr = a,
            "directed read of " & hex(a) & ": raddr is " & hex(raddr));
      hold_data  := rdata;
      hold_addr  := raddr;
      hold_valid := true;

    end loop;

    check(addrs_issued = starts_taken,
          "the engine issued " & integer'image(addrs_issued) &
          " addresses for " & integer'image(starts_taken) & " requests");
    check(beats_seen = addrs_issued,
          "the engine accepted " & integer'image(beats_seen) &
          " data beats for " & integer'image(addrs_issued) & " addresses");

    done <= true;

    if errors = 0 then
      report "axi_read_channel testbench PASSED: all " &
        integer'image(checks) & " checks passed, over " &
        integer'image(starts_taken) & " reads." severity note;
    else
      report "axi_read_channel testbench FAILED: " & integer'image(errors) &
        " of " & integer'image(checks) & " checks failed." severity failure;
    end if;
    wait;
  end process;

end behavioral;
