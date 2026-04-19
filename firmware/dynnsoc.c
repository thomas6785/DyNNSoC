#include "dynnsoc.h"
#include <stdint.h>

typedef volatile uint32_t vuint32_t;

void dynnsoc_write_reg(uint32_t addr, uint32_t value) {
    *((vuint32_t*)addr) = value;
}

uint32_t dynnsoc_read_reg(uint32_t addr) {
    return *((vuint32_t*)addr);
}

// TODO Add more API functions as needed for UART, MVU, etc.
// MVU data transposition is a big one (though it might be better to do that in hardware long-term)
