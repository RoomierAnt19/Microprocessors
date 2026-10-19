#-------------------------------------------------------------------------------
# CENG 442 Lab 5                                                       t4_load.S
#
# Loads, on top of t1 to t3.  This is the first program that uses the
# load/store unit, so it is the first that can fail because of something
# the Lab 4 core did not have.  If it fails and load_store_unit_testbench
# passed, look at the sequencer: the usual fault is writing the destination
# register before the load/store unit has raised ready, or writing it twice.
#
#     x4 = 1              every check passed
#     x4 = 0, x3 = n      check n failed
#
# Everything is loaded out of .rodata, which the linker puts in ROM, so no
# startup code has to run first and the fetch unit and the load/store unit are
# both reading from the same memory.  The test values are chosen so that every
# byte and every halfword is different and the top bit is set in some of them
# and clear in others, which is what makes a sign extension bug visible.
#-------------------------------------------------------------------------------

	.text
	.globl _start
_start:
	addi	gp, zero, 0
	addi	tp, zero, 0

	lui	s0, %hi(testdata)
	addi	s0, s0, %lo(testdata)	# s0 = address of testdata

	#--- lw --------------------------------------------------------------
	addi	gp, zero, 1		# 1: lw of the first word
	lw	t0, 0(s0)
	lui	t1, 0x89abd		# 0x89abcdef = lui 0x89abd + (-0x211)
	addi	t1, t1, -529
	bne	t0, t1, fail

	addi	gp, zero, 2		# 2: lw of the second word, nonzero offset
	lw	t0, 4(s0)
	li	t1, 0x01234567
	bne	t0, t1, fail

	#--- lbu, all four byte lanes ---------------------------------------
	addi	gp, zero, 3		# 3: lbu lane 0
	lbu	t0, 0(s0)
	li	t1, 0xef
	bne	t0, t1, fail

	addi	gp, zero, 4		# 4: lbu lane 1
	lbu	t0, 1(s0)
	li	t1, 0xcd
	bne	t0, t1, fail

	addi	gp, zero, 5		# 5: lbu lane 2
	lbu	t0, 2(s0)
	li	t1, 0xab
	bne	t0, t1, fail

	addi	gp, zero, 6		# 6: lbu lane 3
	lbu	t0, 3(s0)
	li	t1, 0x89
	bne	t0, t1, fail

	#--- lb, sign extension ---------------------------------------------
	addi	gp, zero, 7		# 7: lb of ef, top bit set
	lb	t0, 0(s0)
	li	t1, 0xffffffef
	bne	t0, t1, fail

	addi	gp, zero, 8		# 8: lb of 67, top bit clear
	lb	t0, 4(s0)
	li	t1, 0x67
	bne	t0, t1, fail

	#--- lhu, both halves -----------------------------------------------
	addi	gp, zero, 9		# 9: lhu low half
	lhu	t0, 0(s0)
	li	t1, 0x0000cdef
	bne	t0, t1, fail

	addi	gp, zero, 10		# 10: lhu high half
	lhu	t0, 2(s0)
	li	t1, 0x000089ab
	bne	t0, t1, fail

	#--- lh, sign extension ---------------------------------------------
	addi	gp, zero, 11		# 11: lh of cdef, top bit set
	lh	t0, 0(s0)
	li	t1, 0xffffcdef
	bne	t0, t1, fail

	addi	gp, zero, 12		# 12: lh of 4567, top bit clear
	lh	t0, 4(s0)
	li	t1, 0x00004567
	bne	t0, t1, fail

	#--- a load must not disturb anything else --------------------------
	addi	gp, zero, 13		# 13: s0 survived every load
	lui	t1, %hi(testdata)
	addi	t1, t1, %lo(testdata)
	bne	s0, t1, fail

	#--- a negative offset ----------------------------------------------
	addi	gp, zero, 14		# 14: lw with a negative offset
	addi	s1, s0, 8
	lw	t0, -8(s1)
	li	t1, 0x89abcdef
	bne	t0, t1, fail

	addi	gp, zero, 0
	addi	tp, zero, 1
park:	jal	zero, park

fail:	jal	zero, fail

	.section .rodata
	.align	2
testdata:
	.word	0x89abcdef		# every byte different, top bits set
	.word	0x01234567		# every byte different, top bits clear
	.word	0xdeadbeef		# a guard word, not read by the tests
