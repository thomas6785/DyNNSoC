`timescale 1ns / 1ns

module imem (
	input wire clk,				// bus clock

	// Read-only memory interface
	input wire rst_n,			// bus reset, active low
	input wire req,				// read request
	input wire [31:0] addr,		// address
	output wire [31:0] rdata,	// read data from slave
	output wire ready,			// ready output from slave

	// Write-only UART interface
	input wire resetHW,			// hardware reset
	input wire loadButton,		// pushbutton to activate loader
	input wire serialRx,	    // serial input
	output [11:0] status,       // 12-bit output to indicate progress of ROM load for debug
	output ROMload			    // loader active
);
	
	localparam ADDR_WIDTH	= 15;		// 32kByte = 8k words of 32 bits
	
	wire [7:0] rxByte;
	wire newByte, wNow;
	wire [ADDR_WIDTH-3:0] wAddr;
	wire [31:0] wData;

	assign status = wAddr;     // widths may not match - ok	
	assign ready = 1'b1; // ROM is always ready to accept requests (no wait states)

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
		.HCLK			(clk),				// bus clock
		.resetHW		(resetHW),			// hardware reset
		.loadButton	(loadButton),		// pushbutton to activate loader
		.rxByte		(rxByte),	      // input byte from uart receiver
		.newByte		(newByte),				// strobe to indicate new byte
		.wAddr		(wAddr),        // write address
		.wData		(wData),			// data to memory
		.wNow			(wNow),					// write control signal
		.ROMload		(ROMload)			// loader active
		);

	imem_ram #(
		.ADDR_W(ADDR_WIDTH)
	) imem (
		.clk(clk),
		.rd_en(req),
		.rd_addr(addr[ADDR_WIDTH-1:0]), // word aligned addresses
		.rd_word(rdata),
		.wr_en(wNow), // write signal from the ROM loader
		.wr_addr({wAddr,2'b0}),
		.wr_word(wData)
	);

endmodule
