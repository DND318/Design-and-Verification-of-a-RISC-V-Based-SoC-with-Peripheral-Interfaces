#!/usr/bin/env bash
# Build the official riscv-tests (env/p, physical memory, M-mode) for address 0
# and run every test with Verilator on
#   TB=cpu_wrapper (default): core alone, behavioural memory with random wait states
#   TB=cpu_axi              : core + AXI4-Lite master + interconnect + 16 KB SRAM + APB bridge
# Usage (from the repo root):  bash scripts/run_riscv_tests.sh [suite ...]
#   suites: rv32ui rv32um rv32mi local (default: all four)
#   local = directed tests in sw/riscv-tests/local (interrupts, access faults)
#   env: TB=cpu_wrapper|cpu_axi  WAIT=<max wait states, default 3>  SEED=<n, default 1>
#   With TB=cpu_axi the "local" suite is skipped (it needs the tb_cpu_wrapper test device);
#   suite "bus" (sw/riscv-tests/bus: APB access, DECERR/SLVERR faults) runs only with TB=cpu_axi.
# Needs: git (first run only), riscv64-unknown-elf-gcc, verilator.
# Output: sim/work/riscv-tests/<suite>/<test>.{elf,hex,dump}, logs in sim/work/riscv-tests/<TB>/, summary on stdout.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/sim/work/riscv-tests"
SRC="$WORK/src"
SUITES="${*:-rv32ui rv32um rv32mi local}"
XFAIL_LIST="$ROOT/sw/riscv-tests/expected_fail.txt"
WAIT="${WAIT:-3}"
SEED="${SEED:-1}"
TB="${TB:-cpu_wrapper}"
LOGDIR="$WORK/$TB"
CC="riscv64-unknown-elf-gcc"
CFLAGS="-march=rv32im_zicsr_zifencei -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles"

mkdir -p "$WORK"
if [ ! -d "$SRC/isa" ]; then
  git clone --depth 1 https://github.com/riscv-software-src/riscv-tests.git "$SRC" || exit 1
  (cd "$SRC" && git submodule update --init --depth 1 env) || exit 1
fi

# Build the testbench once (the bus TB has 16 KB of SRAM: images must fit)
BIN="$WORK/obj_$TB/sim_$TB"
mkdir -p "$LOGDIR"
sed "s#^#$ROOT/#" "$ROOT/sim/tb_$TB.f" > "$WORK/tb_$TB.abs.f"
verilator --binary -Wall -Wno-DECLFILENAME --timing --assert \
  -Wno-fatal -Wno-SYNCASYNCNET -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -f "$WORK/tb_$TB.abs.f" --top-module "tb_$TB" -Mdir "$WORK/obj_$TB" -o "sim_$TB" \
  > "$LOGDIR/verilator_build.log" 2>&1 || { tail -30 "$LOGDIR/verilator_build.log"; exit 1; }

pass=0; fail=0; xfail=0; failed=""
for suite in $SUITES; do
  if [ "$suite" = local ] && [ "$TB" != cpu_wrapper ]; then echo "SKIP  local suite (needs TB=cpu_wrapper)"; continue; fi
  if [ "$suite" = bus ] && [ "$TB" != cpu_axi ]; then echo "SKIP  bus suite (needs TB=cpu_axi)"; continue; fi
  mkdir -p "$WORK/$suite"
  case "$suite" in
    local|bus) dir="$ROOT/sw/riscv-tests/$suite" ;;
    *)         dir="$SRC/isa/$suite" ;;
  esac
  for src in "$dir"/*.S; do
    t="$(basename "$src" .S)"
    plusargs="$(sed -n 's/^# PLUSARGS: //p' "$src")"
    out="$WORK/$suite/$t"
    if ! $CC $CFLAGS -I"$SRC/env/p" -I"$SRC/isa/macros/scalar" \
         -I"$SRC/isa/rv64ui" \
         -T "$ROOT/sw/riscv-tests/link.ld" "$src" -o "$out.elf" 2> "$out.build.log"; then
      echo "SKIP  $suite-$t (does not build for rv32im, see $out.build.log)"
      continue
    fi
    riscv64-unknown-elf-objdump -d "$out.elf" > "$out.dump"
    riscv64-unknown-elf-objcopy -O binary "$out.elf" "$out.bin"
    od -An -v -tx4 -w4 "$out.bin" | tr -d ' ' > "$out.hex"
    tohost="$(riscv64-unknown-elf-nm "$out.elf" | awk '$3=="tohost"{print $1}')"
    "$BIN" +verilator+seed+"$SEED" +HEX="$out.hex" +TOHOST="$tohost" +WAIT="$WAIT" $plusargs > "$LOGDIR/$suite-$t.log" 2>&1
    log="$LOGDIR/$suite-$t.log"
    if grep -q "TEST PASSED" "$log" && ! grep -qE "ERROR|TEST FAILED" "$log"; then
      pass=$((pass+1)); echo "PASS  $suite-$t"
    elif grep -q "^$suite-$t " "$XFAIL_LIST"; then
      xfail=$((xfail+1)); echo "XFAIL $suite-$t ($(grep "^$suite-$t " "$XFAIL_LIST" | sed 's/^[^ ]* *//'))"
    else
      fail=$((fail+1)); failed="$failed $suite-$t"; echo "FAIL  $suite-$t (see $log)"
    fi
  done
done
echo "riscv-tests: $pass passed, $fail failed, $xfail expected failures"
[ -n "$failed" ] && echo "failed:$failed"
[ $fail -eq 0 ]
