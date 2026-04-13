`timescale 1ns/1ps

module ahb_rw_regs_tb;

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
    // ---------- AHB interface ----------
    ahb_intf_m #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dmac_bus_intf ( hclk, hresetn );
    ahb_intf_s #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) regs_bus_intf ( hclk, hresetn );
    ahb_1to1_interconnect interconn (
        .master (dmac_bus_intf.interconn),
        .slave  (regs_bus_intf.interconn)
    );

    // ---------- DUT ----------
    logic [DATA_WIDTH-1:0] regs_out [NUM_REGS];

    ahb_rw_regs #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_REGS   (NUM_REGS)
    ) dut (
        .bus      (regs_bus_intf),
        .regs_out (regs_out)
    );

    // ---------- Master model ----------
    ahb_master #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .TIMEOUT_CYCLES (100)
    ) master (
        .bus (dmac_bus_intf)
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

        // =============================================
        // Test 1: All registers zero after reset
        // =============================================
        $display("\n=== Test 1: Registers zero after reset ===");
        reset();
        for (int i = 0; i < NUM_REGS; i++) begin
            check($sformatf("reg[%0d] after reset", i), 32'h0, regs_out[i]);
        end

        // =============================================
        // Test 2: Write and read back each register
        // =============================================
        $display("\n=== Test 2: Write then read each register ===");
        for (int i = 0; i < NUM_REGS; i++) begin
            master.write(i * 4, 32'hA000_0000 + i);
        end
        for (int i = 0; i < NUM_REGS; i++) begin
            master.read(i * 4, rdata);
            check($sformatf("read reg[%0d]", i), 32'hA000_0000 + i, rdata);
        end

        // =============================================
        // Test 3: Verify regs_out matches written data
        // =============================================
        $display("\n=== Test 3: regs_out port matches ===");
        for (int i = 0; i < NUM_REGS; i++) begin
            check($sformatf("regs_out[%0d]", i), 32'hA000_0000 + i, regs_out[i]);
        end

        // =============================================
        // Test 4: Overwrite a register and verify
        // =============================================
        $display("\n=== Test 4: Overwrite register 0 ===");
        master.write(32'h0, 32'hDEAD_BEEF);
        master.read(32'h0, rdata);
        check("reg[0] overwritten", 32'hDEAD_BEEF, rdata);
        // Other registers should be unaffected
        master.read(32'h4, rdata);
        check("reg[1] unchanged", 32'hA000_0001, rdata);

        // =============================================
        // Test 5: Write to all regs with unique pattern
        // =============================================
        $display("\n=== Test 5: Unique pattern write/read ===");
        for (int i = 0; i < NUM_REGS; i++) begin
            master.write(i * 4, (i + 1) * 32'h1111_1111);
        end
        for (int i = 0; i < NUM_REGS; i++) begin
            master.read(i * 4, rdata);
            check($sformatf("pattern reg[%0d]", i), (i + 1) * 32'h1111_1111, rdata);
        end

        // =============================================
        // Test 6: Reset clears all registers
        // =============================================
        $display("\n=== Test 6: Reset clears registers ===");
        reset();
        for (int i = 0; i < NUM_REGS; i++) begin
            master.read(i * 4, rdata);
            check($sformatf("reg[%0d] zero after 2nd reset", i), 32'h0, rdata);
        end

        // =============================================
        // Test 7: Pipelined write-all then read-all
        // =============================================
        $display("\n=== Test 7: Pipelined stress test ===");
        begin
            logic [31:0] seq_addr     [];
            logic [31:0] seq_data     [];
            logic        seq_is_write [];

            // Phase 1: pipelined writes to all registers
            seq_addr     = new[NUM_REGS];
            seq_data     = new[NUM_REGS];
            seq_is_write = new[NUM_REGS];
            for (int i = 0; i < NUM_REGS; i++) begin
                seq_addr[i]     = i * 4;
                seq_data[i]     = 32'hBEEF_0000 + i;
                seq_is_write[i] = 1'b1;
            end
            master.transaction_sequence(seq_addr, seq_data, seq_is_write,
                                        pass_count, fail_count);

            // Phase 2: pipelined reads to verify
            for (int i = 0; i < NUM_REGS; i++)
                seq_is_write[i] = 1'b0;
            master.transaction_sequence(seq_addr, seq_data, seq_is_write,
                                        pass_count, fail_count);

            // Phase 3: interleaved write-read-write-read (back-to-back mixed)
            seq_addr     = new[NUM_REGS * 2];
            seq_data     = new[NUM_REGS * 2];
            seq_is_write = new[NUM_REGS * 2];
            for (int i = 0; i < NUM_REGS; i++) begin
                // Write with new pattern
                seq_addr[i*2]       = i * 4;
                seq_data[i*2]       = 32'hFACE_0000 + i;
                seq_is_write[i*2]   = 1'b1;
                // Immediate read-back
                seq_addr[i*2+1]     = i * 4;
                seq_data[i*2+1]     = 32'hFACE_0000 + i;
                seq_is_write[i*2+1] = 1'b0;
            end
            master.transaction_sequence(seq_addr, seq_data, seq_is_write,
                                        pass_count, fail_count);
        end

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
