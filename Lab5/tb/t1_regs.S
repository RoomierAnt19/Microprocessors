#-------------------------------------------------------------------------------
# CENG 442 Lab 4                                                       t1_regs.S
#
# Register-register and register-immediate instructions only.  No branches,
# no jumps, no memory.  Run this one first: if it fails, the fault is in the
# sequencer, the decoder or the datapath, and nothing else can be blamed.
#
# There is exactly one control transfer in this program, the jump at the end
# that parks the core.  Everything before it is straight-line code, so a core
# that fetches sequentially and executes what it fetches will get through it.
#
# Because there are no branches, the checking is arithmetic.  Every result is
# folded into two accumulators, and at the end those are compared against
# constants by subtraction.  Watch x4:
#
#     x4 = 1   every value below was correct
#     x4 = 0   something was wrong, or the core never got to the end
#
# When x4 is 0, a0 and a1 hold the two accumulators and a3 holds the bits
# that differ, and the comment beside each instruction says what that register
# should have held.  Read the register file and find the first one that
# disagrees.
#-------------------------------------------------------------------------------

	.text
	.globl _start
_start:
	# a0 is the running sum, a1 the running exclusive or.  Neither is a
	# destination anywhere below, which matters: an accumulator that is
	# also under test folds itself away.  a1 is shifted before each fold
	# so that it depends on the order the values arrive in: without that,
	# two results that are wrong in opposite directions cancel, and slt
	# behaving like sltu is exactly such a pair.
	addi	a0, zero, 0
	addi	a1, zero, 0

	#--- register-immediate ---------------------------------------------
	addi	t0, zero, 1		# t0  = 00000001
	add	a0, a0, t0
	slli	a1, a1, 1
	xor	a1, a1, t0

	addi	s7, zero, -2048		# s7  = fffff800  (most negative imm)
	add	a0, a0, s7
	slli	a1, a1, 1
	xor	a1, a1, s7

	andi	s8, s7, 2047		# s8  = 00000000
	add	a0, a0, s8
	slli	a1, a1, 1
	xor	a1, a1, s8

	ori	s9, s7, 255		# s9  = fffff8ff
	add	a0, a0, s9
	slli	a1, a1, 1
	xor	a1, a1, s9

	xori	s10, s7, -1		# s10 = 000007ff
	add	a0, a0, s10
	slli	a1, a1, 1
	xor	a1, a1, s10

	slti	a2, s7, 0		# a2  = 00000001  (signed)
	add	a0, a0, a2
	slli	a1, a1, 1
	xor	a1, a1, a2

	sltiu	a3, s7, 0		# a3  = 00000000  (unsigned)
	add	a0, a0, a3
	slli	a1, a1, 1
	xor	a1, a1, a3

	slli	a4, t0, 31		# a4  = 80000000
	add	a0, a0, a4
	slli	a1, a1, 1
	xor	a1, a1, a4

	srli	a5, a4, 28		# a5  = 00000008
	add	a0, a0, a5
	slli	a1, a1, 1
	xor	a1, a1, a5

	srai	a6, a4, 28		# a6  = fffffff8
	add	a0, a0, a6
	slli	a1, a1, 1
	xor	a1, a1, a6

	#--- upper immediate ------------------------------------------------
	lui	a7, 0xabcde		# a7  = abcde000
	add	a0, a0, a7
	slli	a1, a1, 1
	xor	a1, a1, a7

	#--- register-register ----------------------------------------------
	add	t1, t0, t0		# t1  = 00000002
	add	a0, a0, t1
	slli	a1, a1, 1
	xor	a1, a1, t1

	sll	t2, t1, t0		# t2  = 00000004
	add	a0, a0, t2
	slli	a1, a1, 1
	xor	a1, a1, t2

	sub	t3, t2, t0		# t3  = 00000003
	add	a0, a0, t3
	slli	a1, a1, 1
	xor	a1, a1, t3

	sub	t4, zero, t0		# t4  = ffffffff
	add	a0, a0, t4
	slli	a1, a1, 1
	xor	a1, a1, t4

	slt	t5, zero, t4		# t5  = 00000000  (signed)
	add	a0, a0, t5
	slli	a1, a1, 1
	xor	a1, a1, t5

	sltu	t6, zero, t4		# t6  = 00000001  (unsigned)
	add	a0, a0, t6
	slli	a1, a1, 1
	xor	a1, a1, t6

	slt	s5, t0, t1		# s5  = 00000001
	add	a0, a0, s5
	slli	a1, a1, 1
	xor	a1, a1, s5

	sltu	s6, zero, zero		# s6  = 00000000
	add	a0, a0, s6
	slli	a1, a1, 1
	xor	a1, a1, s6

	xor	s0, t4, t3		# s0  = fffffffc
	add	a0, a0, s0
	slli	a1, a1, 1
	xor	a1, a1, s0

	sra	s1, s0, t0		# s1  = fffffffe
	add	a0, a0, s1
	slli	a1, a1, 1
	xor	a1, a1, s1

	srl	s2, s0, t0		# s2  = 7ffffffe
	add	a0, a0, s2
	slli	a1, a1, 1
	xor	a1, a1, s2

	or	s3, t2, t0		# s3  = 00000005
	add	a0, a0, s3
	slli	a1, a1, 1
	xor	a1, a1, s3

	and	s4, s3, t2		# s4  = 00000004
	add	a0, a0, s4
	slli	a1, a1, 1
	xor	a1, a1, s4

	#--- x0 is hard wired to zero ---------------------------------------
	addi	zero, zero, 7		# must have no effect
	add	a0, a0, zero
	slli	a1, a1, 1
	xor	a1, a1, zero

	#--- the verdict ----------------------------------------------------
	# a0 is the sum of every result above, a1 their exclusive or.  The two
	# constants are what those come to when every instruction is right.
	.set	EXPECT_SUM, 0xabcdd90b
	.set	EXPECT_XOR, 0xe6ec1a0c

	li	t0, EXPECT_SUM
	li	t1, EXPECT_XOR
	xor	t2, a0, t0
	xor	t3, a1, t1
	or	a3, t2, t3		# a3 = 0 when both agree
	sltiu	tp, a3, 1		# x4 = 1 when a3 is zero

park:	jal	zero, park
