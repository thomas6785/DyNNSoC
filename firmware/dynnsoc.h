// ifndef is used to prevent accidentally including this header files twice
#ifndef DYNNSOC_H
#define DYNNSOC_H

#include <stdint.h>

// ------------------------------------------------------------------
// Helper macros
// ------------------------------------------------------------------
#define REG32(addr) (*(volatile uint32_t *)(addr))

#define SET_BIT(reg, bit) ((reg) |=  (1u << (bit)))
#define CLR_BIT(reg, bit) ((reg) &= ~(1u << (bit)))
#define CHK_BIT(reg, bit) ((reg) &   (1u << (bit)))

// Define base addresses for each peripheral
#define ROM_BASE         0x00000000u
#define RAM_BASE         0x01000000u
#define GPIO_BASE        0x02000000u
#define UART_BASE        0x03000000u
#define DMAC_BASE        0x04000000u

#define MVU_DATA_BASE    0x10000000u

#define MVU_WEIGHTS_BASE 0x11000000u
#define MVU_BIAS_BASE    0x12000000u
#define MVU_SCALERS_BASE 0x13000000u
#define MVU_CSR_BASE     0x14000000u

// GPIO Registers
//   Offset  Name    Note
//   0x00    OUT0    output port 0 (LEDs)
//   0x04    OUT1    output port 1
//   0x08    IN0     input port 0 (slide switches)   (READ ONLY)
//   0x0C    IN1     input port 1 (buttons)          (READ ONLY)
// Note that these registers are only 16-bit, though their addresses are spaced by 4
// to keep the address space word-aligned
// effectively there are 16 bits of padding between each register in the memory

#define GPIO_OUT0       REG32(GPIO_BASE + 0x00)
#define GPIO_OUT1       REG32(GPIO_BASE + 0x04)
#define GPIO_IN0        REG32(GPIO_BASE + 0x08)
#define GPIO_IN1        REG32(GPIO_BASE + 0x0C)

// UART registers
//   Offset  Name      Width   Description
//   0x00    RXDATA    8-bit   receive data (from RX FIFO) (READ ONLY)
//   0x04    TXDATA    8-bit   transmit data (to TX FIFO)  (WRITE ONLY)
//   0x08    STATUS    4-bit   status flags                (READ ONLY)
//   0x0C    CONTROL   4-bit   interrupt enables
//
//   STATUS bits:
//     [0] TX_FULL       TX FIFO is full
//     [1] TX_EMPTY      TX FIFO is empty
//     [2] RX_FULL       RX FIFO is full
//     [3] RX_NOT_EMPTY  RX FIFO has data available
//
//   CONTROL bits (interrupt enables, active high):
//     [0] TX_FULL_IE
//     [1] TX_EMPTY_IE
//     [2] RX_FULL_IE
//     [3] RX_NOT_EMPTY_IE

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

// Interrupt configuration bit positions

// Software interrupt enable
#define MIE_MSIE    (1u << 3)
// Timer interrupt enable
#define MIE_MTIE    (1u << 7)
// External interrupt enable
#define MIE_MEIE    (1u << 11)
// Fast interrupts for peripherals
#define MIE_FAST(n) (1u << (16 + (n)))

#define MIE_UART    MIE_FAST(1)   /* fast IRQ 1 = UART */

// ------------------------------------------------------------------
// Helpers for interrupt control
// ------------------------------------------------------------------

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

// ------------------------------------------------------------------
// GPIO helpers
// ------------------------------------------------------------------

static inline void gpio_write0(uint16_t val) {
    GPIO_OUT0 = val;
}

static inline void gpio_write1(uint16_t val) {
    GPIO_OUT1 = val;
}

static inline uint16_t gpio_read0(void) {
    return (uint16_t)GPIO_IN0;
}

static inline uint16_t gpio_read1(void) {
    return (uint16_t)GPIO_IN1;
}

// ------------------------------------------------------------------
// UART helpers
// ------------------------------------------------------------------

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

// ------------------------------------------------------------------
// DMAC Helpers
// ------------------------------------------------------------------
typedef struct {
    uint32_t src_addr;
    uint32_t dst_addr;
    uint32_t length; // in bytes
    uint32_t control;
} dmac_config_t;

#define DMAC_CONFIG ((volatile dmac_config_t *)(DMAC_BASE))

// ------------------------------------------------------------------
// MVU helpers
// ------------------------------------------------------------------

static inline void mvu_write_data(uint32_t offset, uint32_t val) {
    REG32(MVU_DATA_BASE + offset) = val;
}

static inline uint32_t mvu_read_data(uint32_t offset) {
    return REG32(MVU_DATA_BASE + offset);
}

static inline void mvu_write_weight(uint32_t offset, uint32_t val) {
    REG32(MVU_WEIGHTS_BASE + offset) = val;
}

static inline uint32_t mvu_read_weight(uint32_t offset) {
    return REG32(MVU_WEIGHTS_BASE + offset);
}

