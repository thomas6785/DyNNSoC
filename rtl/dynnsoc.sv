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

    localparam  BAD_DATA = 32'hdeadbeef;  // value read from invalid slave
    localparam  OKAY = 1'b0, ERROR = 1'b1;  // values for the HRESP signal

    // ========================= Bus Signals =====================================
    // Define AHB Lite bus signals - do not change any of these
    // Note that signals HMASTLOCK and HBURST are omitted - not used by processor
    wire        HRESETn;    // active low reset
    // Signals from the processor to all the slaves
    wire [31:0]	HWDATA;     // write data
    wire [31:0]	HADDR;      // address
    wire 		HWRITE;     // write signal
    wire [1:0] 	HTRANS;     // transaction type
    wire [3:0] 	HPROT;      // protection (not used here)
    wire [2:0] 	HSIZE;      // transaction width
    // Signals to the processor from the multiplexers
    wire [31:0] HRDATA;     // read data
    wire		HREADY;     // ready signal from active slave
    wire 		HRESP;      // error response

    // ========================= Interface for instruction fetches =====================
    instruction_fetch_if instr_if(); // instantiate the instruction fetch interface

    // ====================== Signals to and from individual slaves ==================
    wire        HSEL_imem, HSEL_ram, HSEL_dummy, HSEL_gpio, HSEL_uart;
    wire [31:0] HRDATA_imem, HRDATA_ram, HRDATA_gpio, HRDATA_uart;     // read data from each slave
    wire        HREADYOUT_imem, HREADYOUT_ram, HREADYOUT_dummy, HREADYOUT_gpio, HREADYOUT_uart;   // ready output from each slave
    wire        HRESP_dummy, HRESP_uart;  // some slaves uses HRESP to signal an error response

    // ======================== Other Interconnecting Signals =======================
    wire        resetHW;        // reset signal for hardware, active high
    wire        CPUreset, CPUsleep;       // status signals
    wire        ROMload;        // rom loader is active
    wire [3:0]  muxSel;         // from address decoder to control the multiplexer
    wire [4:0]  buttons = {btnU, btnD, btnL, btnC, btnR};   // concatenate 5 pushbuttons

    wire        IRQ_uart;
    wire        NMI;        // non-maskable interrupt (not used here)
    wire [14:0]	IRQ;        // interrupt signals from up to 16 devices - active high

    // Wires and multiplexer to drive LEDs from two different sources - needed for ROM loader
    wire [11:0] led_rom;        // status output from ROM loader
    wire [15:0] led_gpio;       // led output from GPIO block
    assign led = ROMload ? {4'b0,led_rom} : led_gpio;    // choose which to display

    // ======================== Signals for display on oscilloscope ===================
    assign JA = {HCLK, HTRANS[1], HREADY, HRESP, '0};

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


    // Instantiate Cortex-M0 DesignStart processor and connect signals
    ibex_wrapper cpu (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        // Outputs to the AHB-Lite bus
        .HWDATA      (HWDATA),
        .HADDR       (HADDR),
        .HWRITE      (HWRITE),
        .HTRANS      (HTRANS),
        .HPROT       (HPROT),
        .HSIZE       (HSIZE),
        // Inputs from the AHB-Lite bus
        .HRDATA      (HRDATA),
        .HREADY      (HREADY),
        .HRESP       (HRESP),
        // Other signals
        .NMI         (NMI),
        .EXT_IRQ     (1'b0),        // no external interrupts in this design
        .IRQ         (IRQ),
        .SYSTICKCLKDIV(24'd1024),  // an interrupt will be generated every 1024 clock cycles. Firmware may ignore this
        .core_sleep_o(CPUsleep),     // CPU sleeping, waiting for interrupt

        // Memory interface for instruction fetches
        .instr_if(instr_if.core)
    );



    // ======================== Address Decoder ======================================
    // Implements address map, generates slave select signals and controls mux
    // ## As you add more slaves, you need to use more of the slave select signals
    AHBDCD decode (
        .HADDR      (HADDR),         // address in
        .HSEL_S0    (HSEL_imem),
        .HSEL_S1    (HSEL_ram),
        .HSEL_S2    (HSEL_gpio),
        .HSEL_S3    (HSEL_uart),
        .HSEL_S4    (),
        .HSEL_S5    (),
        .HSEL_S6    (),
        .HSEL_S7    (),
        .HSEL_S8    (),
        .HSEL_S9    (),
        .HSEL_NOMAP (HSEL_dummy),   // select dummy slave if invalid address given
        .MUX_SEL    (muxSel)        // multiplexer control signal out
    );


    // ======================== Multiplexer ======================================
    // Selects appropriate slave output signals to pass to master
    AHBMUX mux (
        .HCLK           (HCLK),             // bus clock and reset
        .HRESETn        (HRESETn),
        .MUX_SEL        (muxSel[3:0]),     // control from address decoder

        // Connect the read data signals to the data multiplexer
        .HRDATA_S0      (HRDATA_imem),
        .HRDATA_S1      (HRDATA_ram),
        .HRDATA_S2      (HRDATA_gpio),
        .HRDATA_S3      (HRDATA_uart),
        .HRDATA_S4      (BAD_DATA),
        .HRDATA_S5      (BAD_DATA),
        .HRDATA_S6      (BAD_DATA),         // unused inputs give BAD_DATA
        .HRDATA_S7      (BAD_DATA),
        .HRDATA_S8      (BAD_DATA),
        .HRDATA_S9      (BAD_DATA),
        .HRDATA_NOMAP   (BAD_DATA),         // dummy slave also gives BAD_DATA
        .HRDATA         (HRDATA),           // read data output to master

        // Connect the ready signals to the ready multiplexer
        .HREADYOUT_S0   (HREADYOUT_imem),
        .HREADYOUT_S1   (HREADYOUT_ram),
        .HREADYOUT_S2   (HREADYOUT_gpio),
        .HREADYOUT_S3   (HREADYOUT_uart),
        .HREADYOUT_S4   (1'b1),
        .HREADYOUT_S5   (1'b1),
        .HREADYOUT_S6   (1'b1),             // unused inputs must be tied to 1
        .HREADYOUT_S7   (1'b1),
        .HREADYOUT_S8   (1'b1),
        .HREADYOUT_S9   (1'b1),
        .HREADYOUT_NOMAP(HREADYOUT_dummy),  // ready signal from dummy slave
        .HREADY         (HREADY),           // ready output to master and all slaves

        // Connect the response signals to the response multiplexer
        .HRESP_S0    (OKAY),    // the ROM and RAM slaves do not have HRESP ports, as they
        .HRESP_S1    (OKAY),    // never signal an error, so response is always OKAY
		.HRESP_S2    (OKAY),
        .HRESP_S3    (HRESP_uart),
        .HRESP_S4    (OKAY),
        .HRESP_S5    (OKAY),
        .HRESP_S6    (OKAY),    // unused reponse inputs should also be OKAY
        .HRESP_S7    (OKAY),
        .HRESP_S8    (OKAY),
        .HRESP_S9    (OKAY),
        .HRESP_NOMAP (HRESP_dummy),  // response signal from dummy slave
        .HRESP       (HRESP)         // reponse output to master
    );


    // ======================== Data memory - block RAM ====================================
    AHBram RAM (
        .HCLK        (HCLK),                // bus clock
        .HRESETn     (HRESETn),             // bus reset, active low
        .HSEL        (HSEL_ram),            // selects this slave
        .HREADY      (HREADY),              // indicates previous transaction completing
        .HADDR       (HADDR),               // address
        .HTRANS      (HTRANS),              // transaction type (only bit 1 used)
        .HSIZE       (HSIZE),               // transaction width (max 32-bit supported)
        .HWRITE      (HWRITE),              // write transaction
        .HWDATA      (HWDATA),              // write data
        .HRDATA      (HRDATA_ram),          // read data output
        .HREADYOUT   (HREADYOUT_ram)        // ready output
    );

    // ======================= GPIO block ======================================
    AHBgpio GPIO(
        // Bus signals
        .HCLK,				  // bus clock
        .HRESETn,			  // bus reset, active low
        .HSEL(HSEL_gpio),	  // selects this slave
        .HREADY,              // indicates previous transaction completing
        .HADDR,               // address
        .HTRANS,              // transaction type (only bit 1 used)
        .HSIZE,               // transaction width (max 32-bit supported)
        .HWRITE,              // write transaction
        .HWDATA,              // write data
        .HRDATA      (HRDATA_gpio),          // read data output
        .HREADYOUT   (HREADYOUT_gpio),        // ready output
        .gpio_out0   (led_gpio),	// read-write address 0
        .gpio_out1   (),	// read-write address 4
        .gpio_in0    (sw),		// read only address 8
        .gpio_in1    ({11'b0, buttons})		// read only address C
    );

    // ======================= UART block ======================================
    AHBuart UART(
        // Bus signals
        .HCLK   (HCLK),				// bus clock
        .HRESETn (HRESETn),            // bus reset, active low
        .HSEL (HSEL_uart),                // selects this slave
        .HREADY      (HREADY),              // indicates previous transaction completing
        .HADDR       (HADDR),               // address
        .HTRANS      (HTRANS),              // transaction type (only bit 1 used)
        .HWRITE      (HWRITE),              // write transaction
        .HWDATA      (HWDATA),              // write data
        .HRDATA      (HRDATA_uart),          // read data output
        .HREADYOUT   (HREADYOUT_uart),        // ready output
        .HRESP(HRESP_uart),			// response output from slave
        .serialRx(serialRx),			// serial receive, idles at 1
        .serialTx(serialTx),		// serial transmit, idles at 1
        .uart_IRQ(IRQ_uart)			// interrupt request
    );

    // ======================= Dummy Slave ======================================
    // Dummy slave only needs the type of transaction to decide how to respond.
    // The response is OKAY for IDLE and BUSY transactions, otherwise ERROR.

    AHBdummy DUMMY(
        .HCLK        (HCLK),            // bus clock
        .HRESETn     (HRESETn),         // bus reset, active low
        .HSEL        (HSEL_dummy),      // selects this slave
        .HREADY      (HREADY),          // indicates previous transaction completing
        .HTRANS      (HTRANS),          // transaction type (only bit 1 used)
        .HREADYOUT   (HREADYOUT_dummy), // ready output
        .HRESP       (HRESP_dummy)      // response output
    );

    // ======================= ROM ======================================
    // Read-only memory which is accessible by three means:
    // - AHB bus has read access
    // - Simple memory interface (for instruction fetches) (read-only)
    // - Loader interface (write-only)

    imem imem (
        // AHB bus
        .HCLK,
        .HRESETn,
        .HSEL       (HSEL_imem),
        .HREADY,
        .HADDR,
        .HTRANS,
        .HRDATA     (HRDATA_imem),
        .HREADYOUT  (HREADYOUT_imem),

        // Memory interface for instruction fetches
        .instr_if(instr_if.rom),

        // Connections for ROM loader
        .resetHW        (resetHW),			// hardware reset
        .loadButton     (btnU),		        // pushbutton to activate loader
        .serialRx	    (serialRx),         // serial input
        .rom_load_status(led_rom),          // 12-bit word count for display on LEDs
        .rom_load_active(ROMload)			// loader active
    );

endmodule
