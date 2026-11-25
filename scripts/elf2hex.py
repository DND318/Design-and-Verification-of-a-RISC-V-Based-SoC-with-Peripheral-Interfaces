#!/usr/bin/env python3
"""Turn a firmware ELF into $readmemh files for the 16 KB SRAM.

Usage: elf2hex.py <prog.elf> <out_prefix> [size_bytes]
Writes <out_prefix>.hex     : one 32-bit word per line (tb_cpu_wrapper)
       <out_prefix>.b0..b3.hex : one byte per line per byte lane (sram_sp)
Needs riscv64-unknown-elf-objcopy in PATH.
"""
import os
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    elf, prefix = sys.argv[1], sys.argv[2]
    size = int(sys.argv[3], 0) if len(sys.argv) > 3 else 16 * 1024
    with tempfile.TemporaryDirectory() as tmp:
        binf = os.path.join(tmp, "prog.bin")
        subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", elf, binf], check=True)
        data = open(binf, "rb").read()
    if len(data) > size:
        sys.exit(f"elf2hex: image is {len(data)} bytes, larger than SRAM ({size})")
    data += bytes((-len(data)) % 4)
    words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
    with open(prefix + ".hex", "w") as f:
        f.writelines(f"{w:08x}\n" for w in words)
    for lane in range(4):
        with open(f"{prefix}.b{lane}.hex", "w") as f:
            f.writelines(f"{(w >> (8 * lane)) & 0xFF:02x}\n" for w in words)
    print(f"elf2hex: {len(data)} bytes, {len(words)} words -> {prefix}.hex, {prefix}.b0..3.hex")


if __name__ == "__main__":
    main()
