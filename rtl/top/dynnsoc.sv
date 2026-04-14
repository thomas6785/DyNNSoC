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
    ahb_intf_m ahb_cpu_if();
    ahb_intf_s ahb_imem_if();
    ahb_intf_s ahb_ram_if();
    ahb_intf_s ahb_gpio_if();
    ahb_intf_s ahb_uart_if();
    ahb_intf_s ahb_mvu_if();
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

    // ======================== Signals for display on oscilloscope ===================
    assign JA = {HCLK, ahb_cpu_if.HTRANS[1], ahb_cpu_if.HREADY, ahb_cpu_if.HRESP, '0};

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
        .master_if   (ahb_cpu_if.interconn),
        .slave_if_s0 (ahb_imem_if.interconn),
        .slave_if_s1 (ahb_ram_if.interconn),
        .slave_if_s2 (ahb_gpio_if.interconn),
        .slave_if_s3 (ahb_uart_if.interconn),
        .slave_if_s4 (ahb_mvu_if.interconn)
    );

    // ========================================
    // MVU array
    // ========================================
    mvutop_wrapper MVU (
        .HCLK,
        .HRESETn,
        .AHB_IF(ahb_mvu_if.slave),
        .irq(mvu_irqs)
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
