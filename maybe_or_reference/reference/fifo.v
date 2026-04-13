`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
//END USER LICENCE AGREEMENT                                                    //
//                                                                              //
//Copyright (c) 2012, ARM All rights reserved.                                  //
//                                                                              //
//THIS END USER LICENCE AGREEMENT (“LICENCE”) IS A LEGAL AGREEMENT BETWEEN      //
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

// Modified 20 October 2014, Brian Mulkeen, UCD:
//		Added reset on fifo data registers to tidy simulations
//		Added comments.
// Modified October 2015, to convert to synchronous reset

module FIFO #(parameter DWIDTH=8, AWIDTH=1)
(
  input wire clk,
  input wire resetn,		// active-low reset
  input wire rd,			// read means that byte is being taken from fifo output
  input wire wr,			// write means that byte should be written to fifo input 
  input wire [DWIDTH-1:0] w_data,	// fifo data in
  
  output wire empty,		// no bytes in queue - output data is rubbish
  output wire full,		// no space in queue - write requests will be ignored
  output wire [DWIDTH-1:0] r_data		// fifo data out
);

//Internal Signal declarations

  reg [DWIDTH-1:0] array_reg [2**AWIDTH-1:0];		// fifo data registers
  reg [AWIDTH-1:0] w_ptr_reg;			// write pointer - points to register 
  reg [AWIDTH-1:0] w_ptr_next;			// where next data should be stored
  reg [AWIDTH-1:0] w_ptr_succ;
  reg [AWIDTH-1:0] r_ptr_reg;			// read pointer - points to oldest
  reg [AWIDTH-1:0] r_ptr_next;			// data in queue = next to be read
  reg [AWIDTH-1:0] r_ptr_succ;
  
  reg full_reg;
  reg empty_reg;
  reg full_next;
  reg empty_next;
  
  wire w_en;

	integer i;  // for use in loop
  always @ (posedge clk)
	 if (~resetn) for (i=0; i<2**AWIDTH; i = i+1)
						array_reg[i] <= {DWIDTH{1'b0}};  // clear array
    else if(w_en)
    begin
      array_reg[w_ptr_reg] <= w_data;    // write to array at write pointer
    end

  assign r_data = array_reg[r_ptr_reg];   // read from array at read pointer

  assign w_en = wr & ~full_reg;    // write enabled on write request if not full  

//State Machine - keeps track of pointers, updates status signals
  always @ (posedge clk)
  begin
    if(!resetn)
      begin
        w_ptr_reg <= 0;
        r_ptr_reg <= 0;
        full_reg <= 1'b0;
        empty_reg <= 1'b1;
      end
    else
      begin
        w_ptr_reg <= w_ptr_next;
        r_ptr_reg <= r_ptr_next;
        full_reg <= full_next;
        empty_reg <= empty_next;
      end
  end


//Next State Logic
  always @*
  begin
    w_ptr_succ = w_ptr_reg + 1;		// calculate where pointers would go next
    r_ptr_succ = r_ptr_reg + 1;		// pointers automatically wrap at end of array
    
    w_ptr_next = w_ptr_reg;		// all registers no change as default
    r_ptr_next = r_ptr_reg;
    full_next = full_reg;
    empty_next = empty_reg;
    
    case({w_en,rd})
      //2'b00: nop
      2'b01:							// read (without write at same time)
        if(~empty_reg)						// if not empty (if empty, nothing to do)
          begin
            r_ptr_next = r_ptr_succ;	// read pointer will advance
            full_next = 1'b0;				// will not be full after read
            if (r_ptr_succ == w_ptr_reg)	// if pointers are going to match, will be empty
              empty_next = 1'b1;
          end
      2'b10:							// write (without read at same time
        if(~full_reg)						// if not full (if full, nothing to do)
          begin
            w_ptr_next = w_ptr_succ;		// write pointer will advance
            empty_next = 1'b0;				// will not be empty after write
            if (w_ptr_succ == r_ptr_reg)	// if pointers are going to match, will be full
              full_next = 1'b1;
          end
      2'b11:							// read and write on same clock edge
        begin
          w_ptr_next = w_ptr_succ;		// both pointers advance
          r_ptr_next = r_ptr_succ;		// status (full, empty) does not change
        end
      default: ;
    endcase
  end

//Set Full and Empty

  assign full = full_reg;
  assign empty = empty_reg;
  
endmodule

 
 

  
