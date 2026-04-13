`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
// 
// Created:   		March 2024
// Design Name: 	Cortex-M0 DesignStart system
// Module Name:   	AHBdummy 
// Description: 	Responds to invalid addresses on AHB-Lite bus. 
//			Response is OK with no wait state if transaction is IDLE or BUSY.
//			Response is ERROR with one wait state otherwise.
//
// Revision: 
//
//////////////////////////////////////////////////////////////////////////////////
module ahb_dummy(
			input HCLK,				// bus clock
			input HRESETn,			// bus reset, active low
			input HSEL,				// selects this slave
			input HREADY,			// indicates previous transaction completing
			input [1:0] HTRANS,		// transaction type
			output reg HREADYOUT,	// ready output from slave
			output reg HRESP		// response output from slave
            );

  localparam  OKAY = 1'b0, ERROR = 1'b1;  // values for the HRESP signal

    /* Detect an invalid transaction at the end of the address phase, if the dummy
       is selected, the previous transaction is completing (HREADY = 1) and the
       transfer type (HTRANS) is NONSEQ (2) or SEQ (3).  */
    wire inValid = HSEL & HREADY & HTRANS[1];

    
    /* Register for HREADYOUT - should go low on clock edge if invalid transaction,
       then return high on the next clock edge.  */
    always @ (posedge HCLK)
        if (~HRESETn)  // if reset is active
            HREADYOUT = 1'b1;   // default is ready
        else
            HREADYOUT = ~(inValid & HREADYOUT);
    
    /*  Register for HRESP - should update on the clock edge to reflect the 
        inValid signal, but not update on the clock edge when HREADYOUT is low.  */
        always @ (posedge HCLK)
            if (~HRESETn)  // if reset is active
                HRESP = OKAY;       // default response is OK
            else if (HREADYOUT)
                HRESP = inValid ? ERROR : OKAY;

endmodule
