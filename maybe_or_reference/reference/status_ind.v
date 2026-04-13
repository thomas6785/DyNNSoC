`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
// 
// Create Date:   21:45:56 10/20/2014 
// Design Name:   Cortex-M0 DesignStart system
// Module Name:   status_ind 
// Description:   Drives two multi-colour LEDs to display status signals.
//			Brightness can be set with parameter.
//			statusIn bit 0 controls LED 1 red
//			         bit 1 controls LED 1 blue
//					 bit 2 controls LED 2 red
//                   bit 3 controls LED 2 blue
//
// Revision 0.01 - File Created
// Revision 1 - March 2018, tidied comments 
//
//////////////////////////////////////////////////////////////////////////////////
module status_ind(
    input clk,				// system bus clock - expected 50 MHz
    input reset,			// reset signal, active high
    input [3:0] statusIn,	// status signals to be displayed
    output [5:0] rgbLED		// output for multi-colour indicator LEDs
    );

    localparam [2:0] BRIGHTNESS = 3'd4; //  1 for bright, 7 for dim
    
// Counter to control PWM signals for LEDs, hence brightness
	reg [13:0] counter;    // 14-bit register, overflows ~3 kHz with 50 MHz clock
	
	always @ (posedge clk or posedge reset)
		if (reset)	counter <= 14'b0;	// reset counter
		else counter <= counter + 14'b1;  // increment counter
		
// Comparator to generate PWM signal
    wire pwm = (counter[13:11] >= BRIGHTNESS);
			
// Output signals
	assign rgbLED[0] = pwm & statusIn[0];	// LED 1 red
	assign rgbLED[1] = 1'b0;	            // LED 1 green
	assign rgbLED[2] = pwm & statusIn[1];	// LED 1 blue
	assign rgbLED[3] = pwm & statusIn[2];	// LED 2 red
	assign rgbLED[4] = 1'b0;	            // LED 2 green
	assign rgbLED[5] = pwm & statusIn[3];	// LED 2 blue

endmodule
