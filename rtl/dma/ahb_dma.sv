module ahb_dma #(
    // Use these parameters to denote "bad address space" i.e. address the DMA cannot access. Normally used to prevent it from writing its own config
    parameter BAD_ADDR_SPACE_VALUE = 32'h1,
    parameter BAD_ADDR_SPACE_MASK = 32'h0000_0000
) (
    input HCLK,
    input HRESETn,

    // The DMA controller is both a master (for performing transfers) and slave (for config by the core)
    ahb_intf_m.master master_if,
    ahb_intf_s.slave config_if,

    output logic irq_flag
);
    // Declare config registers
    logic [31:0] config_in_src_addr;
    logic [31:0] config_in_dest_addr;
    logic [15:0] config_in_transfer_size;
    logic        start_signal;
    logic        irq_pulse;

    // Instantiate the DMA controller
    dmac #(
        .BAD_ADDR_SPACE_VALUE(BAD_ADDR_SPACE_VALUE),
        .BAD_ADDR_SPACE_MASK(BAD_ADDR_SPACE_MASK)
    ) dma_controller (
        .dma_bus(master_if),
        .config_in_src_addr(config_in_src_addr),
        .config_in_dest_addr(config_in_dest_addr),
        .config_in_transfer_size(config_in_transfer_size),
        .start_signal(start_signal),
        .clk(HCLK),
        .reset(HRESETn),
        .irq(irq_pulse)
    );

    // Instantiate the register block (AHB to simple CSR interface)
    logic reg_access [3:0];
    logic reg_write;
    logic [31:0] reg_wdata;
    logic [31:0] reg_rdata [3:0];
    logic reg_error;
    logic reg_ready;

    ahb_to_csr #(
        .ADDR_WIDTH(32),
        .NUM_REGS(4)
    ) I_ahb_to_csr (
        .HCLK,
        .HRESETn,
        .AHB_IF(config_if),

        // Memory interface for the CSR registers
        .access(reg_access),
        .write(reg_write),
        .wdata(reg_wdata),
        .rdata(reg_rdata),
        .error(reg_error),
        .ready(reg_ready)
    );

    always_ff @ (posedge HCLK) begin
        if (!HRESETn)                                           irq_flag <= 1'b0; // clear IRQ on reset
        else if (irq_pulse)                                     irq_flag <= 1'b1; // set the flag when an IRQ pulse is received from the DMAC
        else if (reg_write && reg_access[3] && reg_wdata[0])    irq_flag <= 1'b0; // clear the flag when the core writes to the appropriate register (currently reg 3 bit 0)
        else                                                    irq_flag <= irq_flag; // otherwise maintain the current value
    end

    always_ff @ (posedge HCLK) begin
        if (!HRESETn) begin
            config_in_src_addr <= '0;
            config_in_dest_addr <= '0;
            config_in_transfer_size <= '0;
        end else if (reg_write) begin
            if (reg_access[0]) begin
                config_in_src_addr <= reg_wdata;
            end else if (reg_access[1]) begin
                config_in_dest_addr <= reg_wdata;
            end else if (reg_access[2]) begin
                config_in_transfer_size <= reg_wdata[15:0]; // upper bits are ignored
            end
            // no write logic for register 3
            // bit 0 is used to clear the IRQ (handled in the always block for the IRQ flag)
            // bit 31 is used to start (combinational, handled by the assign statement for start_signal)
        end
    end
    assign start_signal = reg_wdata[31] && reg_write && reg_access[3];

    assign reg_rdata[0] = config_in_src_addr;
    assign reg_rdata[1] = config_in_dest_addr;
    assign reg_rdata[2] = {16'b0, config_in_transfer_size};
    assign reg_rdata[3] = {31'b0, irq_flag};
    // TODO status register should have a 'busy' and 'error' flag as well as the IRQ

    assign reg_ready = 1'b1;
    assign reg_error = 1'b0; // TODO write these better
endmodule