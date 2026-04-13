module lfsr_array (
    input                    clk,
    input                    rst_n,
    input        [31:0]      wdata,
    output logic [31:0]      rdata,
    input        [4:0]       addr,
    input                    req,
    input                    we
);
    // Simple LFSR slave
    // There are 32 LFSRs each with a 23-bit shift register
    // Writing to an address loads the seed for that LFSR
    // Reading from any address will read the current state of all 32 LFSRs as a 32-bit value
    // LFSR's only update when read

    logic [31:0] rdata_internal;
    genvar i;
    generate for (i=0; i<32; i++) begin : gen_lfsr
        lfsr lfsr_i (
            .clk(clk),
            .rst_n(rst_n),
            .step(req && !we),
            .out(rdata_internal[i]),
            .seed(wdata[22:0]),
            .load_seed(req && we && addr == i)
        );
    end endgenerate

    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            rdata <= 32'b0;
        end else if (req && !we) begin
            rdata <= rdata_internal;
        end
    end
endmodule