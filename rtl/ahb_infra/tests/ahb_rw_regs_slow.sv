`timescale 1ns/1ps

// AHB register slave with random wait states.
// Functionally identical to ahb_rw_regs READYOUT is only asserted randomly 1 in every 8 cycles
// This is to arbitrarily slow down registeres to exercise AHB infrastructure

// TODO KNOWN ISSUE:
// We are using !hreadyout to hold the value in valid_q, addr_q, write_q
// This means when a new transaction comes in after an idle, we might simply
// miss it if readyout happens to be low at that moment
// this works fine in an architecture where readyout defaults to high and only goes low when we are consciously inserting wait states
// but here we are using an LFSR to randomly drive readyout
// anyway we're not actually using these they're just for stress testing the DMA which seems to be working fine

module ahb_rw_regs #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 4,
    parameter     LFSR_SEED  = 23'h5A5A5A // seed for the LFSR
)(
    ahb_intf_s.slave bus,
    output [DATA_WIDTH-1:0] regs_out [NUM_REGS]
);

    // HTRANS encodings
    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_BUSY   = 2'b01;

    // ---------- LFSR for random wait time generation ----------
    localparam NLFSR_BITS = 3; // 3 bits gives a 12.5% chance of all bits being 1
    logic [NLFSR_BITS-1:0] lfsr_out;

    genvar i;
    generate for(i=0; i<NLFSR_BITS;i++) begin
        lfsr lfsr_inst (.clk(bus.hclk),.rst_n(bus.hresetn),.step(1'b1),.out(lfsr_out[i]),.seed(i+LFSR_SEED),.load_seed(1'b0));
    end endgenerate

    assign bus.hreadyout = &lfsr_out; // wait until all LFSR bits are 1 (12.5% chance each cycle)

    // ---------- Register storage ----------
    logic [DATA_WIDTH-1:0] regs [NUM_REGS];
    assign regs_out = regs;

    // ---------- Address-phase sampling ----------
    logic [ADDR_WIDTH-1:0] addr_q;
    logic                  write_q;
    logic                  valid_q;

    always_ff @(posedge bus.hclk or negedge bus.hresetn) begin
        if (!bus.hresetn) begin
            addr_q  <= '0;
            write_q <= 1'b0;
            valid_q <= 1'b0;
        end else if (bus.hreadyout) begin
            addr_q  <= bus.haddr;
            write_q <= bus.hwrite;
            valid_q <= bus.hsel && (bus.htrans != HTRANS_IDLE) && (bus.htrans != HTRANS_BUSY);
        end
    end

    // ---------- Address decode ----------
    localparam int IDX_BITS = $clog2(NUM_REGS);
    logic [IDX_BITS-1:0] reg_idx;
    logic                addr_hit;

    assign reg_idx  = addr_q[2 +: IDX_BITS];
    assign addr_hit = (addr_q[ADDR_WIDTH-1:2+IDX_BITS] == '0) && (reg_idx < NUM_REGS);

    // ---------- Write logic (data phase) ----------
    always_ff @(posedge bus.hclk or negedge bus.hresetn) begin
        if (!bus.hresetn) begin
            for (int i = 0; i < NUM_REGS; i++)
                regs[i] <= '0;
        end else if (valid_q && write_q && addr_hit && bus.hreadyout) begin
            regs[reg_idx] <= bus.hwdata;
        end
    end

    // ---------- Read logic (data phase, combinational) ----------
    always_comb begin
        if (valid_q && !write_q && addr_hit)
            bus.hrdata = regs[reg_idx];
        else
            bus.hrdata = '0;
    end

    // ---------- Response ----------
    assign bus.hresp = 1'b0;  // OKAY

endmodule
