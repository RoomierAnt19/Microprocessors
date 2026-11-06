#-------------------------------------------------------------------------------
# CENG 442 Lab 6                                                       t6_trap.S
#
# The CSRs, exceptions, mret, and the machine timer interrupt, on top of
# everything before.
#
#     x4 = 1              every check passed
#     x4 = 0, x3 = n      check n failed
#     x4 = 0, x3 = 99     a trap went to a vector slot that should never be
#                         used.  mcause is in t6.
#
# The order matters.  Checks 1 to 17 use only the CSR instructions, with
# interrupts off, so a core that cannot read and write a CSR fails there and
# not in a trap handler.  Checks 18 to 31 take exceptions, which need mtvec,
# mepc, mcause and mstatus to work.  Checks 32 to 40 use the timer.
#
# Registers the handlers own, so the main program leaves them alone:
#
#     s0  mcause, s1  mepc, s2  mstatus     as the exception handler saw them
#     s3  exceptions taken
#     s4  timer interrupts taken
#     s5  mcause, s6  mepc                  as the timer handler saw them
#     t5, t6                                handler scratch
#
# The machine timer is at 40020000: mtime at +0 and +4, mtimecmp at +8 and
# +C, low word first.  mtimecmp resets to all ones.
#
# Nothing here uses RAM, and nothing here needs the stack.
#
# The board build
# ---------------
# Built with -DBOARD (the Makefile's trap_cylon), the same checks run on the
# FPGA, and the LEDs (the AXI GPIO at 40000000) say how it went:
#
#   a failed check      LEDs 15 and 14 lit, and the check number in the low
#                       bits: C000 + n.  No frame of the eye lights two LEDs.
#   every check passed  the Cylon eye, one step per timer interrupt, while
#                       the main program sits in a wfi loop
#
# The eye sweeps out and back for as long as the board is powered.  x4 is
# set to 1 once it has taken PASS_STEPS steps (30, one sweep out and back),
# and the sweep carries on regardless, so a simulation that reports PASSED
# has seen the interrupts drive it.  CYLON_TICKS is the time each LED stays lit, in
# clocks; the default is 60 ms at 50 MHz, the Lab 6 block design's clock.
# trap_cylon_sim uses 300.
#
# In the eye, the timer handler also owns a0 (the pattern), a1 (the
# direction), s8 (nonzero once the eye is running), s9 (steps taken), and
# t3 and t4, which the main program no longer uses by then.
#-------------------------------------------------------------------------------

#ifndef PASS_STEPS
#define PASS_STEPS 30
#endif

#ifndef CYLON_TICKS
#define CYLON_TICKS 3000000
#endif

	.equ	TIMER, 0x40020000
	.equ	INTERVAL, 2000		# clocks between timer interrupts
	.equ	GPIO, 0x40000000	# the LEDs, in the board build

	.section .text.init
	.globl _start
_start:
	jal	zero, init

	#--- the trap vector table ---------------------------------------------
	# mtvec is vectored and its base is 128-byte aligned.  Exceptions go to
	# the base.  Interrupt n goes to base + 4n.
	.balign	128
trap_table:
	jal	zero, exc_handler	# 0  exceptions
	jal	zero, unexpected	# 1
	jal	zero, unexpected	# 2
	jal	zero, unexpected	# 3  machine software interrupt
	jal	zero, unexpected	# 4
	jal	zero, unexpected	# 5
	jal	zero, unexpected	# 6
	jal	zero, timer_handler	# 7  machine timer interrupt
	jal	zero, unexpected	# 8
	jal	zero, unexpected	# 9
	jal	zero, unexpected	# 10
	jal	zero, unexpected	# 11 machine external interrupt

	#--- the exception handler ---------------------------------------------
	# Records what it saw, counts, and returns to the instruction after the
	# one that trapped.  mepc points at the trapping instruction itself, so
	# returning without the +4 would take the same exception forever.
exc_handler:
	csrr	s0, mcause
	csrr	s1, mepc
	csrr	s2, mstatus
	addi	s3, s3, 1
	addi	t6, s1, 4
	csrw	mepc, t6
	mret

	#--- the timer handler -------------------------------------------------
	# Records what it saw and counts.  The interrupt is level sensitive, and
	# the only way to clear it is to move mtimecmp past mtime: INTERVAL
	# clocks on for the first two, and out of reach for good on the third.
timer_handler:
	bne	s8, zero, cylon_tick
	addi	s4, s4, 1
	csrr	s5, mcause
	csrr	s6, mepc
	li	t5, TIMER
	li	t6, 3
	blt	s4, t6, 1f
	li	t6, -1
	sw	t6, 12(t5)		# mtimecmp high = all ones: never again
	mret
