`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
// 
// Create Date:   20 October 2014 
// Design Name: 	Cortex-M0 DesignStart system
// Module Name:   AHBgpio 
// Description: 	Provides two 16-bit output ports at relative address 0 and 4,
//						and two 16-bit input ports at address 8 and C.
//						16-bit data is right-justified in words on 32-bit transfers.
//						Also supports byte and half-word write transactions.
//						This version does not support interrupt generation...
//
// Revision: 
// Revision 0.01 - File Created
// Revision 1 - modified for synchronous reset, October 2015
//
//////////////////////////////////////////////////////////////////////////////////
module AHBgpio(
			// Bus signals
			input wire HCLK,				// bus clock
			input wire HRESETn,			// bus reset, active low
			input wire HSEL,				// selects this slave
			input wire HREADY,			// indicates previous transaction completing
			input wire [31:0] HADDR,	// address
			input wire [1:0] HTRANS,	// transaction type (only bit 1 used)
			input wire HWRITE,			// write transaction
			input wire [2:0] HSIZE,		// transaction width (max 32-bit supported)
			input wire [31:0] HWDATA,	// write data
			output wire [31:0] HRDATA,	// read data from slave
			output wire HREADYOUT,		// ready output from slave
			// GPIO signals
			output [15:0] gpio_out0,	// read-write address 0
			output [15:0] gpio_out1,	// read-write address 4
			input [15:0] gpio_in0,		// read only address 8
			input [15:0] gpio_in1		// read only address C
    );
	
	// Registers to hold signals from address phase
	reg [3:0] rHADDR;			// only need 4 bits of address
	reg [1:0] rHSIZE;			// only need 2 bits of size
	reg rWrite;                // store one bit to indicate write transaction 
	
	// Registers for input and output ports
	reg [15:0] in0A, in0B, in1A, in1B;		// double registers for sync.
	reg [7:0] out0L, out0H, out1L, out1H;	// byte registers - two per port
	assign gpio_out0 = {out0H, out0L};		// concatenate two bytes to get 16-bit output
	assign gpio_out1 = {out1H, out1L};
	

	// Internal control signals
	reg [1:0] byteWrite;	// individual byte write enable signals
	wire  nextWrite = HSEL & HWRITE & HTRANS[1];	// slave selected for write transfer
	reg [15:0]	readData;		// 16-bit data from read multiplexer

 	// Capture bus and internal signals in address phase
	always @(posedge HCLK)
		if(!HRESETn)
			begin
				rHADDR <= 4'b0;
				rHSIZE <= 2'b0;
				rWrite <= 1'b0;
			end
		else if(HREADY)       // only update if HREADY is 1 - previous transaction completing
             begin
                rHADDR <= HADDR[3:0];         // capture signals from address phase
                rHSIZE <= HSIZE[1:0];         // for use in data phase
                rWrite <= nextWrite;
             end

	// Generate byte write enable signals based on captured control signals
	always @ (rWrite, rHSIZE, rHADDR[1:0])
		if (rWrite)		// write transaction in progress
			case ({rHSIZE, rHADDR[1:0]})	// select on size and LSBs of address
				4'b00_00:	byteWrite = 2'b01;		// writing least significant byte
				4'b00_01:	byteWrite = 2'b10;		// writing second byte
				4'b01_00:	byteWrite = 2'b11;		// writing least significant halfword
				4'b10_00:	byteWrite = 2'b11;		// writing full word
				default:    byteWrite = 2'b00;		// anything else - no write				
			endcase
		else				byteWrite = 2'b00;		// not writing
	
	//	Output port registers
	always @(posedge HCLK)
		if(!HRESETn)
			begin
				out0L <= 8'b0;
				out0H <= 8'b0;
				out1L <= 8'b0;
				out1H <= 8'b0;
			end
		else 
		 begin		
				if (byteWrite[0] && (rHADDR[3:2] == 2'h0)) out0L <= HWDATA[7:0];
				if (byteWrite[1] && (rHADDR[3:2] == 2'h0)) out0H <= HWDATA[15:8];
				if (byteWrite[0] && (rHADDR[3:2] == 2'h1)) out1L <= HWDATA[7:0];
				if (byteWrite[1] && (rHADDR[3:2] == 2'h1)) out1H <= HWDATA[15:8];
		 end
	
	//	Input port registers
	always @(posedge HCLK)
		if(!HRESETn)
			begin
				in0A <= 16'b0;
				in0B <= 16'b0;
				in1A <= 16'b0;
				in1B <= 16'b0;
			end
		else 
		 begin		
				in0A <= gpio_in0;  // A registers take data from ports, not synchronised
				in1A <= gpio_in1;
				in0B <= in0A;		// B registers copy from A registers - should be safe
				in1B <= in1A;
		 end
		
	// Bus output signals
	always @(in0B, in1B, gpio_out0, gpio_out1, rHADDR)
		case (rHADDR[3:2])		// select on word address
			2'h0:		readData = gpio_out0;		// address ends in 0x0
			2'h1:		readData = gpio_out1;		// address ends in 0x4
			2'h2:		readData = in0B;		    // address ends in 0x8
			2'h3:		readData = in1B;			// address ends in 0xC			
		endcase
		
	assign HRDATA = {16'b0, readData};	// extend with 0 bits for bus read
	assign HREADYOUT = 1'b1;	// always ready - transaction never delayed
       
endmodule
