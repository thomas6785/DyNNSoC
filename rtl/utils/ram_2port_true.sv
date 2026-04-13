`timescale 1ns / 1ps

/**
 * 2-port (both read/write) RAM
 */

module ram_2port_true #(
    parameter WORD = 32, // Size of the words on the write port (in bits)
    parameter ADDR = 10 // Size of the address on the read port (size of the write port address will be inferred from this and the ratio)
) (
    input   wire                   clk,

    input   wire                   p1_en,
    input   wire   [  ADDR-1 : 0]  p1_addr,
    input   wire   [  WORD-1 : 0]  p1_din,
    output  logic  [  WORD-1 : 0]  p1_dout,
    input   wire                   p1_we,

    input   wire                   p2_en,
    input   wire   [  ADDR-1 : 0]  p2_addr,
    input   wire   [  WORD-1 : 0]  p2_din,
    output  logic  [  WORD-1 : 0]  p2_dout,
    input   wire                   p2_we
);
    logic [WORD-1 : 0] mem [2**ADDR-1 : 0];
    
    always_ff @(posedge clk)
        if (p1_en && p1_we) mem[p1_addr] <= p1_din;

    always_ff @ (posedge clk)
        if (p2_en && p2_we) mem[p2_addr] <= p2_din;

    always_ff @ (posedge clk)
        if (p1_en && ~p1_we) p1_dout <= mem[p1_addr];

    always_ff @ (posedge clk)
        if (p2_en && ~p2_we) p2_dout <= mem[p2_addr];

    // Vivado insists we use a separate "always" block for each read/write port or it won't infer BRAM
endmodule