1:	lw	t6, 0(t5)		# mtime, low word
	li	t5, INTERVAL
	add	t6, t6, t5
	li	t5, TIMER
	sw	t6, 8(t5)		# mtimecmp low = now + INTERVAL
	mret

	#--- the eye's timer handler, board build only ------------------------
	# One step of the eye per interrupt.  mtimecmp is moved CYLON_TICKS
	# past mtime, as a 64-bit sum.  mtime is read high, low, high, and
	# again if the high word changed, because the low word can wrap between
	# two loads.  The low word of mtimecmp is set to all ones before the
	# high word changes, so that it can never match early in between.
cylon_tick:
	bne	a1, zero, 2f
	slli	a0, a0, 1		# moving left
	li	t6, 0x8000
	bne	a0, t6, 3f
	addi	a1, zero, 1		# at the end: turn around
	jal	zero, 3f
2:	srli	a0, a0, 1		# moving right
	addi	t6, zero, 1
	bne	a0, t6, 3f
	addi	a1, zero, 0
3:	li	t6, GPIO
	sw	a0, 0(t6)
	addi	s9, s9, 1
	addi	t6, zero, PASS_STEPS
	bltu	s9, t6, cylon_arm
	addi	tp, zero, 1		# x4 = 1, and keep sweeping
cylon_arm:
	li	t5, TIMER
4:	lw	t4, 4(t5)		# mtime high
	lw	t6, 0(t5)		# mtime low
	lw	t3, 4(t5)		# mtime high again
	bne	t3, t4, 4b
	li	t3, CYLON_TICKS
	add	t3, t6, t3		# new low word
	sltu	t6, t3, t6		# carry into the high word
	add	t4, t4, t6
	addi	t6, zero, -1
	sw	t6, 8(t5)		# mtimecmp low = all ones
	sw	t4, 12(t5)		# mtimecmp high
	sw	t3, 8(t5)		# mtimecmp low
	mret

unexpected:
	csrr	t6, mcause
	addi	gp, zero, 99
	jal	zero, fail

	#=======================================================================
init:
	addi	gp, zero, 0
	addi	tp, zero, 0
	addi	s3, zero, 0
	addi	s4, zero, 0
	addi	s8, zero, 0
	la	t0, trap_table
	csrw	mtvec, t0

	#--- reading and writing CSRs ------------------------------------------
	addi	gp, zero, 1		# 1: misa says RV32I, machine mode
	csrr	t0, misa
	li	t1, 0x40000100
	bne	t0, t1, fail

	addi	gp, zero, 2		# 2: mtvec holds the table, MODE = 1
	csrr	t0, mtvec
	la	t1, trap_table
	ori	t1, t1, 1
	bne	t0, t1, fail

	addi	gp, zero, 3		# 3: mtvec bits 6..0 are fixed at 0000001
	li	t0, 0x1234567f
	csrrw	t2, mtvec, t0		# t2 = the old value, for check 4
	csrr	t1, mtvec
	csrw	mtvec, t2		# put the table back before anything traps
	li	t0, 0x12345601
	bne	t1, t0, fail

	addi	gp, zero, 4		# 4: csrrw returned the old value
	la	t1, trap_table
	ori	t1, t1, 1
	bne	t2, t1, fail

	addi	gp, zero, 5		# 5: csrw then csrr, mscratch
	li	t0, 0xdeadbeef
	csrw	mscratch, t0
	csrr	t1, mscratch
	bne	t0, t1, fail

	addi	gp, zero, 6		# 6: csrrs returns the old value
	li	t0, 0x0000ff00
	csrrs	t1, mscratch, t0
	li	t2, 0xdeadbeef
	bne	t1, t2, fail

	addi	gp, zero, 7		# 7: and sets the bits
	csrr	t1, mscratch
	li	t2, 0xdeadffef
	bne	t1, t2, fail

	addi	gp, zero, 8		# 8: csrrc returns the old value
	li	t0, 0xffff0000
	csrrc	t1, mscratch, t0
	li	t2, 0xdeadffef
	bne	t1, t2, fail

	addi	gp, zero, 9		# 9: and clears the bits
	csrr	t1, mscratch
	li	t2, 0x0000ffef
	bne	t1, t2, fail

	addi	gp, zero, 10		# 10: csrrwi
	csrrwi	t1, mscratch, 21
	csrr	t1, mscratch
	li	t2, 21
	bne	t1, t2, fail

	addi	gp, zero, 11		# 11: csrrsi
	csrrsi	t1, mscratch, 10
	csrr	t1, mscratch
	li	t2, 31
	bne	t1, t2, fail

	addi	gp, zero, 12		# 12: csrrci
	csrrci	t1, mscratch, 5
	csrr	t1, mscratch
	li	t2, 26
	bne	t1, t2, fail

	addi	gp, zero, 13		# 13: csrrw with rd = rs1 swaps the two
	li	t0, 0x13579bdf
	csrrw	t0, mscratch, t0
	li	t2, 26
	bne	t0, t2, fail
	csrr	t1, mscratch
	li	t2, 0x13579bdf
	bne	t1, t2, fail

	addi	gp, zero, 14		# 14: mcycle counts
	csrr	t0, mcycle
	nop
	csrr	t1, mcycle
	bgeu	t0, t1, fail

	# minstret is the count of instructions retired before the one reading
	# it.  Between the two reads below are the first read and three nops.
	# A csrr that writes the CSR back (it must not: rs1 is x0) would
	# replace the count with the value it read and lose its own increment.
	addi	gp, zero, 15		# 15: minstret counts exactly
	csrr	t0, minstret
	nop
	nop
	nop
	csrr	t1, minstret
	sub	t1, t1, t0
	li	t2, 4
	bne	t1, t2, fail

	addi	gp, zero, 16		# 16: mcycleh, early on, is zero
	csrr	t0, mcycleh
	bne	t0, zero, fail

	addi	gp, zero, 17		# 17: a CSR that does not exist reads zero
	csrr	t0, 0x7c0
	bne	t0, zero, fail

	#--- exceptions --------------------------------------------------------
	# mie is still zero, so MIE can be set safely: nothing can interrupt.
	# It is set so that checks 21 and 22 can watch it saved and restored.
	li	t0, 8
	csrs	mstatus, t0

	addi	gp, zero, 18		# 18: ecall reaches the handler once
