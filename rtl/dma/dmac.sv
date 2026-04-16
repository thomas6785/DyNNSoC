`timescale 1ns/1ps

module dmac #(
    parameter BAD_ADDR_SPACE_VALUE = 32'h1,
    parameter BAD_ADDR_SPACE_MASK = 32'h0000_0000
) (
    ahb_intf_m.master dma_bus, // Interface for AHB bus communication
    //ahb_intf_s.slave config_bus, // Interface for configuration bus
    input [31:0] config_in_src_addr,
    input [31:0] config_in_dest_addr,
    input [15:0] config_in_transfer_size,
    input start_signal,
    input logic clk,
    input logic reset,
    output logic irq
);
    // Create an FSM for the state of the DMA controller
    // Typical flow:
    //                             IDLE STATE  <------------------------------------------------------------|
    //                                 ||                                                                   |
    //                                 \/                                                                   |
    //                          INITIAL_SRC_ADDR                                                            |
    //                                 ||                                                                   |
    //                                 \/                                                                   |
    //                      |--------------------|      |--------------------|                              |
    // |-----HREADYOUT=0--- |                    | ===> |                    | -----HREADYOUT=0---|         |
    // |                    | SRC_DATA_DEST_ADDR |      | DEST_DATA_SRC_ADDR |                    |         |
    // |----------------->  |                    | <=== |                    | <------------------|         |
    //                      |--------------------|      |--------------------|                              |
    //                                ||                                                                    |
    //                                \/                                                                    |
    //                      |--------------------|                                                          |
    // |-----HREADYOUT=0--- |                    |                                                          |
    // |                    | FINAL_DEST_DATA    | ---------HREADYOUT=1-------------------------------------|
    // |----------------->  |                    |
    //                      |--------------------|

    typedef enum logic [2:0] {
        IDLE_STATE,
        INITIAL_SRC_ADDR,
        SRC_DATA_DEST_ADDR,
        SRC_ADDR_DEST_DATA,
        FINAL_DEST_DATA
    } state_t;

    logic error_flag, error_next;
    // TODO error detection logic is present but doesn't actually do anything. It should terminate the transaction and send an IRQ

    logic [31:0] src_addr, src_addr_next, dest_addr, dest_addr_next;
    logic [31:0] data_buffer;
    state_t current_state, next_state;
    logic [15:0] counter, counter_next;

    // State transition logic
    always_ff @(posedge clk) begin
        if (!reset) begin
            current_state <= IDLE_STATE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always_comb begin
        if (error_next) begin
            next_state = IDLE_STATE; // Reset to idle on error
        end else begin
            case (current_state)
                IDLE_STATE: begin
                    if (start_signal) begin
                        next_state = INITIAL_SRC_ADDR;
                    end else begin
                        next_state = IDLE_STATE;
                    end
                end
                INITIAL_SRC_ADDR: begin // AHB does not allow stalling in the address phase so we can move straight from INITIAL_SRC_ADDR to SRC_DATA_DEST_ADDR
                    next_state = SRC_DATA_DEST_ADDR;
                end
                SRC_DATA_DEST_ADDR: begin
                    if (!dma_bus.HREADY) begin
                        next_state = SRC_DATA_DEST_ADDR;
                    end else if (counter == 0) begin
                        next_state = FINAL_DEST_DATA;
                    end else begin
                        next_state = SRC_ADDR_DEST_DATA; // Stay in this state until data phase is ready
                    end
                end
                SRC_ADDR_DEST_DATA: begin
                    if (!dma_bus.HREADY) begin
                        next_state = SRC_ADDR_DEST_DATA;
                    end else begin
                        next_state = SRC_DATA_DEST_ADDR;
                    end
                end
                FINAL_DEST_DATA: begin
                    if (!dma_bus.HREADY) begin
                        next_state = FINAL_DEST_DATA;
                    end else begin
                        next_state = IDLE_STATE;
                    end
                end
                default: next_state = IDLE_STATE;
            endcase
        end
    end

    // Output logic based on the current state

    always_comb begin
        // Default values for outputs
        dma_bus.HWRITE = (current_state == SRC_DATA_DEST_ADDR); // 'write' is valid during the ADDRESS phase so we want it high when the address phase is on destination

        dma_bus.HADDR =
            (current_state == INITIAL_SRC_ADDR) ? src_addr :
            (current_state == SRC_DATA_DEST_ADDR) ? dest_addr :
            (current_state == SRC_ADDR_DEST_DATA) ? src_addr :
            32'b0; // Default to address 0

        dma_bus.HTRANS =
            ((current_state == INITIAL_SRC_ADDR) ||
             (current_state == SRC_DATA_DEST_ADDR) ||
             (current_state == SRC_ADDR_DEST_DATA)) ? 2'b10 : 2'b00;
            // 'NONSEQ' for address phases, 'IDLE' otherwise
    end

    assign dma_bus.HWDATA = data_buffer; // Data to be written during the data phase

    // Data buffer updates after every read
    always_ff @(posedge clk) begin
        if (!reset) begin
            data_buffer <= 32'b0; // Clear data buffer on reset
        end else
        if (current_state == SRC_DATA_DEST_ADDR && dma_bus.HREADY) begin
            data_buffer <= dma_bus.HRDATA; // Capture read data into buffer
        end
    end

    // Error handling logic
    assign error_next = (dest_addr_next && BAD_ADDR_SPACE_MASK) == BAD_ADDR_SPACE_VALUE;
    // allows address filtering to prevent the DMA from accessing certain address spaces (generally its own config regs)
    always_ff @ (posedge clk) begin
        if (!reset) begin
            error_flag <= 1'b0; // Clear error flag on reset
        end else begin
            error_flag <= error_next | error_flag; // Update error flag based on next state logic
        end
    end

    // Source address and destination address updates
    always_ff @(posedge clk) begin
        if (!reset) begin
            src_addr <= 32'b0; // Clear source address on reset
            dest_addr <= 32'b0; // Clear destination address on reset
            counter <= 16'b0; // Clear counter on reset
        end else begin
            src_addr <= src_addr_next;
            dest_addr <= dest_addr_next;
            counter <= counter_next;
        end
    end


    always_comb begin
        src_addr_next = src_addr; // Default to no change
        dest_addr_next = dest_addr; // Default to no change
        counter_next = counter; // Default to no change

        if (current_state == IDLE_STATE && start_signal) begin
            src_addr_next = config_in_src_addr; // Load source address from config bus
            dest_addr_next = config_in_dest_addr; // Load destination address from config bus
            counter_next = config_in_transfer_size; // Load transfer size from config bus
        end
        if (current_state == SRC_DATA_DEST_ADDR && dma_bus.HREADY) begin
            src_addr_next = src_addr + 4; // Increment source address for next transfer
            counter_next = counter - 1; // Decrement transfer counter
        end
        if (current_state == SRC_ADDR_DEST_DATA && dma_bus.HREADY) begin
            dest_addr_next = dest_addr + 4; // Increment destination address for next transfer
        end
        // TODO allow disabling the increment e.g. for SPI or UART peripherals
    end

    // IRQ generation logic
    assign irq = (current_state == FINAL_DEST_DATA) && dma_bus.HREADY;

    assign dma_bus.HPROT = 4'b0011;
    assign dma_bus.HSIZE = 3'b010;
endmodule
