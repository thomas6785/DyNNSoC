`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
//END USER LICENCE AGREEMENT                                                    //
//                                                                              //
//Copyright (c) 2012, ARM All rights reserved.                                  //
//                                                                              //
//THIS END USER LICENCE AGREEMENT (�LICENCE�) IS A LEGAL AGREEMENT BETWEEN      //
//YOU AND ARM LIMITED ("ARM") FOR THE USE OF THE SOFTWARE EXAMPLE ACCOMPANYING  //
//THIS LICENCE. ARM IS ONLY WILLING TO LICENSE THE SOFTWARE EXAMPLE TO YOU ON   //
//CONDITION THAT YOU ACCEPT ALL OF THE TERMS IN THIS LICENCE. BY INSTALLING OR  //
//OTHERWISE USING OR COPYING THE SOFTWARE EXAMPLE YOU INDICATE THAT YOU AGREE   //
//TO BE BOUND BY ALL OF THE TERMS OF THIS LICENCE. IF YOU DO NOT AGREE TO THE   //
//TERMS OF THIS LICENCE, ARM IS UNWILLING TO LICENSE THE SOFTWARE EXAMPLE TO    //
//YOU AND YOU MAY NOT INSTALL, USE OR COPY THE SOFTWARE EXAMPLE.                //
//                                                                              //
//ARM hereby grants to you, subject to the terms and conditions of this Licence,//
//a non-exclusive, worldwide, non-transferable, copyright licence only to       //
//redistribute and use in source and binary forms, with or without modification,//
//for academic purposes provided the following conditions are met:              //
//a) Redistributions of source code must retain the above copyright notice, this//
//list of conditions and the following disclaimer.                              //
//b) Redistributions in binary form must reproduce the above copyright notice,  //
//this list of conditions and the following disclaimer in the documentation     //
//and/or other materials provided with the distribution.                        //
//                                                                              //
//THIS SOFTWARE EXAMPLE IS PROVIDED BY THE COPYRIGHT HOLDER "AS IS" AND ARM     //
//EXPRESSLY DISCLAIMS ANY AND ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING     //
//WITHOUT LIMITATION WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR //
//PURPOSE, WITH RESPECT TO THIS SOFTWARE EXAMPLE. IN NO EVENT SHALL ARM BE LIABLE/
//FOR ANY DIRECT, INDIRECT, INCIDENTAL, PUNITIVE, OR CONSEQUENTIAL DAMAGES OF ANY/
//KIND WHATSOEVER WITH RESPECT TO THE SOFTWARE EXAMPLE. ARM SHALL NOT BE LIABLE //
//FOR ANY CLAIMS, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, //
//TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE    //
//EXAMPLE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE EXAMPLE. FOR THE AVOIDANCE/
// OF DOUBT, NO PATENT LICENSES ARE BEING LICENSED UNDER THIS LICENSE AGREEMENT.//
//////////////////////////////////////////////////////////////////////////////////


module ahb_decoder (
    input [31:0] HADDR,       // AHB bus address  
    output reg HSEL_S0,       // slave select line 0
    output reg HSEL_S1,
    output reg HSEL_S2,
    output reg HSEL_S3,
    output reg HSEL_S4,
    output reg HSEL_S5,
    output reg HSEL_S6,
    output reg HSEL_S7,
    output reg HSEL_S8,
    output reg HSEL_S9,       // slave select line 9
    output reg HSEL_NOMAP,    // indicates invalid address
    output reg [3:0] MUX_SEL  // multiplexer control signal
    );  // end of port list


// Address decoding logic to implement the address map: 
// decide which slave is active by checking the 8 MSBs of the address.
always @ (HADDR)
    begin
        HSEL_S0 = 1'b0;         // all slave select outputs will be 0
        HSEL_S1 = 1'b0;         // unless one of them is set to 1 below
        HSEL_S2 = 1'b0;
        HSEL_S3 = 1'b0;
        HSEL_S4 = 1'b0;
        HSEL_S5 = 1'b0;
        HSEL_S6 = 1'b0;
        HSEL_S7 = 1'b0;
        HSEL_S8 = 1'b0;
        HSEL_S9 = 1'b0;
        HSEL_NOMAP = 1'b0;
        
// Logic to select one slave, and also output the slave number to the multiplexers
// ## As you add more slaves, you need to extend this logic to select them
        case(HADDR[31:24])      // Use the top 8 bits of the address to select
            8'h00: 				// Address range 0x0000_0000 to 0x00FF_FFFF  16MB
                begin
                    HSEL_S0 = 1'b1;     // activate slave select 0 output
                    MUX_SEL = 4'd0;     // send slave number 0 to multiplexers
                end
                
            8'h20: 				// Address range 0x2000_0000 to 0x20FF_FFFF  16MB
                begin
                    HSEL_S1 = 1'b1;     // activate slave select 1 output
                    MUX_SEL = 4'd1;     // send slave number 1 to multiplexers
                end

            8'h50:
                begin
                    HSEL_S2 = 1'b1;
                    MUX_SEL = 4'd2;
                end
            8'h51:
                begin
                    HSEL_S3 = 1'b1;
                    MUX_SEL = 4'd3;
                end
             
         
            default: 			// Address not mapped to any slave
                begin
                    HSEL_NOMAP = 1'b1;   // activate the NOMAP output
                    MUX_SEL = 4'd15;     // send dummy slave number 15 to multiplexers 
                end
        endcase
    end  // end of always block
    
endmodule
