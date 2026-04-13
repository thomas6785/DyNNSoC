`timescale 1ns/1ps

module dma_config_regs (
    ahb_intf_s.slave config_bus, // Interface for configuration bus

    output logic start_signal,                      // Signal to start the DMA transfer
    output logic [31:0] src_addr,         // Source address from configuration bus
    output logic [31:0] dest_addr,        // Destination address from configuration bus
    output logic [15:0] transfer_size,    // Number of bytes to transfer
    output logic        src_incr,
    output logic        dest_incr,
    input error
);
    // Address-phase sampling
    logic [ADDR_WIDTH-1:0] addr_q;
    logic                  valid_q;  // address phase was a real transfer
    logic                  write_q;

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
endmodule