ecall_at:
	ecall
	li	t0, 1
	bne	s3, t0, fail

	addi	gp, zero, 19		# 19: mcause = 11
	li	t0, 11
	bne	s0, t0, fail

	addi	gp, zero, 20		# 20: mepc = the ecall
	la	t0, ecall_at
	bne	s1, t0, fail

	addi	gp, zero, 21		# 21: in the handler, MIE = 0 and MPIE = 1
	andi	t0, s2, 0x88
	li	t1, 0x80
	bne	t0, t1, fail

	addi	gp, zero, 22		# 22: after mret, MIE = 1 and MPIE = 1
	csrr	t0, mstatus
	andi	t0, t0, 0x88
	li	t1, 0x88
	bne	t0, t1, fail

	li	t0, 8
	csrc	mstatus, t0

	addi	gp, zero, 23		# 23: ebreak, mcause = 3
ebreak_at:
	ebreak
	li	t0, 3
	bne	s0, t0, fail

	addi	gp, zero, 24		# 24: mepc = the ebreak, two traps so far
	la	t0, ebreak_at
	bne	s1, t0, fail
	li	t0, 2
	bne	s3, t0, fail

	addi	gp, zero, 25		# 25: the all-zeros word is illegal, mcause = 2
ill0_at:
	.word	0x00000000
	li	t0, 2
	bne	s0, t0, fail

	addi	gp, zero, 26		# 26: mepc = the illegal word
	la	t0, ill0_at
	bne	s1, t0, fail

	# SYSTEM with funct3 = 100 is not a CSR instruction.  This one names
	# t1 as rd, so a core that half-decodes it as a CSR read writes t1.
	addi	gp, zero, 27		# 27: SYSTEM funct3 = 100 is illegal
	li	t1, 0x55
ill4_at:
	.word	0x00004373		# funct3 = 100, rd = t1, csr = 0
	li	t0, 2
	bne	s0, t0, fail
	la	t0, ill4_at
	bne	s1, t0, fail

	addi	gp, zero, 28		# 28: and it did not write rd
	li	t0, 0x55
	bne	t1, t0, fail

	addi	gp, zero, 29		# 29: so far, exactly four traps
	li	t0, 4
	bne	s3, t0, fail

	addi	gp, zero, 30		# 30: wfi and fence are no-ops, not traps
	wfi
	fence
	li	t0, 4
	bne	s3, t0, fail

	# mret on its own: PC <= mepc, MIE <= MPIE, MPIE <= 1.
	addi	gp, zero, 31		# 31: mret goes to mepc and sets MIE
	la	t0, mret_target
	csrw	mepc, t0
	li	t0, 0x80
	csrs	mstatus, t0		# MPIE = 1
	li	t0, 0x08
	csrc	mstatus, t0		# MIE = 0
	mret
	jal	zero, fail		# mret fell through
