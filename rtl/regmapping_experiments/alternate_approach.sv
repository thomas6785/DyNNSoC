interface reg_if (clk,rst);
    logic       byte_write [NUM_BYTES-1:0]; // master to slave
    logic       byte_read  [NUM_BYTES-1:0]; // master to slave
    logic [7:0] wdata;                      // master to slave
    logic       rdata [(NUM_BYTES*8)-1:0];  // slave to master
    logic       ready [(NUM_BYTES*8)-1:0];  // slave to master (a ready signal for every single bit may seem wasteful, but synthesis will the vast majority, and it means we can flexibly treat any subset of bits as their own field with their own behaviour)
    logic       error [(NUM_BYTES*8)-1:0];  // slave to master (^ ditto)
endinterface

module config_field #(
    parameter BYTE_ADDR = 0,
    parameter LSB = 0,
    parameter MSB = 7,
    parameter DEFAULT_VALUE = 0
) (
    reg_if REG_IF,
    output [MSB-LSB:0] value_out
);
    logic [MSB-LSB:0] reg_value;
    always_ff @ (posedge REG_IF.clk or negedge REG_IF.rst) begin
        if (!REG_IF.rst)                        reg_value <= DEFAULT_VALUE;
        else if (REG_IF.byte_write[BYTE_ADDR])  reg_value <= REG_IF.wdata[MSB:LSB];
        else                                    reg_value <= reg_value;
    end

    assign value_out = reg_value;
    assign REG_IF.rdata[(BYTE_ADDR*8)+MSB:(BYTE_ADDR*8)+LSB] = reg_value;
    assign REG_IF.ready[(BYTE_ADDR*8)+MSB:(BYTE_ADDR*8)+LSB] = '1;
    assign REG_IF.error[(BYTE_ADDR*8)+MSB:(BYTE_ADDR*8)+LSB] = '0;
endmodule

module ahb_regmap (

) (
    logic       wr_en [NUM_BYTES-1:0]; // master to slave
    logic       rd_en [NUM_BYTES-1:0]; // master to slave
    logic [7:0] wdata [NUM_BYTES-1:0]; // master to slave
    logic [7:0] rdata [NUM_BYTES-1:0]; // slave to master
    logic       ready [NUM_BYTES-1:0]; // slave to master
    logic       error [NUM_BYTES-1:0]; // slave to master
);
endmodule

/*
Sample instantiation

typedef struct packed {

} cfg_regs_t;

wor  reg_error;
wand reg_ready;
config_reg #( .WIDTH(32). ADDR(32'h0000_0000) ) mixing_mode_reg (  )

*/