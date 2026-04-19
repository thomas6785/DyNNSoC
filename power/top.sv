`timescale 1ns / 1ns
/////////////////////////////////////////////////////////////////
// Module Name: TB_toplevel
// Simple testbench for SoC - no program load, just clock and reset
/////////////////////////////////////////////////////////////////
module TB_toplevel;
    int i;
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

    // Load ROM with firmware
    initial $readmemh("/home/tudentstudent/DyNNSoC/power/artefacts/main.hex", dut.imem.bram.mem);  // load the program into ROM

    // Clock generation
    initial begin
        clk = 1'b0;
        forever     // generate 50 MHz clock
            #10 clk = ~clk;  // invert clock every 10 ns
    end

    task randomise_mvu_data();
        int mvu_id;
        int addr;
        for(mvu_id = 0; mvu_id<4; mvu_id++) begin
            force dut.MVU.mvu_ext_if.wrc_en = (1<<mvu_id); // one-hot enable for each MVU
            for(addr = 0; addr<32767; addr++) begin
                force dut.MVU.mvu_ext_if.wrc_word = {$urandom,$urandom};  // random data
                force dut.MVU.mvu_ext_if.wrc_addr = addr;
                @(posedge clk); // wait for write to complete
            end
        end
        release dut.MVU.mvu_ext_if.wrc_en;
        release dut.MVU.mvu_ext_if.wrc_word;
        release dut.MVU.mvu_ext_if.wrc_addr;
    endtask

    task randomise_mvu_weights();
        int mvu_id;
        int addr;
        // Write random weights to the MVUs
        for(mvu_id = 0; mvu_id<4; mvu_id++) begin
            force dut.MVU.mvu_ext_if.wrw_be = '1;          // write all bytes
            force dut.MVU.mvu_ext_if.wrw_en = (1<<mvu_id); // one-hot enable for each MVU
            for(addr = 0; addr < 512; addr++) begin
                logic [4095:0] random_weight;
                for (int j = 0; j<4096; j=j+32) begin // $urandom only proivides 32 bits of randomness, so we need this loop to get a whole 4096-bit random word
                    random_weight[j +: 32] = $urandom; // random 32 bits of weight data
                end
                force dut.MVU.mvu_ext_if.wrw_word = random_weight;  // random data
                force dut.MVU.mvu_ext_if.wrw_addr = addr;
                @(posedge clk); // wait for write to complete
            end
            release dut.MVU.mvu_ext_if.wrw_be;
            release dut.MVU.mvu_ext_if.wrw_en;
            release dut.MVU.mvu_ext_if.wrw_word;
            release dut.MVU.mvu_ext_if.wrw_addr;
        end
    endtask

    task phase(string name); // simple task to mark phases of the test. Tests will stop (and can be restarted) at the end of each phase.
        $display("\n[PHASE] %3t %s\n", $time, name);
        //$stop;
    endtask

    task info(string txt); // simple task to display text with a consistent format
        $display("[INFO ] %3t %s", $time, txt);
    endtask

    task interrupt(string txt);
        info(txt);
        $stop;
    endtask

    // Main procedure: check ROM is loaded, assert reset, then release reset and wait for interrupts
    initial begin
        phase("Initialisation");
        gpio_in0 = $urandom;    // set a value on the switches
        serialRx = 1'b1;        // serial line idle high
        btnCpuResetn = 1'b0;    // start with reset active
        #400;                 // wait for cpu and bus clock to be stable
        repeat(10) @(posedge clk); // hold reset for a while

        info("ROM peek:"); // display 16 bytes of ROM to allow checking the correct firmware is loaded
        for(i = 0; i < 16; i++) begin
            info($sformatf("ROM[%0d] = %h", i, dut.imem.bram.mem[i]));
        end
        for(i = 'h80; i < 'h90; i++) begin // also peek from address 0x80 which is where main program starts
            info($sformatf("ROM[%0d] = %h", i, dut.imem.bram.mem[i]));
        end

        // Randomise the data in the weights banks
        fork
            randomise_mvu_data();
            randomise_mvu_weights();
        join

        btnCpuResetn = 1'b0;    // assert reset
        repeat(10) @(posedge clk); // hold reset for a while

        phase("Running firmware");
        btnCpuResetn = 1'b1;    // release reset
    end

    // Monitor GPIO_OUT1 for testbench interrupts
    always @ (gpio_out0) begin
        if (gpio_out0 == 16'hBEEF)
        interrupt($sformatf("Testbench halted by software with code %2x", gpio_out1));
    end
endmodule
