#-------------------------------------------------------------------------------
# CENG 442 Lab 4                                                       t3_jump.S
#
# Jumps and PC-relative addressing, on top of t1 and t2.  This is where the
# program counter itself is under test: JAL and JALR have to leave the right
# return address behind, and AUIPC has to see the PC of the instruction it is
# in, not the one after it.
#
#     x4 = 1              every check passed
#     x4 = 0, x3 = n      check n failed
#
# If check 2 or 3 fails, look at what your datapath puts on the D bus for a
# jump.  The link register gets the address of the instruction after the jump,
# which is the PC before the jump took effect, plus four.
#-------------------------------------------------------------------------------

	.text
	.globl _start
_start:
	addi	gp, zero, 0
	addi	tp, zero, 0

	#--- jal jumps forward ----------------------------------------------
	addi	gp, zero, 1		# 1: jal reaches its target
	jal	zero, 1f
	jal	zero, fail
1:

	#--- jal leaves the right return address ----------------------------
	addi	gp, zero, 2		# 2: ra is the address after the jal
here:
	jal	ra, target
	# target returns to the instruction below, and put the address it
	# returned to in a0.  ra must equal that address.
	bne	ra, a0, fail

	#--- jalr returns -----------------------------------------------------
	addi	gp, zero, 3		# 3: the call above actually came back
	addi	a1, zero, 1
	bne	a2, a1, fail		# target sets a2 to 1

	#--- auipc sees its own pc ------------------------------------------
	addi	gp, zero, 4		# 4: auipc plus an offset is a label
	auipc	a3, 0
pc_here:
	# a3 is the address of the auipc, which is four bytes before pc_here
	lui	a4, %hi(pc_here)
	addi	a4, a4, %lo(pc_here)
	addi	a5, a3, 4
	bne	a4, a5, fail

	#--- jalr with an offset --------------------------------------------
	addi	gp, zero, 5		# 5: jalr adds its immediate to the base
	lui	a6, %hi(indirect)
	addi	a6, a6, %lo(indirect)
	addi	a6, a6, -8
	jalr	ra, a6, 8
	addi	a7, zero, 1
	bne	s0, a7, fail		# indirect sets s0 to 1

	#--- jal with x0 as the link register writes nothing -----------------
	addi	gp, zero, 6		# 6: jal zero does not disturb x0
	jal	zero, 1f
1:
	bne	zero, zero, fail

	#--- a jump must not disturb the other registers ---------------------
	addi	gp, zero, 7		# 7: a1 survived the jumps
	addi	s1, zero, 1
	bne	a1, s1, fail

	addi	gp, zero, 0
	addi	tp, zero, 1
park:	jal	zero, park

# A subroutine.  It records where it was called from and returns.
target:
	addi	a0, ra, 0		# a0 = the return address it was given
	addi	a2, zero, 1		# a2 = 1, proof it ran
	jalr	zero, ra, 0

indirect:
	addi	s0, zero, 1		# s0 = 1, proof it ran
	jalr	zero, ra, 0

fail:	jal	zero, fail
