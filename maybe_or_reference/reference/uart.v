`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
// 
// Create Date:    16:20:38 10 July 2012 
// Module Name:    uart   
// Target Devices: Spartan3, Kintex7
// Description: 	 Simple self-contained UART block for clock >> bit rate.
//			Transmit & receive 8 bit, no parity, 1 stop bit.
//			Bit rate is set using INCR parameter in timing block.
//
// Revision 0 - File Created
// Revision 1, 20 October 2014 - modified to sample rxd on bit8x,
//					added FF for bit8x for timing, tidied state names and comments
// Revision 2 - modified for synchronous reset, October 2015
//////////////////////////////////////////////////////////////////////////////////
module uart(
    input clk,						// main clock, drives all logic
    input rst,						// asynchronous reset
    input [7:0] txdin,			// 8-bit data to be transmitted
    input txgo,					// indicates new data to send, ignored if not ready
    output reg txd,				// serial data out (idle at logic 1, high)
    output txrdy,					// transmitter ready for new data
    input rxd,						// serial data in (idle at logic 1, high)
    output reg [7:0] rxdout,	// 8-bit received data
    output rxnew					// indicates new data available, asserted for 1 clock
    );

// Timing block:  Receiver needs pulses at 8 X bitrate, transmitter at bitrate.
// Uses frequency synthesis technique with 20-bit accumulator.
// bit8x frequency is clock frequency * increment / 2**20
// so with 50 MHz clock, increment of 6442 gives bit8x at 307178.5 Hz = 8 X 38397.3 Hz
	//localparam INCR = 20'd6442;	// increment value for 38400 bit/s at 50 MHz
	localparam INCR = 20'd3221;	// increment value for 19200 bit/s at 50 MHz
	//localparam INCR = 20'd206144;  // 32 times faster for simulation
	
	reg [20:0] accum;		// 20-bit accumulator register with extra bit for carry
	wire [20:0] accsum = accum[19:0] + INCR;	// ignore previous carry on add
	
	always @(posedge clk)	// accumulator behaviour
		if (rst) accum <= 21'b0;		// clear on reset
		else accum <= accsum;	// load sum bits on clock

	wire bit8x = accum[20];	// carry gives 8 X bit clock pulse for receive block
	
	reg [2:0] div8;		// 3-bit counter for divide by 8
	always @(posedge clk)	// counter behaviour
		if (rst) div8 <= 3'b0;			// clear on reset
		else if (bit8x) div8 <= div8 + 3'b1;		// increment on clock

	wire bit1x = bit8x & (div8 == 3'b111);	// bit clock pulse for transmit block

// =====================================================================================	
// Transmit block:  Takes 8-bit data input and transmits start bit (0), data bits
// (LSB first), then stop bit (1).  Signal txrdy is low during transmission, high during
// stop bit and idle. Signal txgo causes new data to be loaded for transmission, if ready.
//	To send continuously, apply new data and assert txgo soon after txrdy returns high
// (within one bit time).  Alternatively, hold txgo at 1.  Then txrdy will go high for 
// one clock cycle at the start of each stop bit, new data will be loaded on clock edge
// just before txrdy returns low.

	reg [7:0] datareg;				// 8-bit data register
	reg [3:0] bitcount;				// bit counter, acting as state machine
	
	always @(posedge clk)	// data register behaviour
		if (rst) datareg <= 8'b0;		// clear on reset
		else if (txgo & txrdy) datareg <= txdin;	// load data on go signal, if ready

// Counter/state machine: 10 = pending, 9 = start bit, 0 = stop bit or idle
// Moves to pending state on go signal while in state 0.  Output remains 1.
// Other state changes happen on bit pulse...
	always @ (posedge clk)
		if (rst) bitcount <= 4'd0;				// reset
		else if (txgo & txrdy) bitcount <= 4'd10;	// pending state
		else if (bit1x & (~txrdy)) bitcount <= bitcount - 4'd1;	// count down
		// counting stops when count reaches 0
		
// Generate the status output - ready for new data if count at zero
	assign txrdy = (bitcount == 4'd0);
	
// Generate the serial output data, using multiplexer
	always @ (bitcount or datareg)
		case (bitcount)
			4'd10:	txd = 1'b1;			// pending state, output 1
			4'd9:		txd = 1'b0;			// start bit
			4'd8:		txd = datareg[0];	// LSB
			4'd7:		txd = datareg[1];
			4'd6:		txd = datareg[2];
			4'd5:		txd = datareg[3];
			4'd4:		txd = datareg[4];
			4'd3:		txd = datareg[5];
			4'd2:		txd = datareg[6];
			4'd1:		txd = datareg[7];	// MSB
			4'd0:		txd = 1'b1;			// stop bit or idle
			default:	txd = 1'b1;
		endcase

// =====================================================================================	
// Receive block: Starts at 1 to 0 transition of rxd, puts samples of rxd in shift reg.
// When stop bit received, copies data into output register, asserts rxnew signal for 
//	one clock cycle.  Ouptut register will be over-written when next byte has arrived, 
// so must be read within less than 10 bit times to avoid data loss.

// Internal signals	 
	reg [1:0] sync;		// 2-bit shift register
	wire din;				// data input (after synchroniser)
	reg [8:0] shiftreg;	// 9-bit shift register
	wire sample;			// enable signal for shift reg
	wire stopbit = shiftreg[8];	// will be stop bit at end of receive
	reg [6:0] rxcount;	// 7-bit counter for timing
	wire done;				// ten bits have been received
	reg [1:0] state, next;	// state machine signals
	wire rxgo;					// output from state machine, controls counter

// First synchronise incoming data with the bit8x pulses
	always @ (posedge clk)
		if (rst) sync <= 2'b11;		// reset to idle input
		else if (bit8x) sync <= {rxd, sync[1]};	// shift right...
		
	assign din = sync[0];	// rightmost bit is synchronised data input

// Main shift register - convert serial to parallel data
	always @ (posedge clk)
		if (rst) shiftreg <= 9'b0;			// reset to zero
		else if (sample)						// on sampling pulse 
			shiftreg <= {din, shiftreg[8:1]};	// shift right...

// 7-bit counter - provides sample times and bit count
	always @ (posedge clk)
		if (rst) rxcount <= 7'b0;				// reset to zero
		else if (rxgo == 1'b0) rxcount <= 7'b0;	// hold at zero when disabled	
		else if (bit8x) rxcount <= rxcount + 1'b1;	// count at 8 X bit rate

// Generate timing signals from counter.  Want to take first sample
// of din after 4 bit8x pulses, then sample every 8 pulses.
// As bit8x pulse arrives at end of rxcount value, compare rxcount with 3.
	assign sample = (rxcount[2:0] == 3'b011) & bit8x;	// pulse one clock cycle long
// done signal goes high soon after stop bit has been sampled
	assign done = (rxcount == 7'b1001100) & bit8x;  // pulse after 9.625 bit intervals
	
// State machine to control things...
	localparam 	INIT = 2'b00,		// state after reset
					IDLE = 2'b01,		// waiting for start bit
					RECV = 2'b10,		// receiving data
					FINI = 2'b11;		// finished - strobe signal

	always @ (posedge clk)	// state register behaviour
		if (rst) state <= INIT;		// reset to INIT
		else state <= next;			// move to next state

	always @ (state or din or done or stopbit)	// next state logic
		case (state)
			INIT:		if (din) next = IDLE;	// receive 1, go to IDLE
						else next = INIT;			// receive 0, stay in INIT
						
			IDLE:		if (din) next = IDLE;	// receive 1, keep waiting
						else next = RECV;			// start receiving on 0
						
			RECV:		if (done) next = FINI;	// finish after 9.5 bit times
						else next = RECV;			// otherwise keep receiving
						
			FINI:		if (stopbit) next = IDLE;	// return to await next start bit
						else next = INIT;			// should not happen - framing error
		endcase

// output signals from state machine
	assign rxgo = (state == RECV);			// run counter while receiving
	assign rxnew = (state == FINI) & stopbit;	// ouptut indicates valid data

//	Output register - loaded when 8-bit data is ready and valid stop bit
	always @ (posedge clk)
		if (rst) rxdout <= 8'b0;		// reset to zero
		else if (done & stopbit) rxdout <= shiftreg[7:0];	

endmodule
