# See sw/riscv-tests/README.md. Directed test for the Zicntr user counters
# (doc/spec, CSR section): cycle/cycleh/instret/instreth read the same
# counters as mcycle/mcycleh/minstret/minstreth, are read-only (a write
# raises an illegal instruction exception, mcause = 2), and time/timeh are
# not implemented (access raises an illegal instruction exception).
# The official rv32mi-zicntr test only checks that reads do not trap.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li s0, 0                        # number of traps handled
  li s1, 0                        # mcause of the last trap

  # 2: cycle counts up
  li TESTNUM, 2
  csrr a0, cycle
  nop
  nop
  csrr a1, cycle
  bgeu a0, a1, fail

  # 3: cycle reads mcycle (set mcycle, read cycle a few clocks later)
  li TESTNUM, 3
  li t0, 0x100000
  csrw mcycle, t0
  csrr a0, cycle
  sub a0, a0, t0
  li t1, 64
  bgeu a0, t1, fail

  # 4: cycleh reads mcycleh
  li TESTNUM, 4
  li t0, 0x55
  csrw mcycleh, t0
  csrr a0, cycleh
  bne a0, t0, fail

  # 5: instret reads minstret (csrr, 3 x nop, csrr -> 4)
  li TESTNUM, 5
  csrr t1, instret
  nop
  nop
  nop
  csrr t2, instret
  sub t2, t2, t1
  li t1, 4
  bne t2, t1, fail

  # 6: instreth reads minstreth
  li TESTNUM, 6
  li t0, 0x2a
  csrw minstreth, t0
  csrr a0, instreth
  bne a0, t0, fail
  bnez s0, fail                   # no trap so far

  # 7: write to cycle -> illegal instruction, counter unchanged
  li TESTNUM, 7
  li t0, 0x7
  csrw mcycleh, t0
  csrw cycleh, zero
  li t1, 1
  bne s0, t1, fail
  li t1, 2
  bne s1, t1, fail
  csrr a0, mcycleh
  bne a0, t0, fail

  # 8: csrrs to instret with a nonzero source (a write) -> illegal instruction
  li TESTNUM, 8
  li s0, 0
  li t0, 1
  csrrs a0, instret, t0
  li t1, 1
  bne s0, t1, fail
  li t1, 2
  bne s1, t1, fail

  # 9: time is not implemented -> illegal instruction
  li TESTNUM, 9
  li s0, 0
  csrr a0, time
  li t1, 1
  bne s0, t1, fail
  li t1, 2
  bne s1, t1, fail

  TEST_PASSFAIL

# Trap handler: record mcause, skip the trapping instruction
  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr s1, mcause
  addi s0, s0, 1
  csrr t6, mepc
  addi t6, t6, 4
  csrw mepc, t6
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
