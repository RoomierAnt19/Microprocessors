#-------------------------------------------------------------------------------
# CENG 442 Lab 5                                                        lstest.S
#
# A load/store test for the board.  t4_load and t5_store check the same
# instructions in simulation and report through x3 and x4, which the board
# cannot show.  This one runs on the block design, from the ROM, and reports
# on the LEDs through the AXI GPIO at 40000000.
#
# What the LEDs say
# -----------------
#   LEDs 7-0 count up   test n is running.  Each test holds its number for
#                       about a tenth of a second, so the count is readable.
#   LED 15 blinking     test n failed, and LEDs 7-0 hold n.  Look n up in the
#                       list below.
#   LED 14 blinking     every test passed.  LEDs 7-0 hold the number of tests.
#   nothing blinking    the core has stopped.  LEDs 7-0 hold the test that
#                       was running, which is usually where to look.
#
# The LEDs are written with SW, which is one of the instructions under test.
# A core whose SW does not work at all leaves every LED off.  Test 1 is that
# store, so a core that gets past it can at least report.
#
# The same results are left in the registers the simulation programs use:
#
#     x4 = 1              every test passed
#     x4 = 0, x3 = n      test n failed
#
# The tests, in order
# -------------------
# Loads come first, from test data in ROM, so they do not depend on stores.
# Stores are then checked with loads that have already passed.
#
#    1      SW to the GPIO (the LEDs show 1)
#    2- 4   LW, three words, at offsets 0, 4 and 12
#    5- 8   LBU, byte lanes 0 to 3
#    9-12   LB, byte lanes 0 to 3, two of them negative
#   13-14   LHU, both halves of a word whose low half has its top bit set
#   15-16   LH, the same two halves
#   17-18   LHU and LH of the other word, the other way round
#   19      a negative offset, on LW and LB
#   20      a load into x0 leaves x0 zero
#   21      a load whose destination is its own base register
#   22      a loaded value used by the very next instruction
#   23      two loads back to back, into different registers
#   24      LB then LBU of the same byte: each keeps its own funct3
#   25-28   SW then LW: AAAAAAAA, 55555555, 00000000, FFFFFFFF in one word
#   29-32   SB into byte lanes 0 to 3 of a cleared word, read back as a word
#   33      SB writes only the low eight bits of its source
#   34-35   SH into both halves of a cleared word
#   36      SH writes only the low sixteen bits of its source
#   37      SB into the middle of three words leaves the outer two alone
#   38      SH into the middle of three words leaves the outer two alone
#   39      SB of 80 read back with LB and LBU: sign extension from RAM
#   40      SH of 8001 read back with LH and LHU
#   41      a store writes no register.  The rd field of an S-type is
#           immediate bits, so SW with offset 8 must not write x8, and SB
#           with offset 9 must not write x9
#   42      two stores to neighbouring words, then both read back
#   43      a word copied from ROM to RAM through a register
#   44      a negative offset on SW
#   45      the last word of RAM
#   46      address march: every word of RAM written with its own address
#           (XOR A5A5A5A5), then all read back.  Catches address bits that
#           are stuck or swapped, which no single store can.
#   47      the same with every bit inverted, so each bit is seen as 0 and 1
#   48      byte march: SB of each byte's own address into 256 bytes, read
#           back as words.  Catches strobes that are wrong at any offset.
#   49      halfword march: SH of each halfword's index into 256 bytes, read
#           back as words
#
# Build options
# -------------
# RAM_BASE and RAM_SIZE must match the block design's address editor.  DELAY
# is the number of trips around the two instruction delay loop per test.  At
# about 30 clock cycles per instruction and 50 MHz, the default holds each
# test for about 0.1 s, and a passing run takes about five seconds.  The
# Makefile builds lstest for the board and lstest_sim, with a delay of 1 and
# a short march, for a simulation of the whole block design.
#-------------------------------------------------------------------------------

#ifndef RAM_BASE
#define RAM_BASE 0x10000000
#endif
#ifndef RAM_SIZE
#define RAM_SIZE 8192
#endif
#ifndef MARCH_WORDS
#define MARCH_WORDS (RAM_SIZE/4)	/* the whole of RAM */
#endif
#ifndef DELAY
#define DELAY 80000
#endif