mret_target:
	csrr	t0, mstatus
	andi	t0, t0, 0x88
	li	t1, 0x88
	bne	t0, t1, fail
	li	t0, 8
	csrc	mstatus, t0

	#--- the machine timer -------------------------------------------------
	li	s7, TIMER

	addi	gp, zero, 32		# 32: mtimecmp resets to all ones
	lw	t0, 12(s7)
	li	t1, -1
	bne	t0, t1, fail
	lw	t0, 8(s7)
	bne	t0, t1, fail

	addi	gp, zero, 33		# 33: mtime counts
	lw	t0, 0(s7)
	lw	t1, 0(s7)
	bgeu	t0, t1, fail

	addi	gp, zero, 34		# 34: nothing pending yet
	csrr	t0, mip
	andi	t0, t0, 0x80
	bne	t0, zero, fail

	# mtimecmp = 0 makes the timer pending at once.  MTIE is set, but MIE
	# is not, so it must show in mip and not be taken.
	addi	gp, zero, 35		# 35: pending shows in mip.MTIP
	sw	zero, 8(s7)
	sw	zero, 12(s7)
	li	t0, 0x80
	csrs	mie, t0
	nop
	nop
	csrr	t0, mip
	andi	t0, t0, 0x80
	beq	t0, zero, fail

	addi	gp, zero, 36		# 36: but is not taken while MIE = 0
	bne	s4, zero, fail

	addi	gp, zero, 37		# 37: moving mtimecmp away clears it
	li	t0, -1
	sw	t0, 12(s7)
	nop
	nop
	csrr	t0, mip
	andi	t0, t0, 0x80
	bne	t0, zero, fail

	# Arm the timer INTERVAL clocks from now, turn on MIE, and wait for
	# three interrupts.  The low word goes in first: the high word is all
	# ones until the second store, so nothing can go pending in between.
	lw	t0, 0(s7)
	li	t1, INTERVAL
	add	t0, t0, t1
	sw	t0, 8(s7)
	sw	zero, 12(s7)

	addi	gp, zero, 38		# 38: three timer interrupts arrive
	li	t2, 500			# give up after this many trips (about 60 needed)
	li	t0, 8
	csrs	mstatus, t0		# interrupts on
wait_top:
	wfi
	addi	t2, t2, -1
	beq	t2, zero, fail
	li	t0, 3
	blt	s4, t0, wait_top
wait_end:
	li	t0, 8
	csrc	mstatus, t0		# interrupts off
	li	t0, 0x80
	csrc	mie, t0

	addi	gp, zero, 39		# 39: mcause = 80000007
	li	t0, 0x80000007
	bne	s5, t0, fail

	addi	gp, zero, 40		# 40: mepc is inside the wait loop
	la	t0, wait_top
	bltu	s6, t0, fail
	la	t0, wait_end
	bgeu	s6, t0, fail

	addi	gp, zero, 41		# 41: and no exceptions along the way
	li	t0, 4
	bne	s3, t0, fail

	addi	gp, zero, 0
#ifdef BOARD
	#--- every check passed: the eye ---------------------------------------
	addi	a0, zero, 1
	addi	a1, zero, 0
	addi	s9, zero, 0
	li	t0, GPIO
	sw	a0, 0(t0)
	addi	s8, zero, 1		# the timer handler steps the eye now
	jal	zero, cylon_arm_first
cylon_armed:
	li	t0, 0x80
	csrs	mie, t0
	li	t0, 8
	csrs	mstatus, t0
cylon_idle:
	wfi
	jal	zero, cylon_idle

	# The first mtimecmp, set up the way the handler does it.  This runs
	# with interrupts off, so borrowing the handler's code would mean an
	# mret with nothing to return to.  It is repeated instead.
cylon_arm_first:
	li	t5, TIMER
5:	lw	t4, 4(t5)
	lw	t6, 0(t5)
	lw	t3, 4(t5)
	bne	t3, t4, 5b
	li	t3, CYLON_TICKS
	add	t3, t6, t3
	sltu	t6, t3, t6
	add	t4, t4, t6
	addi	t6, zero, -1
	sw	t6, 8(t5)
	sw	t4, 12(t5)
	sw	t3, 8(t5)
	jal	zero, cylon_armed
#else
	addi	tp, zero, 1
park:	jal	zero, park
#endif

fail:
#ifdef BOARD
	li	t0, GPIO
	li	t1, 0xc000
	or	t1, t1, gp
	sw	t1, 0(t0)
#endif
failed:	jal	zero, failed
