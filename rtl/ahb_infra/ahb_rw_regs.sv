`timescale 1ns/1ps

// Simple AHB register slave.
// Creates NUM_REGS read/write flops at consecutive word-aligned
// addresses (0x0, 0x4, 0x8, ...). Accesses beyond the register
// space return zero with an OKAY response.
module ahb_rw_regs #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 4
) (
    input HCLK,
    input HRESETn,
    ahb_intf_s.slave bus,
    output [DATA_WIDTH-1:0] regs_out [NUM_REGS]
);

    // HTRANS encodings
    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_BUSY   = 2'b01;

    // ---------- Register storage ----------
    logic [DATA_WIDTH-1:0] regs [NUM_REGS];
    assign regs_out = regs;  // expose register values for testbench checking

    // ---------- Address-phase sampling ----------
    // Latch address-phase signals so they are available during the
    // data phase (one cycle later).
    logic [ADDR_WIDTH-1:0] addr_q;
    logic                  write_q;
    logic                  valid_q;  // address phase was a real transfer

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            addr_q  <= '0;
            write_q <= 1'b0;
            valid_q <= 1'b0;
        end else if (bus.HREADY) begin
            addr_q  <= bus.HADDR;
            write_q <= bus.HWRITE;
            valid_q <= bus.HSEL && (bus.HTRANS != HTRANS_IDLE) && (bus.HTRANS != HTRANS_BUSY);
        end
    end

    // ---------- Address decode ----------
    // Word index = address >> 2 (4-byte spacing)
    localparam int IDX_BITS = $clog2(NUM_REGS);
    logic [IDX_BITS-1:0] reg_idx;
    logic                addr_hit;

    assign reg_idx  = addr_q[2 +: IDX_BITS];
    assign addr_hit = (addr_q[ADDR_WIDTH-1:2+IDX_BITS] == '0) && (reg_idx < NUM_REGS);

    // ---------- Write logic (data phase) ----------
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            for (int i = 0; i < NUM_REGS; i++)
                regs[i] <= '0;
        end else if (valid_q && write_q && addr_hit) begin
            regs[reg_idx] <= bus.HWDATA;
        end
    end

    // ---------- Read logic (data phase, combinational) ----------
    always_comb begin
        if (valid_q && !write_q && addr_hit)
            bus.HRDATA = regs[reg_idx];
        else
            bus.HRDATA = '0;
    end

    // ---------- Response ----------
    // Always ready, never error
    assign bus.HREADYOUT = 1'b1;
    assign bus.HRESP     = 1'b0;  // OKAY

endmodule
