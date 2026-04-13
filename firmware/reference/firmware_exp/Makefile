name := test

CROSS = riscv32-unknown-elf
CC  = $(CROSS)-gcc
AS  = $(CROSS)-as
LD  = $(CROSS)-ld
OC  = $(CROSS)-objcopy
OD  = $(CROSS)-objdump
CPP = $(CROSS)-cpp

CCFLAGS = -Wall -march=rv32i_zicsr -save-temps -std=gnu99 -ffast-math -fno-builtin-printf -T common/link.ld -falign-functions=4 -mabi=ilp32  -nostartfiles -mstrict-align -nostdlib -lgcc

%.hex: $(name).c common/n5_drv.c common/crt0.S common/link.ld
	$(CC) $(CCFLAGS) -o $(name).elf -I ./common common/crt0.S common/n5_drv.c $(name).c
	$(OC) -O binary $(name).elf $(name).bin
	$(OC) -O verilog --verilog-data-width 4 $(name).elf $(name).hex
	$(OD) -D $(name).elf > $(name).lst

all: $(name).hex

clean:
	rm -f $(name).elf $(name).bin $(name).hex $(name).lst
