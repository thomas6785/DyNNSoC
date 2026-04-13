`timescale 1ns / 1ns

// Adapted from Brian Mulkeen's ROM module for Digital & Embedded Systems
// TODO add details to source

/*
Instantiates a RAM with two read/write ports

Generally:
- Port A is read-only and accessible via the AHB bus. Only 32-bit words are supported.
- Port B is also read-only and accessible via the simpler memory inteface (addr,rdata,ready,req). This is intended for the core to fetch instructions without going through the AHB bus. Only 32-bit words are supported.

The ROM can be loaded via UART. While it is loading, port B is disabled for reading.
*/

module imem (
    input wire HCLK,				// bus clock

    // AHB interface - read only
    input wire HRESETn,			// bus reset, active low
    input wire HSEL,			// selects this slave
    input wire HREADY,			// indicates previous transaction completing
    input wire [31:0] HADDR,	// address
    input wire [1:0] HTRANS,	// transaction type (only bit 1 used)
//	input wire HWRITE,			// write transaction (ignored)
//	input wire [2:0] HSIZE,		// transaction width (ignored)
//	input wire [31:0] HWDATA,	// write data (ignored)
    output wire [31:0] HRDATA,	// read data from slave
    output wire HREADYOUT,		// ready output from slave

    // Memory interface for core instruction fetches - read only
    instruction_fetch_if.rom instr_if,

    // UART loader connections
    input wire resetHW,			// hardware reset
    input wire loadButton,		// pushbutton to activate loader
    input wire serialRx,	    // serial input
    output [11:0] rom_load_status,        // 12-bit output to indicate progress
    output rom_load_active			// loader active
);
    localparam ADDR_WIDTH	= 15;		// 32kByte = 8k words of 32 bits

    wire [7:0] rxByte;
    wire newByte, wNow;
    wire [ADDR_WIDTH-3:0] wAddr;
    wire [31:0] wData;

    assign HREADYOUT = 1'b1;	// always ready - transaction never delayed
    assign status = wAddr;     // widths may not match - ok

    // Instantiate UART receive block (includes bit-rate generator)
    uart_RXonly uart1 (
        .clk        (HCLK),          // 50 MHz clock
        .rst        (resetHW),       // asynchronous reset
        .rxd        (serialRx),      // serial data in (idle at logic 1)
        .rxdout     (rxByte),        // 8-bit received data
        .rxnew      (newByte)       // one-cycle strobe signal
        );

    // Instantiate the loader hardware
    ram_loader # (.ADDR_WIDTH(ADDR_WIDTH)) loader (
        .HCLK			(HCLK),				// bus clock
        .resetHW		(resetHW),			// hardware reset
        .loadButton	(loadButton),		// pushbutton to activate loader
        .rxByte		(rxByte),	      // input byte from uart receiver
        .newByte		(newByte),				// strobe to indicate new byte
        .wAddr		(wAddr),        // write address
        .wData		(wData),			// data to memory
        .wNow			(wNow),					// write control signal
        .ROMload		(ROMload)			// loader active
        );

    // Instantiate the block RAM
    assign rom_load_active = ROMload;
    assign instr_if.ready = ~ROMload; // disale reads on the memory interface while loading
    ram_2port_true #(
        .ADDR(ADDR_WIDTH-2) // this module expects word addresses, so we can cut off 2 LSBs
    ) bram (
        .clk      ( HCLK ),

        // Port A - read for memory interface (or writes while loading)
        .p1_en    ( 1'b1 ), // always enabled - the loader will just disable writes when it's not active and the memory interface is always ready
        .p1_addr  ( ROMload ? wAddr : instr_if.addr[ADDR_WIDTH-1:2] ), // read address from memory interface, write address from loader
        .p1_din   ( wData ), // write data from the UART loader
        .p1_dout  ( instr_if.rdata ), // read data to the memory interface
        .p1_we    ( ROMload ? wNow : 1'b0 ), // enable writes when loading, disable otherwise

        // Port B - read for AHB interface
        .p2_en    ( ~ROMload                ),
        .p2_addr  ( HADDR[ADDR_WIDTH-1:2]   ),
        .p2_din   ( '0                      ), // irrelevant - writes are disabled
        .p2_dout  ( HRDATA                  ),
        .p2_we    ( 1'b0                    ) // disable writes on this port
    );
    initial $readmemh("/home/tudentstudent/DyNNSoC/firmware/dynnsoc/main.hex", bram.mem);  // preload ROM with some data for testing
endmodule
