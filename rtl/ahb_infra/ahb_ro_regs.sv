`timescale 1ns/1ps

// Simple AHB read-only register slave.
// Exposes NUM_REGS status registers at consecutive word-aligned
// addresses (0x0, 0x4, 0x8, ...). Values are driven externally
// via regs_in. Write transactions receive an ERROR response.
module ahb_ro_regs #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 4
)(
    ahb_intf_s.slave bus,
    input [DATA_WIDTH-1:0] regs_in [NUM_REGS]
);

    // HTRANS encodings
    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_BUSY   = 2'b01;

    // ---------- Address-phase sampling ----------
    logic [ADDR_WIDTH-1:0] addr_q;
    logic                  write_q;
    logic                  valid_q;

    always_ff @(posedge bus.hclk or negedge bus.hresetn) begin
        if (!bus.hresetn) begin
            addr_q  <= '0;
            write_q <= 1'b0;
            valid_q <= 1'b0;
        end else if (bus.hready) begin
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

    // ---------- Read logic (data phase, combinational) ----------
    always_comb begin
        if (valid_q && !write_q && addr_hit)
            bus.hrdata = regs_in[reg_idx];
        else
            bus.hrdata = '0;
    end

    // ---------- Response ----------
    // Always ready; ERROR on writes, OKAY on reads
    assign bus.hreadyout = 1'b1;
    assign bus.hresp     = (valid_q && write_q) ? 1'b1 : 1'b0;

endmodule
