`timescale 1ns / 1ns
/////////////////////////////////////////////////////////////////
// Module Name: TB_toplevel
// Simple testbench for SoC - no program load, just clock and reset
/////////////////////////////////////////////////////////////////
module TB_toplevel;
    int fail_count = 0;

    logic btnCpuResetn, clk50, btnU;
    logic [15:0] sw;    // switch inputs
    wire [15:0] LED;
    logic serialRx;     // serial receive at idle
    wire serialTx;      // serial transmit

    dynnsoc dut(
        .HCLK(clk50),
        .btnCpuResetn(btnCpuResetn),
        .btnU(btnU),
        .serialRx(serialRx),
        .sw(sw),
        .led(LED),
        .serialTx(serialTx)
    );

    initial $readmemh("/home/tudentstudent/DyNNSoC/firmware/main.hex", dut.imem.bram.mem);  // load the program into ROM

    initial begin
        clk50 = 1'b0;
        forever     // generate 50 MHz clock
            #10 clk50 = ~clk50;  // invert clock every 10 ns
    end

    int i;

    initial begin
        sw = 16'h5a4b;          // set a value on the switches
        serialRx = 1'b1;        // serial line idle high
        btnCpuResetn = 1'b1;    // start with reset inactive
        btnU = 1'b0;            // loader button not pressed
        #400;                 // wait for cpu and bus clock to be stable

        $display("ROM peek:"); // display 16 bytes of ROM to allow checking the correct firmware is loaded
        for(i = 0; i < 16; i++) begin
            $display("ROM[%0d] = %h", i, dut.imem.bram.mem[i]);
        end

        btnCpuResetn = 1'b0;    // assert reset
        repeat(10) @(posedge clk50); // hold reset for a while
        btnCpuResetn = 1'b1;    // release reset
        repeat(100) @(posedge clk50); // wait for some time to allow the program to run

        for(i = 0; i < 15; i++) begin
            repeat(200) @(posedge clk50);
            $display("          Asserting slave IRQ %d",i);
            force dut.IRQ = 15'b1 << i;
            repeat(3) @(posedge clk50);  // hold IRQ high for a few cycles to make sure the core sees it
            release dut.IRQ;
            $display("          Released slave IRQ %d",i);
            repeat(100) @(posedge clk50); // wait for the ISR to finish
            assert_equal(LED,i, $sformatf("LED should indicate IRQ %d was handled", i));
        end

        // Attempt NMI
        repeat(200) @(posedge clk50);
        $display("          Asserting NMI");
        force dut.NMI = 1'b1;
        repeat(3) @(posedge clk50);  // hold NMI high for a few cycles to make sure the core sees it
        release dut.NMI;
        $display("          Released NMI");
        repeat(100) @(posedge clk50); // wait for the ISR to finish
        assert_equal(LED,128, "LED should indicate NMI was handled");

        repeat(1000) @(posedge clk50); // wait for some time to allow the program to run

        $display("\n========================================");
        if (fail_count == 0) begin
            $display("  ALL TESTS PASSED");
        end else begin
            $display("  %0d ASSERTION(S) FAILED", fail_count);
        end
        $display("========================================\n");

        $stop;
    end

    //initial begin
    //    forever begin
    //        @(posedge clk50);
    //        $display("Time: %50t | imem raddr: %8h | imem rdata: %8h | LED: %2h", $time, dut.instr_if.addr, dut.instr_if.rdata, LED);
    //    end
    //end

    always @ (posedge dut.cpu.div) $display("          Systick IRQ triggered at time %t", $time);

    function assert_equal(input logic [31:0] meas, input logic [31:0] exp, input string message);
        if (meas !== exp) begin
            $error("[FAIL!!!] Assertion failed: %s | Expected: %h, Got: %h", message, exp, meas);
            fail_count++;
        end else begin
            $display("[pass...] Assertion passed: %s", message);
        end
    endfunction
endmodule
