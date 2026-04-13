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
module reset_gen(
    input clk,					// system bus clock
    input resetPBn,			// reset pushbutton, active low
    input pll_lock,			// clock management PLL is locked
    input loader_active,	// ROM loader hardware is active
    input cpu_request,		// CPU is requesting reset
    output resetHW,			// hardware reset, active high
    output resetCPUn,		// CPU and bus reset, active low
    output resetLED			// signal for indicator LED - inverse of above
    );

// Five flip-flops (four would be enough - just being safe!)
	reg [4:0] resetFF;
	
// Asynchronous reset signal for flip-flops
	wire asyncReset = ~resetPBn | ~pll_lock;
	
// Flip-flops all have async reset, act like shift register, but last three loaded
// synchronously with 0 if loader_active or cpu_request, so get quick CPU reset
	always @ (posedge clk or posedge asyncReset)
		if (asyncReset)	resetFF <= 5'b0;	// reset all flip-flops
		else begin
			resetFF[0] <= pll_lock;  
			resetFF[1] <= resetFF[0]; // this FF ignores other signals
			resetFF[2] <= resetFF[1] & ~loader_active & ~cpu_request;
			resetFF[3] <= resetFF[2] & ~loader_active & ~cpu_request;
			resetFF[4] <= resetFF[3] & ~loader_active & ~cpu_request;
			end
			
// Output signals
	assign resetHW = ~resetFF[1];	// asserted until PLL locked, plus 1 clock
	assign resetCPUn = resetFF[4];	// asserted min 2 clocks
	assign resetLED = ~resetFF[4];	// inverse of above			

endmodule