static inline void mvu_write_bias(uint32_t offset, uint32_t val) {
    REG32(MVU_BIAS_BASE + offset) = val;
}

static inline uint32_t mvu_read_bias(uint32_t offset) {
    return REG32(MVU_BIAS_BASE + offset);
}

static inline void mvu_write_scaler(uint32_t offset, uint32_t val) {
    REG32(MVU_SCALERS_BASE + offset) = val;
}

static inline uint32_t mvu_read_scaler(uint32_t offset) {
    return REG32(MVU_SCALERS_BASE + offset);
}

// CSR register block for each MVU (must match mvu_csr_t enum in mvu_pkg.sv)
typedef struct {
    uint32_t wbaseptr;          // 0x000  Weights base pointer
    uint32_t ibaseptr;          // 0x004  Inputs base pointer
    uint32_t sbaseptr;          // 0x008  Scalers base pointer
    uint32_t bbaseptr;          // 0x00c  Biases base pointer
    uint32_t obaseptr;          // 0x010  Output base pointer
    uint32_t wjump_0;           // 0x014  Weight address jump 0
    uint32_t wjump_1;           // 0x018  Weight address jump 1
    uint32_t wjump_2;           // 0x01c  Weight address jump 2
    uint32_t wjump_3;           // 0x020  Weight address jump 3
    uint32_t wjump_4;           // 0x024  Weight address jump 4
    uint32_t ijump_0;           // 0x028  Input address jump 0
    uint32_t ijump_1;           // 0x02c  Input address jump 1
    uint32_t ijump_2;           // 0x030  Input address jump 2
    uint32_t ijump_3;           // 0x034  Input address jump 3
    uint32_t ijump_4;           // 0x038  Input address jump 4
    uint32_t sjump_0;           // 0x03c  Scaler address jump 0
    uint32_t sjump_1;           // 0x040  Scaler address jump 1
    uint32_t sjump_2;           // 0x044  Scaler address jump 2
    uint32_t sjump_3;           // 0x048  Scaler address jump 3
    uint32_t sjump_4;           // 0x04c  Scaler address jump 4
    uint32_t bjump_0;           // 0x050  Bias address jump 0
    uint32_t bjump_1;           // 0x054  Bias address jump 1
    uint32_t bjump_2;           // 0x058  Bias address jump 2
    uint32_t bjump_3;           // 0x05c  Bias address jump 3
    uint32_t bjump_4;           // 0x060  Bias address jump 4
    uint32_t ojump_0;           // 0x064  Output address jump 0
    uint32_t ojump_1;           // 0x068  Output address jump 1
    uint32_t ojump_2;           // 0x06c  Output address jump 2
    uint32_t ojump_3;           // 0x070  Output address jump 3
    uint32_t ojump_4;           // 0x074  Output address jump 4
    uint32_t wlength_1;         // 0x078  Weight loop length 1
    uint32_t wlength_2;         // 0x07c  Weight loop length 2
    uint32_t wlength_3;         // 0x080  Weight loop length 3
    uint32_t wlength_4;         // 0x084  Weight loop length 4
    uint32_t ilength_1;         // 0x088  Input loop length 1
    uint32_t ilength_2;         // 0x08c  Input loop length 2
    uint32_t ilength_3;         // 0x090  Input loop length 3
    uint32_t ilength_4;         // 0x094  Input loop length 4
    uint32_t slength_1;         // 0x098  Scaler loop length 1
    uint32_t slength_2;         // 0x09c  Scaler loop length 2
    uint32_t slength_3;         // 0x0a0  Scaler loop length 3
    uint32_t slength_4;         // 0x0a4  Scaler loop length 4
    uint32_t blength_1;         // 0x0a8  Bias loop length 1
    uint32_t blength_2;         // 0x0ac  Bias loop length 2
    uint32_t blength_3;         // 0x0b0  Bias loop length 3
    uint32_t blength_4;         // 0x0b4  Bias loop length 4
    uint32_t olength_1;         // 0x0b8  Output loop length 1
    uint32_t olength_2;         // 0x0bc  Output loop length 2
    uint32_t olength_3;         // 0x0c0  Output loop length 3
    uint32_t olength_4;         // 0x0c4  Output loop length 4
    uint32_t precision;         // 0x0c8  Precision config
    uint32_t status;            // 0x0cc  Status
    uint32_t command;           // 0x0d0  Command register
    uint32_t quant;             // 0x0d4  Quantisation
    uint32_t scaler;            // 0x0d8  Scaler value
    uint32_t config1;           // 0x0dc  Misc config
    uint32_t omvusel;           // 0x0e0  Output MVU select
    uint32_t usescaler_mem;     // 0x0e4  Use scaler memory
    uint32_t usebias_mem;       // 0x0e8  Use bias memory
} mvu_csr_t;

// Get a pointer to the CSR block for a given MVU
#define MVU_CSR(mvu_id) ((volatile mvu_csr_t *)(MVU_CSR_BASE | ((mvu_id) << 20)))

#endif
