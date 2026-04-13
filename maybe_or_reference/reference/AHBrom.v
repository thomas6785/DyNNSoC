`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
//
// Create Date:   21:37:44 10/14/2014
// Design Name: 	Cortex-M0 DesignStart system
// Module Name:   AHBrom
// Description: 	Provides on-chip program memory on AHBlite bus - 32kByte.
//			Uses dual-port block ram, with load facilty through serial port.
//			Loader active if button signal high after reset.
//
// Revision:
// Revision 0.01 - File Created
//
//////////////////////////////////////////////////////////////////////////////////
module AHBrom(
			input wire HCLK,				// bus clock
			// Bus interface - read only
			input wire HRESETn,			// bus reset, active low
			input wire HSEL,			// selects this slave
			input wire HREADY,			// indicates previous transaction completing
			input wire [31:0] HADDR,	// address
			input wire [1:0] HTRANS,	// transaction type (only bit 1 used)
//			input wire HWRITE,			// write transaction (ignored)
//			input wire [2:0] HSIZE,		// transaction width (ignored)
//			input wire [31:0] HWDATA,	// write data (ignored)
			output wire [31:0] HRDATA,	// read data from slave
			output wire HREADYOUT,		// ready output from slave
			// Loader connections
			input wire resetHW,			// hardware reset
			input wire loadButton,		// pushbutton to activate loader
			input wire serialRx,	    // serial input
			output [11:0] status,        // 12-bit output to indicate progress
			output ROMload			// loader active
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

	// Instantiate the block ram - created by Xilinx IP generator (in VHDL)
    blk_mem_8Kword bram1 (
        .clka       (HCLK),             // port A is write port
        .ena        (ROMload),          // port A enabled during rom load only
        .wea        (wNow),        // write enable
        .addra      (wAddr),        // write address
        .dina       (wData),           // write data
        .clkb       (HCLK),             // port B is read port
        .enb        (~ROMload),         // port B disabled during rom load
        .addrb      (HADDR[ADDR_WIDTH-1:2]),      // read uses bus address
        .doutb      (HRDATA)            // read data goes directly to bus
        );

endmodule
