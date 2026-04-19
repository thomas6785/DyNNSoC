`timescale 1ns / 1ns

module dynnsoc (
    input HCLK,     // clock
    input rst_n_in, // reset (active low)

    // serial communications
    input serialRx,     // serial port receive line
    output serialTx,    // serial port transmit line

    // GPIO
    output [15:0] gpio_out0,
    output [15:0] gpio_out1,
    input  [15:0] gpio_in0,
    input  [15:0] gpio_in1
);
    // ========================================
    // Interfaces for connecting components
    // ========================================
    // Masters on the AHB bus
    ahb_intf_m ahb_cpu_if();            // The CPU has a master interface it drives (into the arbiter)
    ahb_intf_m ahb_dmac_m_if();         // The DMAC has a master interface it drives (into the arbiter)
    ahb_intf_m ahb_arbitrated_if();     // The arbiter drives this (MUX'd between the CPU and the DMAC)

    // Slaves on the AHB bus
    ahb_intf_s ahb_dmac_s_if();         // The DMAC is also a slave (so the CPU can configure it)
    ahb_intf_s ahb_imem_if();           // Instruction memoy is a slave (read-only)
    ahb_intf_s ahb_ram_if();            // General-purpose RAM is a slave (read/write)
    ahb_intf_s ahb_gpio_if();           // GPIO is a slave (read/write)
    ahb_intf_s ahb_uart_if();           // UART is a slave (read/write)
    ahb_intf_s ahb_mvu_if();            // MVU is a slave (read/write)

    // Instruction fetch backchannel
    instruction_fetch_if instr_if(); // connect CPU directly to imem, bypassing the AHB bus

    // ========================================
    // Declare interrupt request lines
    // ========================================
    logic            IRQ_uart;
    logic            DMAC_irq;
    logic [3:0] mvu_irqs;

    logic [14:0] IRQ; // interrupt request vector to the core. Should remain high until addressed
    assign IRQ = {
        mvu_irqs,      // faster interrupts 14,13,12,11
        8'b0,
        DMAC_irq,      // fast interrupt 2
        IRQ_uart,      // fast interrupt 1
        1'b0
    };

    // ========================================
    // Declare some other connecting signals
    // ========================================
    logic        HRESETn;            // active low bus reset
    logic        CPUsleep;           // CPU status signals
    logic        ROMload;            // rom loader is active
    logic        rst_p;              // active-high reset
    logic [11:0] rom_load_status;    // status output from ROM loader (e.g. for displaying on LEDs)

    // ========================================
    // Create arbiter for DMAC and CPU to share the AHB bus
    // ========================================
    ahb_transparent_arbiter arbiter ( // TODO create forbidden addresses
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .ahb_if_m1(ahb_dmac_m_if.interconn),    // DMAC master interface into arbiter
        .ahb_if_m2(ahb_cpu_if.interconn),       // CPU master interface into arbiter - this interface has priority (internally)
        .ahb_if_mi(ahb_arbitrated_if.master)    // Output of arbiter to interconnect
    );
    // Note that this arbiter is "transparent" i.e. the masters have no awareness that they are sharing the bus
    // The 'ready' signal will stall while the other master is using the bus, and there is no BUSREQ or BUSGNT signal
    // They have no way of differentiating a SLAVE stalling them vs. another master

    // ========================================
    // Reset generator
    // ========================================
    // Handles timing for reset de-asserting
    // Also ensure reset is asserted while the ROM loader is active
    reset_gen resetGen (                // Instantiate reset generator module
        .clk            (HCLK),         // input: system bus clock
        .rst_n_async    (rst_n_in),     // input: external reset signal
        .loader_active  (ROMload),      // input: ROM loader requesting reset
        .rst_p          (rst_p),        // output: active high reset
        .rst_n          (HRESETn)       // output: active low reset
    );

    // ========================================
    // CPU Core
    // ========================================
    ibex_wrapper cpu (
        .HCLK,
        .HRESETn,
        .AHB_IF     (ahb_cpu_if.master),

        // Other signals
        .NMI         (1'b0),        // non-maskable interrupt
        .EXT_IRQ     (1'b0),        // external interrupt
        .IRQ         (IRQ),         // interrupt lines from peripherals
        .SYSTICKCLKDIV(24'd1024),   // a "systick" interrupt will be generated every 1024 clock cycles. Firmware may ignore this
        .core_sleep_o(CPUsleep),    // CPU sleeping, waiting for interrupt

        // Memory interface for instruction fetches
        .instr_if(instr_if.core)
    );

    // ========================================
    // AHB interconnect
    // ========================================
    // Connects the interconnect master to all the slaves
    // Handles multiplexing slave responses (read data, response code, ready signal)
    // and driving select lines to each slave
    // Detail of the memory map is inside this module
    ahb_interconn interconn (
        .HCLK,
        .HRESETn,
        .master_if   ( ahb_arbitrated_if.interconn ),
        .slave_if_s0 ( ahb_imem_if.interconn       ),
        .slave_if_s1 ( ahb_ram_if.interconn        ),
        .slave_if_s2 ( ahb_gpio_if.interconn       ),
        .slave_if_s3 ( ahb_uart_if.interconn       ),
        .slave_if_s4 ( ahb_mvu_if.interconn        ),
        .slave_if_s5 ( ahb_dmac_s_if.interconn     )
    );

    // ========================================
    // DMA Controller
    // ========================================
    // Both a master and a slave on the AHB bus
    ahb_dma #(
        .BAD_ADDR_SPACE_VALUE(32'h0400_0000),
        .BAD_ADDR_SPACE_MASK (32'hFF00_0000)
        // addresses in the range 0x0400_0000 to 0x04FF_FFFF are the DMAC's own configuration,
        // so it is forbidden from accessing them
    ) DMAC (
        .HCLK,
        .HRESETn,
        .master_if(ahb_dmac_m_if.master),   // DMAC master interface to arbiter
        .config_if(ahb_dmac_s_if.slave),    // DMAC slave interface from interconnect
        .irq_flag(DMAC_irq)
    );

    // ========================================
    // MVU array
    // ========================================
    mvutop_wrapper MVU (
        .HCLK,
        .HRESETn,
        .AHB_IF(ahb_mvu_if.slave),
        .irq_flag(mvu_irqs)
    );

    // ========================================
    // General-purpose read-write RAM
    // ========================================
    ahb_ram RAM (
        .HCLK,                                  // bus clock
        .HRESETn,                               // bus reset, active low
        .AHB_IF      (ahb_ram_if.slave)
    );

    // ========================================
    // GPIO slave
    // ========================================
    ahb_gpio GPIO (
        // Bus signals
        .HCLK,                                      // bus clock
        .HRESETn,                                   // bus reset, active low
        .AHB_IF         (ahb_gpio_if.slave),        // AHB slave interface
        // GPIO signals
        .gpio_out0,      // read-write address 0
        .gpio_out1,      // read-write address 4
        .gpio_in0,       // read-only address 8
        .gpio_in1        // read-only address C
    );

    // ========================================
    // UART slave
    // ========================================
    ahb_uart UART (
        // Bus signals
        .HCLK,                                      // bus clock
        .HRESETn,                                   // bus reset, active low
        .HSEL           (ahb_uart_if.HSEL),         // selects this slave
        .HREADY         (ahb_uart_if.HREADY),       // indicates previous transaction completing
        .HADDR          (ahb_uart_if.HADDR),        // address
        .HTRANS         (ahb_uart_if.HTRANS),       // transaction type (only bit 1 used)
        .HWRITE         (ahb_uart_if.HWRITE),       // write transaction
        .HWDATA         (ahb_uart_if.HWDATA),       // write data
        .HRDATA         (ahb_uart_if.HRDATA),       // read data output
        .HREADYOUT      (ahb_uart_if.HREADYOUT),    // ready output
        .HRESP          (ahb_uart_if.HRESP),        // response output from slave
        // UART signals
        .serialRx(serialRx),                        // serial receive, idles at 1
        .serialTx(serialTx),                        // serial transmit, idles at 1
        .uart_IRQ(IRQ_uart)                         // interrupt request
    );

    // ========================================
    // ROM
    // ========================================
    // Read-only memory which is accessible by three means:
    // - AHB bus has read access
    // - Simple memory interface (for instruction fetches) (read-only)
    // - Loader interface (write-only)
    imem imem (
        .HCLK,
        .HRESETn,
        .AHB_IF         (ahb_imem_if.slave), // AHB slave interface - read-only, gives error on writes
        .instr_if       (instr_if.rom),      // Read-only memory interface for instruction fetches

        // Connections for ROM loader
        .resetHW        (rst_p),            // hardware reset
        .loadButton     (TODO),             // pushbutton to activate loader
        .serialRx       (serialRx),         // serial input
        .rom_load_status(rom_load_status),  // 12-bit word count for display on LEDs
        .rom_load_active(ROMload)           // loader active
    ); // TODO might be a bug here with the reset signal - doesn't come up in test cases because we are writing to ROM directly. Need a UART test case TODO
endmodule
