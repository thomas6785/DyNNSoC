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

    // ========================= Bus Signals =====================================
    wire        HRESETn;    // active low reset
    ahb_intf_m ahb_cpu_if();
    ahb_intf_s ahb_imem_if();
    ahb_intf_s ahb_ram_if();
    ahb_intf_s ahb_gpio_if();
    ahb_intf_s ahb_uart_if();
    instruction_fetch_if instr_if(); // connect CPU directly to imem, bypassing the AHB bus

    // ======================== Other Interconnecting Signals =======================
    wire        resetHW;        // reset signal for hardware, active high
    wire        CPUreset, CPUsleep;       // status signals
    wire        ROMload;        // rom loader is active
    wire [4:0]  buttons = {btnU, btnD, btnL, btnC, btnR};   // concatenate 5 pushbuttons

    wire        IRQ_uart;
    wire        NMI;        // non-maskable interrupt (not used here)
    wire [14:0] IRQ;        // interrupt signals from up to 16 devices - active high

    // Wires and multiplexer to drive LEDs from two different sources - needed for ROM loader
    wire [11:0] led_rom;        // status output from ROM loader
    wire [15:0] led_gpio;       // led output from GPIO block
    assign led = ROMload ? {4'b0,led_rom} : led_gpio;    // choose which to display

    // ======================== Signals for display on oscilloscope ===================
    assign JA = {HCLK, ahb_cpu_if.HTRANS[1], ahb_cpu_if.HREADY, ahb_cpu_if.HRESP, '0};

    // ======================== Reset Generator ======================================
    // Asserts hardware reset until the clock module is locked, also if reset button pressed.
    // Asserts CPU and bus reset to meet Cortex-M0 requirements, also if ROM loader is active.
    reset_gen resetGen (        // Instantiate reset generator module
        .clk            (HCLK),         // works on system bus clock
        .resetPBn       (btnCpuResetn), // signal from CPU reset pushbutton
        .pll_lock       (1'b1),         // from clock management PLL
        .loader_active  (ROMload),      // from ROM loader hardware
        .cpu_request    (1'b0),  // from CPU, requesting reset
        .resetHW        (resetHW),      // hardware reset output, active high
        .resetCPUn      (HRESETn),      // CPU and bus reset, active low
        .resetLED       (CPUreset)      // status signal for indicator LED
    );

    // ======================== Status Indicator ======================================
    // Drives multi-colour LEDs to indicate status of processor and ROM loader.
    status_ind statusInd (      // Instantiate status indicator module
        .clk            (HCLK),       // works on system bus clock
        .reset          (resetHW),    // hardware reset signal
        .statusIn       ({CPUreset, 1'b0, CPUsleep, ROMload}),  // status inputs
        .rgbLED         (rgbLED)      // output signals for colour LEDs
    );

    // ======================== Processor ========================================
    // Set processor inputs to safe values
    assign RXEV = 1'b0;     // no event
    assign NMI = 1'b0;      // non-maskable interrupt is not active

    // Connect the interrupt signal from the slave to the appropriate bit of IRQ
    // Leave any unused interrupt inputs wired to 0 (inactive)
    assign IRQ = {
        13'b0, IRQ_uart, 1'b0
    };

    // Instantiate Ibex core
    ibex_wrapper cpu (
        .HCLK,
        .HRESETn,
        .AHB_IF     (ahb_cpu_if.master),

        // Other signals
        .NMI         (NMI),         // non-maskable interrupt
        .EXT_IRQ     (1'b0),        // external interrupt
        .IRQ         (IRQ),         // interrupt lines from peripherals
        .SYSTICKCLKDIV(24'd1024),   // a "systick" interrupt will be generated every 1024 clock cycles. Firmware may ignore this
        .core_sleep_o(CPUsleep),    // CPU sleeping, waiting for interrupt

        // Memory interface for instruction fetches
        .instr_if(instr_if.core)
    );

    // ======================== AHB interconnect ======================================
    ahb_interconn interconn (
        .HCLK,
        .HRESETn,
        .master_if   (ahb_cpu_if.interconn),
        .slave_if_s0 (ahb_imem_if.interconn),
        .slave_if_s1 (ahb_ram_if.interconn),
        .slave_if_s2 (ahb_gpio_if.interconn),
        .slave_if_s3 (ahb_uart_if.interconn)
    );

    // ======================== Data memory - block RAM ====================================
    ahb_ram RAM (
        .HCLK,                                  // bus clock
        .HRESETn,                               // bus reset, active low
        .HSEL        (ahb_ram_if.HSEL),         // selects this slave
        .HREADY      (ahb_ram_if.HREADY),       // indicates previous transaction completing
        .HADDR       (ahb_ram_if.HADDR),        // address
        .HTRANS      (ahb_ram_if.HTRANS),       // transaction type (only bit 1 used)
        .HSIZE       (ahb_ram_if.HSIZE),        // transaction width (max 32-bit supported)
        .HWRITE      (ahb_ram_if.HWRITE),       // write transaction
        .HWDATA      (ahb_ram_if.HWDATA),       // write data
        .HRDATA      (ahb_ram_if.HRDATA),       // read data output
        .HREADYOUT   (ahb_ram_if.HREADYOUT)     // ready output
    ); // TODO modify module to take an interface input
    assign ahb_ram_if.HRESP = OKAY;

    // ======================= GPIO block ======================================
    ahb_gpio GPIO (
        // Bus signals
        .HCLK,				                        // bus clock
        .HRESETn,			                        // bus reset, active low
        .HSEL           (ahb_gpio_if.HSEL),	        // selects this slave
        .HREADY         (ahb_gpio_if.HREADY),       // indicates previous transaction completing
        .HADDR          (ahb_gpio_if.HADDR),        // address
        .HTRANS         (ahb_gpio_if.HTRANS),       // transaction type (only bit 1 used)
        .HSIZE          (ahb_gpio_if.HSIZE),        // transaction width (max 32-bit supported)
        .HWRITE         (ahb_gpio_if.HWRITE),       // write transaction
        .HWDATA         (ahb_gpio_if.HWDATA),       // write data
        .HRDATA         (ahb_gpio_if.HRDATA),       // read data output
        .HREADYOUT      (ahb_gpio_if.HREADYOUT),    // ready output
        // GPIO signals
        .gpio_out0      (led_gpio),                 // read-write address 0
        .gpio_out1      (),                         // read-write address 4
        .gpio_in0       (sw),                       // read only address 8
        .gpio_in1       ({11'b0, buttons})          // read only address C
    );
    assign ahb_gpio_if.HRESP = OKAY;

    // ======================= UART block ======================================
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

    // ======================= ROM ======================================
    // Read-only memory which is accessible by three means:
    // - AHB bus has read access
    // - Simple memory interface (for instruction fetches) (read-only)
    // - Loader interface (write-only)

    imem imem (
        // AHB bus
        // TODO add a write port and detect illegal writes to generate an error response
        .HCLK,
        .HRESETn,
        .HSEL           (ahb_imem_if.HSEL),
        .HREADY         (ahb_imem_if.HREADY),
        .HADDR          (ahb_imem_if.HADDR),
        .HTRANS         (ahb_imem_if.HTRANS),
        .HRDATA         (ahb_imem_if.HRDATA),
        .HREADYOUT      (ahb_imem_if.HREADYOUT),

        // Memory interface for instruction fetches
        .instr_if       (instr_if.rom),

        // Connections for ROM loader
        .resetHW        (resetHW),			// hardware reset
        .loadButton     (btnU),		        // pushbutton to activate loader
        .serialRx	    (serialRx),         // serial input
        .rom_load_status(led_rom),          // 12-bit word count for display on LEDs
        .rom_load_active(ROMload)			// loader active
    );
    assign ahb_imem_if.HRESP = OKAY;
endmodule