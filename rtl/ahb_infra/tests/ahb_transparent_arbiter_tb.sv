module ahb_transparent_arbiter_tb;
    // Clock and reset
    logic HCLK = 0;
    logic HRESETn = 0;

    // Clock stimulus
    initial begin
        forever #10 HCLK = ~HCLK;
    end

    // SV won't let us pass the interfaces straight into the tasks, so we have to split out these signals
    logic [31:0]  HADDR  [1:0];
    logic [1:0]   HTRANS [1:0];
    logic         HWRITE [1:0];
    logic [31:0]  HWDATA [1:0];
    logic         HREADY [1:0];
    logic [31:0]  HRDATA [1:0];

    assign HREADY[0] = ahb_if_m1.HREADY;
    assign HREADY[1] = ahb_if_m2.HREADY;
    assign HRDATA[0] = ahb_if_m1.HRDATA;
    assign HRDATA[1] = ahb_if_m2.HRDATA;
    assign ahb_if_m1.HADDR = HADDR[0];
    assign ahb_if_m1.HTRANS = HTRANS[0];
    assign ahb_if_m1.HWRITE = HWRITE[0];
    assign ahb_if_m1.HWDATA = HWDATA[0];
    assign ahb_if_m2.HADDR = HADDR[1];
    assign ahb_if_m2.HTRANS = HTRANS[1];
    assign ahb_if_m2.HWRITE = HWRITE[1];
    assign ahb_if_m2.HWDATA = HWDATA[1];

    // Create AHB interfaces (two masters, one MUX'd master 'slave')
    ahb_intf_m ahb_if_m1(); // first master
    ahb_intf_m ahb_if_m2(); // second master
    ahb_intf_m ahb_if_mi(); // interconnect master (output of arbiter)
    ahb_intf_s ahb_if_s(); // slave

    ahb_transparent_arbiter dut (
        .HCLK,
        .HRESETn,
        .ahb_if_m1,
        .ahb_if_m2,
        .ahb_if_mi
    );

    ahb_1to1_interconnect interconn_m1 (
        .master(ahb_if_m1),
        .slave(ahb_if_s)
    );

    ahb_rw_regs #(
        .DATA_WIDTH(32),
        .NUM_REGS(2)
    ) reg_slave (
        .HCLK,
        .HRESETn,
        .bus(ahb_if_s),
        .regs_out()
    );

    // NOTE: YOU MUST CALL ANOTHER AHB TASK AFTER AHB_WRITE - AHB_IDLE IF NOTHING ELSE
    task ahb_write(
        int master,
        input logic [31:0] addr,
        input logic [31:0] data
    );
        HADDR[master]  = addr;
        HTRANS[master] = 2'b10; // NONSEQ
        HWRITE[master] = 1;
        $display("%3t Master %d waiting to write %h to address %h", $time, master, data, addr);
        // Hold signals until HREADY
        @(posedge HCLK iff HREADY[master]);
        HWDATA[master] = data;
    endtask

    task ahb_read(
        int master,
        input logic [31:0] addr
    );
        HADDR[master]  = addr;
        HTRANS[master] = 2'b10; // NONSEQ
        HWRITE[master] = 0;
        $display("%3t Master %d waiting to read from address %h", $time, master, addr);
        // Hold signals until HREADY
        @(posedge HCLK iff HREADY[master]);
        // you must NOW wait for HREADY again before HRDATA is valid
    endtask

    task ahb_idle(
        int master
    );
        HTRANS[master] = 2'b00; // IDLE
    endtask

    task ahb_if_init();
        HADDR  = '{default: '0};
        HTRANS = '{default: '0};
        HWRITE = '{default: '0};
        HWDATA = '{default: '0};
        ahb_if_m1.HSIZE = 3'b010;
        ahb_if_m1.HPROT = 4'b0011;
        ahb_if_m2.HSIZE = 3'b010;
        ahb_if_m2.HPROT = 4'b0011;
    endtask

    task ahb_finish(
        int master
    );
        @(posedge HCLK iff HREADY[master]);
    endtask

    localparam M1 = 0;
    localparam M2 = 1;

    initial begin
        // Initialises interfaces
        $display("%3t Initialising AHB interfaces", $time);
        ahb_if_init();
        $display("%3t Initialised interfaces", $time);

        HRESETn = 0;
        repeat(2) @(posedge HCLK);
        HRESETn = 1;
        repeat(2) @(posedge HCLK);
        $display("%3t Release reset", $time);

        // Test sequence
        ahb_write   (M1, 0, 32'hA5A5A5A5);
        $display("%3t Called AHB write", $time);
        ahb_idle    (M1);
        $display("%3t Called AHB idle", $time);
        ahb_read    (M1, 0);
        $display("%3t Called AHB read", $time);
        ahb_idle    (M1);
        $display("%3t Called AHB idle", $time);
        ahb_finish  (M1);
        $display("%3t Called AHB finish", $time);
        $display("%3t Calling assertion:", $time);
        assert (HRDATA[M1] == 32'hA5A5A5A5) else $display("ERROR: M1 readback incorrect");

        ahb_read    (M1, 0);
        ahb_idle    (M1);
        ahb_finish  (M1);
        assert (HRDATA[M1] == 32'hA5A5A5A5) else $display("ERROR: second M1 readback inc    orrect");

        ahb_write   (M1, 4, 32'hDEADBEEF);
        ahb_read    (M1, 4);
        ahb_idle    (M1);
        ahb_finish  (M1);
        assert (HRDATA[M1] == 32'hDEADBEEF) else $display("ERROR: M1 fast readback of reg1 incorrect");

        $stop;
    end
endmodule