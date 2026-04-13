`timescale 1ns / 1ns
/////////////////////////////////////////////////////////////////
// Module Name: TB_toplevel
// Simple testbench for SoC - no program load, just clock and reset
/////////////////////////////////////////////////////////////////
module TB_toplevel;

    logic btnCpuResetn, clk50, btnU;
    logic [15:0] sw;		// switch inputs
    wire [15:0] LED;
    logic serialRx;		// serial receive at idle
    wire serialTx;        		// serial transmit

    dynnsoc dut(
        .HCLK(clk50),
        .btnCpuResetn(btnCpuResetn),
        .btnU(btnU),
        .serialRx(serialRx),
        .sw(sw),
        .led(LED),
        .serialTx(serialTx)
    );

    initial begin
        clk50 = 1'b0;
        forever     // generate 50 MHz clock
            #10 clk50 = ~clk50;  // invert clock every 10 ns
    end

    initial begin
        sw = 16'h5a4b;			// set a value on the switches
        serialRx = 1'b1;		// serial line idle high
        btnCpuResetn = 1'b1;		// start with reset inactive
        btnU = 1'b0;				// loader button not pressed
        #400;         // wait for cpu and bus clock to be stable

        // Enable the ROM loader
        //btnU = 1'b1;
        //repeat(10) @(posedge clk50);
        //btnCpuResetn = 1'b0;
        //repeat(10) @(posedge clk50);
        //btnCpuResetn = 1'b1;
        //repeat(10) @(posedge clk50);
        //btnU = 1'b0;
        //
        //repeat (100) begin
        //    @(posedge clk50);
        //    serialRx = ~serialRx;    // toggle serial input to simulate some activity
        //end
        //$display("ROM loader active, serialRx toggled 100 times");

        // Using UART is tricky to simulate so I'll just force write to ROM
        //dut.ROM.bram1.mem[0] = 32'h20000000;  // Initial stack pointer
        //dut.ROM.bram1.mem[1] = 32'h00000001;  // Reset handler - infinite loop
        //dut.ROM.bram1.mem[2] = 32'hE7FE0000;  // infinite loop instruction
        //dut.ROM.bram1.mem[3] = 32'hDEADBEEF;  // some data word

        $display("ROM peek:");
        for(int i = 0; i < 256; i++) begin
            $display("ROM[%0d] = %h", i, dut.imem.bram.mem[i]);  // peek at first 16 words in ROM
        end

        btnCpuResetn = 1'b0;    // assert reset
        repeat(10) @(posedge clk50); // hold reset for a while
        btnCpuResetn = 1'b1;    // release reset

        repeat(500) begin
            sw = $urandom; // change switch values randomly
            @(posedge clk50);
        end

        $stop;
    end

    initial begin
        forever begin
            @(posedge clk50);
            $display("Time: %50t | imem raddr: %8h | imem rdata: %8h | sw: %2h | LED: %2h", $time, dut.instr_if.addr, dut.instr_if.rdata, sw, LED);
        end
    end
endmodule
