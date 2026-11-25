#!/usr/bin/env bash
# Print the version of every tool the flow uses. Missing tools are listed, not fatal.
check() {
  local name="$1"; shift
  if command -v "$name" >/dev/null 2>&1; then
    printf "  %-24s %s\n" "$name" "$("$@" 2>&1 | head -n1)"
  else
    printf "  %-24s MISSING\n" "$name"
  fi
}
echo "Tools:"
check verilator              verilator --version
check xvlog                  xvlog --version
check xelab                  xelab --version
check xsim                   xsim --version
check xcrg                   xcrg -version
check riscv64-unknown-elf-gcc riscv64-unknown-elf-gcc --version
check riscv32-unknown-elf-gcc riscv32-unknown-elf-gcc --version
check gtkwave                gtkwave --version
check python3                python3 --version
check pdflatex               pdflatex --version
check make                   make --version
check git                    git --version
