`timescale 1ns / 1ps

/**
 * 2-port (1 read, 1 write) RAM
 *
 *
 */


module imem_ram #(
    parameter ADDR_W = 10
) (
    input   wire                 clk,
    input   wire                 rd_en,
    input   wire[ ADDR_W-1 : 0]  rd_addr, 
    output  reg [    32-1 : 0]  rd_word,
    input   wire                 wr_en,
    input   wire[ ADDR_W-1 : 0]  wr_addr,
    input   wire[     32-1 : 0]  wr_word
);
    logic [31:0] mem [0:(2**ADDR_W)-1]; // Vivado should infer block ram here
    always @ (posedge clk) begin
        if (rd_en) begin
            rd_word <= mem[rd_addr];
        end
        if (wr_en) begin
            mem[wr_addr] <= wr_word;
        end
    end
endmodule
