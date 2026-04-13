`timescale 1ns / 1ps

/**
 * 2-port (1 read, 1 write) RAM
 */

module ram_2port #(
    parameter WORD = 32, // Size of the words on the write port (in bits)
    parameter ADDR = 10 // Size of the address on the read port (size of the write port address will be inferred from this and the ratio)
) (
    input   wire                   clk,
    input   wire                   rd_en,
    input   wire  [   ADDR-1 : 0]  rd_addr,
    output  logic [   WORD-1 : 0]  rd_word,
    input   wire                   wr_en,
    input   wire  [   ADDR-1 : 0]  wr_addr,
    input   wire  [   WORD-1 : 0]  wr_word
);
    logic [WORD-1 : 0] mem [2**ADDR-1 : 0];
    
    always_ff @(posedge clk) begin
        if (rd_en) rd_word <= mem[rd_addr];
        if (wr_en) mem[wr_addr] <= wr_word;
    end
    // Vivado should infer a simply dual-port BRAM here
endmodule