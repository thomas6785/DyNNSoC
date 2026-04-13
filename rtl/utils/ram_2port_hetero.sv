`timescale 1ns / 1ps

/**
 * 2-port (1 read, 1 write) RAM
 * "hetero" meaning the read and write ports are heterogeneous - they have different word sizes and address sizes
 * This is useful for "reshaping" memory - e.g. you want to write 32 bits at a time to interface with a standard system bus, but read 128 bits at a time to feed a wide interface
 */

module ram_2port_hetero #(
    parameter WR_WORD = 32, // Size of the words on the write port (in bits)
    parameter RD_ADDR = 10, // Size of the address on the read port (size of the write port address will be inferred from this and the ratio)
    parameter RD_WORD = 256, // Number of bits read at a time
    localparam RD_RATIO = RD_WORD / WR_WORD, // Ratio of the read word size to the write word size (e.g. for 128-bit read words and a 32-bit write word, this should be 4. $clog2(RD_RATIO) bits will be added to the read address width to get the write address width, with the LSB's used for sub-words)
    localparam BLOCK_SEL_BITS = $clog2(RD_RATIO),
    localparam WR_ADDR = RD_ADDR + BLOCK_SEL_BITS // Address space for writes is larger because we write smaller words
) (
    input   wire                 clk,
    input   wire                 rd_en,
    input   wire[RD_ADDR-1 : 0]  rd_addr, 
    output  reg [RD_WORD-1 : 0]  rd_word,
    input   wire                 wr_en,
    input   wire[WR_ADDR-1 : 0]  wr_addr,
    input   wire[WR_WORD-1 : 0]  wr_word
);
    // If you require a different word size for writing vs. reading (e.g. write 32 bits for standard system bus,
    // read 128-bits to feed a wide interface), you can use this module to "reshape" your memory.
    // The read address space is specified by RD_ADDR (e.g. 10 bits for 1024 addresses)
    // The write address space has LSB's appended to index individual words in that address space, so it is larger by $clog2(RD_RATIO) bits

    // Example:
    // 32-bit writes, 512-bit reads (16 read words)
    // WR_WORD = 32
    // RD_ADDR = 4
    // RD_RATIO = 16
    // Writes to address 0000_0000 will affect bits 31:0 of the read word at address 0
    // Writes to address 0000_1111 will affect bits 511:480 of the read word at address 0
    // Writes to address 0001_0000 will affect bits 31:0 of the read word at address 1

    // Note that WR_WORD*(2**WR_ADDR) = RD_WORD*(2**RD_ADDR)
    // The RD_ADDR MSB's of WR_ADDR will line up with the RD_ADDR addresses
    // The LSB's will be used to identify which BRAM to write
    // Only one BRAM can write at a time
    // and only all BRAM's can read at a time

    /*
    // A simple behavioural implementation is shown below (but commented out)
    // However Vivado has trouble inferring block RAM's if the ratio
    // of read word size to write word size is too large - as far as I
    // can tell it won't allow more than a 256-bit read word for a 32-
    // bit write word
    // Because of this, I have implemented the RAM as multiple smaller RAMs
    // Each of which has a 32-bit word read and write port
    // Then we CONCATENATE the read data to get our larger read word
    // and demultiplex our write_en signal to only write to one smaller RAM at a time

    reg [WR_WORD-1 : 0] mem[2**WR_ADDR-1 : 0];

    always @(posedge clk) begin
        if (rd_en) begin
            for (int i = 0; i < RD_RATIO; i++) begin
                rd_word[i*WR_WORD +: WR_WORD] <= mem[rd_addr * RD_RATIO + i];
            end
        end
        if (wr_en) begin
            mem[wr_addr] <= wr_word;
        end
    end
    */

    // Implementation with multiple smaller RAMs
    
    logic [BLOCK_SEL_BITS-1:0] wr_block_select;
    logic [RD_ADDR-1:0] wr_addr_msbs;
    assign wr_block_select = wr_addr[BLOCK_SEL_BITS-1:0];
    assign wr_addr_msbs = wr_addr[WR_ADDR-1 : BLOCK_SEL_BITS];

    genvar i;
    generate for (i=0; i<RD_RATIO; i=i+1) begin : gen_rams
        logic [WR_WORD-1 : 0] mem [(2**RD_ADDR)-1:0];
        always @(posedge clk) begin
            if (rd_en) begin
                rd_word[i*WR_WORD +: WR_WORD] <= mem[rd_addr];
            end
            if (wr_en && (wr_block_select == i)) begin
                mem[wr_addr_msbs] <= wr_word;
            end
        end
    end endgenerate
endmodule


module ram_2port_tb;
    parameter WR_WORD = 32;
    parameter RD_WORD = 64;
    parameter RD_ADDR = 3;
    localparam RD_RATIO = RD_WORD / WR_WORD;
    localparam WR_ADDR = RD_ADDR + $clog2(RD_RATIO);

    reg clk;
    reg rd_en;
    reg [RD_ADDR-1 : 0] rd_addr;
    wire [RD_WORD-1 : 0] rd_word;
    reg wr_en;
    reg [WR_ADDR-1 : 0] wr_addr;
    reg [WR_WORD-1 : 0] wr_word;

    ram_2port #(
        .WR_WORD(WR_WORD),
        .RD_WORD(RD_WORD),
        .RD_ADDR(RD_ADDR)
    ) dut (
        .clk(clk),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_word(rd_word),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_word(wr_word)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    logic [$clog2(RD_RATIO)-1:0] random_word_index;
    logic [RD_ADDR-1:0] random_addr;
    logic [WR_WORD-1:0] random_wr_word;
    logic [RD_WORD-1 : 0] original_data, modified_data, read_back_data;

    int i;

    initial begin
        rd_en   = 0;
        rd_addr = 0;
        // Test writing and reading back a single word
        wr_en = 1;
        for (i = 0; i < 2**WR_ADDR; i++) begin // write random data to all addresses
            wr_addr = i;
            wr_word = $urandom;
            @(posedge clk); #3
            $display("Wrote %h to address %h (i.e. %d.%d)", wr_word, wr_addr, dut.wr_addr_msbs, dut.wr_block_select);
        end
        wr_en = 0;

        repeat (10) begin
            // Read a random address
            // Overwrite one of the words in that address
            // Verify that the new word is read back correctly and the others are unchanged
            random_addr       = $urandom_range(0,2**RD_ADDR-1);
            random_word_index = $urandom_range(0,RD_RATIO-1);
            random_wr_word = $urandom;
            
            // Read the original data
            rd_en   = 1;
            rd_addr = random_addr;
            @(posedge clk); #3
            rd_en = 0;
            original_data = rd_word;

            // Modify one word
            modified_data = original_data;
            modified_data[random_word_index*WR_WORD +: WR_WORD] = random_wr_word;

            // Write the modified data back
            wr_en   = 1;
            wr_addr = (random_addr << $clog2(RD_RATIO)) + random_word_index; // Calculate the write address
            wr_word = random_wr_word;
            @(posedge clk); #3 // TODO fix hack: using #3 to make sure wires are updated AFTER clock edge, but this is not best practice
            wr_en = 0;

            // Read back the data
            rd_en   = 1;
            rd_addr = random_addr;
            @(posedge clk); #3
            rd_en = 0;
            read_back_data = rd_word;

            $display("\nTesting address %h, word index %h", random_addr, random_word_index);
            $display("Original data: %h", original_data);
            $display("New word: %h", random_wr_word);
            $display("Modified data: %h", modified_data);
            $display("Read back data: %h", read_back_data);
            if (read_back_data !== modified_data) begin
                $display("[FAIL] Test failed at address %h", random_addr);
            end else begin
                $display("[PASS] Test passed at address %h", random_addr);
            end
        end

        rd_en   = 0;
        rd_addr = 0;
        @(posedge clk); #3
        
        $finish;
    end
endmodule