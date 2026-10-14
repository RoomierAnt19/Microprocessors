--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- load_store_unit_testbench
--
-- Self-checking testbench for the Lab 5 load/store unit.  Unlike the two
-- engine testbenches, this one has a real memory behind it, because byte
-- lanes are the whole point of the unit and the only way to tell whether
-- they are right is to look at what ends up stored.
--
-- The unit under test must be an entity named load_store_unit with an
-- architecture named behavioral and exactly the interface given in the
-- Lab 5 handout.  It instantiates your axi_read_channel and your
-- axi_write_channel, so this exercises the whole stack: get either
-- engine wrong and this fails too.  Run the two engine testbenches
-- first.  A failure here with both of those passing is a byte lane
-- problem, which is what this testbench is for.
--
-- The memory
-- ----------
-- 256 words at C0000000, which is where Lab 6 puts RAM.  It starts out
-- holding mem(a) = a xor A5A5A5A5, so every word is different and no
-- word holds its own address.  The subordinate merges writes under
-- WSTRB, one byte lane at a time, exactly as a real memory does: get
-- the strobes wrong and the neighbouring bytes are destroyed, and the
-- testbench says which ones.
--
-- The subordinate also checks that every address it is given lies
-- inside its window.  A unit that mangles the high address bits, or
-- that forgets to clear the low two, is caught there rather than by a
-- confusing data mismatch later.
--
-- What is checked
-- ---------------
-- The testbench keeps a shadow copy of memory and performs a random mix
-- of loads and stores of bytes, halfwords and words at every legal
-- offset.  After every operation:
--
--   1. A store put the right bytes in the right lanes: the addressed
--      word matches the shadow after the merge.
--   2. A store left its neighbours alone.  Over-wide strobes are caught
--      here.
--   3. A load returned the right lane, extended the right way.  LB and
--      LH sign extend, LBU and LHU zero extend, LW takes the word.
--   4. A load changed nothing in memory.
--   5. ready fell after the request was taken and came back up when the
--      access was done.
--   6. The access used the channels it should have.  A load puts exactly
--      one address on the read channel and nothing on the write channel,
--      and a store does the opposite.  A unit that starts both engines
--      on every access still returns the right answers, so nothing else
--      here would notice, but it doubles its traffic on a shared bus.
--
-- And at the end, the whole memory is compared against the shadow.
--
-- Both channels of the subordinate stall at random and independently,
-- so the address and data phases land in either order and with a
-- different gap every time.  The stalls come from LFSRs with different
-- seeds, so the run is random but repeats exactly.
--
-- Every check is counted.  The run ends with one PASSED or FAILED line,
-- and a failing run ends with severity failure so that a scripted
-- simulation exits with an error.  After 25 failures the individual
-- reports stop, but the count in the summary line is complete.
--
-- Running it
-- ----------
--   ghdl -a --std=08 axi_read_channel.vhdl axi_write_channel.vhdl \
--                    load_store_unit.vhdl load_store_unit_testbench.vhdl
--   ghdl -e --std=08 load_store_unit_testbench
--   ghdl -r --std=08 load_store_unit_testbench
--
-- Analyse anything the engines depend on, such as a register entity of
-- your own, ahead of them on that first line.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity load_store_unit_testbench is
end load_store_unit_testbench;

