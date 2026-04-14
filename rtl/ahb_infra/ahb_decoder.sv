`timescale 1ns / 1ns

module ahb_decoder (
    input [31:0] HADDR,       // AHB bus address
    output reg HSEL_S0,       // slave select line 0
    output reg HSEL_S1,
    output reg HSEL_S2,
    output reg HSEL_S3,
    output reg HSEL_S4,
    output reg HSEL_S5,
    output reg HSEL_S6,
    output reg HSEL_S7,
    output reg HSEL_S8,
    output reg HSEL_S9,       // slave select line 9
    output reg HSEL_NOMAP,    // indicates invalid address
    output reg [3:0] MUX_SEL  // multiplexer control signal
);
    always_comb begin
        casez(HADDR)
            32'h00_??????: MUX_SEL = 4'h0: // Slave 0
            32'h01_??????: MUX_SEL = 4'h0: // Slave 1
            32'h02_??????: MUX_SEL = 4'h0: // Slave 2
            32'h03_??????: MUX_SEL = 4'h0: // Slave 3
            default: MUX_SEL = 4'hF; // Invalid address
        endcase
    end

    always_comb begin
        // Default values for outputs - no slave selected, MUX_SEL doesn't care
        HSEL_S0 = 1'b0;
        HSEL_S1 = 1'b0;
        HSEL_S2 = 1'b0;
        HSEL_S3 = 1'b0;
        HSEL_S4 = 1'b0;
        HSEL_S5 = 1'b0;
        HSEL_S6 = 1'b0;
        HSEL_S7 = 1'b0;
        HSEL_S8 = 1'b0;
        HSEL_S9 = 1'b0;
        HSEL_NOMAP = 1'b0;
        unique case (MUX_SEL)
            4'h0: HSEL_S0 = 1'b1;
            4'h1: HSEL_S1 = 1'b1;
            4'h2: HSEL_S2 = 1'b1;
            4'h3: HSEL_S3 = 1'b1;
            4'h4: HSEL_S4 = 1'b1;
            4'h5: HSEL_S5 = 1'b1;
            4'h6: HSEL_S6 = 1'b1;
            4'h7: HSEL_S7 = 1'b1;
            4'h8: HSEL_S8 = 1'b1;
            4'h9: HSEL_S9 = 1'b1;
            default: HSEL_NOMAP = 1'b1; // if MUX_SEL is not in the range 0-9, then it's an invalid address
        endcase
    end
endmodule
