`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
// 
// Create Date:     16 March 2023 
// Design Name:     Cortex-M0 DesignStart system
// Module Name:     AHBdisp
// Description:     Provides AHB interface to drive multiplexed 8-digit 
//                  7-segment display on Nexys-4 board.
//      Address 0 - 8-bit read/write register with data for digit 0 (rightmost digit)
//      Address 1 to 7 - same for other digits, address 7 is for leftmost digit
//      Address 8 - 8-bit read/write register with mode bits, one per digit
//                  0 = raw mode, data in register controls segments directly: PABCDEFG
//                      0 = off, 1 = on
//                  1 = hex mode, data[7] controls the dot as above, data[4:0] selects
//                      a pattern to display: hex digits and others, see table in code
//      Address 9 - 8-bit read/write register with enable bits: 0 = off, 1 - enabled 
//      For registers 8 and 9, bit 0 controls the rightmost digit
//
//      This version only allows 8-bit write transactions, reads can be 8, 16 or 32 bits.
//
//      The display refresh rate is the clock frequency divided by
//      2^D_WIDTH.  D_WIDTH is a parameter, with default value 20, which sets
//      number of bits in a counter that controls cycling through the digits.
//      With a 50 MHz clock, D_WIDTH = 20 gives refresh rate ~48 Hz, so the 
//      display cycles through all 8 digits every ~21 ms.
//
// Version: 1.2, March 2023 - using byte writes only
//
//////////////////////////////////////////////////////////////////////////////////
module  AHBdisp #(D_WIDTH = 20) (
            // Bus signals
            input wire HCLK,            // bus clock
            input wire HRESETn,         // bus reset, active low
            input wire HSEL,            // selects this slave
            input wire HREADY,          // indicates previous transaction completing
            input wire [31:0] HADDR,    // address
            input wire [1:0] HTRANS,    // transaction type (only bit 1 used)
            input wire HWRITE,          // write transaction
//          input wire [2:0] HSIZE,     // transaction width ignored
            input wire [31:0] HWDATA,   // write data
            output wire [31:0] HRDATA,  // read data from slave
            output wire HREADYOUT,      // ready output from slave
            // LED output signals
            output reg [7:0] digit,     // digit enable lines, active low, 0 on right
            output [7:0] segment        // segment lines, active low, PABCDEFG
             );  // end of port list

//================================  AHB-Lite Bus Interface =============================
    
// Registers to hold signals from address phase
    reg [3:0] rHADDR;           // only need four bits of address
    reg rWrite;                 // write enable signal

// Internal signals
    reg [31:0] readData;       // ouptut of read multiplexer

// Capture bus signals in the address phase
    always @ (posedge HCLK)
        if (!HRESETn)
            begin
                rHADDR <= 4'b0;
                rWrite <= 1'b0;
            end
        else if (HREADY)    // previous bus transaction is completing
            begin
                rHADDR <= HADDR[3:0];  // capture address bits for for use in data phase
                rWrite <= HSEL & HWRITE & HTRANS[1]; // this slave selected for write transfer       
            end

// Ten registers visible on the AHB-Lite bus, as described above
    reg [7:0] displayReg [0:9];
    integer i;
    always @ (posedge HCLK)
        if (!HRESETn)                       // reset is active
            for (i = 0; i < 10; i = i + 1)  // for each register
                displayReg[i] <= 8'b0;      // set it to 0
        else if (rWrite)                    // writing to a register
            case (rHADDR)                   // choose which register to change
                4'd0:     displayReg[0] <= HWDATA[7:0];   // get data from correct byte lane
                4'd1:     displayReg[1] <= HWDATA[15:8];
                4'd2:     displayReg[2] <= HWDATA[23:16];
                4'd3:     displayReg[3] <= HWDATA[31:24];
                4'd4:     displayReg[4] <= HWDATA[7:0];
                4'd5:     displayReg[5] <= HWDATA[15:8];
                4'd6:     displayReg[6] <= HWDATA[23:16];
                4'd7:     displayReg[7] <= HWDATA[31:24];
                4'd8:     displayReg[8] <= HWDATA[7:0];
                default:  displayReg[9] <= HWDATA[15:8];  // address 9 to 15 selects register 9
            endcase

// Bus read multiplexer - output a full word and let the bus master select the byte
    always @(rHADDR, displayReg[0], displayReg[1], displayReg[2], displayReg[3], displayReg[4], 
               displayReg[5], displayReg[6], displayReg[7], displayReg[8], displayReg[9])
        case (rHADDR[3:2])      // select on word address (stored from address phase)
            2'd0:     readData = {displayReg[3], displayReg[2], displayReg[1], displayReg[0]};
            2'd1:     readData = {displayReg[7], displayReg[6], displayReg[5], displayReg[4]};
            default:  readData = {16'b0, displayReg[9], displayReg[8]};
        endcase
        
    assign HRDATA = readData;   
    assign HREADYOUT = 1'b1;    // always ready - transaction is never delayed

    
//================================  Display Interface ===============================

    reg [D_WIDTH-1:0] clkCount; // counter to scan digits
    wire [2:0] digitSel;   // 3-bit value to select one digit
    wire [7:0] raw, pattern;    // segment patterns for the selected digit
    wire mode, enable;     // mode and enable signals for the selected digit
    reg [6:0] hexPattern;  // pattern to represent hex digit or other symbol
    
// Scanning counter driven by clock - width is a parameter
    always @ (posedge HCLK)        
        if (!HRESETn) clkCount <= {D_WIDTH{1'b0}};
        else clkCount <= clkCount + 1'b1;

// 3-bit signal to select the active digit
    assign digitSel = clkCount[D_WIDTH-1:D_WIDTH-3];  // 3 MSB of counter   

// 3 to 8 decoder, active low outputs, to enable one digit of display
    always @ (digitSel)
        case(digitSel)
            3'd0:  digit = 8'b11111110;  // enable rightmost digit
            3'd1:  digit = 8'b11111101;
            3'd2:  digit = 8'b11111011;
            3'd3:  digit = 8'b11110111;
            3'd4:  digit = 8'b11101111;
            3'd5:  digit = 8'b11011111;
            3'd6:  digit = 8'b10111111;
            3'd7:  digit = 8'b01111111;  // enable leftmost digit
        endcase  // no need for default, as all possibilities covered

// Multiplexer to select the data from the display register
    assign raw = displayReg[digitSel];
    
// Multiplexer to select the mode signal
    assign mode = displayReg[8] [digitSel];
    
// Multiplexer to select the enable signal
    assign enable = displayReg[9] [digitSel];
    
// Multiplexer to select the segment pattern for the selected digit (active low)
// either a combination of dot from raw and pattern from table, or inverted raw
    assign pattern = mode ? {~raw[7], hexPattern} : ~raw;

// Multiplexer to select final segment output for the selected digit
// either pattern from above or all 1 (blank)
    assign segment = enable ? pattern : 8'hff;

// Look-up table to convert 5-bit value to 7-segment pattern ABCDEFG (active low)
    always @ (raw[4:0])    
        case(raw[4:0])        // input value is 5 bits from the raw signal
            5'h0:    hexPattern = 7'b0000001;  // display 0 - all segments on except G
            5'h1:    hexPattern = 7'b1001111;  // display 1 - segments B and C on
            5'h2:    hexPattern = 7'b0010010;
            5'h3:    hexPattern = 7'b0000110;
            5'h4:    hexPattern = 7'b1001100;
            5'h5:    hexPattern = 7'b0100100;
            5'h6:    hexPattern = 7'b0100000;
            5'h7:    hexPattern = 7'b0001111;
            5'h8:    hexPattern = 7'b0000000;
            5'h9:    hexPattern = 7'b0000100;
            5'hA:    hexPattern = 7'b0001000;
            5'hB:    hexPattern = 7'b1100000;
            5'hC:    hexPattern = 7'b0110001;
            5'hD:    hexPattern = 7'b1000010;
            5'hE:    hexPattern = 7'b0110000;
            5'hF:    hexPattern = 7'b0111000;  // display F
            5'h10:   hexPattern = 7'b1110111;  // bottom bar
            5'h11:   hexPattern = 7'b1111110;  // middle bar or dash or minus
            5'h12:   hexPattern = 7'b0111111;  // top bar
            5'h13:   hexPattern = 7'b1001000;  // display H
            5'h14:   hexPattern = 7'b1110001;  // display L
            5'h15:   hexPattern = 7'b1101010;  // display n
            5'h16:   hexPattern = 7'b1100010;  // display o
            5'h17:   hexPattern = 7'b0011000;  // display P
            5'h18:   hexPattern = 7'b1111010;  // display r
            5'h19:   hexPattern = 7'b1110000;  // display t
            5'h1a:   hexPattern = 7'b1100011;  // display u
            5'h1b:   hexPattern = 7'b1000100;  // display y
            default: hexPattern = 7'b1111111;  // default is blank
        endcase

endmodule