architecture behavioral of load_store_unit_testbench is

  constant NUM_WORDS : natural := 256;
  constant BASE      : unsigned(31 downto 0) := x"C0000000";
  constant NUM_OPS   : natural := 300;
  constant TIMEOUT   : natural := 200;

  constant HALF_PERIOD : time := 10 ns;

  -- funct3 encodings, straight from the instruction
  constant F_B  : std_logic_vector(2 downto 0) := "000";  -- LB  / SB
  constant F_H  : std_logic_vector(2 downto 0) := "001";  -- LH  / SH
  constant F_W  : std_logic_vector(2 downto 0) := "010";  -- LW  / SW
  constant F_BU : std_logic_vector(2 downto 0) := "100";  -- LBU
  constant F_HU : std_logic_vector(2 downto 0) := "101";  -- LHU

  type mem_t is array(0 to NUM_WORDS-1) of std_logic_vector(31 downto 0);

  function initial_mem return mem_t is
    variable m : mem_t;
    variable a : unsigned(31 downto 0);
  begin
    for i in 0 to NUM_WORDS-1 loop
      a    := BASE + to_unsigned(i*4, 32);
      m(i) := std_logic_vector(a) xor x"A5A5A5A5";
    end loop;
    return m;
  end function;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Client interface
  signal start  : std_logic := '0';
  signal store  : std_logic := '0';
  signal addr   : std_logic_vector(31 downto 0) := (others => '0');
  signal funct3 : std_logic_vector(2 downto 0) := (others => '0');
  signal wdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal rdata  : std_logic_vector(31 downto 0);
  signal ready  : std_logic;

  -- AXI4 Write Address Channel
  signal awid    : std_logic_vector(0 downto 0);
  signal awaddr  : std_logic_vector(31 downto 0);
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
  signal wwdata : std_logic_vector(31 downto 0);
  signal wwstrb : std_logic_vector(3 downto 0);
  signal wlast  : std_logic;
  signal wvalid : std_logic;
  signal wready : std_logic := '0';

  -- AXI4 Write Response Channel
  signal bid    : std_logic_vector(0 downto 0) := "0";
  signal bresp  : std_logic_vector(1 downto 0) := "00";
  signal bvalid : std_logic := '0';
  signal bready : std_logic;

  -- AXI4 Read Address Channel
  signal arid    : std_logic_vector(0 downto 0);
  signal araddr  : std_logic_vector(31 downto 0);
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
  signal rid    : std_logic_vector(0 downto 0) := "0";
  signal rrdata : std_logic_vector(31 downto 0) := x"BAD1BAD1";
  signal rresp  : std_logic_vector(1 downto 0) := "00";
  signal rlast  : std_logic := '0';
  signal rvalid : std_logic := '0';
  signal rready : std_logic;

  -- The memory itself, driven by the write process alone.
  signal mem : mem_t := initial_mem;

  -- Handshake bookkeeping between the three write-side processes.
  signal ar_taken  : natural := 0;
  signal aw_taken  : natural := 0;
  signal w_taken   : natural := 0;
  signal held_addr : std_logic_vector(31 downto 0) := (others => '0');
  signal held_data : std_logic_vector(31 downto 0) := (others => '0');
  signal held_strb : std_logic_vector(3 downto 0) := (others => '0');

  -- One counter per driving process: a signal may have only one driver.
  signal bad_raddr : natural := 0;
  signal bad_waddr : natural := 0;
  signal done : boolean := false;

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

  procedure next_rand(s : inout unsigned(31 downto 0)) is
  begin
    s := s(30 downto 0) & (s(31) xor s(21) xor s(1) xor s(0));
  end procedure;

  -- Word index of an address, or -1 if it is outside the window or is
  -- not word aligned.
  function word_index(a : std_logic_vector(31 downto 0)) return integer is
    variable u : unsigned(31 downto 0) := unsigned(a);
    variable n : integer;
  begin
    if u < BASE or u >= BASE + to_unsigned(NUM_WORDS*4, 32) then
      return -1;
    end if;
    if a(1 downto 0) /= "00" then
      return -1;
    end if;
    n := to_integer((u - BASE) srl 2);
    return n;
  end function;

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
  uut : entity work.load_store_unit(behavioral)
    generic map (
      C_M_AXI_ID_WIDTH   => 1,
      C_M_AXI_ADDR_WIDTH => 32,
      C_M_AXI_DATA_WIDTH => 32
      )
    port map (
      start  => start,
      store  => store,
      addr   => addr,
      funct3 => funct3,
      wdata  => wdata,
      rdata  => rdata,
      ready  => ready,

      clk           => clk,
      rst           => rst,

      M_AXI_AWID    => awid,
      M_AXI_AWADDR  => awaddr,
      M_AXI_AWLEN   => awlen,
      M_AXI_AWSIZE  => awsize,
      M_AXI_AWBURST => awburst,
      M_AXI_AWLOCK  => awlock,
      M_AXI_AWCACHE => awcache,
      M_AXI_AWPROT  => awprot,
      M_AXI_AWQOS   => awqos,
      M_AXI_AWVALID => awvalid,
      M_AXI_AWREADY => awready,

      M_AXI_WDATA   => wwdata,
      M_AXI_WSTRB   => wwstrb,
      M_AXI_WLAST   => wlast,
      M_AXI_WVALID  => wvalid,
      M_AXI_WREADY  => wready,

      M_AXI_BID     => bid,
      M_AXI_BRESP   => bresp,
      M_AXI_BVALID  => bvalid,
      M_AXI_BREADY  => bready,

      M_AXI_ARID    => arid,
      M_AXI_ARADDR  => araddr,
      M_AXI_ARLEN   => arlen,
      M_AXI_ARSIZE  => arsize,
      M_AXI_ARBURST => arburst,
      M_AXI_ARLOCK  => arlock,
      M_AXI_ARCACHE => arcache,
      M_AXI_ARPROT  => arprot,
      M_AXI_ARQOS   => arqos,
      M_AXI_ARVALID => arvalid,
      M_AXI_ARREADY => arready,

      M_AXI_RID     => rid,
      M_AXI_RDATA   => rrdata,
      M_AXI_RRESP   => rresp,
      M_AXI_RLAST   => rlast,
      M_AXI_RVALID  => rvalid,
      M_AXI_RREADY  => rready
      );

  ------------------------------------------------------------------------------
  -- Subordinate, read channels.
  ------------------------------------------------------------------------------
  read_slave : process is
    variable seed  : unsigned(31 downto 0) := x"13579BDF";
    variable stall, hold : natural;
    variable got : boolean;
    variable idx : integer;
  begin
    arready <= '0';
    rvalid  <= '0';
    rlast   <= '0';
    rrdata  <= x"BAD1BAD1";
    wait until rising_edge(clk) and rst = '0';

    while not done loop
      got := false;
      while not got loop
        next_rand(seed);
        stall   := to_integer(seed(1 downto 0));
        arready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;
        arready <= '1';
        hold := 1 + to_integer(seed(3 downto 2));
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if arvalid = '1' then
            idx := word_index(araddr);
            got := true;
          end if;
          exit when got;
        end loop;
      end loop;
      arready  <= '0';
      ar_taken <= ar_taken + 1;

      if idx < 0 then
        report "ARADDR " & hex(araddr) &
          " is outside the memory window or is not word aligned"
          severity error;
        bad_raddr <= bad_raddr + 1;
        idx := 0;
      end if;

      next_rand(seed);
      stall := to_integer(seed(4 downto 2));
      if stall > 4 then
        stall := stall - 4;
      end if;
      for i in 1 to stall loop
        wait until rising_edge(clk);
      end loop;

      rrdata <= mem(idx);
      rid    <= "0";
      rresp  <= "00";
      rlast  <= '1';
      rvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when rready = '1';
      end loop;
      rvalid <= '0';
      rlast  <= '0';
      rrdata <= x"BAD1BAD1";
    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- Subordinate, write address channel.
  ------------------------------------------------------------------------------
  aw_slave : process is
    variable seed  : unsigned(31 downto 0) := x"0F1E2D3C";
    variable stall, hold : natural;
    variable got : boolean;
  begin
    awready <= '0';
    wait until rising_edge(clk) and rst = '0';

    while not done loop
      got := false;
      while not got loop
        next_rand(seed);
        stall   := to_integer(seed(1 downto 0));
        awready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;
        awready <= '1';
        hold := 1 + to_integer(seed(3 downto 2));
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if awvalid = '1' then
            held_addr <= awaddr;
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
  -- Subordinate, write data channel.
  ------------------------------------------------------------------------------
  w_slave : process is
    variable seed  : unsigned(31 downto 0) := x"2468ACE0";
    variable stall, hold : natural;
    variable got : boolean;
  begin
    wready <= '0';
    wait until rising_edge(clk) and rst = '0';

    while not done loop
      got := false;
      while not got loop
        next_rand(seed);
        stall  := to_integer(seed(2 downto 0));
        if stall > 4 then
          stall := stall - 4;
        end if;
        wready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;
        wready <= '1';
        hold := 1 + to_integer(seed(4 downto 3));
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if wvalid = '1' then
            held_data <= wwdata;
            held_strb <= wwstrb;
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
  -- Subordinate, write response channel.  This is also where the write is
  -- applied, one byte lane at a time under the strobes, which is what a
  -- real memory does and what makes a wrong WSTRB visible.
  ------------------------------------------------------------------------------
  b_slave : process is
    variable seed : unsigned(31 downto 0) := x"5A5A1234";
    variable stall : natural;
    variable n : natural := 0;
    variable idx : integer;
    variable word : std_logic_vector(31 downto 0);
  begin
    bvalid <= '0';
    bresp  <= "00";
    wait until rising_edge(clk) and rst = '0';

    while not done loop
      n := n + 1;
      while aw_taken < n or w_taken < n loop
        wait until rising_edge(clk);
      end loop;

      idx := word_index(held_addr);
      if idx < 0 then
        report "AWADDR " & hex(held_addr) &
          " is outside the memory window or is not word aligned"
          severity error;
        bad_waddr <= bad_waddr + 1;
      else
        word := mem(idx);
        for b in 0 to 3 loop
          if held_strb(b) = '1' then
            word(8*b+7 downto 8*b) := held_data(8*b+7 downto 8*b);
          end if;
        end loop;
        mem(idx) <= word;
      end if;
      wait until rising_edge(clk);

      next_rand(seed);
      stall := to_integer(seed(2 downto 0));
      if stall > 4 then
        stall := stall - 4;
      end if;
      for i in 1 to stall loop
        wait until rising_edge(clk);
      end loop;

      bresp  <= "00";
      bid    <= "0";
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
  -- Client and checker.
  ------------------------------------------------------------------------------
  test : process is
    variable checks : natural := 0;
    variable errors : natural := 0;
    variable seed   : unsigned(31 downto 0) := x"0BADF00D";

    variable shadow : mem_t := initial_mem;

    variable idx, off, cycles : integer;
    variable sz : integer;
    variable is_store, is_unsigned : boolean;
    variable f3 : std_logic_vector(2 downto 0);
    variable a  : std_logic_vector(31 downto 0);
    variable d  : std_logic_vector(31 downto 0);
    variable expect : std_logic_vector(31 downto 0);
    variable ar_at, aw_at : natural;
    variable word   : std_logic_vector(31 downto 0);
    variable lo     : integer;

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

    procedure step is
    begin
      wait until rising_edge(clk);
    end procedure;

    -- Name an operation the way the assembler would, so a failure reads
    -- like the instruction that caused it.
    function op_name(st : boolean; f : std_logic_vector(2 downto 0))
      return string is
    begin
      if st then
        case f is
          when F_B    => return "SB";
          when F_H    => return "SH";
          when others => return "SW";
        end case;
      else
        case f is
          when F_B    => return "LB";
          when F_H    => return "LH";
          when F_BU   => return "LBU";
          when F_HU   => return "LHU";
          when others => return "LW";
        end case;
      end if;
    end function;

  begin
    rst <= '1';
    start   <= '0';
    for i in 1 to 4 loop
      step;
      check(arvalid = '0' and awvalid = '0' and wvalid = '0',
            "a VALID is high while the unit is in reset");
    end loop;
    rst <= '0';
    step;

    for trial in 1 to NUM_OPS loop

      -- Pick an operation.  Sizes are naturally aligned, because RV32I
      -- lets a core trap on anything else and this one cannot trap yet.
      next_rand(seed);
      is_store := seed(0) = '1';
      sz       := to_integer(seed(2 downto 1));
      if sz > 2 then
        sz := 2;
      end if;
      is_unsigned := seed(3) = '1' and not is_store and sz < 2;

      next_rand(seed);
      idx := to_integer(seed(7 downto 0)) mod NUM_WORDS;
      case sz is
        when 0      => off := to_integer(seed(9 downto 8));
        when 1      => off := 2 * to_integer(seed(9 downto 9));
        when others => off := 0;
      end case;

      case sz is
        when 0 =>
          if is_unsigned then f3 := F_BU; else f3 := F_B; end if;
        when 1 =>
          if is_unsigned then f3 := F_HU; else f3 := F_H; end if;
        when others =>
          f3 := F_W;
      end case;

      a := std_logic_vector(BASE + to_unsigned(idx*4 + off, 32));

      next_rand(seed);
      d := std_logic_vector(seed);

      -- What the operation should produce.
      word := shadow(idx);
      lo   := 8 * off;
      if is_store then
        expect := (others => '0');
        case sz is
          when 0      => word(lo+7 downto lo)  := d(7 downto 0);
          when 1      => word(lo+15 downto lo) := d(15 downto 0);
          when others => word := d;
        end case;
      else
        case sz is
          when 0 =>
            if is_unsigned then
              expect := x"000000" & word(lo+7 downto lo);
            else
              expect := (31 downto 8 => word(lo+7)) & word(lo+7 downto lo);
            end if;
          when 1 =>
            if is_unsigned then
              expect := x"0000" & word(lo+15 downto lo);
            else
              expect := (31 downto 16 => word(lo+15)) & word(lo+15 downto lo);
            end if;
          when others =>
            expect := word;
        end case;
      end if;

      -- Issue it.
      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            "ready never came up before operation " & integer'image(trial));
      exit when cycles >= TIMEOUT;

      ar_at := ar_taken;
      aw_at := aw_taken;

      addr   <= a;
      wdata  <= d;
      funct3 <= f3;
      if is_store then
        store <= '1';
      else
        store <= '0';
      end if;
      start <= '1';
      step;
      start <= '0';

      -- The client moves on.  The unit must have captured everything it
      -- needs, including the byte offset it will use on the way back.
      addr   <= (others => '1');
      wdata  <= not d;
      funct3 <= "111";
      store  <= '0';

      step;
      check(ready = '0',
            "ready stayed high after " & op_name(is_store, f3) &
            " was accepted, on operation " & integer'image(trial));

      cycles := 0;
      while ready /= '1' and cycles < TIMEOUT loop
        step;
        cycles := cycles + 1;
      end loop;
      check(cycles < TIMEOUT,
            op_name(is_store, f3) & " at " & hex(a) & " never finished");
      exit when cycles >= TIMEOUT;

      if is_store then
        check(aw_taken = aw_at + 1 and ar_taken = ar_at,
              op_name(is_store, f3) & " at " & hex(a) & " used the read " &
              "channel: " & integer'image(ar_taken - ar_at) &
              " addresses were read and " &
              integer'image(aw_taken - aw_at) & " written");
        shadow(idx) := word;
        check(mem(idx) = word,
              op_name(is_store, f3) & " of " & hex(d) & " at " & hex(a) &
              ": memory holds " & hex(mem(idx)) & ", expected " & hex(word));
        -- Over-wide strobes show up next door.
        if idx > 0 then
          check(mem(idx-1) = shadow(idx-1),
                op_name(is_store, f3) & " at " & hex(a) &
                " also changed the word below it");
        end if;
        if idx < NUM_WORDS-1 then
          check(mem(idx+1) = shadow(idx+1),
                op_name(is_store, f3) & " at " & hex(a) &
                " also changed the word above it");
        end if;
      else
        check(ar_taken = ar_at + 1 and aw_taken = aw_at,
              op_name(is_store, f3) & " at " & hex(a) & " used the write " &
              "channel: " & integer'image(ar_taken - ar_at) &
              " addresses were read and " &
              integer'image(aw_taken - aw_at) & " written");
        check(rdata = expect,
              op_name(is_store, f3) & " at " & hex(a) & ": rdata is " &
              hex(rdata) & ", expected " & hex(expect));
        check(mem(idx) = shadow(idx),
              op_name(is_store, f3) & " at " & hex(a) & " changed memory");
      end if;

    end loop;

    -- Nothing anywhere else moved.
    for i in 0 to NUM_WORDS-1 loop
      check(mem(i) = shadow(i),
            "word " & integer'image(i) & " holds " & hex(mem(i)) &
            ", expected " & hex(shadow(i)));
    end loop;

    check(bad_raddr + bad_waddr = 0,
          integer'image(bad_raddr + bad_waddr) &
          " addresses were put on the bus outside the memory window");

    done <= true;

    if errors = 0 then
      report "load_store_unit testbench PASSED: all " &
        integer'image(checks) & " checks passed, over " &
        integer'image(NUM_OPS) & " accesses." severity note;
    else
      report "load_store_unit testbench FAILED: " & integer'image(errors) &
        " of " & integer'image(checks) & " checks failed." severity failure;
    end if;
    wait;
  end process;

end behavioral;
