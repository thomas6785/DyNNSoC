#ifndef DYNNSOC_H
#define DYNNSOC_H

#include <stdint.h>

/* ------------------------------------------------------------------ */
/* Helper macros                                                       */
/* ------------------------------------------------------------------ */
#define REG32(addr) (*(volatile uint32_t *)(addr))

#define SET_BIT(reg, bit) ((reg) |=  (1u << (bit)))
#define CLR_BIT(reg, bit) ((reg) &= ~(1u << (bit)))
#define CHK_BIT(reg, bit) ((reg) &   (1u << (bit)))

/* ------------------------------------------------------------------ */
/* Memory map (AHB data bus -- from AHBDCD address decoder)            */
/*                                                                     */
/*   Slave   Address range          Peripheral                         */
/*   S0      0x0000_0000            ROM  (32 KB, read-only)            */
/*   S1      0x2000_0000            RAM  (16 KB)                       */
/*   S2      0x5000_0000            GPIO                               */
/*   S3      0x5100_0000            UART                               */
/*                                                                     */
/* ROM is also accessible via the instruction fetch interface.          */
/* ------------------------------------------------------------------ */

#define ROM_BASE        0x00000000u
#define RAM_BASE        0x20000000u
#define GPIO_BASE       0x50000000u
#define UART_BASE       0x51000000u

/* ------------------------------------------------------------------ */
/* GPIO registers (AHBgpio)                                            */
/*                                                                     */
/*   Offset  Name       Access  Width   Description                    */
/*   0x00    OUT0       R/W     16-bit  output port 0 (LEDs)           */
/*   0x04    OUT1       R/W     16-bit  output port 1                  */
/*   0x08    IN0        R       16-bit  input port 0 (slide switches)  */
/*   0x0C    IN1        R       16-bit  input port 1 (buttons)         */
/* ------------------------------------------------------------------ */

#define GPIO_OUT0       REG32(GPIO_BASE + 0x00)
#define GPIO_OUT1       REG32(GPIO_BASE + 0x04)
#define GPIO_IN0        REG32(GPIO_BASE + 0x08)
#define GPIO_IN1        REG32(GPIO_BASE + 0x0C)

/* ------------------------------------------------------------------ */
/* UART registers (AHBuart)                                            */
/*                                                                     */
/*   Offset  Name       Access  Width   Description                    */
/*   0x00    RXDATA     R       8-bit   receive data (from RX FIFO)    */
/*   0x04    TXDATA     W       8-bit   transmit data (to TX FIFO)     */
/*   0x08    STATUS     R       4-bit   status flags                   */
/*   0x0C    CONTROL    R/W     4-bit   interrupt enables              */
/*                                                                     */
/*   STATUS bits:                                                      */
/*     [0] TX_FULL       TX FIFO is full                               */
/*     [1] TX_EMPTY      TX FIFO is empty                              */
/*     [2] RX_FULL       RX FIFO is full                               */
/*     [3] RX_NOT_EMPTY  RX FIFO has data available                    */
/*                                                                     */
/*   CONTROL bits (interrupt enables, active high):                    */
/*     [0] TX_FULL_IE                                                  */
/*     [1] TX_EMPTY_IE                                                 */
/*     [2] RX_FULL_IE                                                  */
/*     [3] RX_NOT_EMPTY_IE                                             */
/* ------------------------------------------------------------------ */

#define UART_RXDATA     REG32(UART_BASE + 0x00)
#define UART_TXDATA     REG32(UART_BASE + 0x04)
#define UART_STATUS     REG32(UART_BASE + 0x08)
#define UART_CONTROL    REG32(UART_BASE + 0x0C)

/* UART status bits */
#define UART_TX_FULL        (1u << 0)
#define UART_TX_EMPTY       (1u << 1)
#define UART_RX_FULL        (1u << 2)
#define UART_RX_NOT_EMPTY   (1u << 3)

/* UART control / interrupt-enable bits */
#define UART_TX_FULL_IE     (1u << 0)
#define UART_TX_EMPTY_IE    (1u << 1)
#define UART_RX_FULL_IE     (1u << 2)
#define UART_RX_NE_IE       (1u << 3)

/* ------------------------------------------------------------------ */
/* Interrupt configuration                                             */
/*                                                                     */
/* Ibex mie CSR bit layout (18-bit internal, mapped to standard CSR):  */
/*   Bit 3  (MIE.MSIE)  - machine software interrupt enable           */
/*   Bit 7  (MIE.MTIE)  - machine timer interrupt enable              */
/*   Bit 11 (MIE.MEIE)  - machine external interrupt enable           */
/*   Bit 16 (MIE.FAST0) - fast interrupt 0 enable                     */
/*   Bit 17 (MIE.FAST1) - fast interrupt 1 enable  = UART             */
/*   ...                                                               */
/*   Bit 30 (MIE.FAST14)                                              */
/*                                                                     */
/* DyNNSoC IRQ wiring:                                                 */
/*   irq_fast_i[0]  = 0        (unused)                               */
/*   irq_fast_i[1]  = UART IRQ                                        */
/*   irq_fast_i[2..14] = 0     (unused)                               */
/* ------------------------------------------------------------------ */

#define MIE_MSIE    (1u << 3)
#define MIE_MTIE    (1u << 7)
#define MIE_MEIE    (1u << 11)
#define MIE_FAST(n) (1u << (16 + (n)))

#define MIE_UART    MIE_FAST(1)   /* fast IRQ 1 = UART */

/* ------------------------------------------------------------------ */
/* Inline helpers for interrupt control                                */
/* ------------------------------------------------------------------ */

static inline void irq_global_enable(void) {
    __asm__ volatile ("csrsi mstatus, 0x8");
}

static inline void irq_global_disable(void) {
    __asm__ volatile ("csrci mstatus, 0x8");
}

static inline void irq_enable(uint32_t mask) {
    __asm__ volatile ("csrs mie, %0" : : "r"(mask));
}

static inline void irq_disable(uint32_t mask) {
    __asm__ volatile ("csrc mie, %0" : : "r"(mask));
}

/* ------------------------------------------------------------------ */
/* GPIO helpers                                                        */
/* ------------------------------------------------------------------ */

static inline void gpio_write(uint16_t val) {
    GPIO_OUT0 = val;
}

static inline uint16_t gpio_read_switches(void) {
    return (uint16_t)GPIO_IN0;
}

static inline uint16_t gpio_read_buttons(void) {
    return (uint16_t)GPIO_IN1;
}

/* ------------------------------------------------------------------ */
/* UART helpers                                                        */
/* ------------------------------------------------------------------ */

static inline int uart_tx_full(void) {
    return UART_STATUS & UART_TX_FULL;
}

static inline int uart_rx_ready(void) {
    return UART_STATUS & UART_RX_NOT_EMPTY;
}

static inline void uart_putc(char c) {
    while (uart_tx_full())
        ;
    UART_TXDATA = (uint8_t)c;
}

static inline char uart_getc(void) {
    while (!uart_rx_ready())
        ;
    return (char)(UART_RXDATA & 0xFF);
}

static inline void uart_puts(const char *s) {
    while (*s)
        uart_putc(*s++);
}

#endif /* DYNNSOC_H */
