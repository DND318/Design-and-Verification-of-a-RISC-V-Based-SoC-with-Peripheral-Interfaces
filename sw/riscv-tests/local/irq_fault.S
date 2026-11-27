# See sw/riscv-tests/README.md. Directed test for features the official
# riscv-tests do not cover on this core: machine timer and external
# interrupts (priority, mip, MIE stack), and bus-error access faults.
# Uses the riscv-tests env/p macros. Testbench test device (tb_cpu_wrapper):
# a store to 0x0002_0000 clears irq_mtip (bit 0) / irq_meip (bit 1);
# addresses >= 64 KB return a bus error.
# PLUSARGS: +IRQ_AT=3000 +EIRQ_AT=3000 +MAXCYC=400000

#include "riscv_test.h"
#include "test_macros.h"

#define IRQ_CLR   0x00020000
#define BAD_ADDR  0x00030000

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li s0, 0                        # number of traps handled
  li s1, 0                        # mcause of trap 1
  li s2, 0                        # mcause of trap 2
  li s3, 0                        # mtval of last trap

  # 2: both lines rise at cycle 3000; with MIE = 0 they show in mip only
  li TESTNUM, 2
  li t0, 0x880
  li t2, 200000
1:addi t2, t2, -1
  beqz t2, fail
  csrr t1, mip
  and t1, t1, t0
  bne t1, t0, 1b
  bnez s0, fail

  # 3: enable both; MEI must be taken before MTI
  li TESTNUM, 3
  csrw mie, t0
  csrsi mstatus, 8
  nop
  nop
  li t1, 2
  bne s0, t1, fail
  li t1, 0x8000000b
  bne s1, t1, fail
  li t1, 0x80000007
  bne s2, t1, fail

  # 4: MRET restored MIE = 1 and set MPIE = 1
  TEST_CASE( 4, t1, 0x88, csrr t1, mstatus; andi t1, t1, 0x88 )
  csrci mstatus, 8
  csrw mie, zero

  # 5: load from an unmapped address -> load access fault (5), mtval = address
  li TESTNUM, 5
  li s0, 0
  li t3, BAD_ADDR
  li a0, 0x1234
  lw a0, 0(t3)
  li t1, 0x1234                   # rd must not be written
  bne a0, t1, fail
  li t1, 5
  bne s1, t1, fail
  bne s3, t3, fail

  # 6: store -> store access fault (7)
  li TESTNUM, 6
  li s0, 0
  sw a0, 4(t3)
  li t1, 7
  bne s1, t1, fail
  addi t1, t3, 4
  bne s3, t1, fail

  # 7: jump to an unmapped address -> instruction access fault (1)
  li TESTNUM, 7
  li s0, 0
  jalr ra, 0(t3)
  li t1, 1
  bne s1, t1, fail
  bne s3, t3, fail

  # 8: minstret counts retired instructions (csrr, 3 x nop, csrr -> 4)
  li TESTNUM, 8
  csrr t1, minstret
  nop
  nop
  nop
  csrr t2, minstret
  sub t2, t2, t1
  li t1, 4
  bne t2, t1, fail

  # 9: misa = RV32IM
  TEST_CASE( 9, t1, 0x40001100, csrr t1, misa )

  TEST_PASSFAIL

# Trap handler, entered through trap_vector for every cause except ECALL
  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr t5, mcause
  csrr t6, mtval
  mv s3, t6
  bnez s0, 2f
  mv s1, t5
  j 3f
2:mv s2, t5
3:addi s0, s0, 1
  bltz t5, irq
  li t6, 1                        # fetch fault: return to the caller
  bne t5, t6, 4f
  csrw mepc, ra
  mret
4:csrr t6, mepc                   # load/store fault: skip the instruction
  addi t6, t6, 4
  csrw mepc, t6
  mret
irq:
  li t6, IRQ_CLR
  andi t5, t5, 0xf
  addi t5, t5, -7
  beqz t5, 5f
  li t5, 2                        # external
  sw t5, 0(t6)
  mret
5:li t5, 1                        # timer
  sw t5, 0(t6)
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
