# sw/riscv-tests

Runs the official RISC-V ISA tests ([riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests),
environment `env/p`: physical memory, machine mode) on `tb/unit_tests/tb_cpu_wrapper.sv`.

```
make riscv-tests                         # rv32ui rv32um rv32mi local
make riscv-tests SUITES=rv32um WAIT=0    # one suite, no memory wait states
```

The first run clones riscv-tests into `sim/work/riscv-tests/src` (needs network). Every test is built with
`riscv64-unknown-elf-gcc -march=rv32im_zicsr_zifencei -mabi=ilp32`, linked at address 0 with `link.ld`,
turned into a `$readmemh` file and run. A test passes when it writes 1 to its `tohost` word.
Per-test files (`.elf .dump .hex .log`) are in `sim/work/riscv-tests/<suite>/`.

| File | Content |
|---|---|
| `link.ld` | Linker script of env/p moved from 0x8000_0000 to 0x0000_0000 |
| `expected_fail.txt` | Tests that fail by design (feature not in the spec), reported as XFAIL |
| `local/*.S` | Own directed tests with the same macros. A `# PLUSARGS:` line passes testbench options |

`local/irq_fault.S` covers what the official suites do not: timer and external interrupts (mip, priority MEI over MTI,
MIE/MPIE stack) and bus-error access faults on fetch, load and store.
`local/zicntr_ro.S` checks the Zicntr user counters: cycle/instret (and the high halves) read mcycle/minstret,
writes trap as illegal instruction, time/timeh are not implemented.
