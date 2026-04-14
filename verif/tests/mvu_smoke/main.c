#include "dynnsoc.h"

void assert_equal(uint32_t a, uint32_t b) {
    if (a != b) {
        gpio_write(0x0BAD); // if we fail an assertion, write DEAD to the GPIOs so testbench can detect it
    } else {
        gpio_write(0);
        gpio_write(0x900D);
    }
}

void test_mvu_data(uint32_t offset, uint32_t val) {
    mvu_write_data(offset, val);
    //GPIO_OUT1 = offset; // write the offset to GPIOs so we can see in the waveform which address we are testing
    uint32_t read_val = mvu_read_data(offset);
    assert_equal(read_val, val);
}

static uint32_t prng_state = 0x12345678; // just a random seed
uint32_t prng(uint32_t feed) {
    // A very simple LFSR-based PRNG, just to generate some pseudo-random test data for the MVU tests
    prng_state ^= feed; // mix in the feed value to make it less predictable
    prng_state ^= (prng_state << 13);
    prng_state ^= (prng_state >> 17);
    prng_state ^= (prng_state << 5);
    return prng_state;
}

static volatile uint32_t waiting_for_interrupt = 0;
void irq_handler_07(void) __attribute__((interrupt("machine")));
void irq_handler_07(void) {
    GPIO_OUT1 = 0x00FF; // TODO remove this debug line
    waiting_for_interrupt = 0;
    MVU_CSR(0) -> status = 1; // clear interrupt (w1c)
}

int main(void) {
    test_mvu_data(  0xfff8,   0xCAFEBABE); // last legel address
    irq_global_enable();
    irq_enable(0xFFFFFFFF); // enable IRQs
    gpio_write(0);
    GPIO_OUT1 = 0x0; // TODO remove this debug line

    uint32_t i;
    for(i=0; i<32; i++) {
        volatile uint32_t val = 0x12345*i;
        uint32_t addr_off = 8*i; // 8 because we can only write to addresses ending 000
        test_mvu_data(addr_off, val);
    }
    GPIO_OUT1 = 0x1; // TODO remove this debug line

    test_mvu_data(  0x3fff8,   0xCAFEBABE); // last legel address
    test_mvu_data(  0x3fff0,   0xCAFEBABE); // last legel address
    GPIO_OUT1 = 0x2; // TODO remove this debug line

    for(i=0; i<36; i++) {
        mvu_write_weight(i*4, prng(i)); // write some random data to the weight memory bank
    } // 9 weights of 4 bits each // TODO need to increase this to much more because of word size ratio

    GPIO_OUT1 = 0x3; // TODO remove this debug line

    for(i=0; i<50; i++) {
        mvu_write_data(i*8, prng(i)); // write some random data to the input data memory bank
    } // 5*5 data points of 2 bits each

    GPIO_OUT1 = 0x4; // TODO remove this debug line

    int weight_max_precision = 4;
    int input_data_max_precision = 2;
    int kernel_size = 9;
    int input_data_side_length = 5;
    int kernel_side_length = 3;
    int weight_addr = 0;
    int input_data_addr = 0;
    int output_data_addr = 131072;
    GPIO_OUT1 = 0x5; // TODO remove this debug line
    MVU_CSR(0) -> wlength_1    =  1-1               ;
    MVU_CSR(0) -> wlength_2    =  1-1               ;
    MVU_CSR(0) -> wlength_3    =  (weight_max_precision*input_data_max_precision-1               ); // need to stay here long enough to iterate over all partial products for bit serial computation
    MVU_CSR(0) -> wlength_4    =  kernel_size-1                  ;
    MVU_CSR(0) -> wjump_0      =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(0) -> wjump_1      =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(0) -> wjump_2      =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(0) -> wjump_3      =  -(kernel_size-1)*weight_max_precision;
    MVU_CSR(0) -> wjump_4      =  1*weight_max_precision;
    MVU_CSR(0) -> ilength_1    =  input_data_side_length-kernel_side_length;
    MVU_CSR(0) -> ilength_2    =  input_data_max_precision*weight_max_precision-1;
    MVU_CSR(0) -> ilength_3    =  kernel_side_length-1;
    MVU_CSR(0) -> ilength_4    =  kernel_side_length-1;
    MVU_CSR(0) -> ijump_0      =  -input_data_max_precision*(kernel_side_length-1)*input_data_side_length-1;
    MVU_CSR(0) -> ijump_1      =  -input_data_max_precision*((kernel_side_length-1)*input_data_side_length+1);
    MVU_CSR(0) -> ijump_2      =  -input_data_max_precision*((kernel_side_length-1)*input_data_side_length+kernel_side_length-1);
    MVU_CSR(0) -> ijump_3      =  input_data_max_precision*(input_data_side_length-kernel_side_length+1);
    MVU_CSR(0) -> ijump_4      =  input_data_max_precision*1;
    MVU_CSR(0) -> wbaseptr     =  weight_addr;
    MVU_CSR(0) -> ibaseptr     =  input_data_addr;
    MVU_CSR(0) -> obaseptr     =  output_data_addr;
    MVU_CSR(0) -> omvusel      =  0xFF;

    // use 4 bits of weights, 2 bits of data, and output 4 bits of precision
    MVU_CSR(0) -> precision   = (4<<0)|(2<<6)|(4<<12);
    MVU_CSR(0) -> quant       = 9; // start output at bit 9

    MVU_CSR(0) -> command = 3*3*3*3*5; // random duration long enough to get a few samples
    GPIO_OUT1 = 0x6; // TODO remove this debug line

    // wait for the MVU IRQ
    waiting_for_interrupt = 1;
    while(waiting_for_interrupt);
    GPIO_OUT1 = 0x7; // TODO remove this debug line

    // Read the output
    for(i=0; i<16; i++) {
        GPIO_OUT1 = 0;
        GPIO_OUT1 = mvu_read_data(output_data_addr+8*i);
    }
    GPIO_OUT1 = 0x8; // TODO remove this debug line

    gpio_write(0xBEEF); // BEEF means the test is over, testbench will recognise it and halt
}
