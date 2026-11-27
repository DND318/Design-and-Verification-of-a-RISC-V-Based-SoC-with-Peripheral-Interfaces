# sw/

Minimal firmware used to run programs on the SoC in simulation (decision 16/10/2026: keep sw/ minimal).

| Path | Content |
|---|---|
| `startup/crt0.S` | Set stack pointer, clear .bss, call `main`, then loop |
| `startup/link.ld` | Code and data in the 16 KB SRAM at 0x0000_0000 |
| `tests/` | `hello.c` (UART hello), `periph.c` (self-checking test of every peripheral, run by `make soc PROG=periph`), `de2_demo.c` (DE2-115 board demo, see `FPGA/de2_115/README.md`) |
| `include/soc.h` | Register addresses and bit masks, CSR macros, inline UART helpers |

riscv-tests (rv32ui, rv32um, rv32mi) are built from their own sources, not stored here:
`make riscv-tests` clones them into `sim/work/` and runs them on the CPU (see `riscv-tests/README.md`).
Build: `make -C sw PROG=<name>` compiles `tests/<name>.c` with `startup/crt0.S` and `startup/link.ld`
(`-march=rv32im_zicsr -mabi=ilp32 -O2`), then `scripts/elf2hex.py` writes `build/<name>.hex` (32-bit words)
and `build/<name>.b0..b3.hex` (one file per SRAM byte lane, used by the SoC testbench and by Quartus).
