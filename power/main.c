#include "dynnsoc.h"

void mark_tb_phase(uint8_t code) {
    gpio_write1(code);   // write the phase code for debug purposes
}

void halt_tb(uint8_t code) {
    gpio_write1(code);   // write the phase code for debug purposes
    gpio_write0(0xBEEF); // testbench will stop when it sees this value on GPIO0
    gpio_write0(0);
}

static uint32_t prng_state = 0x12345678; // just a random seed
uint32_t prng(uint32_t feed) {
    // A very simple LFSR-based PRNG, just to generate some pseudo-random test data for the MVU tests
    prng_state ^= feed; // mix in the feed value to make it less predictable (probably unnecessary)
    prng_state ^= (prng_state << 13);
    prng_state ^= (prng_state >> 17);
    prng_state ^= (prng_state << 5);
    return prng_state;
}

static volatile uint32_t waiting_for_interrupt = 0;
void irq_handler_11(void) __attribute__((interrupt("machine")));
void irq_handler_11(void) {
    waiting_for_interrupt = 0;
    MVU_CSR(0) -> status = 1; // clear interrupt (w1c)
}
void irq_handler_12(void) __attribute__((interrupt("machine")));
void irq_handler_12(void) {
    waiting_for_interrupt = 0;
    MVU_CSR(1) -> status = 1; // clear interrupt (w1c)
}
void irq_handler_13(void) __attribute__((interrupt("machine")));
void irq_handler_13(void) {
    waiting_for_interrupt = 0;
    MVU_CSR(2) -> status = 1; // clear interrupt (w1c)
}
void irq_handler_14(void) __attribute__((interrupt("machine")));
void irq_handler_14(void) {
    waiting_for_interrupt = 0;
    MVU_CSR(3) -> status = 1; // clear interrupt (w1c)
}

// GPIO_OUT0 is monitored by the testbench:
//    - values 0x900D ("good") signals a passing test
//    - value 0x0BAD ("bad") will trigger a failed assertion in the TB
//    - value 0xBEEF ends the test

// GPIO_OUT1 is written to as crude debug tool - by inspecting its value in waveforms we can roughly estimate where in the program we are without having to consult the instructions and listing file

#define NMVU 4
// number of MVU's, parametrisable

// Test phases (written to GPIO_OUT1 for debugging purposes):
#define PHASE_INIT 0x0
#define PHASE_CONFIGURE_MVU 0x1
#define PHASE_START_MVU 0x2
#define PHASE_DONE 0x3

void configure_mvu(uint8_t mvu_id) {
    // Configures an MVU for a convolution
    // It will read from address 0 and write to address 131072 of the NEXT MVU
    // The idea being that we can chain them together to do multiple layers

    // NOTE this configuration is not necessarily all correct
    // for example we are assuming each layer has a 5x5 input but this doesn't make sense
    // it should get smaller with each layer
    // however it is sufficient for the pupose of this test case: establishing power consumption for switching activity
    int weight_max_precision = 4;
    int input_data_max_precision = 4;
    int kernel_size = 9;
    int input_data_side_length = 16;
    int kernel_side_length = 3;
    int weight_addr = 0;
    int input_data_addr = 0;
    int output_data_addr = 131072;
    MVU_CSR(mvu_id) -> wlength_1     =  1-1               ;
    MVU_CSR(mvu_id) -> wlength_2     =  1-1               ;
    MVU_CSR(mvu_id) -> wlength_3     =  (weight_max_precision*input_data_max_precision-1               ); // need to stay here long enough to iterate over all partial products for bit serial computation
    MVU_CSR(mvu_id) -> wlength_4     =  kernel_size-1                  ;
    MVU_CSR(mvu_id) -> wjump_0       =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(mvu_id) -> wjump_1       =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(mvu_id) -> wjump_2       =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(mvu_id) -> wjump_3       =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(mvu_id) -> wjump_4       =  1*weight_max_precision;
    MVU_CSR(mvu_id) -> ilength_1     =  input_data_side_length-kernel_side_length;
    MVU_CSR(mvu_id) -> ilength_2     =  input_data_max_precision*weight_max_precision-1;
    MVU_CSR(mvu_id) -> ilength_3     =  kernel_side_length-1;
    MVU_CSR(mvu_id) -> ilength_4     =  kernel_side_length-1;
    MVU_CSR(mvu_id) -> ijump_0       =  -input_data_max_precision*(kernel_side_length-1)*input_data_side_length-1;
    MVU_CSR(mvu_id) -> ijump_1       =  -input_data_max_precision*((kernel_side_length-1)*input_data_side_length+1);
    MVU_CSR(mvu_id) -> ijump_2       =  -input_data_max_precision*((kernel_side_length-1)*input_data_side_length+kernel_side_length-1);
    MVU_CSR(mvu_id) -> ijump_3       =  input_data_max_precision*(input_data_side_length-kernel_side_length+1);
    MVU_CSR(mvu_id) -> ijump_4       =  input_data_max_precision*1;
    MVU_CSR(mvu_id) -> wbaseptr      =  weight_addr;
    MVU_CSR(mvu_id) -> ibaseptr      =  input_data_addr;
    MVU_CSR(mvu_id) -> obaseptr      =  output_data_addr;
    MVU_CSR(mvu_id) -> omvusel       =  (1<<((mvu_id+1)%NMVU));

    // use 4 bits of weights, 2 bits of data, and output 4 bits of precision
    MVU_CSR(mvu_id) -> precision   = (4<<0)|(4<<6)|(4<<12);
    MVU_CSR(mvu_id) -> quant       = 9; // start output at bit 9
}

void start_mvu(uint8_t mvu_id) {
    MVU_CSR(mvu_id) -> command = 3*3*14*14*4*4;
}

int main(void) {
    int i;

    mark_tb_phase(PHASE_INIT);

    irq_global_enable();
    irq_enable(0xFFFFFFFF); // enable IRQs

    prng(gpio_read0()); // seed the PRNG with the switches (we can randomise them in the TB)

    mark_tb_phase(PHASE_CONFIGURE_MVU);
    for (i=0; i<NMVU; i++) {
        configure_mvu(i);
    }

    halt_tb(PHASE_START_MVU);
    for (i=0; i<NMVU; i++) {
        start_mvu(i);
    }

    // wait for the MVU IRQ
    waiting_for_interrupt = 1;
    while(waiting_for_interrupt);

    halt_tb(PHASE_DONE);
}
