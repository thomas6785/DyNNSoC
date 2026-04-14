`timescale 1ns/1ps

module mvutop_wrapper_tb;

import mvu_pkg::*;

// ---- Clock and reset ----
logic HCLK = 0;
logic HRESETn;
logic [NMVU-1:0] irq;

always #10 HCLK = ~HCLK; // 50 MHz

// ---- AHB interface ----
ahb_intf_s ahb_if();
assign ahb_if.HREADY = ahb_if.HREADYOUT; // single slave

// ---- DUT ----
mvutop_wrapper dut (
    .HCLK    (HCLK),
    .HRESETn (HRESETn),
    .irq     (irq),
    .AHB_IF  (ahb_if)
);

// ---- Address helpers ----
// {reg_type[27:24], mvu_id[23:20], reserved[19:18], addr[17:2], byte_sel[1:0]}
localparam [3:0] REG_DATA   = 4'h0;
localparam [3:0] REG_WEIGHT = 4'h1;
localparam [3:0] REG_BIAS   = 4'h2;
localparam [3:0] REG_SCALER = 4'h3;
localparam [3:0] REG_CSR    = 4'h4;

function automatic [31:0] make_addr(
    input [3:0] reg_type,
    input [3:0] mvu_id,
    input [15:0] addr
);
    make_addr = {4'b0, reg_type, mvu_id, 2'b00, addr, 2'b00};
endfunction

task automatic ahb_write(input [31:0] addr, input [31:0] data);
    wait (ahb_if.HREADY);
    @(posedge HCLK); #1;
    ahb_if.HADDR  = addr;
    ahb_if.HTRANS = 2'b10; // NONSEQ
    ahb_if.HWRITE = 1'b1;
    ahb_if.HSIZE  = 3'b010; // WORD
    ahb_if.HSEL   = 1'b1;
    ahb_if.HPROT  = 4'b0;

    wait (ahb_if.HREADY);
    @(posedge HCLK); #1;
    ahb_if.HWDATA = data;
    ahb_if.HTRANS = 2'b00; // IDLE
    ahb_if.HSEL   = 1'b0;
    ahb_if.HWRITE = 1'b0;
endtask

task automatic ahb_read(input [31:0] addr, output [31:0] data);
    wait (ahb_if.HREADY);
    @(posedge HCLK); #1;
    ahb_if.HADDR  = addr;
    ahb_if.HTRANS = 2'b10;
    ahb_if.HWRITE = 1'b0;
    ahb_if.HSIZE  = 3'b010;
    ahb_if.HSEL   = 1'b1;
    ahb_if.HPROT  = 4'b0;

    wait (ahb_if.HREADY);
    @(posedge HCLK); #1;
    ahb_if.HTRANS = 2'b00;
    ahb_if.HSEL   = 1'b0;

    // Data reads may stall (HREADYOUT depends on MVU grant)
    wait (ahb_if.HREADY);
    @(posedge HCLK);
    data = ahb_if.HRDATA;
    #1;
endtask

// ---- Test parameters ----
localparam NUM_ADDRS = 16;
localparam MVU_ID    = 4'd0;

// ---- Main test ----
integer i;
logic [31:0] wdata, rdata;
logic [31:0] addr;
integer errors = 0;

initial begin
    // Initialise bus to idle
    ahb_if.HADDR  = 32'b0;
    ahb_if.HTRANS = 2'b00;
    ahb_if.HWRITE = 1'b0;
    ahb_if.HSIZE  = 3'b010;
    ahb_if.HSEL   = 1'b0;
    ahb_if.HWDATA = 32'b0;
    ahb_if.HPROT  = 4'b0;

    // Assert reset
    HRESETn = 1'b0;
    repeat (5) @(posedge HCLK);
    HRESETn = 1'b1;
    repeat (5) @(posedge HCLK);

    $display("=== MVU Wrapper Testbench ===");

    // ---- Write phase ----
    // Data memory: addr[0] must be 0 for writes (addresses ending 000)
    $display("--- Write phase ---");
    for (i = 0; i < NUM_ADDRS; i = i + 1) begin
        addr  = make_addr(REG_DATA, MVU_ID, {i[14:0], 1'b0});
        wdata = 32'hA000_0000 + i;
        ahb_write(addr, wdata);
        $display("  Write [0x%08h] = 0x%08h", addr, wdata);
    end

    // ---- Read phase ----
    // Data memory: can read from addresses ending x00 (any addr[0])
    $display("--- Read phase ---");
    for (i = 0; i < NUM_ADDRS; i = i + 1) begin
        addr  = make_addr(REG_DATA, MVU_ID, {i[14:0], 1'b0});
        wdata = 32'hA000_0000 + i;
        ahb_read(addr, rdata);
        if (rdata !== wdata) begin
            $display("  ERROR: Read [0x%08h] = 0x%08h, expected 0x%08h", addr, rdata, wdata);
            errors = errors + 1;
        end else begin
            $display("  OK:    Read [0x%08h] = 0x%08h", addr, rdata);
        end
    end

    // Back-to-back write-then-read
    $display("--- Back-to-back write-then-read ---");
    for (i = 0; i < NUM_ADDRS; i = i + 1) begin
        addr  = make_addr(REG_DATA, MVU_ID, {i[14:0], 1'b0});
        wdata = 32'hB000_0000 + (i<<4);
        ahb_if.HTRANS = 2'b10; // NONSEQ
        ahb_if.HWRITE = 1'b1;
        ahb_if.HSIZE  = 3'b010;
        ahb_if.HSEL   = 1'b1;
        ahb_if.HPROT  = 4'b0011;
        ahb_if.HADDR  = addr;
        wait (ahb_if.HREADY); @(posedge HCLK); #1;
        ahb_if.HWDATA = wdata;

        ahb_if.HTRANS = 2'b10; // NONSEQ
        ahb_if.HWRITE = 1'b0; // read
        ahb_if.HSIZE  = 3'b010;
        ahb_if.HSEL   = 1'b1;
        ahb_if.HPROT  = 4'b0011;
        ahb_if.HADDR  = addr;
        wait (ahb_if.HREADY); @(posedge HCLK); #1;
        ahb_if.HTRANS = 2'b00; // IDLE
        ahb_if.HSEL   = 1'b0;
        wait (ahb_if.HREADY); @(posedge HCLK);
        rdata = ahb_if.HRDATA;

        if (rdata !== wdata) begin
            $display("  ERROR: Read [0x%08h] = 0x%08h, expected 0x%08h", addr, rdata, wdata);
            errors = errors + 1;
        end else begin
            $display("  OK:    Read [0x%08h] = 0x%08h", addr, rdata);
        end
    end

    // ---- Report ----
    $display("=== Test complete: %0d errors ===", errors);
    if (errors == 0) $display("PASS");
    else             $display("FAIL");

    $finish;
end

endmodule