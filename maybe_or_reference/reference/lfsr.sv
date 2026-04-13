`timescale 1ns/1ps

module lfsr (
  input                    clk,
  input                    rst_n,
  input                    step,
  output                   out,
  input        [22:0]      seed,
  input                    load_seed
);
    logic [22:0] state;

    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            state <= 23'h1;
        end else if (load_seed) begin
            state <= seed;
        end else if (step) begin
            state <= {state[21:0], state[22] ^ state[17]};
        end
    end

    assign out = state[22];
endmodule
