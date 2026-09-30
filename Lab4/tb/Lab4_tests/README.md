# CENG 442 Lab 4 test programs and board files

Three test programs and the Cylon eye for the core you build in Lab 4, a
simulation memory model, two testbenches, and the files that put the
block design on the Nexys A7.

## What is here

| File | What it is |
| --- | --- |
| `t1_regs.S` | Register instructions only. No branches, no jumps, no memory. |
| `t2_branch.S` | Adds branches: all six conditions, taken and not taken. |
| `t3_jump.S` | Adds JAL, JALR and AUIPC, and checks the link register. |
| `cylon.S` | The Cylon eye, in registers only. Shown on the LEDs through the debug port. |
| `axi_memory.vhdl` | An AXI4 subordinate for GHDL: memory, loaded from a `.hex` file. |
| `cpu_testbench_template.vhdl` | GHDL harness: your `cpu_core` and one `axi_memory`. Nothing to fill in. |
| `cpu_system_testbench.vhdl` | Vivado harness: your block design. Nothing to fill in. |
| `nexys_a7.xdc` | Pins for the block design: `DBGsel` on SW4..SW0, `DBGreg` on the LEDs. |
| `link.ld` | ROM at 00000000. The same map Labs 5 and 6 use. |
| `Makefile` | Builds each program to `.dis`, `.hex` and `.coe`. |

## Building

```sh
make
```

Each program produces three files you care about. The `.dis` is the
disassembly: keep it open, because when the core does nothing it is how
you find out what the first few instructions actually were. The `.hex` is
what `axi_memory` reads in GHDL. The `.coe` is the same words in the
format the Block Memory Generator wants.

The Cylon eye is built twice. `cylon` waits long enough between steps to
see by eye, and is the one for the board. `cylon_sim` is the same program
with a delay of 4, so that a simulation sees a whole sweep in a few
thousand cycles.

The toolchain prefix defaults to `riscv32-unknown-elf-`, which is on the
PATH on the lab machines. Override it for the copy that ships with Vitis:

```sh
make TOOLPREFIX=/opt/Xilinx/2025.1/gnu/riscv/lin/riscv64-unknown-elf/x86_64-oesdk-linux/usr/bin/riscv32-xilinx-elf/riscv32-xilinx-elf-
```

## Running in GHDL

Run the simulation **from this directory**, because the program name the
testbench is given is a relative path. The testbench instantiates
`cpu_core` from the skeleton, so there is nothing to fill in.

```sh
G="--std=08 -fsynopsys"
ghdl -a $G <your core's files> axi_memory.vhdl cpu_testbench_template.vhdl
ghdl -e $G cpu_testbench_template
ghdl -r $G cpu_testbench_template -gPROGRAM=t1_regs.hex
ghdl -r $G cpu_testbench_template -gPROGRAM=cylon_sim.hex -gCYLON=true
```

`-fsynopsys` is there because `project_types.vhdl` uses
`std_logic_arith`.

This is the quick way to debug the core. Get all three programs and
`cylon_sim` passing here before building the block design.

## Running the block design

Add `cpu_system_testbench.vhdl` to a simulation set and make it the top.
Set the Block Memory Generator's Memory Type to Single Port ROM, which is
what makes Load Init File available behind a BRAM controller, initialise
it from a `.coe`, generate the output products, and run. The testbench
drives the board's 100 MHz clock into the Clocking Wizard, and nothing
happens for the first few thousand cycles while it locks. To run a
different program, change the `.coe` and regenerate.
Set the `PROGRAM` generic to the program's name, which is used only in
the report, and set `CYLON` to true for `cylon_sim.coe`.

## How a program reports

Every test program leaves its verdict in two registers and then parks in
a one instruction loop.

| | |
| --- | --- |
| `x4 = 1` | the program passed |
| `x4 = 0`, `x3 = n` | check `n` failed |
| `x4 = 0`, `x3 = 0` | the core never reached the end |

The testbench reads both through the debug port and prints one line. When
a check fails, its number is in a comment beside that check in the `.S`
file, so you get the name of the instruction that broke rather than an
address in a waveform.

`t1_regs` is the odd one out: it has no branches, so it cannot check
itself the way the others do. It folds every result into two accumulators
and compares those against constants at the end, which is why a failure
gives no check number. When it fails, read the register file: the comment
beside each instruction says what that register should have held, and the
first one that disagrees is the one to chase.

## On the board

The block design's wrapper is the top module. Add `nexys_a7.xdc`. The
Clocking Wizard in the block design runs the core at 50 MHz, because a
whole instruction executes in one clock cycle and that path does not
fit in the board's 10 ns. Initialise the block memory from `cylon.coe`.

Set the five low slide switches to 01010 and press CPU RESET. **With all
the switches down the LEDs show x0, which is always zero, and the board
looks dead.** Any other switch setting shows that register's low half on
the LEDs, while the program runs. s1 (01001) lights the leftmost LED as
soon as the program starts, which is a quick check that the core runs at
all.

## Two things worth doing

**Run each program twice in GHDL.** `MAX_STALL` starts at 0, which
answers as fast as the bus allows. Once a program passes, set it to 3 and
run again. A core with a handshake bug often passes against instant
memory and fails against slow memory.

**Let the model complain.** It reports an address outside its window, a
burst longer than one beat, a transfer that is not four bytes, and a
write to the read only ROM. Every one of those is a real fault in the
core, and the message says which, which is quicker than reading a
waveform.
