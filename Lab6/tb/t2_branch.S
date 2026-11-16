#-------------------------------------------------------------------------------
# CENG 442 Lab 4                                                     t2_branch.S
#
# Branches, on top of what t1_regs.S covered.  Every one of the six conditions
# is tested twice, once where it must be taken and once where it must not, and
# a branch that goes the wrong way lands on a failure.
#
# From here on the checking is done with branches, which makes it precise.
# Watch x4 and x3:
#
#     x4 = 1              every check passed
#     x4 = 0, x3 = n      check n failed, and the core is parked at "fail"
#     x4 = 0, x3 = 0      the core never started, or never got past the top
#
# The check numbers are in the comments beside each check.  Note the shape of
# a not-taken test: the branch is followed by a jump over the failure, so a
# branch that is wrongly taken skips the jump and lands on it.
#-------------------------------------------------------------------------------

	.text
	.globl _start
_start:
	addi	gp, zero, 0
	addi	tp, zero, 0

	addi	t0, zero, 1		# t0 =  1
	addi	t1, zero, 2		# t1 =  2
	addi	t2, zero, -1		# t2 = -1  (and 0xffffffff unsigned)

	#--- beq ------------------------------------------------------------
	addi	gp, zero, 1		# 1: beq taken when equal
	beq	t0, t0, 1f
	jal	zero, fail
1:
	addi	gp, zero, 2		# 2: beq not taken when unequal
	beq	t0, t1, fail

	#--- bne ------------------------------------------------------------
	addi	gp, zero, 3		# 3: bne taken when unequal
	bne	t0, t1, 1f
	jal	zero, fail
1:
	addi	gp, zero, 4		# 4: bne not taken when equal
	bne	t0, t0, fail

	#--- blt, signed ----------------------------------------------------
	addi	gp, zero, 5		# 5: blt taken, -1 < 1 signed
	blt	t2, t0, 1f
	jal	zero, fail
1:
	addi	gp, zero, 6		# 6: blt not taken, 1 < -1 is false
	blt	t0, t2, fail

	addi	gp, zero, 7		# 7: blt not taken when equal
	blt	t0, t0, fail

	#--- bge, signed ----------------------------------------------------
	addi	gp, zero, 8		# 8: bge taken, 1 >= -1 signed
	bge	t0, t2, 1f
	jal	zero, fail
1:
	addi	gp, zero, 9		# 9: bge taken when equal
	bge	t0, t0, 1f
	jal	zero, fail
1:
	addi	gp, zero, 10		# 10: bge not taken, -1 >= 1 is false
	bge	t2, t0, fail

	#--- bltu, unsigned -------------------------------------------------
	addi	gp, zero, 11		# 11: bltu taken, 1 < ffffffff unsigned
	bltu	t0, t2, 1f
	jal	zero, fail
1:
	addi	gp, zero, 12		# 12: bltu not taken the other way round
	bltu	t2, t0, fail

	#--- bgeu, unsigned -------------------------------------------------
	addi	gp, zero, 13		# 13: bgeu taken, ffffffff >= 1 unsigned
	bgeu	t2, t0, 1f
	jal	zero, fail
1:
	addi	gp, zero, 14		# 14: bgeu taken when equal
	bgeu	t0, t0, 1f
	jal	zero, fail
1:
	addi	gp, zero, 15		# 15: bgeu not taken, 1 >= ffffffff is false
	bgeu	t0, t2, fail

	#--- a backward branch, and a loop that has to terminate -------------
	addi	gp, zero, 16		# 16: ten times round a countdown loop
	addi	a0, zero, 10
	addi	a1, zero, 0
2:
	addi	a1, a1, 1
	addi	a0, a0, -1
	bne	a0, zero, 2b
	addi	a2, zero, 10
	bne	a1, a2, fail

	#--- a branch must not write a register ------------------------------
	addi	gp, zero, 17		# 17: t0 still 1 after all of the above
	addi	a3, zero, 1
	bne	t0, a3, fail

	addi	gp, zero, 0
	addi	tp, zero, 1
park:	jal	zero, park

fail:	jal	zero, fail
