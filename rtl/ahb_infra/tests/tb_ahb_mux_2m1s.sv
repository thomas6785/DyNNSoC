`timescale 1ns/1ps

module tb_ahb_mux_2m1s;
    localparam CLK_PERIOD = 10;
    localparam DATA_WIDTH = 32;
    localparam NUM_REGS   = 8;

    // Clock and reset
    logic HCLK = 0;
    logic HRESETn = 0;
    always #(CLK_PERIOD/2) HCLK = ~HCLK;

    // Master 1 signals
    logic [31:0]  HADDR_M1;
    logic [1:0]   HTRANS_M1;
    logic         HWRITE_M1;
    logic [2:0]   HSIZE_M1;
    logic [DATA_WIDTH-1:0] HWDATA_M1;
    logic         HREADY_M1;
    logic [DATA_WIDTH-1:0] HRDATA_M1;

    // Master 2 signals
    logic [31:0]  HADDR_M2;
    logic [1:0]   HTRANS_M2;
    logic         HWRITE_M2;
    logic [2:0]   HSIZE_M2;
    logic [DATA_WIDTH-1:0] HWDATA_M2;
    logic         HREADY_M2;
    logic [DATA_WIDTH-1:0] HRDATA_M2;

    // Slave signals
    logic         HREADY;
    logic [DATA_WIDTH-1:0] HRDATA;
    logic [31:0]  HADDR;
    logic [1:0]   HTRANS;
    logic         HWRITE;
    logic [2:0]   HSIZE;
    logic [DATA_WIDTH-1:0] HWDATA;

    // Instantiate the DUT
    ahb_mux_2m1s dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HADDR_M1(HADDR_M1), .HTRANS_M1(HTRANS_M1), .HWRITE_M1(HWRITE_M1), .HSIZE_M1(HSIZE_M1), .HWDATA_M1(HWDATA_M1), .HREADY_M1(HREADY_M1), .HRDATA_M1(HRDATA_M1),
        .HADDR_M2(HADDR_M2), .HTRANS_M2(HTRANS_M2), .HWRITE_M2(HWRITE_M2), .HSIZE_M2(HSIZE_M2), .HWDATA_M2(HWDATA_M2), .HREADY_M2(HREADY_M2), .HRDATA_M2(HRDATA_M2),
        .HREADY(HREADY), .HRDATA(HRDATA),
        .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE), .HSIZE(HSIZE), .HWDATA(HWDATA)
    );


    // Instantiate AHB slave interface
    ahb_intf_s #(32, DATA_WIDTH) slave_if();

    // Tie off interface signals to mux outputs
    assign slave_if.HADDR    = HADDR;
    assign slave_if.HTRANS   = HTRANS;
    assign slave_if.HWRITE   = HWRITE;
    assign slave_if.HSIZE    = HSIZE;
    assign slave_if.HWDATA   = HWDATA;
    assign slave_if.HSEL     = 1'b1;
    assign slave_if.HREADY   = HREADY;
    assign HREADY            = slave_if.HREADYOUT;
    assign HRDATA            = slave_if.HRDATA;

    // Instantiate the register slave
    logic [DATA_WIDTH-1:0] regs_out [NUM_REGS];
    ahb_rw_regs #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) reg_slave (
        .HCLK,
        .HRESETn,
        .bus(slave_if),
        .regs_out(regs_out)
    );

    // Test sequence
    initial begin
        HRESETn = 0;
        HADDR_M1 = 0; HTRANS_M1 = 2'b00; HWRITE_M1 = 0; HSIZE_M1 = 3'b010; HWDATA_M1 = 0;
        HADDR_M2 = 0; HTRANS_M2 = 2'b00; HWRITE_M2 = 0; HSIZE_M2 = 3'b010; HWDATA_M2 = 0;
        repeat (2) @(posedge HCLK);
        HRESETn = 1;
        @(posedge HCLK);


        // Master 1 writes to reg 0
        fork
            begin
                @(posedge HCLK);
                HADDR_M1 = 0;
                HTRANS_M1 = 2'b10; // NONSEQ
                HWRITE_M1 = 1;
                $display("M1 waiting to write A5A5A5A5 to address 0");
                // Hold signals until HREADY_M1
                @(posedge HCLK iff HREADY_M1);
                HWDATA_M1 = 32'hA5A5A5A5;
                HTRANS_M1 = 2'b00; // IDLE
                HWRITE_M1 = 0;
            end
            // Master 2 writes to reg 1
            begin
                @(posedge HCLK);
                HADDR_M2 = 4;
                HTRANS_M2 = 2'b10; // NONSEQ
                HWRITE_M2 = 1;
                $display("M2 waiting to write DEADBEEF to address 4");
                // Hold signals until HREADY_M2
                @(posedge HCLK iff HREADY_M2);
                HWDATA_M2 = 32'HDEADBEEF;
                HTRANS_M2 = 2'b00; // IDLE
                HWRITE_M2 = 0;
            end
        join
        @(posedge HCLK);

        // Master 1 reads reg 0
        HADDR_M1 = 0;
        HTRANS_M1 = 2'b10;
        HWRITE_M1 = 0;
        @(posedge HCLK iff HREADY_M1);
        HTRANS_M1 = 2'b00;
        @(posedge HCLK iff HREADY_M1);
        $display("M1 read reg0: %h", HRDATA_M1);

        // Master 2 reads reg 1
        HADDR_M2 = 4;
        HTRANS_M2 = 2'b10;
        HWRITE_M2 = 0;
        @(posedge HCLK iff HREADY_M2);
        HTRANS_M2 = 2'b00;
        @(posedge HCLK iff HREADY_M2);
        $display("M2 read reg1: %h", HRDATA_M2);

        $finish;
    end
endmodule
