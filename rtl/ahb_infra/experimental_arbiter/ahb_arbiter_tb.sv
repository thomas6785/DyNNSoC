`timescale 1ns / 1ps

// CAUTION:
// This testbench is AI-generated
// It was generated using a different model and agent to the DUT
// and inspected by me (Thomas O'Dea)
// However it should still be viewed with caution
// Ideally we would use a formal TB instead as they are best suited to
// bus protocol verification and are less error-prone than directed tests like this one
// but I don't have access to formal tools

module ahb_arbiter_tb;

    // ---------- Parameters ----------
    localparam ADDR_WIDTH  = 32;
    localparam DATA_WIDTH  = 32;
    localparam CLK_PERIOD  = 10;

    // HTRANS encodings
    localparam HTRANS_IDLE   = 2'b00;
    localparam HTRANS_NONSEQ = 2'b10;

    // ---------- Clock and reset ----------
    logic hclk;
    logic hresetn;

    initial hclk = 0;
    always #(CLK_PERIOD/2) hclk = ~hclk;

    // ---------- Interface instances ----------
    ahb_intf #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) ext_bus  (.hclk(hclk), .hresetn(hresetn));
    ahb_intf #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) core_bus (.hclk(hclk), .hresetn(hresetn));
    ahb_intf #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dmac_bus (.hclk(hclk), .hresetn(hresetn));
    ahb_intf #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) s_bus    (.hclk(hclk), .hresetn(hresetn));

    logic ext_hgrant, core_hgrant, dmac_hgrant;

    // ---------- DUT ----------
    ahb_arbiter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .hclk       (hclk),
        .hresetn    (hresetn),
        .ext_bus    (ext_bus),
        .core_bus   (core_bus),
        .dmac_bus   (dmac_bus),
        .ext_hgrant (ext_hgrant),
        .core_hgrant(core_hgrant),
        .dmac_hgrant(dmac_hgrant),
        .s_bus      (s_bus)
    );

    // ---------- Simple slave model (always ready, no error) ----------
    assign s_bus.hreadyout = 1'b1;
    assign s_bus.hresp     = 1'b0;
    assign s_bus.hrdata    = 32'hDEAD_BEEF;

    // ---------- Helpers ----------
    int test_pass_count;
    int test_fail_count;

    task automatic reset();
        hresetn = 0;
        idle_ext(); idle_core(); idle_dmac();
        repeat (3) @(posedge hclk);
        hresetn = 1;
        @(posedge hclk);
    endtask

    // --- Drive / idle helpers for each named master ---
    task automatic drive_ext(logic [31:0] addr, logic wr);
        ext_bus.haddr  = addr;
        ext_bus.hsize  = 3'b010;
        ext_bus.htrans = HTRANS_NONSEQ;
        ext_bus.hwrite = wr;
        if (wr) ext_bus.hwdata = addr;
    endtask

    task automatic drive_core(logic [31:0] addr, logic wr);
        core_bus.haddr  = addr;
        core_bus.hsize  = 3'b010;
        core_bus.htrans = HTRANS_NONSEQ;
        core_bus.hwrite = wr;
        if (wr) core_bus.hwdata = addr;
    endtask

    task automatic drive_dmac(logic [31:0] addr, logic wr);
        dmac_bus.haddr  = addr;
        dmac_bus.hsize  = 3'b010;
        dmac_bus.htrans = HTRANS_NONSEQ;
        dmac_bus.hwrite = wr;
        if (wr) dmac_bus.hwdata = addr;
    endtask

    task automatic idle_ext();
        ext_bus.haddr = '0; ext_bus.htrans = HTRANS_IDLE;
        ext_bus.hwrite = '0; ext_bus.hwdata = '0;
    endtask

    task automatic idle_core();
        core_bus.haddr = '0; core_bus.htrans = HTRANS_IDLE;
        core_bus.hwrite = '0; core_bus.hwdata = '0;
    endtask

    task automatic idle_dmac();
        dmac_bus.haddr = '0; dmac_bus.htrans = HTRANS_IDLE;
        dmac_bus.hwrite = '0; dmac_bus.hwdata = '0;
    endtask

    task automatic check(string name, logic [31:0] expected, logic [31:0] actual);
        if (expected === actual) begin
            $display("[PASS] %s: expected 0x%08h, got 0x%08h", name, expected, actual);
            test_pass_count++;
        end else begin
            $display("[FAIL] %s: expected 0x%08h, got 0x%08h", name, expected, actual);
            test_fail_count++;
        end
    endtask

    // ---------- Tests ----------

    // Test 1: ext alone — should be granted
    task automatic test_ext_alone();
        $display("\n=== Test 1: ext alone ===");
        reset();
        drive_ext(32'hEE00_0000, 1'b0);
        @(posedge hclk); @(negedge hclk);
        check("ext granted",    1, {31'b0, ext_hgrant});
        check("Slave sees addr", 32'hEE00_0000, s_bus.haddr);
        idle_ext();
        @(posedge hclk);
    endtask

    // Test 2: core alone — should be granted
    task automatic test_core_alone();
        $display("\n=== Test 2: core alone ===");
        reset();
        drive_core(32'hCC00_0000, 1'b1);
        @(posedge hclk); @(negedge hclk);
        check("core granted",   1, {31'b0, core_hgrant});
        check("Slave sees addr", 32'hCC00_0000, s_bus.haddr);
        idle_core();
        @(posedge hclk);
    endtask

    // Test 3: dmac alone — should be granted
    task automatic test_dmac_alone();
        $display("\n=== Test 3: dmac alone ===");
        reset();
        drive_dmac(32'hDD00_0000, 1'b0);
        @(posedge hclk); @(negedge hclk);
        check("dmac granted",   1, {31'b0, dmac_hgrant});
        check("Slave sees addr", 32'hDD00_0000, s_bus.haddr);
        idle_dmac();
        @(posedge hclk);
    endtask

    // Test 4: ext beats core and dmac (strict priority)
    task automatic test_ext_beats_all();
        $display("\n=== Test 4: ext > core > dmac priority ===");
        reset();
        drive_ext(32'hEE00_0000, 1'b0);
        drive_core(32'hCC00_0000, 1'b1);
        drive_dmac(32'hDD00_0000, 1'b0);
        @(posedge hclk); @(negedge hclk);
        check("ext wins",       1, {31'b0, ext_hgrant});
        check("core denied",    0, {31'b0, core_hgrant});
        check("dmac denied",    0, {31'b0, dmac_hgrant});
        check("Slave sees ext", 32'hEE00_0000, s_bus.haddr);
        idle_ext(); idle_core(); idle_dmac();
        @(posedge hclk);
    endtask

    // Test 5: core beats dmac when ext is idle
    task automatic test_core_beats_dmac();
        $display("\n=== Test 5: core > dmac (ext idle) ===");
        reset();
        drive_core(32'hCC00_0000, 1'b0);
        drive_dmac(32'hDD00_0000, 1'b1);
        @(posedge hclk); @(negedge hclk);
        check("core wins",       1, {31'b0, core_hgrant});
        check("dmac denied",     0, {31'b0, dmac_hgrant});
        check("Slave sees core", 32'hCC00_0000, s_bus.haddr);
        idle_core(); idle_dmac();
        @(posedge hclk);
    endtask

    // Test 6: ext preempts after core was granted
    task automatic test_ext_preempts_core();
        $display("\n=== Test 6: ext preempts core ===");
        reset();

        // core gets the bus first
        drive_core(32'hCC00_0000, 1'b0);
        @(posedge hclk); @(negedge hclk);
        check("core granted initially", 1, {31'b0, core_hgrant});

        // ext comes in — should take over next cycle
        drive_ext(32'hEE00_0000, 1'b1);
        @(posedge hclk); @(negedge hclk);
        check("ext preempts",    1, {31'b0, ext_hgrant});
        check("Slave sees ext",  32'hEE00_0000, s_bus.haddr);

        idle_ext(); idle_core();
        @(posedge hclk);
    endtask

    // Test 7: No requests — bus idle
    task automatic test_no_request();
        $display("\n=== Test 7: No active requests ===");
        reset();
        repeat (3) @(posedge hclk);
        @(negedge hclk);
        check("Slave htrans idle", HTRANS_IDLE, {30'b0, s_bus.htrans});
    endtask

    // ---------- Main ----------
    initial begin
        test_pass_count = 0;
        test_fail_count = 0;

        test_ext_alone();
        test_core_alone();
        test_dmac_alone();
        test_ext_beats_all();
        test_core_beats_dmac();
        test_ext_preempts_core();
        test_no_request();

        $display("\n========================================");
        $display("  Results: %0d PASSED, %0d FAILED", test_pass_count, test_fail_count);
        $display("========================================\n");

        if (test_fail_count > 0)
            $fatal(1, "Some tests FAILED");
        else
            $display("All tests PASSED");

        $finish;
    end

endmodule
