`timescale 1ns / 1ns
/////////////////////////////////////////////////////////////////
// Module Name: TB_toplevel
// Simple testbench for SoC - no program load, just clock and reset
/////////////////////////////////////////////////////////////////
module TB_toplevel;
    int fail_count = 0;

    logic btnCpuResetn, clk;
    logic [15:0] gpio_in0, gpio_in1, gpio_out0, gpio_out1;
    logic serialRx;     // serial receive at idle
    wire serialTx;      // serial transmit

    dynnsoc dut(
        .HCLK(clk),
        .rst_n_in(btnCpuResetn),
        .serialRx(serialRx),
        .serialTx(serialTx),
        .gpio_in0,
        .gpio_out0,
        .gpio_in1,
        .gpio_out1
    );

    initial $readmemh("main.hex", dut.imem.bram.mem);  // load the program into ROM

    initial begin
        clk = 1'b0;
        forever     // generate 50 MHz clock
            #10 clk = ~clk;  // invert clock every 10 ns
    end

    int i;

    initial begin
        gpio_in0 = 16'h5a4b;    // set a value on the switches
        serialRx = 1'b1;        // serial line idle high
        btnCpuResetn = 1'b1;    // start with reset inactive
        #400;                 // wait for cpu and bus clock to be stable

        $display("ROM peek:"); // display 16 bytes of ROM to allow checking the correct firmware is loaded
        for(i = 0; i < 16; i++) begin
            $display("ROM[%0d] = %h", i, dut.imem.bram.mem[i]);
        end

        btnCpuResetn = 1'b0;    // assert reset
        repeat(10) @(posedge clk); // hold reset for a while
        btnCpuResetn = 1'b1;    // release reset
        repeat(100) @(posedge clk); // wait for some time to allow the program to run

        for(i = 0; i < 15; i++) begin
            repeat(200) @(posedge clk);
            $display("          Asserting slave IRQ %d",i);
            force dut.IRQ = 15'b1 << i;
            repeat(4) @(posedge clk);  // hold IRQ high for a few cycles to make sure the core sees it
            release dut.IRQ;
            $display("          Released slave IRQ %d",i);
            repeat(250) @(posedge clk); // wait for the ISR to finish
            assert_equal(gpio_out0,i, $sformatf("gpio_out0 should indicate IRQ %d was handled", i));
        end

        repeat(1000) @(posedge clk); // wait for some time to allow the program to run

        $display("\n========================================");
        if (fail_count == 0) begin
            $display("  ALL TESTS PASSED");
        end else begin
            $display("  %0d ASSERTION(S) FAILED", fail_count);
        end
        $display("========================================\n");

        $stop;
    end

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
