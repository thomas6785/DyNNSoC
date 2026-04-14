ENTRY(_start)

/*
 * DyNNSoC Memory Map
 *
 * ROM: 32 KB at 0x0000_0000  -- read-only, accessible via both
 *      instruction fetch interface and AHB data bus (load/store).
 * RAM: 16 KB at 0x2000_0000  -- read/write via AHB data bus only.
 *
 * Because ROM is readable via load/store, .rodata can live in ROM and
 * .data initializers are stored in ROM (AT > ROM) and copied to RAM by
 * startup code in crt0.S.
 */

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    RAM (rw)  : ORIGIN = 0x01000000, LENGTH = 12K
    stack (rw): ORIGIN = 0x01000000 + 12K, LENGTH = 4K
}

PROVIDE(_fstack = ORIGIN(stack) + LENGTH(stack) - 4);

SECTIONS
{
    .text : {
        KEEP(*(.vectors))
        *(.text*)
    } > ROM

    .rodata : {
        *(.rodata*)
    } > ROM

    .data : ALIGN(4) {
        __data_start__ = .;
        *(.data*)
        . = ALIGN(4);
        __data_end__ = .;
    } > RAM AT > ROM

    __data_load__ = LOADADDR(.data);

    .sdata : ALIGN(4) {
        __sdata_start__ = .;
        *(.sdata*)
        . = ALIGN(4);
        __sdata_end__ = .;
    } > RAM AT > ROM

    __sdata_load__ = LOADADDR(.sdata);

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start__ = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > RAM

    .sbss (NOLOAD) : ALIGN(4) {
        __sbss_start__ = .;
        *(.sbss*)
        . = ALIGN(4);
        __sbss_end__ = .;
    } > RAM
}
