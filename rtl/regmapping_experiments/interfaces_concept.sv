/*

This proposes a design for AHB-to-register-map interfacing
The idea is to have a simple byte-oriented interface for each register with signals for
wr_en, rd_en, wdata, rdata, ready, error

Then define a module capable of driving those interfaces (from an AHB slave interface)
and a library of modules for common register behaviours (read/write config, read-only status, sticky IRQ flag, etc.)

This gets tricky if we want a multi-byte register
It also gets tricky when it comes to aligning words

*/

interface reg_byte_if (clk,rst);
    logic       wr_en; // master to slave
    logic       rd_en; // master to slave
    logic [7:0] wdata; // master to slave
    logic [7:0] rdata; // slave to master
    logic       ready; // slave to master
    logic       error; // slave to master

    modport master ( output wr_en, rd_en, wdata, input  rdata, ready, error );
    modport slave  ( input  wr_en, rd_en, wdata, output rdata, ready, error );
endinterface

module ahb_regmap #(
    parameter NUM_REGS = 4
) (
    ahb_intf_s.slave AHB_IF,
    reg_byte_if.master reg_array[NUM_REGS-1:0]
);

endmodule

/*

Sample instantiation:

// Declare all registers
reg_byte_if control(clk,rst);       // 8-bit
reg_byte_if status(clk_rst);        // 8-bit
reg_byte_if dummy0(clk,rst);        // 8-bit, unused, here to word-align the data register
reg_byte_if dummy1(clk,rst);        // 8-bit, unused, here to word-align the data register
reg_byte_if [3:0] data(clk,rst);    // 32-bit word

// Hook them up to the AHB
ahb_regmap #(
    .NUM_REGS(4)
) my_regmap (
    .clk,
    .rst,
    .AHB_IF
    .reg_array({
        control, status, dummy0, dummy1,
        data
    }),
);

// Define their behaviour
config_byte (
    .reg_if(control),
    .value_out(control_value)
);

config_word spidata_config (
    .reg_array(data),
    .value_out(data_value)
);

status_byte status_impl (
    .reg_if(status),
    .value_in(status_value)
);

// This is... pretty clean? I don't like how multi-byte registers are handled, and I really don't like needing to include dummy registers
*/

module config_byte #(
    parameter DEFAULT_VALUE = 0
) (
    reg_byte_if.slave reg_if,
    output logic [7:0] value
);
    logic [7:0] stored_value;

    always_ff @ (posedge reg_if.clk or negedge reg_if.rst) begin
        if (!reg_if.rst)        stored_value <= DEFAULT_VALUE;
        else if (reg_if.wr_en)  stored_value <= reg_if.wdata;
        else                    stored_value <= stored_value;
    end

    assign value = stored_value;
    assign reg_if.rdata = stored_value;
    assign reg_if.ready = 1'b1; // always ready
    assign reg_if.error = 1'b0; // never error
endmodule

module config_word #(
    parameter DEFAULT_VALUE = 0,
    parameter NUM_BYTES = 4
) (
    reg_byte_if.slave reg_array[NUM_BYTES-1:0],
    output logic [(NUM_BYTES*8)-1:0] value
);
    genvar i;
    generate for (i = 0; i < NUM_BYTES; i++) begin
        config_byte #(
            .DEFAULT_VALUE((DEFAULT_VALUE >> (i*8)) & 8'hFF)
        ) I_config_byte (
            .reg_if(reg_array[i]),
            .value(value[(i*8)+7:(i*8)])
        );
    end endgenerate
endmodule

// Byte zero has special behaviours
    // bit 7 -
    // bit 6 -
    // bit 5 -
    // bit 4 -
    // bit 3 -
    // bit 2 - IRQ enable. Does not affect flag, only the outgoing IRQ line
    // bit 1 - IRQ flag. Write to clear
    // bit 0 - trigger. Reads zero. Writes cause a 'trigger' pulse into the hardware

/*
Pulse on write
Pulse on read
Read external
Write external

Read-write
Read-only
IRQ flag
IRQ enable

Use-case oriented taxonomy:
    IRQ flag (sticky wtc)
    IRQ enable (cfg)

    Read/write config
    Read-only status
    Custom behaviour registers (e.g. timer) need to be implemented externally

    'Trigger' pulses


*/