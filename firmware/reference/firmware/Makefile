name := test

%.hex: $(name).c n5_drv.c crt0.S link.ld
	riscv32-unknown-elf-gcc -Wall  -falign-functions=4 -march=rv32ic_zicsr -mabi=ilp32  -nostartfiles -mstrict-align -T link.ld -o $(name).elf -lgcc crt0.S n5_drv.c $(name).c  -lgcc
	riscv32-unknown-elf-objcopy -O binary $(name).elf $(name).bin
	riscv32-unknown-elf-objcopy -O verilog --verilog-data-width 4 $(name).elf $(name).hex
	riscv32-unknown-elf-objdump -D $(name).elf > $(name).lst

all: $(name).hex

clean:
	rm -f $(name).elf $(name).bin $(name).hex $(name).lst