#define GPIO_BASE 0x40000000
#define NTESTS    49

# Start test n: record it in x3 and show it on the LEDs.
.macro TEST n
	addi	gp, zero, \n
	jal	ra, show
.endm

# Fail unless reg holds value.  Uses t2.
.macro CHECK reg, value
	li	t2, \value
	bne	\reg, t2, fail
.endm

	.text
	.globl _start
_start:
	addi	gp, zero, 0
	addi	tp, zero, 0
	li	s10, GPIO_BASE		# s10 = the GPIO data register
	li	s11, RAM_BASE		# s11 = the base of RAM
	li	s9, DELAY		# s9  = delay loop trips per test
	lui	s0, %hi(testdata)
	addi	s0, s0, %lo(testdata)	# s0  = testdata, in ROM

	#=== the LEDs ========================================================
	TEST 1				# reaching test 2 means SW works

	#=== loads, from ROM =================================================
	# testdata: 80FF7F01 7FFF8000 12345678 FEDCBA98
	TEST 2
	lw	t0, 0(s0)
	CHECK	t0, 0x80ff7f01
	TEST 3
	lw	t0, 4(s0)
	CHECK	t0, 0x7fff8000
	TEST 4
	lw	t0, 12(s0)
	CHECK	t0, 0xfedcba98

	TEST 5
	lbu	t0, 0(s0)
	CHECK	t0, 0x01
	TEST 6
	lbu	t0, 1(s0)
	CHECK	t0, 0x7f
	TEST 7
	lbu	t0, 2(s0)
	CHECK	t0, 0xff
	TEST 8
	lbu	t0, 3(s0)
	CHECK	t0, 0x80

	TEST 9
	lb	t0, 0(s0)
	CHECK	t0, 0x00000001
	TEST 10
	lb	t0, 1(s0)
	CHECK	t0, 0x0000007f
	TEST 11
	lb	t0, 2(s0)
	CHECK	t0, 0xffffffff
	TEST 12
	lb	t0, 3(s0)
	CHECK	t0, 0xffffff80

	TEST 13
	lhu	t0, 4(s0)
	CHECK	t0, 0x00008000
	TEST 14
	lhu	t0, 6(s0)
	CHECK	t0, 0x00007fff
	TEST 15
	lh	t0, 4(s0)
	CHECK	t0, 0xffff8000
	TEST 16
	lh	t0, 6(s0)
	CHECK	t0, 0x00007fff

	TEST 17
	lhu	t0, 2(s0)
	CHECK	t0, 0x000080ff
	TEST 18
	lh	t0, 0(s0)
	CHECK	t0, 0x00007f01
	lh	t0, 2(s0)
	CHECK	t0, 0xffff80ff

	TEST 19
	addi	s1, s0, 8
	lw	t0, -8(s1)
	CHECK	t0, 0x80ff7f01
	lb	t0, -5(s1)
	CHECK	t0, 0xffffff80

	TEST 20
	lw	zero, 0(s0)
	add	t0, zero, zero
	CHECK	t0, 0

	TEST 21
	addi	s1, s0, 0
	lw	s1, 8(s1)
	CHECK	s1, 0x12345678

	TEST 22
	lw	t0, 0(s0)
	addi	t1, t0, 1
	CHECK	t1, 0x80ff7f02

	TEST 23
	lw	t0, 8(s0)
	lw	t1, 12(s0)
	CHECK	t0, 0x12345678
	CHECK	t1, 0xfedcba98

	TEST 24
	lb	t0, 3(s0)
	lbu	t1, 3(s0)
	CHECK	t0, 0xffffff80
	CHECK	t1, 0x00000080

	#=== stores, to RAM ==================================================
	TEST 25
	li	t0, 0xaaaaaaaa
	sw	t0, 0(s11)
	lw	t1, 0(s11)
	CHECK	t1, 0xaaaaaaaa
	TEST 26
	li	t0, 0x55555555
	sw	t0, 0(s11)
	lw	t1, 0(s11)
	CHECK	t1, 0x55555555
	TEST 27
	sw	zero, 0(s11)
	lw	t1, 0(s11)
	CHECK	t1, 0x00000000
	TEST 28
	li	t0, 0xffffffff
	sw	t0, 0(s11)
	lw	t1, 0(s11)
	CHECK	t1, 0xffffffff

	sw	zero, 4(s11)
	TEST 29
	li	t0, 0x11
	sb	t0, 4(s11)
	lw	t1, 4(s11)
	CHECK	t1, 0x00000011
	TEST 30
	li	t0, 0x22
	sb	t0, 5(s11)
	lw	t1, 4(s11)
	CHECK	t1, 0x00002211
	TEST 31
	li	t0, 0x33
	sb	t0, 6(s11)
	lw	t1, 4(s11)
	CHECK	t1, 0x00332211
	TEST 32
	li	t0, 0x44
	sb	t0, 7(s11)
	lw	t1, 4(s11)
	CHECK	t1, 0x44332211

	TEST 33
	sw	zero, 8(s11)
	li	t0, 0xabcdef77
	sb	t0, 8(s11)
	lw	t1, 8(s11)
	CHECK	t1, 0x00000077

	TEST 34
	sw	zero, 12(s11)
	li	t0, 0x5566
	sh	t0, 12(s11)
	lw	t1, 12(s11)
	CHECK	t1, 0x00005566
	TEST 35
	li	t0, 0x7788
	sh	t0, 14(s11)
	lw	t1, 12(s11)
	CHECK	t1, 0x77885566

	TEST 36
	sw	zero, 16(s11)
	li	t0, 0xabcde123
	sh	t0, 16(s11)
	lw	t1, 16(s11)
	CHECK	t1, 0x0000e123

	# three words: guard, middle, guard
	li	t0, 0xa5a5a5a5
	sw	t0, 0x20(s11)
	sw	t0, 0x28(s11)
	li	t0, 0xffffffff
	sw	t0, 0x24(s11)
	TEST 37
	sb	zero, 0x25(s11)
	lw	t1, 0x24(s11)
	CHECK	t1, 0xffff00ff
	lw	t1, 0x20(s11)
	CHECK	t1, 0xa5a5a5a5
	lw	t1, 0x28(s11)
	CHECK	t1, 0xa5a5a5a5
	TEST 38
	li	t0, 0x1234
	sh	t0, 0x26(s11)
	lw	t1, 0x24(s11)
	CHECK	t1, 0x123400ff
	lw	t1, 0x20(s11)
	CHECK	t1, 0xa5a5a5a5
	lw	t1, 0x28(s11)
	CHECK	t1, 0xa5a5a5a5

	TEST 39
	sw	zero, 0x30(s11)
	li	t0, 0x80
	sb	t0, 0x31(s11)
	lb	t1, 0x31(s11)
	CHECK	t1, 0xffffff80
	lbu	t1, 0x31(s11)
	CHECK	t1, 0x00000080
	TEST 40
	sw	zero, 0x34(s11)
	li	t0, 0x8001
	sh	t0, 0x36(s11)
	lh	t1, 0x36(s11)
	CHECK	t1, 0xffff8001
	lhu	t1, 0x36(s11)
	CHECK	t1, 0x00008001

	TEST 41
	addi	s1, zero, 0x99		# s1 is x9
	li	t0, 0x01020304
	sw	t0, 8(s11)		# rd field = 01000 = x8 = s0
	sb	t0, 9(s11)		# rd field = 01001 = x9 = s1
	lui	t1, %hi(testdata)
	addi	t1, t1, %lo(testdata)
	bne	s0, t1, fail
	CHECK	s1, 0x99

	TEST 42
	li	t0, 0x13579bdf
	li	t1, 0x2468ace0
	sw	t0, 0x40(s11)
	sw	t1, 0x44(s11)
	lw	t3, 0x40(s11)
	lw	t4, 0x44(s11)
	CHECK	t3, 0x13579bdf
	CHECK	t4, 0x2468ace0

	TEST 43
	lw	t0, 12(s0)
	sw	t0, 0x48(s11)
	lw	t1, 0x48(s11)
	CHECK	t1, 0xfedcba98

	TEST 44
	addi	s1, s11, 0x50
	li	t0, 0x0badf00d
	sw	t0, -4(s1)
	lw	t1, 0x4c(s11)
	CHECK	t1, 0x0badf00d

	TEST 45
	li	t0, RAM_SIZE-4
	add	s1, s11, t0
	li	t0, 0xc001d00d
	sw	t0, 0(s1)
	lw	t1, 0(s1)
	CHECK	t1, 0xc001d00d

	#=== marches =========================================================
	# s1 walks the words, s2 is the end, s3 the pattern
	li	s3, 0xa5a5a5a5
	li	t0, MARCH_WORDS*4
	add	s2, s11, t0

	TEST 46
	addi	s1, s11, 0
