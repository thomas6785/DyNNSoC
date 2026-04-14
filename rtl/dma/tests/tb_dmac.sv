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
    logic HCLK;
    logic HRESETn;

    initial HCLK = 0;
    always #(CLK_PERIOD/2) HCLK = ~HCLK;

    // ---------- AHB interfaces ----------
    ahb_intf_s #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) config_intf (); // drives the DMA
    ahb_intf_m #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dmac_bus_intf (); // driven by the DMA
    ahb_intf_s #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) regs_bus_intf (); // drives the test registers
    // Hook up the DMA to the test registers
    ahb_1to1_interconnect interconn (
        .master (dmac_bus_intf.interconn),
        .slave  (regs_bus_intf.interconn)
    );

    // ---------- AHB slave: register file ----------
    logic [31:0] regs_out [NUM_REGS];

    ahb_rw_regs #(
        .NUM_REGS (NUM_REGS)
    ) slave (
        .HCLK,
        .HRESETn,
        .bus      (regs_bus_intf),
        .regs_out (regs_out)
    );

    // ---------- DUT: DMA controller ----------
    logic        start_signal;
    logic [31:0] config_src_addr;
    logic [31:0] config_dest_addr;
    logic [15:0] config_transfer_size;
    logic        irq;

    ahb_dma dut (
        .HCLK,
        .HRESETn,
        .master_if               (dmac_bus_intf),
        .config_if               (config_intf),
        .irq_flag                (irq)
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

    assign config_intf.HREADY = config_intf.HREADYOUT;
    assign config_intf.HSEL = 1'b1;

    `define AHB_WRITE(addr,data)   config_intf.HTRANS <= 2'b10; config_intf.HWRITE <= 1; config_intf.HADDR <= addr;   @(posedge HCLK iff config_intf.HREADYOUT); config_intf.HWDATA <= data;
    `define AHB_IDLE               config_intf.HTRANS <= 2'b00;
    `define AHB_FINISH             config_intf.HTRANS <= 2'b00; @(posedge HCLK iff config_intf.HREADYOUT);

    // ---------- Test sequence ----------
    int i;
    initial begin
        //$dumpfile("tb_dmac.vcd");
        //$dumpvars(0, tb_dmac);

        pass_count = 0;
        fail_count = 0;

        // Initialise DMA config inputs
        `AHB_WRITE(0, 32'h0) ; // src addr
        `AHB_WRITE(4, 32'h0) ; // dest addr
        `AHB_WRITE(8, 32'h0) ; // transfer size
        `AHB_WRITE(12, 32'h0) ; // start signal (only LSB is used)
        `AHB_IDLE ;

        // ===== Reset =====
        HRESETn = 1'b0;
        repeat (5) @(posedge HCLK);
        HRESETn = 1'b1;
        repeat (2) @(posedge HCLK);

        // ===== Force initial data into source registers 0-15 =====
        $display("\n=== Loading source data into registers 0-15 ===");
        for (i = 0; i < NUM_XFERS; i++) begin
            slave.regs[i] = 32'hCAFE_0000 + i;
        end
        @(posedge HCLK);

        // Sanity-check: source data is present
        for (i = 0; i < NUM_XFERS; i++) begin
            check($sformatf("src reg[%0d] init", i),
                  32'hCAFE_0000 + i, regs_out[i]);
        end

        // ===== Configure DMA =====
        $display("\n=== Configuring DMA: src=0x00, dest=0x80, count=%0d ===", NUM_XFERS);
        `AHB_WRITE(0,32'h0000_0000); // src addr  // address 0   -> regs[0..15]
        `AHB_WRITE(4,32'h0000_0080); // dest addr // address 128 -> regs[32..47]
        `AHB_WRITE(8,NUM_XFERS);     // transfer size
        `AHB_WRITE(12,'1);           // start signal
        `AHB_IDLE;

        // ===== Wait for DMA to finish =====
        $display("\n=== Waiting for DMA to complete ===");
        begin
            int cycles;
            logic seen_active;
            cycles      = 0;
            seen_active = 1'b0;
            while (cycles < TIMEOUT) begin
                @(posedge HCLK);
                cycles++;
                // Track that the DMA left IDLE at least once
                if (dut.dma_controller.current_state != dut.dma_controller.IDLE_STATE)
                    seen_active = 1'b1;
                // Done when DMA returns to IDLE after having been active
                if (seen_active && dut.dma_controller.current_state == dut.dma_controller.IDLE_STATE) begin
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
        repeat (5) @(posedge HCLK);

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