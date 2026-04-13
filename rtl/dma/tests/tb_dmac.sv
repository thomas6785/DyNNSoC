`timescale 1ns/1ps

module tb_dmac;

    // ---------- Parameters ----------
    localparam CLK_PERIOD  = 10;
    // Source regs: 0–15 (addr 0x00–0x3C)
    // Dest   regs: 32–47 (addr 0x80–0xBC)
    localparam NUM_REGS    = 48;
    localparam NUM_XFERS   = 16;
    localparam TIMEOUT     = 10000;

    // ---------- Clock and reset ----------
    logic hclk;
    logic hresetn;

    initial hclk = 0;
    always #(CLK_PERIOD/2) hclk = ~hclk;

    // ---------- AHB interface ----------
    ahb_intf_m #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dmac_bus_intf ( hclk, hresetn );
    ahb_intf_s #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) regs_bus_intf ( hclk, hresetn );
    ahb_1to1_interconnect interconn (
        .master (dmac_bus_intf.interconn),
        .slave  (regs_bus_intf.interconn)
    );

    // ---------- AHB slave: register file ----------
    logic [31:0] regs_out [NUM_REGS];

    ahb_rw_regs #(
        .NUM_REGS (NUM_REGS)
    ) slave (
        .bus      (regs_bus_intf),
        .regs_out (regs_out)
    );

    // ---------- DUT: DMA controller ----------
    logic        start_signal;
    logic [31:0] config_src_addr;
    logic [31:0] config_dest_addr;
    logic [15:0] config_transfer_size;
    logic        irq;

    dma dut (
        .dma_bus                 (dmac_bus_intf),
        .clk                     (hclk),
        .reset                   (hresetn),
        .start_signal            (start_signal),
        .config_in_src_addr      (config_src_addr),
        .config_in_dest_addr     (config_dest_addr),
        .config_in_transfer_size (config_transfer_size),
        .irq                     (irq)
    );

    // ---------- Helpers ----------
    int pass_count;
    int fail_count;

    task automatic check(string name, logic [31:0] expected, logic [31:0] actual);
        if (expected === actual) begin
            $display("[PASS] %s: 0x%08h", name, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected 0x%08h, got 0x%08h", name, expected, actual);
            fail_count++;
        end
    endtask

    // ---------- Test sequence ----------
    int i;
    initial begin
        //$dumpfile("tb_dmac.vcd");
        //$dumpvars(0, tb_dmac);

        pass_count = 0;
        fail_count = 0;

        // Initialise DMA config inputs
        start_signal         = 1'b0;
        config_src_addr      = 32'h0;
        config_dest_addr     = 32'h0;
        config_transfer_size = 16'h0;

        // ===== Reset =====
        hresetn = 1'b0;
        repeat (5) @(posedge hclk);
        hresetn = 1'b1;
        repeat (2) @(posedge hclk);

        // ===== Force initial data into source registers 0-15 =====
        $display("\n=== Loading source data into registers 0-15 ===");
        for (i = 0; i < NUM_XFERS; i++) begin
            slave.regs[i] = 32'hCAFE_0000 + i;
        end
        @(posedge hclk);

        // Sanity-check: source data is present
        for (i = 0; i < NUM_XFERS; i++) begin
            check($sformatf("src reg[%0d] init", i),
                  32'hCAFE_0000 + i, regs_out[i]);
        end

        // ===== Configure DMA =====
        $display("\n=== Configuring DMA: src=0x00, dest=0x80, count=%0d ===", NUM_XFERS);
        config_src_addr      = 32'h0000_0000;   // address 0   -> regs[0..15]
        config_dest_addr     = 32'h0000_0080;   // address 128 -> regs[32..47]
        config_transfer_size = NUM_XFERS;

        // ===== Start DMA =====
        @(posedge hclk);
        start_signal = 1'b1;
        @(posedge hclk);
        start_signal = 1'b0;

        // ===== Wait for DMA to finish =====
        $display("\n=== Waiting for DMA to complete ===");
        begin
            int cycles;
            logic seen_active;
            cycles      = 0;
            seen_active = 1'b0;
            while (cycles < TIMEOUT) begin
                @(posedge hclk);
                cycles++;
                // Track that the DMA left IDLE at least once
                if (dut.current_state != dut.IDLE_STATE)
                    seen_active = 1'b1;
                // Done when DMA returns to IDLE after having been active
                if (seen_active && dut.current_state == dut.IDLE_STATE) begin
                    $display("DMA completed after %0d cycles", cycles);
                    break;
                end
            end
            if (cycles >= TIMEOUT) begin
                $display("[FAIL] DMA did not complete within %0d cycles", TIMEOUT);
                fail_count++;
            end
        end

        // A few extra cycles for the final write to settle
        repeat (5) @(posedge hclk);

        // ===== Verify destination registers 32-47 =====
        $display("\n=== Verifying destination registers (regs 32-47) ===");
        for (i = 0; i < NUM_XFERS; i++) begin
            check($sformatf("dest reg[%0d]", 32 + i),
                  32'hCAFE_0000 + i,
                  regs_out[32 + i]);
        end

        // ===== Verify source registers 0-15 unchanged =====
        $display("\n=== Verifying source registers (regs 0-15) unchanged ===");
        for (i = 0; i < NUM_XFERS; i++) begin
            check($sformatf("src reg[%0d]", i),
                  32'hCAFE_0000 + i,
                  regs_out[i]);
        end

        // ===== Summary =====
        $display("\n========================================");
        $display("  PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count > 0)
            $display("*** TEST FAILED ***");
        else
            $display("*** TEST PASSED ***");

        $finish;
    end

endmodule