1:	xor	t0, s1, s3
	sw	t0, 0(s1)
	addi	s1, s1, 4
	bne	s1, s2, 1b
	addi	s1, s11, 0
2:	lw	t1, 0(s1)
	xor	t0, s1, s3
	bne	t1, t0, fail
	addi	s1, s1, 4
	bne	s1, s2, 2b

	TEST 47
	xori	s3, s3, -1		# every bit inverted
	addi	s1, s11, 0
1:	xor	t0, s1, s3
	sw	t0, 0(s1)
	addi	s1, s1, 4
	bne	s1, s2, 1b
	addi	s1, s11, 0
2:	lw	t1, 0(s1)
	xor	t0, s1, s3
	bne	t1, t0, fail
	addi	s1, s1, 4
	bne	s1, s2, 2b

	# 256 bytes from 0x100: s1 walks, s2 is the end
	addi	s2, s11, 0x200

	TEST 48
	addi	s1, s11, 0x100
1:	sb	s1, 0(s1)		# each byte gets its own address
	addi	s1, s1, 1
	bne	s1, s2, 1b
	addi	s1, s11, 0x100
	li	t0, 0x03020100		# word k holds 4k+3 4k+2 4k+1 4k
	li	t3, 0x04040404
2:	lw	t1, 0(s1)
	bne	t1, t0, fail
	add	t0, t0, t3
	addi	s1, s1, 4
	bne	s1, s2, 2b

	TEST 49
	addi	s1, s11, 0x100
	addi	t0, zero, 0		# t0 = halfword index
