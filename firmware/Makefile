PREFIX  = riscv32-unknown-elf-
CC      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump

CFLAGS  = -Wall -Os -march=rv32i_zicsr -mabi=ilp32 \
           -mstrict-align -falign-functions=4 -ffreestanding -nostartfiles
LDFLAGS = -T link.ld -nostartfiles -lgcc

NAME    = main
SRCS_C  = $(wildcard *.c)
SRCS_S  = crt0.S

all: $(NAME).hex

$(NAME).elf: $(SRCS_S) $(SRCS_C) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS_S) $(SRCS_C)

$(NAME).hex: $(NAME).elf
	$(OBJCOPY) -O verilog --verilog-data-width 4 $< $@

$(NAME).bin: $(NAME).elf
	$(OBJCOPY) -O binary $< $@

$(NAME).lst: $(NAME).elf
	$(OBJDUMP) -D $< > $@

disasm: $(NAME).lst

clean:
	rm -f $(NAME).elf $(NAME).bin $(NAME).hex $(NAME).lst

.PHONY: all clean disasm
