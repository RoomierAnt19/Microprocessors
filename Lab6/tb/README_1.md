# CENG 442 Lab 5 test programs and memory model

Two test programs for the loads and stores your core gains in Lab 5, a
simulation memory model to run them against, and a testbench template
that puts the two together. Nothing here is synthesisable and none of it
goes on the FPGA. The three Lab 4 programs, `t1_regs`, `t2_branch` and
`t3_jump`, run in this template too. Copy their `.hex` files here and run
them first.

## What is here

| File | What it is |
| --- | --- |
| `t4_load.S` | Adds loads: LW, LH, LHU, LB, LBU, at every offset. |
| `t5_store.S` | Adds stores: SW, SH, SB, read back, and the neighbours checked. |
| `axi_memory.vhdl` | An AXI4 subordinate: memory, optionally loaded from a file. |
| `cpu_testbench_template.vhdl` | Your `cpu_core`, two memories, and a watcher. One note to read. |
| `link.ld` | ROM at 00000000, RAM at 10000000, the memory map used on the board. |
| `Makefile` | Builds each program to `.dis`, `.hex` and `.coe`. |

## Building

```sh
make
```

Each program produces three files you care about. The `.dis` is the
disassembly: keep it open, because when the core does nothing it is how
you find out what the first few instructions actually were. The `.hex` is
what `axi_memory` reads in simulation. The `.coe` is the same words in the
format Vivado wants for a block memory, which is what Part B needs.

The toolchain prefix defaults to `riscv32-unknown-elf-`, which is on the
PATH on the lab machines. Override it for the copy that ships with Vitis:

```sh
make TOOLPREFIX=/opt/Xilinx/2025.1/gnu/riscv/lin/riscv64-unknown-elf/x86_64-oesdk-linux/usr/bin/riscv32-xilinx-elf/riscv32-xilinx-elf-
```

## Running

Read the one FILL IN note in `cpu_testbench_template.vhdl`, then run
the simulation **from this directory**, because the program name the
testbench is given is a relative path.

```sh
G="--std=08 -fsynopsys"
ghdl -a $G <your core's files> axi_memory.vhdl cpu_testbench_template.vhdl
ghdl -e $G cpu_testbench_template
ghdl -r $G cpu_testbench_template -gPROGRAM=t4_load.hex
```

`-fsynopsys` is there because `project_types.vhdl` uses
`std_logic_arith`.

In Vivado, add the files to a simulation set, make
`cpu_testbench_template` the top, and set `PROGRAM` in the simulation
settings.

## How a program reports

Every program leaves its verdict in two registers and then parks in a one
instruction loop.

| | |
| --- | --- |
| `x4 = 1` | the program passed |
| `x4 = 0`, `x3 = n` | check `n` failed |
| `x4 = 0`, `x3 = 0` | the core never reached the end |

The testbench reads both through the debug port and prints one line. When
a check fails, its number is in a comment beside that check in the `.S`
file, so you get the name of the instruction that broke rather than an
address in a waveform.

Run the Lab 4 programs first. They do not load or store, so a failure in
one of them means the new wiring broke something that used to work. Then
`t4_load`, then `t5_store`.

## Two things worth doing

**Run each program twice.** `MAX_STALL` on the memories starts at 0, which
answers as fast as the bus allows. Once a program passes, set it to 3 and
run again. A core with a handshake bug often passes against instant memory
and fails against slow memory, and the DDR on the board in Part B is very
slow indeed.

**Let the model complain.** It reports an address outside its window, a
burst longer than one beat, a transfer that is not four bytes, and a write
to the read only ROM. Every one of those is a real fault in the core, and
the message says which, which is quicker than reading a waveform.
