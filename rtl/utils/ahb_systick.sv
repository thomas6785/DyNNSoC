module ahb_systick (
    input HCLK,
    input HRESETn,

    ahb_intf_s.slave AHB_IF,

    output logic irq
);
    logic           reg_access [2:];
    logic           reg_write;
    logic [31:0]    reg_wdata;
    logic [31:0]    reg_rdata [2:0];
    logic [3:0]     reg_wstrb;

    ahb_to_csr #(
        .ADDR_WIDTH(32),
        .NUM_REGS(3),
        .ALLOW_STROBING(1)
    ) I_ahb_to_csr (
        .HCLK,
        .HRESETn,
        .AHB_IF,

        .acces(reg_access),
        .write(reg_write),
        .wdata(reg_wdata),
        .rdata(reg_rdata),
        .error(1'b0),
        .ready(1'b1),
        .wstrb(reg_wstrb)
    );

    // Reload value register
    logic [31:0]    reload_value;
    logic reg_access_reload_value = reg_access[2];
    assign reg_rdata[2] = reload_value;

    // Current value register
    logic [31:0]    counter;
    logic reg_access_counter = reg_access[1];
    assign reg_rdata[1] = counter;

    // Control/status register
    logic reg_access_control = reg_access[0];
    logic clear_irq;        // bit 31 (write-1-to-clear)
    logic reload_now;       // bit 24 (self-clearing)
    logic generate_irq;     // bit 16
    logic reload_on_zero;   // bit 8
    logic run;              // bit 0
    assign reg_rdata[0] = ( generate_irq << 16 )  |     // bit 16
                          ( reload_on_zero << 8 ) |     // bit 8
                          ( run );                      // bit 0
    assign reload_now = reg_access_control && reg_write && (reg_wdata[24] & reg_wstrb[3]);
    assign clear_irq  = reg_access_control && reg_write && (reg_wdata[31] & reg_wstrb[3]);

    // Implement the reload value register
    always_ff @ (posedge HCLK) begin
        if (!HRESETn)                                   reload_value <= (1<<20); // default config: every 1M clock cycles
        else if (reg_access_reload_value && reg_write)  reload_value <= (reg_wdata & reg_wstrb) | (reload_value & ~reg_wstrb);
    end

    // Implement the counter
    logic counter_next;
    always_comb begin
        if (reg_access_counter && reg_write)        counter_next = (reg_wdata & reg_wstrb) | (counter & ~reg_wstrb);
        else if (reload_now)                        counter_next = reload_value;
        else if (run && counter != 0)               counter_next = counter - 1;
        else if (reload_on_zero && counter == 0)    counter_next = reload_value;
        else                                        counter_next = counter;
    end

    always_ff @ (posedge HCLK) begin
        if (!HRESETn)    counter <= '0;
        else             counter <= counter_next;
    end

    // Implement the control register
    always_ff @ (posedge HCLK) begin
        if (!HRESETn) begin
            generate_irq    <= 1'b0;
            reload_on_zero  <= 1'b0;
            run             <= 1'b0;
        end else if (reg_access_control && reg_write) begin
            generate_irq    <= reg_wdata[16] & reg_wstrb[2];
            reload_on_zero  <= reg_wdata[8]  & reg_wstrb[1];
            run             <= reg_wdata[0]  & reg_wstrb[0];
        end
    end

    // Implement the interrupt generation
    always_ff @ (posedge HCLK) begin
        if (!HRESETn)                               irq <= 1'b0;
        else if (clear_irq)                         irq <= 1'b0;
        else if (generate_irq && counter == 0)      irq <= 1'b1;
        else                                        irq <= irq; // hold the value
    end
endmodule