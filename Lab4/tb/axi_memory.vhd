--------------------------------------------------------------------------------
-- Copyright (c) 2026 Larry D. Pyeatt
-- All rights reserved.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- AXI4 memory, for simulation only                                   axi_memory
--
-- A subordinate to hang on the other end of a fetch unit or a load/store
-- unit.  It holds MEM_SIZE_BYTES of memory at BASE_ADDR, optionally
-- initialised from a file, and answers single beat reads and writes.
--
-- In Lab 4 one of these is the ROM the test programs are linked for:
--
--   ROM  8 KB at 00000000   the program, from the .hex the Makefile builds
--
-- Lab 5 adds a second, 8 KB of RAM at C0000000, for loads and stores.
--
-- This is a simulation model.  It is not synthesisable and it is not meant
-- to be: it uses processes, file reading and a large array, none of which
-- belong in the core you are building.  The block design in Lab 4 uses a
-- Vivado block memory instead, initialised from the .coe file that the
-- same Makefile produces.
--
-- Generics
-- --------
--   MEM_SIZE_BYTES  size of the memory, a multiple of 4
--   BASE_ADDR       the address the first word answers to
--   INIT_FILE       a text file of 32 bit hex words, lowest address first,
--                   one per line.  "" leaves the memory at zero.  A file
--                   shorter than the memory fills the front of it.
--   READ_ONLY       true refuses writes and reports them.  Use it for the
--                   ROM: a core that writes to its own program is telling
--                   you something, and you want to hear it early
--   MAX_STALL       how many cycles the model may hold a READY low, and
--                   hold back read data and write responses.  0 answers
--                   as fast as the bus allows, which is the easiest case
--                   for your core and the least like real memory.  Leave
--                   it at 3 or more once the core works at 0: an engine
--                   with a handshake bug often passes against instant
--                   memory and fails against slow memory
--   NAME            what this instance is called in its reports
--
-- Everything it complains about is a real fault, and the message says which:
-- an address outside its window, a burst longer than one beat, a write to a
-- read only memory, or a transfer size other than four bytes.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use STD.textio.all;

