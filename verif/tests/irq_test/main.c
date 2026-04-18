#include "dynnsoc.h"

/* Create handlers for each interrupts that will simply write that interrupts ID to GPIO. Useful for testing the interrupts all work correctly */
#define IRQ_HANDLER(name, id) \
    void name(void) __attribute__((interrupt("machine"))); \
    void name(void) { gpio_write0(id); }

IRQ_HANDLER(irq_handler_sw,      32)
IRQ_HANDLER(irq_handler_systick, 64)
IRQ_HANDLER(irq_handler_ext,     11)
IRQ_HANDLER(irq_handler_00,       0)
IRQ_HANDLER(irq_handler_01,       1)
IRQ_HANDLER(irq_handler_02,       2)
IRQ_HANDLER(irq_handler_03,       3)
IRQ_HANDLER(irq_handler_04,       4)
IRQ_HANDLER(irq_handler_05,       5)
IRQ_HANDLER(irq_handler_06,       6)
IRQ_HANDLER(irq_handler_07,       7)
IRQ_HANDLER(irq_handler_08,       8)
IRQ_HANDLER(irq_handler_09,       9)
IRQ_HANDLER(irq_handler_10,      10)
IRQ_HANDLER(irq_handler_11,      11)
IRQ_HANDLER(irq_handler_12,      12)
IRQ_HANDLER(irq_handler_13,      13)
IRQ_HANDLER(irq_handler_14,      14)
IRQ_HANDLER(irq_handler_nmi,    128)

int main(void) {
    /* Write to GPIO initially */
    gpio_write0(0xFFFF);

    irq_enable(0xFFFFFFFF); // enable all interrupts
    irq_global_enable(); // enable global interrupt enable

    /* Send a greeting */
    uart_puts("DyNNSoC ready\r\n");

    // Do nothing (to test interrupts)
    while (1);
}
