`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
// 
// Create Date:   21:37:44 10/14/2014 
// Design Name: 	Cortex-M0 DesignStart system
// Module Name:   ram_loader 
// Description: 	State machine to enter ROMload mode if button pressed after reset.
//			When active, takes bytes from uart, converts from ASCII hex to binary,
//			outputs 32-bit words and control signal to write words to block ram.
//			Returns to normal if Q received, or on normal reset.
//
// Revision: 
// Revision 0.01 - File Created
// Revision 1 - modified for synchronous reset, October 2015
//
//////////////////////////////////////////////////////////////////////////////////
module ram_loader( HCLK, resetHW, loadButton, rxByte, newByte, wAddr, wData, wNow, ROMload);
		parameter ADDR_WIDTH	= 15;		// 32kByte = 8k words of 32 bits
		input  HCLK;				// bus clock
		input  resetHW;			// hardware reset
		input  loadButton;		// pushbutton to activate loader
		input  [7:0] rxByte;	      // input byte from uart receiver
		input  newByte;				// strobe to indicate new byte
		output [ADDR_WIDTH-3:0] wAddr;        // write address
		output [31:0] wData;			// data to memory
		output wNow;					// write control signal
		output reg ROMload;			// loader active
	

// =============== Loader Hardware =========================================
// If button is pressed on first clock edge after reset, enter active state.
// If not, go to idle state and stay there forever.
// In active state, act on bytes received: if hex char, store nibble in array,
// after 8 nibbles, if end of line, write word to PROM, if Q, go to idle state.
// If anything unexpected arrives, go to error state and stay there forever.

    // State machine to control everything
	localparam [1:0] INIT = 2'd0, IDLE = 2'd1, ACTIVE = 2'd2, ERROR = 2'd3;
	reg [1:0] loadState, loadNext;	// state register
	reg storeNibble, storeWord;		// FSM output signals (also ROMload)

    // Signals for decoder
	localparam [1:0] ENDL = 2'd0, HEX = 2'd1, QUIT = 2'd2, OTHER = 2'd3;
	reg [1:0] byteType, nextType;	// decoder output - type of byte received
	reg [3:0] nibbleIn, nextIn;		// decoded nibble
	reg newDecode;					// new decoded output

    // Storage for the received nibbles, with counter	
	reg [3:0] nibbleReg [0:7];			// array of 8 nibble registers
	reg [3:0] nibbleCount;				// nibble count (0 to 8 as received)
	wire fullWord = (nibbleCount == 4'd8);	// 8 nibbles received
	wire partWord = (nibbleCount > 4'd0);	// some nibbles received
	
	// Nibbles combined to word, first on left, for writing to memory
	wire [31:0] wData = {nibbleReg[0], nibbleReg[1], nibbleReg[2], nibbleReg[3], 
	                       nibbleReg[4], nibbleReg[5], nibbleReg[6], nibbleReg[7]};
	reg [ADDR_WIDTH-3:0] wordCount;	// word count
	assign wAddr = wordCount;     // memory address is same as word count
	assign wNow = storeWord;		// write enable comes from state machine
	
//====================================== State Machine =====================================
	// State register
	always @ (posedge HCLK)
		if (resetHW) loadState <= INIT;
		else loadState <= loadNext;
		
	// Next state and output logic - Mealy machine
	always @ (loadState, loadButton, newDecode, byteType, fullWord, partWord)
		begin
			loadNext = loadState;  // default is no state change
			storeNibble = 1'b0;	// default values of output signals
			storeWord = 1'b0;
			
			case (loadState)
				INIT:		begin	// move to active or idle, depending on button
								if (loadButton) loadNext = ACTIVE;
								else loadNext = IDLE;
								ROMload = 1'b0;	// not active
							end
				IDLE:		ROMload = 1'b0;	// not active, no state change...
				ACTIVE:	begin
								ROMload = 1'b1;	// indicate active
								if (newDecode)	// if a byte has been received
									case (byteType)
										HEX: 	if (fullWord) loadNext = ERROR; // ninth nibble
												else storeNibble = 1'b1;  // store nibble
										ENDL: if (fullWord) storeWord = 1'b1;  // store word
												else if (partWord) loadNext = ERROR; // end of line mid-word
										QUIT: if (partWord) loadNext = ERROR;	// unexpected quit
												else loadNext = IDLE; // quit at nibble count 0
										default:	loadNext = ERROR;	// unexpected byte
									endcase
							end
				ERROR:	ROMload = 1'b1;	// indicate active, but no state change
				default:	ROMload = 1'b0;	// not active, no state change...
			endcase
		end

//================================ Nibble storage, Nibbles and Word counters =================================		
	// Nibble registers
    integer i;
    always @ (posedge HCLK)
        if (resetHW) for (i=0; i<=7; i=i+1) nibbleReg[i] <= 4'b0;    // clear all
        else if (storeNibble) nibbleReg[nibbleCount] <= nibbleIn;    // store nibble

	// Nibble counter - advance on storeNibble, clear on storeWord
	always @ (posedge HCLK)
		if (resetHW) nibbleCount <= 4'd0;
		else if (storeNibble) nibbleCount <= nibbleCount + 1'd1;
		else if (storeWord) nibbleCount <= 4'd0;
		
	// Word counter - advance on storeWord signal - wraps if too many words!!
	always @ (posedge HCLK)
		if (resetHW) wordCount <= {ADDR_WIDTH{1'b0}};
		else if (storeWord) wordCount <= wordCount + 1'd1;

//========================== Byte decoding =================================================
// Decoder converts received bytes into data nibbles, detects end of line, etc.	
	// All outputs registered, so delayed one clock cycle - plenty of time for comb. logic
	always @ (posedge HCLK)
		if (resetHW) begin
							nibbleIn <= 4'b0;
							byteType	<= ENDL;
							newDecode <= 1'b0;
						 end
		else 	begin
							nibbleIn <= nextIn;
							byteType <= nextType;
							newDecode <= newByte;
				end

    // Decoding logic
	always @ (rxByte, newByte)
		begin
			nextType = OTHER;			// default value
			nextIn = rxByte[3:0];	// take lower 4 bits of received byte
		
			case (rxByte[7:4])	// test upper half of byte
				4'h0:		// control group - check for LF or CR
						if (nextIn == 4'hA || nextIn == 4'hD) nextType = ENDL;
				4'h3:		// number group - check <= 9
						if (nextIn <= 4'h9) nextType = HEX;
				4'h4, 4'h6:		// letter groups - check A to F
						if (nextIn > 4'h0 && nextIn < 4'h7) begin
									nextType = HEX;			// set type as hex
									nextIn = nextIn + 4'h9;	// set nibble value
								end
				4'h5, 4'h7:		// letter groups - check for Q
						if (nextIn == 4'h1) nextType = QUIT;
				default: nextType = OTHER;		// not really needed
			endcase
		end
 
endmodule