entity axi_memory is
  generic (
    MEM_SIZE_BYTES : integer  := 8192;
    BASE_ADDR      : unsigned(31 downto 0) := x"00000000";
    INIT_FILE      : string   := "";
    READ_ONLY      : boolean  := false;
    MAX_STALL      : integer  := 3;
    NAME           : string   := "memory";
    ID_WIDTH       : integer  := 1
    );
  port (
    clk     : in  std_logic;
    aresetn : in  std_logic;          -- active low, as AXI has it

    -- AXI4 Write Address Channel
    s_axi_awid    : in  std_logic_vector(ID_WIDTH-1 downto 0);
    s_axi_awaddr  : in  std_logic_vector(31 downto 0);
    s_axi_awlen   : in  std_logic_vector(7 downto 0);
    s_axi_awsize  : in  std_logic_vector(2 downto 0);
    s_axi_awburst : in  std_logic_vector(1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;

    -- AXI4 Write Data Channel
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wlast   : in  std_logic;
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;

    -- AXI4 Write Response Channel
    s_axi_bid     : out std_logic_vector(ID_WIDTH-1 downto 0);
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;

    -- AXI4 Read Address Channel
    s_axi_arid    : in  std_logic_vector(ID_WIDTH-1 downto 0);
    s_axi_araddr  : in  std_logic_vector(31 downto 0);
    s_axi_arlen   : in  std_logic_vector(7 downto 0);
    s_axi_arsize  : in  std_logic_vector(2 downto 0);
    s_axi_arburst : in  std_logic_vector(1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;

    -- AXI4 Read Data Channel
    s_axi_rid     : out std_logic_vector(ID_WIDTH-1 downto 0);
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rlast   : out std_logic;
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic
    );
end axi_memory;

architecture sim of axi_memory is

  constant NUM_WORDS : integer := MEM_SIZE_BYTES / 4;

  type mem_t is array(0 to NUM_WORDS-1) of std_logic_vector(31 downto 0);

  -- Read INIT_FILE into the front of the memory.  One 32 bit hex word per
  -- line, lowest address first, which is what the Makefile's .hex target
  -- produces.  Anything the file does not reach stays at zero.
  impure function load_init return mem_t is
    file     f    : text;
    variable st   : file_open_status;
    variable l    : line;
    variable w    : std_logic_vector(31 downto 0);
    variable m    : mem_t := (others => (others => '0'));
    variable i    : integer := 0;
  begin
    if INIT_FILE = "" then
      return m;
    end if;
    file_open(st, f, INIT_FILE, read_mode);
    if st /= open_ok then
      report NAME & ": cannot open init file """ & INIT_FILE & """"
        severity failure;
      return m;
    end if;
    while not endfile(f) and i < NUM_WORDS loop
      readline(f, l);
      if l'length > 0 then
        hread(l, w);
        m(i) := w;
        i    := i + 1;
      end if;
    end loop;
    if not endfile(f) then
      report NAME & ": init file """ & INIT_FILE &
        """ is larger than the memory; the rest is ignored" severity warning;
    end if;
    file_close(f);
    report NAME & ": loaded " & integer'image(i) & " words from """ &
      INIT_FILE & """" severity note;
    return m;
  end function;

  signal mem : mem_t := load_init;

  -- Handshake bookkeeping between the write side processes.
  signal aw_taken  : natural := 0;
  signal w_taken   : natural := 0;
  signal held_addr : std_logic_vector(31 downto 0) := (others => '0');
  signal held_id   : std_logic_vector(ID_WIDTH-1 downto 0) := (others => '0');
  signal held_data : std_logic_vector(31 downto 0) := (others => '0');
  signal held_strb : std_logic_vector(3 downto 0) := (others => '0');

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

  -- Word index of an address, or -1 if it is not one this memory holds.
  -- Everything that can be wrong about an address is reported here, by the
  -- caller, with the channel it arrived on.
  function word_index(a : std_logic_vector(31 downto 0)) return integer is
    variable u : unsigned(31 downto 0) := unsigned(a);
  begin
    if u < BASE_ADDR or u >= BASE_ADDR + to_unsigned(MEM_SIZE_BYTES, 32) then
      return -1;
    end if;
    if a(1 downto 0) /= "00" then
      return -2;
    end if;
    return to_integer((u - BASE_ADDR) srl 2);
  end function;

  procedure complain(constant channel : in string;
                     constant a       : in std_logic_vector(31 downto 0);
                     constant idx     : in integer) is
  begin
    if idx = -1 then
      report NAME & ": " & channel & " address " & hex(a) &
        " is outside this memory, which holds " &
        integer'image(MEM_SIZE_BYTES) & " bytes at " &
        hex(std_logic_vector(BASE_ADDR)) severity error;
    elsif idx = -2 then
      report NAME & ": " & channel & " address " & hex(a) &
        " is not word aligned.  The load/store unit is supposed to clear " &
        "the low two bits before the address reaches the bus" severity error;
    end if;
  end procedure;

begin

  ------------------------------------------------------------------------------
  -- Read channels
  ------------------------------------------------------------------------------
  read_side : process is
    variable seed  : unsigned(31 downto 0) := x"13579BDF";
    variable stall : natural;
    variable hold  : natural;
    variable got   : boolean;
    variable idx   : integer;
    variable id    : std_logic_vector(ID_WIDTH-1 downto 0);
  begin
    s_axi_arready <= '0';
    s_axi_rvalid  <= '0';
    s_axi_rlast   <= '0';
    s_axi_rresp   <= "00";
    s_axi_rdata   <= (others => '0');
    s_axi_rid     <= (others => '0');

    wait until rising_edge(clk) and aresetn = '1';

    loop
      -- Take an address, after a stall of up to MAX_STALL cycles.  ARREADY
      -- is withdrawn again while waiting, which a subordinate is allowed to
      -- do and which your engine has to cope with.
      got := false;
      while not got loop
        next_rand(seed);
        if MAX_STALL > 0 then
          stall := to_integer(seed(3 downto 0)) mod (MAX_STALL + 1);
        else
          stall := 0;
        end if;
        s_axi_arready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;

        s_axi_arready <= '1';
        hold := 1 + (to_integer(seed(5 downto 4)) mod 3);
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if s_axi_arvalid = '1' then
            idx := word_index(s_axi_araddr);
            id  := s_axi_arid;
            if idx < 0 then
              complain("read", s_axi_araddr, idx);
              idx := 0;
            end if;
            if s_axi_arlen /= x"00" then
              report NAME & ": ARLEN is " & hex(s_axi_arlen) &
                ".  This model answers single beat reads only" severity error;
            end if;
            if s_axi_arsize /= "010" then
              report NAME & ": ARSIZE is not 010, so the beat is not four " &
                "bytes wide" severity error;
            end if;
            got := true;
          end if;
          exit when got;
        end loop;
      end loop;
      s_axi_arready <= '0';

      -- Hold the data back for a while, then hand over one beat.
      next_rand(seed);
      if MAX_STALL > 0 then
        stall := to_integer(seed(3 downto 0)) mod (MAX_STALL + 1);
      else
        stall := 0;
      end if;
      for i in 1 to stall loop
        wait until rising_edge(clk);
      end loop;

      s_axi_rdata  <= mem(idx);
      s_axi_rid    <= id;
      s_axi_rresp  <= "00";
      s_axi_rlast  <= '1';
      s_axi_rvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when s_axi_rready = '1';
      end loop;
      s_axi_rvalid <= '0';
      s_axi_rlast  <= '0';
      -- RDATA means nothing while RVALID is low, so leave something
      -- recognisable on it.  A core that latches it anyway will show this.
      s_axi_rdata  <= x"BAD1BAD1";
    end loop;
  end process;

  ------------------------------------------------------------------------------
  -- Write address channel
  ------------------------------------------------------------------------------
  aw_side : process is
    variable seed  : unsigned(31 downto 0) := x"0F1E2D3C";
    variable stall : natural;
    variable hold  : natural;
    variable got   : boolean;
  begin
    s_axi_awready <= '0';
    wait until rising_edge(clk) and aresetn = '1';

    loop
      got := false;
      while not got loop
        next_rand(seed);
        if MAX_STALL > 0 then
          stall := to_integer(seed(3 downto 0)) mod (MAX_STALL + 1);
        else
          stall := 0;
        end if;
        s_axi_awready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;

        s_axi_awready <= '1';
        hold := 1 + (to_integer(seed(5 downto 4)) mod 3);
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if s_axi_awvalid = '1' then
            held_addr <= s_axi_awaddr;
            held_id   <= s_axi_awid;
            if s_axi_awlen /= x"00" then
              report NAME & ": AWLEN is " & hex(s_axi_awlen) &
                ".  This model accepts single beat writes only" severity error;
            end if;
            got := true;
          end if;
          exit when got;
        end loop;
      end loop;
      s_axi_awready <= '0';
      aw_taken      <= aw_taken + 1;
    end loop;
  end process;

  ------------------------------------------------------------------------------
  -- Write data channel
  ------------------------------------------------------------------------------
  w_side : process is
    variable seed  : unsigned(31 downto 0) := x"2468ACE0";
    variable stall : natural;
    variable hold  : natural;
    variable got   : boolean;
  begin
    s_axi_wready <= '0';
    wait until rising_edge(clk) and aresetn = '1';

    loop
      got := false;
      while not got loop
        next_rand(seed);
        if MAX_STALL > 0 then
          stall := to_integer(seed(3 downto 0)) mod (MAX_STALL + 1);
        else
          stall := 0;
        end if;
        s_axi_wready <= '0';
        for i in 1 to stall loop
          wait until rising_edge(clk);
        end loop;

        s_axi_wready <= '1';
        hold := 1 + (to_integer(seed(5 downto 4)) mod 3);
        for i in 1 to hold loop
          wait until rising_edge(clk);
          if s_axi_wvalid = '1' then
            held_data <= s_axi_wdata;
            held_strb <= s_axi_wstrb;
            if s_axi_wlast /= '1' then
              report NAME & ": WLAST is low on the only beat of the burst"
                severity error;
            end if;
            got := true;
          end if;
          exit when got;
        end loop;
      end loop;
      s_axi_wready <= '0';
      w_taken      <= w_taken + 1;
    end loop;
  end process;

  ------------------------------------------------------------------------------
  -- Write response channel.  This is also where the write is applied, one
  -- byte lane at a time under the strobes, which is what a real memory does.
  ------------------------------------------------------------------------------
  b_side : process is
    variable seed  : unsigned(31 downto 0) := x"5A5A1234";
    variable stall : natural;
    variable n     : natural := 0;
    variable idx   : integer;
    variable word  : std_logic_vector(31 downto 0);
    variable resp  : std_logic_vector(1 downto 0);
  begin
    s_axi_bvalid <= '0';
    s_axi_bresp  <= "00";
    s_axi_bid    <= (others => '0');
    wait until rising_edge(clk) and aresetn = '1';

    loop
      n := n + 1;
      while aw_taken < n or w_taken < n loop
        wait until rising_edge(clk);
      end loop;

      resp := "00";
      idx  := word_index(held_addr);
      if idx < 0 then
        complain("write", held_addr, idx);
        resp := "10";                   -- SLVERR
      elsif READ_ONLY then
        report NAME & ": a write to " & hex(held_addr) &
          " was refused.  This memory is read only, so something in your " &
          "core is storing into its own program" severity error;
        resp := "10";
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
      if MAX_STALL > 0 then
        stall := to_integer(seed(3 downto 0)) mod (MAX_STALL + 1);
      else
        stall := 0;
      end if;
      for i in 1 to stall loop
        wait until rising_edge(clk);
      end loop;

      s_axi_bresp  <= resp;
      s_axi_bid    <= held_id;
      s_axi_bvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when s_axi_bready = '1';
      end loop;
      s_axi_bvalid <= '0';
    end loop;
  end process;

end sim;
