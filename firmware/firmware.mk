# firmware.mk — Shared toolchain configuration for DyNNSoC firmware
#
# Usage: from any test Makefile, set FW_DIR and then include this file:
#
#   FW_DIR  := $(SOCROOT)/firmware
#   include $(FW_DIR)/firmware.mk
#
# The including Makefile must have a main.c (or set SRCS_C).
# Build products (main.elf, main.hex, main.lst) go in the current directory.

# ── Toolchain ────────────────────────────────────────────────────
PREFIX  := riscv32-unknown-elf-
CC      := $(PREFIX)gcc
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump

# ── Flags ────────────────────────────────────────────────────────
CFLAGS  := -Wall -O0 -march=rv32i_zicsr -mabi=ilp32 \
           -mstrict-align -falign-functions=4 -ffreestanding -nostartfiles \
           -I$(FW_DIR)
LDFLAGS := -T $(FW_DIR)/link.ld -nostartfiles -lgcc

# ── Sources ──────────────────────────────────────────────────────
# Shared startup code (always linked)
FW_CRT0 := $(FW_DIR)/crt0.S

# Test-local C sources (default: all .c in the including Makefile's directory)
SRCS_C  ?= $(wildcard *.c)

# ── Targets ──────────────────────────────────────────────────────
# Pattern rules: request any <name>.hex, <name>.elf, or <name>.lst
# and Make will figure out the dependency chain automatically.
#   e.g.  make main.hex   or   make foo.hex

%.elf: $(FW_CRT0) $(SRCS_C) $(FW_DIR)/link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(FW_CRT0) $(SRCS_C)

%.hex: %.elf
	echo "\n\n\nCompiling $@"
	$(OBJCOPY) -O verilog --verilog-data-width 4 $< $@

%.lst: %.elf
	$(OBJDUMP) -D $< > $@

fw_clean:
	rm -f *.elf *.bin *.hex *.lst

.PHONY: fw_clean
