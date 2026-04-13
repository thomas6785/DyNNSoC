#include "dynnsoc.h"

/* Override the weak default handler for fast IRQ 1 (cause 17) */
void irq_handler_01(void) __attribute__((interrupt("machine")));
void irq_handler_01(void) {
    /* Echo received character back and light LEDs */
    char c = uart_getc();
    uart_putc(c);
    gpio_write(0xAAAA);
}

int main(void) {
    /* Write to LEDs */
    gpio_write(0x0001);

    /* Enable UART RX interrupt */
    UART_CONTROL = UART_RX_NE_IE;
    irq_enable(MIE_UART);
    irq_global_enable();

    /* Send a greeting */
    uart_puts("DyNNSoC ready\r\n");

    /* Read switches and display on LEDs */
    while (1) {
        uint16_t sw = gpio_read_switches();
        gpio_write(sw);
    }
}
