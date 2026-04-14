`timescale 1ns / 1ns

module dynnsoc (
    input HCLK,         // 50 MHz clock
    input btnCpuResetn, // reset pushbutton, active low (marked CPU RESET)
    input btnU,         // up button - if pressed after reset, ROM loader activated
    input btnD,         // down button
    input btnL,         // left button
    input btnC,         // centre button
    input btnR,         // right button
    input [15:0] sw,    // 16 slide switches on Nexys 4 board
    input serialRx,     // serial port receive line
    output [15:0] led,  // 16 individual LEDs above slide switches
    output [5:0] rgbLED,   // multi-colour LEDs {blu2, grn2, red2, blu1, grn1, red1}
    output [7:0] JA,      // monitoring connector on FPGA board - use with oscilloscope
    output serialTx       // serial port transmit line
);  // end of module port list

    localparam  OKAY = 1'b0, ERROR = 1'b1;  // values for the HRESP signal

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
    logic       IRQ_uart;
    logic [7:0] mvu_irqs;

    wire [14:0] IRQ; // interrupt request vector to the core. Should remain high until addressed
    assign IRQ = {
        mvu_irqs, 5'b0, IRQ_uart, 1'b0
    };

    // ========================================
    // Declare some other connecting signals
    // ========================================
    wire        HRESETn;            // active low bus reset
    wire        resetHW;            // reset signal for hardware, active high TODO remove this an use a common reset for everything
    wire        CPUsleep;           // CPU status signals
    wire        ROMload;            // rom loader is active
    wire [4:0]  buttons = {btnU, btnD, btnL, btnC, btnR};   // concatenate 5 pushbuttons

    // Wires and multiplexer to drive LEDs from two different sources - needed for ROM loader
    wire [11:0] led_rom;        // status output from ROM loader
    wire [15:0] led_gpio;       // led output from GPIO block
    assign led = ROMload ? {4'b0,led_rom} : led_gpio;    // choose which to display

    logic [15:0] gpio_out1;

    // ========================================
    // Signals to monitor on oscilloscope
    // ========================================
    assign JA = {HCLK, ahb_arbitrated_if.HTRANS[1], ahb_arbitrated_if.HREADY, ahb_arbitrated_if.HWRITE, '0};

    // ========================================
    // Temporarily drive DMAC for testing
    // ========================================
    assign ahb_dmac_m_if.HTRANS = 2'b10; // constantly driving stuff
    assign ahb_dmac_m_if.HWRITE = 1'b0;
    assign ahb_dmac_m_if.HWDATA = 32'b0;
    assign ahb_dmac_m_if.HPROT = 4'b00011;
    assign ahb_dmac_m_if.HSIZE = 3'b010;
    always_ff @ (posedge HCLK) begin
        if (!HRESETn) ahb_dmac_m_if.HADDR <= 32'h0;
        else if (ahb_dmac_m_if.HREADY) ahb_dmac_m_if.HADDR <= ahb_dmac_m_if.HADDR ^ 32'h4; // alternate between 0 and 4
    end

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
    // Asserts hardware reset until the clock module is locked, also if reset button pressed.
    // Asserts CPU and bus reset to meet Cortex-M0 requirements, also if ROM loader is active.
    reset_gen resetGen (                // Instantiate reset generator module
        .clk            (HCLK),         // works on system bus clock
        .resetPBn       (btnCpuResetn), // signal from CPU reset pushbutton
        .pll_lock       (1'b1),         // from clock management PLL
        .loader_active  (ROMload),      // from ROM loader hardware
        .cpu_request    (1'b0),         // from CPU, requesting reset
        .resetHW        (resetHW),      // hardware reset output, active high
        .resetCPUn      (HRESETn)       // CPU and bus reset, active low
    );

    // ========================================
    // Status indicator
    // ========================================
    // Drives multi-colour LEDs to indicate status of processor and ROM loader.
    status_ind statusInd (      // Instantiate status indicator module
        .clk            (HCLK),       // works on system bus clock
        .reset          (resetHW),    // hardware reset signal
        .statusIn       ({~HRESETn, 1'b0, CPUsleep, ROMload}),  // status inputs
        .rgbLED         (rgbLED)      // output signals for colour LEDs
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
    ahb_interconn interconn (
        .HCLK,
        .HRESETn,
        .master_if   (ahb_arbitrated_if.interconn),
        .slave_if_s0 (ahb_imem_if.interconn),
        .slave_if_s1 (ahb_ram_if.interconn),
        .slave_if_s2 (ahb_gpio_if.interconn),
        .slave_if_s3 (ahb_uart_if.interconn),
        .slave_if_s4 (ahb_mvu_if.interconn)
    );

    // ========================================
    // DMA Controller
    // ========================================
    // Both a master and a slave on the AHB bus
    //ahb_dmac DMAC (
    //    .HCLK,
    //    .HRESETn,
    //    .master_if(ahb_dmac_m_if.master),   // DMAC master interface to arbiter
    //    .config_if(ahb_dmac_s_if.slave)     // DMAC slave interface from interconnect
    //);

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
        .HCLK,				                        // bus clock
        .HRESETn,			                        // bus reset, active low
        .AHB_IF         (ahb_gpio_if.slave),         // AHB slave interface
        // GPIO signals
        .gpio_out0      (led_gpio),                 // read-write address 0
        .gpio_out1      (gpio_out1),                // read-write address 4
        .gpio_in0       (sw),                       // read only address 8
        .gpio_in1       ({11'b0, buttons})          // read only address C
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
        .resetHW        (resetHW),			// hardware reset
        .loadButton     (btnU),		        // pushbutton to activate loader
        .serialRx	    (serialRx),         // serial input
        .rom_load_status(led_rom),          // 12-bit word count for display on LEDs
        .rom_load_active(ROMload)			// loader active
    );
endmodule
