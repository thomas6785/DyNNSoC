`timescale 1ns/1ps

/*
An extremely simple AHB register block
Its uses are:
    - de-pipeline the control signals for simpler timing with peripherals
    - reject non-word-aligned transactions
    - decode addresses to give an 'access' signal for each register

The registers are not instantiated as flip flops - you may do this externally.

Maps AHB to a simple register interface:
    rdata - one per register. Useful for status. For config, connect back to 'dout' drive to zero
    access - one per register. Goes high when a register is read or written to - stays high until 'ready'
    wdata - shared - data to write to the accessed register
    write - shared - indicates a write access
    error - shared - indicates an error response. Only valid when ready is 1. You may tie this to zero, or you may wish to detect writes to read-only registers
    ready - shared - indicates din is valid for the current 'access'. It is recommended to tie this to 1 - if you need wait states, this module may be too simple for your needs.

Register addresses are 4 apart (word-aligned). Two LSBs will cause error. The upper bits are ignored if ADDR_WIDTH is larger than $clog2(NUM_REGS)

*/

module ahb_to_csr #(
    parameter  ADDR_WIDTH = 10,
    parameter  NUM_REGS   = 4,
    parameter  ALLOW_STROBING = 0, // if 1, allow byte and halfword accesses with appropriate wstrb. If 0, only allow word accesses and wstrb is always 1111. Cross-word accesses are not allowed in either case.
    localparam DATA_WIDTH = 32, // localparam - not configurable
    localparam RELEVANT_ADDR_WIDTH = 2+$clog2(NUM_REGS) // The number of bits of the address that are relevant for decoding which register is being accessed. The upper bits are ignored. Add two bits for word-alignment.
) (
	input                   HCLK,
	input                   HRESETn,

    ahb_intf_s.slave AHB_IF,

    // Memory interface signals
    output                    access    [NUM_REGS-1:0],   // access[n] will pulse when register number n is read or written. Usually ignored but can be used to trigger side effects
    output                    write,                      // 1 indicates that the accessed register is being written to. 0 means the register is being read
    output [DATA_WIDTH-1:0]   wdata,
    input  [DATA_WIDTH-1:0]   rdata     [NUM_REGS-1:0],
    input                     error,                      // only valid when ready is 1. Can be tied to 0
    input                     ready,                      // can be tied to 1
    output [DATA_WIDTH/8-1:0] wstrb                       // which bytes to write
);
    logic [ADDR_WIDTH-1:0] rHADDR;
    logic [2:0] rSize;
    logic rWrite, rAccess;

    // Flop the control signals
    always_ff @ (posedge HCLK) begin
        if (!HRESETn) begin
            rHADDR   <= '0;
            rWrite   <= '0;
            rAccess  <= '0;
            rSize    <= '0;
        end else if (AHB_IF.HREADY) begin // AHB standard page 55 "A Subordinate must only sample the HSELx, address, and control signals when HREADY is HIGH"
            rHADDR   <= AHB_IF.HADDR[ADDR_WIDTH-1:0];
            rWrite   <= AHB_IF.HWRITE;
            rAccess  <= AHB_IF.HSEL && AHB_IF.HTRANS[1];
            rSize    <= AHB_IF.HSIZE;
            // HTRANS[1] indicates if a transaction is happening
            // HTRANS[0] is for distinguishing between NONSEQ and SEQ, which we don't care about for this
        end
    end

    assign AHB_IF.HRDATA = rdata[rHADDR[RELEVANT_ADDR_WIDTH-1:2]]; // The upper bits of the address are ignored and two LSBs are ignored (word-aligned)

    logic bad_tx;

    // Handle non-word-aligned accesses
    generate if (ALLOW_STROBING) begin
        logic invalid_strobe;
        assign bad_tx = rSize[2] || invalid_strobe;
        always_comb begin
            invalid_strobe = 0;
            unique case ({rSize, rHADDR[1:0]})
                4'b000_00: wstrb = 4'b0001; // one byte at word LSbyte
                4'b000_01: wstrb = 4'b0010; // one byte at word mid-low byte
                4'b000_10: wstrb = 4'b0100; // one byte at word mid-high byte
                4'b000_11: wstrb = 4'b1000; // one byte at word MSbyte

                4'b001_00: wstrb = 4'b0011; // halfword at word low half
                4'b001_10: wstrb = 4'b1100; // halfword at word high half

                4'b010_00: wstrb = 4'b1111; // word access, aligned

                default: begin // anything else is invalid
                    wstrb = 4'b000;
                    invalid_strobe = 1'b1;
                end
            endcase
        end
    end else begin
        wstrb = 4'b1111; // if strobing is not allowed, we only allow word-aligned accesses and all bytes are always written
        assign bad_tx = (rSize != 3'b010) ||    // if it's not a word access, it's a bad transaction
                        (rHADDR[1:0] != 2'b00); // if it's not word-aligned, it's a bad transaction
    end endgenerate

    // Note there is potential timing pressure on this path:
    // 'ready' has to come from the memory interface (which is not pipelined), through HREADYOUT and to the AHB MUX, then back to all the slaves via HREADY
    // however the majority of slaves will probably tie ready to 1 which eliminates this timing problem
    // if a slave needs finer control over its ready state, we COULD pipeline it before it goes into this module, but that will mean every transaction stalls
    // so this ahb_csr module is best suited to simple peripherals with 'ready = 1'

    // Drive the memory interface
    genvar reg_index;
    generate for (reg_index = 0; reg_index < NUM_REGS; reg_index++) begin
        // Demultiplex the 'access' signal to the individual registers
        assign access[reg_index] = (rHADDR[RELEVANT_ADDR_WIDTH-1:2] == reg_index) && (rAccess) && (~bad_tx);
    end endgenerate
    assign write = rWrite;
    assign wdata = AHB_IF.HWDATA;

    // Slave responses
    assign AHB_IF.HREADYOUT = ready;
    assign AHB_IF.HRESP =  error

endmodule
