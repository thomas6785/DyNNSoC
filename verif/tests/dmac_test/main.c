#include "dynnsoc.h"

// Handler for the DMA interrupt
static volatile uint32_t waiting_for_interrupt = 0;
void irq_handler_02(void) __attribute__((interrupt("machine"))); \
void irq_handler_02(void) {
    waiting_for_interrupt = 0;
    DMAC_CONFIG->control = 1; // write last bit to clear IRQ
}

static uint32_t prng_state = 0x12345678; // just a random seed
uint32_t prng(uint32_t feed) { // feed is not totally necessary, can be zero, but feeding something ensures that slight changes to the code will give different test values
    // A very simple LFSR-based PRNG, just to generate some pseudo-random test data for tests
    prng_state ^= feed; // mix in the feed value to make it less predictable (probably not necessary tbh)
    prng_state ^= (prng_state << 13);
    prng_state ^= (prng_state >> 17);
    prng_state ^= (prng_state << 5);
    return prng_state;
}

uint32_t test_data[256];
uint32_t test_dest[256];
// Generate some test data to be used by the DMAC test

int main(void) {
    irq_global_enable();
    irq_enable(MIE_FAST(2)); // enable DMAC IRQ

    // Write pseudorandom test data to the test_data array
    for (int i = 0; i < 256; i++) {
        test_data[i] = prng(i);
    }

    // Configure the DMA to transfer data
    DMAC_CONFIG->src_addr = (uint32_t)test_data; // source address is the test_data array
    DMAC_CONFIG->dst_addr = (uint32_t)test_dest; // write to the destination array
    DMAC_CONFIG->length = 256; // length of the transaction
    DMAC_CONFIG->control = (1<<31); // bit 31 = start transfer

    // Wait for interrupt
    waiting_for_interrupt = 1;
    while (waiting_for_interrupt);

    // Check the data was transferred correctly
    for (int i = 0; i < 256; i++) {
        gpio_write(0);
        if (test_dest[i] != test_data[i]) {
            gpio_write(0x0BAD); // if we fail, write BAD to the GPIO
        }
    }

    gpio_write(0xBEEF); // BEEF means the test is over
}
