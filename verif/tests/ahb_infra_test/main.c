#include "dynnsoc.h"

static const uint32_t expected[] = { 10, 20, 30, 40, 50 };
static uint32_t init_var[] = {13, 17, 19, 23, 29};

__attribute__((noinline)) int32_t multiply(int32_t a, int32_t b) {
    return a * b;
}

int main(void) {
    irq_global_disable();
    // Test the core is basically working and can use GPIO
    volatile int i,j;
    i = 0;
    for (j = 0; j < 200; j++) {
        i++;
    };
    gpio_write(i-200); // should be 0

    // Test .rodata is accessible
    uint32_t sum = 0;
    for (i = 0; i < 5; i++) {
        sum += expected[i];
    }

    /* If .rodata is accessible, sum == 150; write (sum - 150) which should be 0 */
    gpio_write(sum - 150);

    // Test initialised variables have their initial values
    gpio_write(init_var[0]-13);
    gpio_write(init_var[1]-17);
    gpio_write(init_var[2]-19);
    gpio_write(init_var[3]-23);
    gpio_write(init_var[4]-29); // TODO FIX

    // Test we can overwrite initialised variables with new values
    for (i = 0; i < 5; i++) {
        init_var[i] = i;
        gpio_write(init_var[i]-i);
    }

    // Test function calls (which also tests the stack is working)
    volatile int32_t a = 6, b = 7, c = - 3, d = 8; // need to declare these as volatile to prevent compiler from pre-computing
    gpio_write(multiply(a,b) - 42); // TODO FIX
    gpio_write(multiply(c,d) + 24);

    gpio_write(0xBEEF); // BEEF means the test is over
}
