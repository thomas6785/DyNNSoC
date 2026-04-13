`timescale 1ns/1ps

// CAUTION:
// This model is AI-generated
// It was inspected by me (Thomas O'Dea) but should still be used with caution

// Simple AHB master model for simulation/verification.
// Provides blocking read() and write() tasks that perform
// single NONSEQ transfers on the connected ahb_intf bus.
module ahb_master #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter TIMEOUT_CYCLES = 1000
)(
    ahb_intf_m.master bus
);

    // HTRANS encodings
    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;

    // HSIZE encoding for full data-width transfer
    localparam [2:0] HSIZE_WORD = (DATA_WIDTH == 64) ? 3'b011 :
                                  (DATA_WIDTH == 16) ? 3'b001 :
                                                       3'b010; // 32-bit default

    // ---------- Timeout helper ----------
    task automatic wait_ready(input string phase);
        int cyc;
        cyc = 0;
        do begin
            @(posedge bus.hclk);
            cyc++;
            if (cyc >= TIMEOUT_CYCLES) begin
                $error("[ahb_master] TIMEOUT after %0d cycles waiting for hreadyout during %s phase", cyc, phase);
                // Return bus to idle to avoid locking the bus
                bus.haddr  <= '0;
                bus.htrans <= HTRANS_IDLE;
                bus.hwrite <= 1'b0;
                return;
            end
        end while (!bus.hready);
    endtask

    // ---------- Initialise bus to idle ----------
    initial begin
        bus.haddr  = '0;
        bus.hsize  = '0;
        bus.htrans = HTRANS_IDLE;
        bus.hwdata = '0;
        bus.hwrite = 1'b0;
    end

    // ---------- Write task ----------
    // Performs a single NONSEQ write and waits for completion.
    task automatic write(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [2:0]            size = HSIZE_WORD
    );
        // Address phase: drive address, control
        @(posedge bus.hclk);
        bus.haddr  <= addr;
        bus.hsize  <= size;
        bus.htrans <= HTRANS_NONSEQ;
        bus.hwrite <= 1'b1;

        // Wait for address phase to be accepted
        wait_ready("write address");

        // Data phase: drive write data, return bus to idle
        bus.hwdata <= data;
        bus.haddr  <= '0;
        bus.htrans <= HTRANS_IDLE;
        bus.hwrite <= 1'b0;

        // Wait for data phase to complete
        wait_ready("write data");
    endtask

    // ---------- Read task ----------
    // Performs a single NONSEQ read and returns the data.
    task automatic read(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        input  logic [2:0]            size = HSIZE_WORD
    );
        // Address phase
        @(posedge bus.hclk);
        bus.haddr  <= addr;
        bus.hsize  <= size;
        bus.htrans <= HTRANS_NONSEQ;
        bus.hwrite <= 1'b0;

        // Wait for address phase to be accepted
        wait_ready("read address");

        // Data phase: return bus to idle, sample read data
        bus.haddr  <= '0;
        bus.htrans <= HTRANS_IDLE;

        // Wait for data phase to complete
        wait_ready("read data");
        data = bus.hrdata;
    endtask

    // ---------- Pipelined transaction sequence ----------
    // Executes a list of read/write transactions with full AHB
    // pipelining: the address phase of transfer N+1 overlaps the
    // data phase of transfer N, giving maximum throughput.
    //
    // is_write[i] = 1 → write, 0 → read
    // For reads, returned data is checked against data[i].
    task automatic transaction_sequence(
        input  logic [ADDR_WIDTH-1:0] addr     [],
        input  logic [DATA_WIDTH-1:0] data     [],
        input  logic                  is_write [],
        inout  int                    pass_count,
        inout  int                    fail_count
    );
        int n;
        logic [DATA_WIDTH-1:0] rdata;
        logic                  prev_is_write;
        logic [DATA_WIDTH-1:0] prev_data;
        logic [ADDR_WIDTH-1:0] prev_addr;
        int                    prev_idx;
        int                    timeout_cyc;

        n = addr.size();
        if (data.size() != n || is_write.size() != n) begin
            $error("[ahb_master] transaction_sequence: mismatched array sizes (addr=%0d, data=%0d, is_write=%0d)",
                   n, data.size(), is_write.size());
            return;
        end
        if (n == 0) return;

        // ---- First address phase ----
        @(posedge bus.hclk);
        bus.haddr  <= addr[0];
        bus.hsize  <= HSIZE_WORD;
        bus.htrans <= HTRANS_NONSEQ;
        bus.hwrite <= is_write[0];

        // Wait for slave to accept the first address phase
        timeout_cyc = 0;
        do begin
            @(posedge bus.hclk);
            timeout_cyc++;
            if (timeout_cyc >= TIMEOUT_CYCLES) begin
                $error("[ahb_master] TIMEOUT in pipelined sequence, addr phase index 0");
                bus.htrans <= HTRANS_IDLE;
                return;
            end
        end while (!bus.hready);

        // ---- Pipeline loop: data phase[i] + address phase[i+1] ----
        for (int i = 0; i < n; i++) begin
            // Save info about the transfer whose data phase is now active
            prev_is_write = is_write[i];
            prev_data     = data[i];
            prev_addr     = addr[i];
            prev_idx      = i;

            // Drive write data for current data phase (harmless if read)
            if (prev_is_write)
                bus.hwdata <= data[i];

            // Drive next address phase, or go idle after the last transfer
            if (i + 1 < n) begin
                bus.haddr  <= addr[i+1];
                bus.htrans <= HTRANS_NONSEQ;
                bus.hwrite <= is_write[i+1];
            end else begin
                bus.haddr  <= '0;
                bus.htrans <= HTRANS_IDLE;
                bus.hwrite <= 1'b0;
            end

            // Wait for data phase to complete (slave asserts hready)
            timeout_cyc = 0;
            do begin
                @(posedge bus.hclk);
                timeout_cyc++;
                if (timeout_cyc >= TIMEOUT_CYCLES) begin
                    $error("[ahb_master] TIMEOUT in pipelined sequence, data phase index %0d", prev_idx);
                    bus.htrans <= HTRANS_IDLE;
                    return;
                end
            end while (!bus.hready);

            // Check read data
            if (!prev_is_write) begin
                rdata = bus.hrdata;
                if (rdata === prev_data) begin
                    $display("[PASS] seq[%0d] read  addr=0x%08h: 0x%08h", prev_idx, prev_addr, rdata);
                    pass_count++;
                end else begin
                    $display("[FAIL] seq[%0d] read  addr=0x%08h: expected 0x%08h, got 0x%08h",
                             prev_idx, prev_addr, prev_data, rdata);
                    fail_count++;
                end
            end
        end

        // Bus is already idle after the loop
        bus.hwdata <= '0;
    endtask

endmodule
