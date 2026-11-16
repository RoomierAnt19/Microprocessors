#-------------------------------------------------------------------------------
# CENG 442 Lab 5                                                      t5_store.S
#
# Stores, on top of everything before.  Each store is read back with a load
# that t4_load.S already proved, so a failure here is the store side.
#
#     x4 = 1              every check passed
#     x4 = 0, x3 = n      check n failed
#
# The order matters.  Checks 2 to 5 build one word out of four byte stores and
# read it back after each one, so a byte store that writes the wrong lane is
# caught on the store that does it rather than three stores later.  Check 10
# then looks at the word next door, which is where a store with strobes that
# are too wide does its damage.
#
# RAM is not initialised, so nothing is read here that was not written first.
#-------------------------------------------------------------------------------

	.text
	.globl _start
_start:
	addi	gp, zero, 0
	addi	tp, zero, 0

	li	s0, 0x10000000		# s0 = the base of RAM

	#--- sw --------------------------------------------------------------
	addi	gp, zero, 1		# 1: sw then lw
	li	t0, 0xaaaaaaaa
	sw	t0, 0(s0)
	lw	t1, 0(s0)
	bne	t0, t1, fail

	#--- sb into each lane of a fresh word -------------------------------
	# Clear the word first, so that what is read back afterwards is only
	# what the byte stores put there.
	sw	zero, 4(s0)

	addi	gp, zero, 2		# 2: sb lane 0
	li	t0, 0x11
	sb	t0, 4(s0)
	lw	t1, 4(s0)
	li	t2, 0x00000011
	bne	t1, t2, fail

	addi	gp, zero, 3		# 3: sb lane 1
	li	t0, 0x22
	sb	t0, 5(s0)
	lw	t1, 4(s0)
	li	t2, 0x00002211
	bne	t1, t2, fail

	addi	gp, zero, 4		# 4: sb lane 2
	li	t0, 0x33
	sb	t0, 6(s0)
	lw	t1, 4(s0)
	li	t2, 0x00332211
	bne	t1, t2, fail

	addi	gp, zero, 5		# 5: sb lane 3
	li	t0, 0x44
	sb	t0, 7(s0)
	lw	t1, 4(s0)
	li	t2, 0x44332211
	bne	t1, t2, fail

	#--- sb only writes eight bits ---------------------------------------
	addi	gp, zero, 6		# 6: the high bits of the source are ignored
	sw	zero, 8(s0)
	li	t0, 0xabcde077
	sb	t0, 8(s0)
	lw	t1, 8(s0)
	li	t2, 0x00000077
	bne	t1, t2, fail

	#--- sh into both halves ---------------------------------------------
	addi	gp, zero, 7		# 7: sh low half
	sw	zero, 12(s0)
	li	t0, 0x00005566
	sh	t0, 12(s0)
	lw	t1, 12(s0)
	bne	t1, t0, fail

	addi	gp, zero, 8		# 8: sh high half
	li	t0, 0x00007788
	sh	t0, 14(s0)
	lw	t1, 12(s0)
	li	t2, 0x77885566
	bne	t1, t2, fail

	#--- sh only writes sixteen bits -------------------------------------
	addi	gp, zero, 9		# 9: the high half of the source is ignored
	sw	zero, 16(s0)
	li	t0, 0xabcde123
	sh	t0, 16(s0)
	lw	t1, 16(s0)
	li	t2, 0x0000e123
	bne	t1, t2, fail

	#--- the neighbours are untouched ------------------------------------
	addi	gp, zero, 10		# 10: the word written in check 1 survived
	lw	t1, 0(s0)
	li	t2, 0xaaaaaaaa
	bne	t1, t2, fail

	addi	gp, zero, 11		# 11: and so did the one from checks 2 to 5
	lw	t1, 4(s0)
	li	t2, 0x44332211
	bne	t1, t2, fail

	#--- a store writes no register --------------------------------------
	addi	gp, zero, 12		# 12: s0 still points at the base of RAM
	li	t2, 0x10000000
	bne	s0, t2, fail

	#--- somewhere further up RAM ----------------------------------------
	addi	gp, zero, 13		# 13: a store well away from the base
	li	t0, 0x00000ffc		# the last word of the first 4 KB
	add	s1, s0, t0
	li	t2, 0x13578889
	sw	t2, 0(s1)
	lw	t1, 0(s1)
	bne	t1, t2, fail

	addi	gp, zero, 0
	addi	tp, zero, 1
park:	jal	zero, park

fail:	jal	zero, fail
