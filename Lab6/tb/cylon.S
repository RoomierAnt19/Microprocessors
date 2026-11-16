#-------------------------------------------------------------------------------
# CENG 442 Lab 5                                                         cylon.S
#
# The Cylon eye again, this time on a peripheral.  The Lab 4 version could
# only show its pattern through the debug port, because a core with no
# load/store unit cannot reach anything on the bus.  This one stores the
# pattern to an AXI GPIO, whose outputs drive the LEDs, so the eye sweeps
# whatever the slide switches say.
#
# The GPIO is at 40000000, 16 bits wide, all outputs.  Its data register is
# at offset 0, and with every bit an output there is no direction register
# to set up.  The pattern still lives in a0 (x10), as before, so setting the
# switches to 01010 shows it on the debug port too.
#
# The one new instruction is SW.  Pass t4_load and t5_store first.
#
# DELAY sets how long each LED stays lit, in trips around the two instruction
# loop in delay.  The Makefile builds two versions: cylon, with the default
# below, for the board, and cylon_sim, with DELAY=4, so that a simulation
# sees the whole sweep in a few thousand cycles instead of about seventy
# million.  The default is the Lab 4 one.  The store adds one bus write per
# LED, which is lost in the delay loop.
#-------------------------------------------------------------------------------

#ifndef DELAY
#define DELAY 80000
#endif

	.text
	.globl _start
_start:
	lui	s0, 0x40000		# s0 = 40000000, the GPIO data register
	addi	a0, zero, 1		# a0 = the pattern, rightmost LED lit
	lui	s1, 8			# s1 = 00008000, the leftmost LED
	addi	s2, zero, 1		# s2 = 00000001, the rightmost LED
	li	s3, DELAY		# s3 = trips around the delay loop

left:	sw	a0, 0(s0)		# show the pattern
	jal	ra, delay
	slli	a0, a0, 1
	bne	a0, s1, left

right:	sw	a0, 0(s0)		# show the pattern
	jal	ra, delay
	srli	a0, a0, 1
	bne	a0, s2, right
	jal	zero, left

# Count s3 down to zero in t0, then return.
delay:	addi	t0, s3, 0
1:	addi	t0, t0, -1
	bne	t0, zero, 1b
	jalr	zero, ra, 0
