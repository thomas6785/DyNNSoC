`timescale 1ns/1ps

// CAUTION:
// This arbiter is AI-generated
// It was generated using a different model and agent to the testbench ahb_arbiter_tb.sv
// and inspected by me (Thomas O'Dea) but should still be used with caution

// Fixed-priority AHB arbiter for three masters: ext, core, dmac.
// Priority (highest to lowest): ext > core > dmac.
// Muxes the granted master's signals onto the slave-side bus and
// routes slave responses back to all masters.
module ahb_arbiter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic hclk,
    input  logic hresetn,

    // Master-side buses (named ports)
    ahb_intf_s.slave  ext_bus,
    ahb_intf_s.slave  core_bus,
    ahb_intf_s.slave  dmac_bus,

    // Grant signals (active-high, one-hot)
    output logic ext_hgrant,
    output logic core_hgrant,
    output logic dmac_hgrant,
    // TODO these can be removed - the masters can detect grant by monitoring the slave bus signals

    // Shared slave-side bus
    ahb_intf_m.master s_bus
);

    // HTRANS encoding
    localparam HTRANS_IDLE = 2'b00;

    // ---------- Request detection ----------
    logic ext_req, core_req, dmac_req;
    assign ext_req  = (ext_bus.htrans  != HTRANS_IDLE);
    assign core_req = (core_bus.htrans != HTRANS_IDLE);
    assign dmac_req = (dmac_bus.htrans != HTRANS_IDLE);

    // ---------- Grant selection (strict priority: ext > core > dmac) ----------
    typedef enum logic [1:0] {
        GRANT_EXT  = 2'd0,
        GRANT_CORE = 2'd1,
        GRANT_DMAC = 2'd2
    } grant_e;

    grant_e next_grant;
    grant_e grant_reg;

    always_comb begin
        if (ext_req)
            next_grant = GRANT_EXT;
        else if (core_req)
            next_grant = GRANT_CORE;
        else if (dmac_req)
            next_grant = GRANT_DMAC;
        else
            next_grant = grant_reg; // hold current grant when idle
    end

    // ---------- Grant register (update when bus is ready) ----------
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            grant_reg <= GRANT_EXT;
        else if (s_bus.hreadyout)
            grant_reg <= next_grant;
    end

    // ---------- Grant outputs ----------
    assign ext_hgrant  = (grant_reg == GRANT_EXT);
    assign core_hgrant = (grant_reg == GRANT_CORE);
    assign dmac_hgrant = (grant_reg == GRANT_DMAC);

    // ---------- Mux granted master onto slave bus ----------
    always_comb begin
        case (grant_reg)
            GRANT_EXT: begin
                s_bus.haddr  = ext_bus.haddr;
                s_bus.hsize  = ext_bus.hsize;
                s_bus.htrans = ext_bus.htrans;
                s_bus.hwdata = ext_bus.hwdata;
                s_bus.hwrite = ext_bus.hwrite;
            end
            GRANT_CORE: begin
                s_bus.haddr  = core_bus.haddr;
                s_bus.hsize  = core_bus.hsize;
                s_bus.htrans = core_bus.htrans;
                s_bus.hwdata = core_bus.hwdata;
                s_bus.hwrite = core_bus.hwrite;
            end
            GRANT_DMAC: begin
                s_bus.haddr  = dmac_bus.haddr;
                s_bus.hsize  = dmac_bus.hsize;
                s_bus.htrans = dmac_bus.htrans;
                s_bus.hwdata = dmac_bus.hwdata;
                s_bus.hwrite = dmac_bus.hwrite;
            end
            default: begin
                s_bus.haddr  = '0;
                s_bus.hsize  = '0;
                s_bus.htrans = HTRANS_IDLE;
                s_bus.hwdata = '0;
                s_bus.hwrite = '0;
            end
        endcase
    end

    // ---------- Route slave responses back to all masters ----------
    assign ext_bus.hrdata    = s_bus.hrdata;
    assign ext_bus.hreadyout = s_bus.hreadyout;
    assign ext_bus.hresp     = s_bus.hresp;

    assign core_bus.hrdata    = s_bus.hrdata;
    assign core_bus.hreadyout = s_bus.hreadyout;
    assign core_bus.hresp     = s_bus.hresp;

    assign dmac_bus.hrdata    = s_bus.hrdata;
    assign dmac_bus.hreadyout = s_bus.hreadyout;
    assign dmac_bus.hresp     = s_bus.hresp;

endmodule
