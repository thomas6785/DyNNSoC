`timescale 1ns / 1ns
/////////////////////////////////////////////////////////////////
// Module Name: TB_toplevel
// Simple testbench for SoC - no program load, just clock and reset
/////////////////////////////////////////////////////////////////
module TB_toplevel;
    int fail_count = 0;

    logic btnCpuResetn, clk50;
    logic [15:0] gpio_in0, gpio_in1, gpio_out0, gpio_out1;
    logic serialRx;     // serial receive at idle
    wire serialTx;      // serial transmit

    dynnsoc dut(
        .HCLK(clk50),
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
        clk50 = 1'b0;
        forever     // generate 50 MHz clock
            #10 clk50 = ~clk50;  // invert clock every 10 ns
    end

    int i;

    initial begin
        gpio_in0 = 16'h5a4b;          // set a value on the switches
        serialRx = 1'b1;        // serial line idle high
        btnCpuResetn = 1'b1;    // start with reset inactive
        #400;                 // wait for cpu and bus clock to be stable

        $display("ROM peek:"); // display 16 bytes of ROM to allow checking the correct firmware is loaded
        for(i = 0; i < 16; i++) begin // peek from address 0 which is where the bootloader is
            $display("ROM[%0d] = %h", i, dut.imem.bram.mem[i]);
        end
        for(i = 'h80; i < 'h90; i++) begin // also peek from address 0x80 which is where main program starts
            $display("ROM[%0d] = %h", i, dut.imem.bram.mem[i]);
        end

        btnCpuResetn = 1'b0;    // assert reset
        repeat(10) @(posedge clk50); // hold reset for a while
        btnCpuResetn = 1'b1;    // release reset

        // Request an interrupt after a while (should be masked away in the firmware)
        repeat(300) @(posedge clk50);
        $display("          Asserting slave IRQ (should be masked in firmware)");
        force dut.IRQ = 15'h0002; // assert all maskable interrupts
        repeat(10) @(posedge clk50);
        release dut.IRQ;
        // nothing should happen
    end

    // Create a timeout to prevent the test from hanging indefinitelye
    initial begin
        #2000000
        $display("\n========================================");
        $display("  FAILED DUE TO TIMEOUT! Something went wrong if we hit this...");
        $display("========================================\n");
        $stop;
    end

    // Monitor the output gpio for any unexpected values (and for "BEEF", which indicates the test is done)
    always @ (posedge clk50) begin
        // this test writes to the gpio as a test mechanism
        // the C program is constructed so it should always write zero (e.g. gpio_write(6*7-42))
        if (gpio_out0 == 16'hBEEF) begin
            $display("          Got signal 'BEEF' on gpio_out0 at time %t, test terminating", $time);
            $display("\n========================================");
            if (fail_count == 0) begin
                $display("  ALL TESTS PASSED");
            end else begin
                $display("  %0d ASSERTION(S) FAILED", fail_count);
            end
            $display("========================================\n");
            $stop;
        end
        else if (gpio_out0 == 16'h0BAD) begin // any other non-zero value is an error (the test program should only write zero to the GPIO out, by design)
            $display("[FAIL!!!] At time %t, GPIO_OUT0: %h", $time, gpio_out0);
            fail_count++;
        end
    end

    initial begin
        forever begin
            @(posedge clk50);
            $display("Time: %50t | imem raddr: %8h | imem rdata: %8h | GPIO1: %4h | gpio_out0: %4h", $time, dut.instr_if.addr, dut.instr_if.rdata, dut.gpio_out1, gpio_out0);
        end
    end
endmodule
