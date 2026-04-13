`timescale 1ns/1ps

module ahb_ro_regs_tb;

    // ---------- Parameters ----------
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam NUM_REGS   = 8;
    localparam CLK_PERIOD = 10;

    // ---------- Clock and reset ----------
    logic hclk;
    logic hresetn;

    initial hclk = 0;
    always #(CLK_PERIOD/2) hclk = ~hclk;

    // ---------- Interface ----------
    ahb_intf #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) bus (.hclk(hclk), .hresetn(hresetn));

    // Tie hready to hreadyout (single-slave, no mux)
    assign bus.hready = bus.hreadyout;

    // ---------- Status register inputs ----------
    logic [DATA_WIDTH-1:0] regs_in [NUM_REGS];

    // ---------- DUT ----------
    ahb_ro_regs #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_REGS   (NUM_REGS)
    ) dut (
        .bus     (bus),
        .regs_in (regs_in)
    );

    // ---------- Master model ----------
    ahb_master #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .TIMEOUT_CYCLES (100)
    ) master (
        .bus (bus)
    );

    // ---------- Helpers ----------
    int pass_count;
    int fail_count;

    task automatic check(string name, logic [DATA_WIDTH-1:0] expected, logic [DATA_WIDTH-1:0] actual);
        if (expected === actual) begin
            $display("[PASS] %s: 0x%08h", name, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected 0x%08h, got 0x%08h", name, expected, actual);
            fail_count++;
        end
    endtask

    task automatic check_bit(string name, logic expected, logic actual);
        if (expected === actual) begin
            $display("[PASS] %s: %0b", name, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected %0b, got %0b", name, expected, actual);
            fail_count++;
        end
    endtask

    task automatic reset();
        hresetn = 0;
        repeat (3) @(posedge hclk);
        hresetn = 1;
        @(posedge hclk);
    endtask

    // ---------- Test sequence ----------
    logic [DATA_WIDTH-1:0] rdata;

    initial begin
        pass_count = 0;
        fail_count = 0;

        // Initialise regs_in to zero
        for (int i = 0; i < NUM_REGS; i++)
            regs_in[i] = '0;

        // =============================================
        // Test 1: Read all registers when inputs are zero
        // =============================================
        $display("\n=== Test 1: Read zeros ===");
        reset();
        for (int i = 0; i < NUM_REGS; i++) begin
            master.read(i * 4, rdata);
            check($sformatf("reg[%0d] read zero", i), 32'h0, rdata);
        end

        // =============================================
        // Test 2: Set regs_in and read back via AHB
        // =============================================
        $display("\n=== Test 2: Set regs_in, read via AHB ===");
        for (int i = 0; i < NUM_REGS; i++)
            regs_in[i] = 32'hBEEF_0000 + i;

        for (int i = 0; i < NUM_REGS; i++) begin
            master.read(i * 4, rdata);
            check($sformatf("reg[%0d] read back", i), 32'hBEEF_0000 + i, rdata);
        end

        // =============================================
        // Test 3: Change a single input and verify
        // =============================================
        $display("\n=== Test 3: Change single input ===");
        regs_in[3] = 32'hCAFE_BABE;
        master.read(32'hC, rdata);
        check("reg[3] updated", 32'hCAFE_BABE, rdata);
        // Neighbour unchanged
        master.read(32'h8, rdata);
        check("reg[2] unchanged", 32'hBEEF_0002, rdata);

        // =============================================
        // Test 4: Write transaction gets ERROR response
        // =============================================
        $display("\n=== Test 4: Write returns ERROR ===");
        // Perform a write and check hresp during the data phase
        fork
            master.write(32'h0, 32'h1234_5678);
            begin
                // Wait until the slave signals a valid data phase with write
                @(posedge hclk);  // align
                // Wait for the data phase (valid_q && write_q asserted)
                wait (dut.valid_q && dut.write_q);
                @(negedge hclk);
                check_bit("hresp ERROR on write", 1'b1, bus.hresp);
            end
        join

        // =============================================
        // Test 5: Read after failed write — data unchanged
        // =============================================
        $display("\n=== Test 5: Read after failed write ===");
        master.read(32'h0, rdata);
        check("reg[0] still matches regs_in", regs_in[0], rdata);

        // =============================================
        // Test 6: Read does NOT produce an error
        // =============================================
        $display("\n=== Test 6: Read has OKAY response ===");
        fork
            master.read(32'h4, rdata);
            begin
                @(posedge hclk);
                wait (dut.valid_q && !dut.write_q);
                @(negedge hclk);
                check_bit("hresp OKAY on read", 1'b0, bus.hresp);
            end
        join
        check("reg[1] value correct", regs_in[1], rdata);

        // =============================================
        // Summary
        // =============================================
        $display("\n========================================");
        $display("  PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        $display("========================================\n");
        if (fail_count > 0)
            $fatal(1, "TEST FAILED");
        else
            $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
