# See sw/riscv-tests/README.md. Directed test for the bus subsystem
# (TB=cpu_axi only): APB register access with byte strobes through the
# AXI4-Lite to APB bridge, and access faults from DECERR (unmapped address)
# and SLVERR (PSLVERR from APB slot 1, disabled slot 7).
# tb_cpu_axi: APB slot 0 = one RW register, slot 1 = PSLVERR, slots 6..15 disabled.

#include "riscv_test.h"
#include "test_macros.h"

#define APB_REG   0x10000000
#define APB_ERR   0x10001000
#define APB_OFF   0x10007000
#define UNMAPPED  0x00004000
#define UNMAPPED2 0x20000000

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li s0, 0                        # number of traps
  li s1, 0                        # last mcause
  li s3, 0                        # last mtval

  # 2-5: word and byte writes to the APB register
  li t3, APB_REG
  li t1, 0x12345678
  sw t1, 0(t3)
  TEST_CASE( 2, t2, 0x12345678, lw t2, 0(t3) )
  li t1, 0xAB
  sb t1, 2(t3)
  TEST_CASE( 3, t2, 0x12AB5678, lw t2, 0(t3) )
  li t1, 0xCDEF
  sh t1, 0(t3)
  TEST_CASE( 4, t2, 0x12ABCDEF, lw t2, 0(t3) )
  TEST_CASE( 5, t2, 0xFFFFFFAB, lb t2, 2(t3) )
  bnez s0, fail

  # 6: load from an unmapped address -> DECERR -> load access fault (5)
  li TESTNUM, 6
  li t3, UNMAPPED
  li a0, 0x55
  lw a0, 0(t3)
  li t1, 0x55
  bne a0, t1, fail
  li t1, 5
  bne s1, t1, fail
  bne s3, t3, fail

  # 7: store to an unmapped high address -> store access fault (7)
  li TESTNUM, 7
  li t3, UNMAPPED2
  sw a0, 8(t3)
  li t1, 7
  bne s1, t1, fail
  addi t1, t3, 8
  bne s3, t1, fail

  # 8: PSLVERR from APB slot 1 -> load access fault
  li TESTNUM, 8
  li s1, 0
  li t3, APB_ERR
  lw a0, 4(t3)
  li t1, 5
  bne s1, t1, fail

  # 9: disabled APB slot 7 -> SLVERR from the bridge -> store access fault
  li TESTNUM, 9
  li s1, 0
  li t3, APB_OFF
  sw a0, 0(t3)
  li t1, 7
  bne s1, t1, fail

  # 10: jump to an unmapped address -> instruction access fault (1)
  li TESTNUM, 10
  li t3, UNMAPPED
  jalr ra, 0(t3)
  li t1, 1
  bne s1, t1, fail

  # 11: exactly five traps so far, and SRAM still fine after errors
  li TESTNUM, 11
  li t1, 5
  bne s0, t1, fail
  la t3, tdat
  lw t2, 0(t3)
  li t1, 0xCAFEF00D
  bne t2, t1, fail

  TEST_PASSFAIL

  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr s1, mcause
  csrr s3, mtval
  addi s0, s0, 1
  li t6, 1
  bne s1, t6, 1f
  csrw mepc, ra                   # fetch fault: return to the caller
  mret
1:csrr t6, mepc                   # load/store fault: skip the instruction
  addi t6, t6, 4
  csrw mepc, t6
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
tdat: .word 0xCAFEF00D
RVTEST_DATA_END
