# Build one firmware program for the SoC.
#   make -C sw PROG=hello      -> sw/build/hello.{elf,dump,hex,b0..b3.hex}
# The .b0..b3.hex files are the SRAM init files (soc_top INIT_FILE_B0..B3,
# FPGA build and tb_soc_top). Needs riscv64-unknown-elf-gcc.
PROG    ?= hello
BUILD   := build
CC      := riscv64-unknown-elf-gcc
OBJDUMP := riscv64-unknown-elf-objdump
CFLAGS  := -march=rv32im_zicsr -mabi=ilp32 -O2 -g -ffreestanding -fno-builtin \
           -nostdlib -nostartfiles -Wall -Wextra -Iinclude -T startup/link.ld \
           -Wl,--no-warn-rwx-segments

.PHONY: all clean
all: $(BUILD)/$(PROG).b0.hex

$(BUILD)/$(PROG).elf: startup/crt0.S tests/$(PROG).c include/soc.h startup/link.ld
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) startup/crt0.S tests/$(PROG).c -lgcc -o $@
	$(OBJDUMP) -d $@ > $(BUILD)/$(PROG).dump

$(BUILD)/$(PROG).b0.hex: $(BUILD)/$(PROG).elf
	python3 ../scripts/elf2hex.py $< $(BUILD)/$(PROG)

clean:
	rm -rf $(BUILD)
