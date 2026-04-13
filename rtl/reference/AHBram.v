`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen
//
// Create Date:     21:37:44 14Oct2014
// Design Name:     Cortex-M0 DesignStart system
// Module Name:     AHBram
// Description:     Provides on-chip RAM on AHBlite bus, using dual-port block ram.
//                  Burst transfers, protection, etc. are not supported.
//
// Revision:
// Revision 0.01 - File Created
// Revision 1 - modified for synchronous reset, October 2015
//
//////////////////////////////////////////////////////////////////////////////////
module AHBram(
    input wire HCLK,             // bus clock
    input wire HRESETn,          // bus reset, active low
    input wire HSEL,             // selects this slave
    input wire HREADY,           // indicates previous transaction completing
    input wire [31:0] HADDR,     // address
    input wire [1:0] HTRANS,     // transaction type (only bit 1 used)
    input wire HWRITE,           // write transaction
    input wire [2:0] HSIZE,      // transaction width (max 32-bit supported)
    input wire [31:0] HWDATA,    // write data
    output wire [31:0] HRDATA,   // read data from slave
    output wire HREADYOUT        // ready output from slave
);

    localparam ADDR_WIDTH= 14; // 16kByte = 4096 words of 32 bits

    // Registers to hold signals from address phase
    reg [ADDR_WIDTH-1:0] rHADDR;
    reg [2:0] rHSIZE;
    reg rHWRITE, rActive;

    reg [3:0] byteWrite;            // individual byte write enable signals
    wire active = HSEL & HTRANS[1]; // slave selected and transfer in progress
    wire wen = rActive & rHWRITE;   // delayed write enable
    wire [31:0] ramData;            // read data from block ram

    // Signals for read-write conflict resolution
    reg [31:0] rWData;             // delayed write data for conflict resolution
    reg [3:0] rConflict;           // byte conflict signals
    wire conflict;                 // write and consecutive read at same address
    assign conflict = (rHADDR[ADDR_WIDTH-1:2] == HADDR[ADDR_WIDTH-1:2]) // address match
                       && wen  //  write in progress
                       && active && !HWRITE;  // next transaction is read

    assign HREADYOUT = 1'b1;    // always ready - transaction never delayed

     // Capture signals for use later
    always @(posedge HCLK)
        if(!HRESETn)
            begin
                rHADDR <= {ADDR_WIDTH{1'b0}};
                rHSIZE <= 3'b0;
                rHWRITE <= 1'b0;
                rActive <= 1'b0;
                rWData <= 32'b0;
                rConflict <= 4'b0;
            end
        else if(HREADY)
         begin
            rHADDR <= HADDR[ADDR_WIDTH-1:0];         // capture bus signals from address phase
            rHSIZE <= HSIZE;                         // for use in data phase
            rHWRITE <= HWRITE;
            rActive <= active;
            rWData <= HWDATA;                           // remember written data
            rConflict <= conflict ? byteWrite : 4'b0;  // if conflict, remember which bytes written
         end

    // Generate byte write enable signals
    always @ (wen, rHSIZE, rHADDR[1:0])
        if (wen) // write transaction in progress
            case ({rHSIZE, rHADDR[1:0]}) // select on size and LSBs of address
                5'b000_00:  byteWrite = 4'b0001;    // writing LS byte
                5'b000_01:  byteWrite = 4'b0010;    //
                5'b000_10:  byteWrite = 4'b0100;    //
                5'b000_11:  byteWrite = 4'b1000;    // writing MS byte
                5'b001_00:  byteWrite = 4'b0011;    // writing LS halfword
                5'b001_10:  byteWrite = 4'b1100;    // writing MS halfword
                5'b010_00:  byteWrite = 4'b1111;    // writing full word
                default:    byteWrite = 4'b0000;    // anything else is illegal
            endcase
        else                byteWrite = 4'b0000;    // not writing

    // Instantiate the block ram - created by Xilinx IP generator (in VHDL)
    blk_mem_4Kword bram0 (
        .clka       (HCLK),             // port A is write port
        .wea        (byteWrite),
        .addra      (rHADDR[ADDR_WIDTH-1:2]),     // write uses delayed address, aligned with data
        .dina       (HWDATA),           // write data
        .clkb       (HCLK),             // port B is read port
        .addrb      (HADDR[ADDR_WIDTH-1:2]),      // read uses bus address
        .doutb      (ramData)            // read data
    );

    // Sort out the read-after write conflicts - four multiplexers
    // If read follows write, return the written data, not the ram output (which is the old content)
    assign HRDATA[31:24] = (rConflict[3]) ? rWData[31:24] : ramData[31:24];
    assign HRDATA[23:16] = (rConflict[2]) ? rWData[23:16] : ramData[23:16];
    assign HRDATA[15:8] = (rConflict[1]) ? rWData[15:8] : ramData[15:8];
    assign HRDATA[7:0] = (rConflict[0]) ? rWData[7:0] : ramData[7:0];

endmodule
