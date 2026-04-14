/*
crt0.S -- Ibex C runtime
Ibex vectored-interrupt vector table layout (mtvec MODE = 1):

Vector offset = cause * 4.
  Cause  Offset  Type
  -----  ------  ----
    0     0x00   Reset / exceptions
    3     0x0C   Machine software interrupt
    7     0x1C   Machine timer interrupt
   11     0x2C   Machine external interrupt
   16     0x40   Fast interrupt 0
   17     0x44   Fast interrupt 1
    ...    ...    ...
   30     0x78   Fast interrupt 14
   31     0x7C   NMI

Each handler is declared weak. Override in C with:
  void irq_handler_N(void) __attribute__((interrupt("machine")));
*/

.section .vectors, "ax"
.global _start

    .org 0x00                       /* Cause  0: reset */
_start:
    j       _reset

    .org 0x0C                       /* Cause  3: machine software IRQ */
    j       irq_handler_sw

    .org 0x1C                       /* Cause  7: machine timer IRQ */
    j       irq_handler_systick

    .org 0x2C                       /* Cause 11: machine external IRQ */
    j       irq_handler_ext

    .org 0x40                       /* Cause 16: fast IRQ 0 */
    j       irq_handler_00
    .org 0x44                       /* Cause 17: fast IRQ 1 */
    j       irq_handler_01
    .org 0x48                       /* Cause 18: fast IRQ 2 */
    j       irq_handler_02
    .org 0x4C                       /* Cause 19: fast IRQ 3 */
    j       irq_handler_03
    .org 0x50                       /* Cause 20: fast IRQ 4 */
    j       irq_handler_04
    .org 0x54                       /* Cause 21: fast IRQ 5 */
    j       irq_handler_05
    .org 0x58                       /* Cause 22: fast IRQ 6 */
    j       irq_handler_06
    .org 0x5C                       /* Cause 23: fast IRQ 7 */
    j       irq_handler_07
    .org 0x60                       /* Cause 24: fast IRQ 8 */
    j       irq_handler_08
    .org 0x64                       /* Cause 25: fast IRQ 9 */
    j       irq_handler_09
    .org 0x68                       /* Cause 26: fast IRQ 10 */
    j       irq_handler_10
    .org 0x6C                       /* Cause 27: fast IRQ 11 */
    j       irq_handler_11
    .org 0x70                       /* Cause 28: fast IRQ 12 */
    j       irq_handler_12
    .org 0x74                       /* Cause 29: fast IRQ 13 */
    j       irq_handler_13
    .org 0x78                       /* Cause 30: fast IRQ 14 */
    j       irq_handler_14

    .org 0x7C                       /* Cause 31: NMI */
    j       irq_handler_nmi

/* ------------------------------------------------------------------ */
.section .text

_reset:
    /* Disable interrupts during init */
    csrci   mstatus, 0x8

    /* Zero all registers */
    li x1, 0
    li x2, 0
    li x3, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x8, 0
    li x9, 0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0

    /* Set up stack pointer */
    lui  sp, %hi(_fstack)
    addi sp, sp, %lo(_fstack)


    /* Copy .data from ROM (LMA) to RAM (VMA) */
    la a0, __data_load__
    la a1, __data_start__
    la a2, __data_end__
    bge a1, a2, .Ldata_done
.Ldata_loop:
    lw a3, 0(a0)
    sw a3, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    blt a1, a2, .Ldata_loop
.Ldata_done:

    /* Copy .sdata from ROM (LMA) to RAM (VMA) */
    la a0, __sdata_load__
    la a1, __sdata_start__
    la a2, __sdata_end__
    bge a1, a2, .Lsdata_done
.Lsdata_loop:
    lw a3, 0(a0)
    sw a3, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    blt a1, a2, .Lsdata_loop
.Lsdata_done:


    /* Clear .bss */
    la a0, __bss_start__
    la a1, __bss_end__
    bge a0, a1, .Lbss_done
.Lbss_loop:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, .Lbss_loop
.Lbss_done:

    /* Clear .sbss */
    la a0, __sbss_start__
    la a1, __sbss_end__
    bge a0, a1, .Lsbss_done
.Lsbss_loop:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, .Lsbss_loop
.Lsbss_done:

    /* Call main */
    jal main

    /* If main returns, spin forever */
.Lhalt:
    wfi
    j   .Lhalt

/* ------------------------------------------------------------------ */
/* Default IRQ handlers (weak -- override in C as needed)              */

.weak irq_handler_sw
.weak irq_handler_systick
.weak irq_handler_ext
.weak irq_handler_00
.weak irq_handler_01
.weak irq_handler_02
.weak irq_handler_03
.weak irq_handler_04
.weak irq_handler_05
.weak irq_handler_06
.weak irq_handler_07
.weak irq_handler_08
.weak irq_handler_09
.weak irq_handler_10
.weak irq_handler_11
.weak irq_handler_12
.weak irq_handler_13
.weak irq_handler_14
.weak irq_handler_nmi

irq_handler_sw:
irq_handler_systick:
irq_handler_ext:
irq_handler_00:
irq_handler_01:
irq_handler_02:
irq_handler_03:
irq_handler_04:
irq_handler_05:
irq_handler_06:
irq_handler_07:
irq_handler_08:
irq_handler_09:
irq_handler_10:
irq_handler_11:
irq_handler_12:
irq_handler_13:
irq_handler_14:
irq_handler_nmi:
    mret
