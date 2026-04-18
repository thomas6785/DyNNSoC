`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
//
// Create Date:   21:45:56 10/13/2014
// Design Name: 	Cortex-M0 DesignStart system
// Module Name:   reset_gen
// Description:   Asserts hardare reset signal asynchronously if button pressed
//						or clock manager not locked.  De-asserts synchronously.
//						Asserts CPU reset asynchonously as above, also synchronously
//						if ROM loader hardware is active or CPU requests reset.
//						De-asserts synchronously after minimum 2 clock cycles.
//
// Revision:
// Revision 0.01 - File Created
// Revision 1	October 2015 - extra FF in shift register to support synchronous reset
//
//////////////////////////////////////////////////////////////////////////////////
// Modified for DyNNSoC by Thomas O'Dea, April 2026

module reset_gen(
    input clk,				// system bus clock
    input rst_n_async,		// reset pushbutton, active low
    input loader_active,	// ROM loader hardware is active
    output rst_n,			// hardware reset, active high
    output rst_p		// CPU and bus reset, active low
);

// Five flip-flops (four would be enough - just being safe!)
	reg [4:0] resetFF;

// Asynchronous reset signal for flip-flops
	wire asyncReset = ~rst_n_async;

// Flip-flops all have async reset, act like shift register, but last three loaded
// synchronously with 0 if loader_active, so get quick CPU reset
	always @ (posedge clk or posedge asyncReset)
		if (asyncReset)	resetFF <= 5'b0;	// reset all flip-flops
		else begin
			resetFF[0] <= 1'b1;
			resetFF[1] <= resetFF[0]; // this FF ignores other signals
			resetFF[2] <= resetFF[1] & ~loader_active;
			resetFF[3] <= resetFF[2] & ~loader_active;
			resetFF[4] <= resetFF[3] & ~loader_active;
			end

// Output signals
	assign rst_p = ~resetFF[1];	// asserted until PLL locked, plus 1 clock
	assign rst_n = resetFF[4];	// asserted min 2 clocks

endmodule
