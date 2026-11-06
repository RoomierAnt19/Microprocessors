# CENG 442 Lab 6 files

The control and status registers, the machine timer, and the test program
for Lab 6.

| File | What it is |
|---|---|
| `CSR_regs.vhdl` | The machine-mode CSRs. Connect it to your datapath and sequencer. You should not need to change it. |
| `generic_CSR.vhdl` | One CSR, used by `CSR_regs`. |
| `status_register.vhdl` | `mstatus`, used by `CSR_regs`. |
| `machine_timer.vhdl` | `mtime` and `mtimecmp` as an AXI4-Lite subordinate. Its `mtip` output is your interrupt source. |
| `t6_trap.S` | The test program: 41 numbered checks. |
| `Makefile` | Builds `t6_trap`, `trap_cylon` and `trap_cylon_sim`. |
| `link.ld` | The Lab 5 memory map. |

Two things to know before you add these to your project.

**`generic_CSR.vhdl` is VHDL-2008.** It uses an else-generate. In Vivado,
select the file in the Sources window and set its file type to VHDL 2008 in
Source File Properties. For GHDL, analyse with `--std=08`.

**`CSR_regs` and `machine_timer` use your `generic_register`.** They
instantiate `entity work.generic_register(behavioral)` with a generic `XLEN`
and the ports `d`, `q`, `clk`, `en` and `rst`, where `rst` is synchronous,
active high, and takes priority over `en`. If your register uses different
names, edit the port maps in the provided files to match it.

The Makefile builds with `-march=rv32i_zicsr`, because the assembler treats
the CSR instructions as an extension of their own. Your own programs need the
same. Run `make` to build everything, and `make clean` to remove what it
generated.