1:	sh	t0, 0(s1)
	addi	t0, t0, 1
	addi	s1, s1, 2
	bne	s1, s2, 1b
	addi	s1, s11, 0x100
	lui	t0, 0x10		# word k holds 2k+1 in the high half, 2k low
	li	t3, 0x00020002
2:	lw	t1, 0(s1)
	bne	t1, t0, fail
	add	t0, t0, t3
	addi	s1, s1, 4
	bne	s1, s2, 2b

	#=== done ============================================================
	addi	gp, zero, 0
	addi	tp, zero, 1
	li	s4, 0x4000 | NTESTS	# LED 14 and the count
	addi	s5, zero, NTESTS	# the count alone
	jal	zero, blink

fail:	li	s4, 0x8000		# LED 15 and the failing test
	or	s4, s4, gp
	addi	s5, gp, 0		# the failing test alone

# Alternate s4 and s5 on the LEDs forever, four tests' worth of delay each.
blink:	slli	a1, s9, 2
	sw	s4, 0(s10)
	jal	ra, wait
	slli	a1, s9, 2
	sw	s5, 0(s10)
	jal	ra, wait
	jal	zero, blink

# Show the test number in x3 on the LEDs, then fall into wait for one
# test's worth of delay.
show:	sw	gp, 0(s10)
	addi	a1, s9, 0

# Count a1 down to zero, then return.
wait:	addi	a1, a1, -1
	bne	a1, zero, wait
	jalr	zero, ra, 0

	.section .rodata
	.balign 4
testdata:
	.word	0x80ff7f01		# bytes 01 7F FF 80
	.word	0x7fff8000		# halves 8000 7FFF
	.word	0x12345678
	.word	0xfedcba98
