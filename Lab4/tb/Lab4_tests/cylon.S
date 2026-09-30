#-------------------------------------------------------------------------------
# CENG 442 Lab 4                                                         cylon.S
#
# The Cylon eye, with no memory access at all.  A core with no load/store
# unit cannot reach a peripheral, so this program never tries.  The LED
# pattern lives in a0 (x10), and the board shows it through the debug port:
# the five low slide switches drive DBGsel, and the low 16 bits of DBGreg
# drive the LEDs.  Set the switches to 01010 and a0 sweeps across the LEDs.
# Any other setting shows that register instead, live, while the program runs.
#
# Every instruction here is one that t1_regs, t2_branch or t3_jump has already
# checked.  Pass those three first.
#
# DELAY sets how long each LED stays lit, in trips around the two instruction
# loop in delay.  The Makefile builds two versions: cylon, with the default
# below, for the board, and cylon_sim, with DELAY=4, so that a simulation
# sees the whole sweep in a few thousand cycles instead of about seventy
# million.
#
# The default was set on the Lab 4 solution: 30 clock cycles per instruction
# through the SmartConnect and the BRAM controller, at 50 MHz, is 1.2 us per
# trip round the loop, so 80000 trips hold each LED for about 96 ms and a
# sweep out and back takes about three seconds.  A core with a different
# cycle count sweeps faster or slower.  Change DELAY to taste.
#-------------------------------------------------------------------------------

#ifndef DELAY
#define DELAY 80000
#endif

	.text
	.globl _start
_start:
	addi	a0, zero, 1		# a0 = the pattern, rightmost LED lit
	lui	s1, 8			# s1 = 00008000, the leftmost LED
	addi	s2, zero, 1		# s2 = 00000001, the rightmost LED
	li	s3, DELAY		# s3 = trips around the delay loop

left:	jal	ra, delay
	slli	a0, a0, 1
	bne	a0, s1, left

right:	jal	ra, delay
	srli	a0, a0, 1
	bne	a0, s2, right
	jal	zero, left

# Count s3 down to zero in t0, then return.
delay:	addi	t0, s3, 0
1:	addi	t0, t0, -1
	bne	t0, zero, 1b
	jalr	zero, ra, 0
