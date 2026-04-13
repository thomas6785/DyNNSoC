`define CONNECT_SLAVE_TO_MASTER(slave,master) \
    assign slave.HREADY   = master.HREADY; \
    assign slave.HWDATA   = master.HWDATA; \
    assign slave.HWRITE   = master.HWRITE; \
    assign slave.HSIZE    = master.HSIZE; \
    assign slave.HPROT    = master.HPROT; \
    assign slave.HTRANS   = master.HTRANS; \
    assign slave.HADDR    = master.HADDR

module ahb_interconn (
    input logic HCLK,
    input logic HRESETn,

    // Master interface
    ahb_intf_m.interconn master_if,

    // Slave interfaces
    ahb_intf_s.interconn slave_if_s0,
    ahb_intf_s.interconn slave_if_s1,
    ahb_intf_s.interconn slave_if_s2,
    ahb_intf_s.interconn slave_if_s3
);
    // A lot of the signals from the master are shared to every slave
    `CONNECT_SLAVE_TO_MASTER(slave_if_s0, master_if);
    `CONNECT_SLAVE_TO_MASTER(slave_if_s1, master_if);
    `CONNECT_SLAVE_TO_MASTER(slave_if_s2, master_if);
    `CONNECT_SLAVE_TO_MASTER(slave_if_s3, master_if);
    // I hate using macros but I really can't think of a cleaner way of doing this
    // Doing this for every single slave is very annoying... Would be nice if we could come up with a clean way of sharing this interface, but that starts to get messy when you have multiple masters (consider the fact that a master shouldn't need to be aware of which number master it is)

    wire [3:0]  muxSel;         // from address decoder to control the multiplexer

    localparam  BAD_DATA = 32'hdeadbeef;  // value read from invalid slave
    localparam  OKAY = 1'b0, ERROR = 1'b1;  // values for the HRESP signal

    ahb_decoder decode (
        .HADDR      (master_if.HADDR),         // address in
        .HSEL_S0    (slave_if_s0.HSEL),
        .HSEL_S1    (slave_if_s1.HSEL),
        .HSEL_S2    (slave_if_s2.HSEL),
        .HSEL_S3    (slave_if_s3.HSEL),
        .HSEL_S4    (),
        .HSEL_S5    (),
        .HSEL_S6    (),
        .HSEL_S7    (),
        .HSEL_S8    (),
        .HSEL_S9    (),
        .HSEL_NOMAP (dummy_if.HSEL),   // select dummy slave if invalid address given
        .MUX_SEL    (muxSel)        // multiplexer control signal out
    );

    ahb_mux mux (
        .HCLK           (HCLK),             // bus clock and reset
        .HRESETn        (HRESETn),
        .MUX_SEL        (muxSel),     // control from address decoder

        // Connect the read data signals to the data multiplexer
        .HRDATA_S0      (slave_if_s0.HRDATA),
        .HRDATA_S1      (slave_if_s1.HRDATA),
        .HRDATA_S2      (slave_if_s2.HRDATA),
        .HRDATA_S3      (slave_if_s3.HRDATA),
        .HRDATA_S4      (BAD_DATA),
        .HRDATA_S5      (BAD_DATA),
        .HRDATA_S6      (BAD_DATA),         // unused inputs give BAD_DATA
        .HRDATA_S7      (BAD_DATA),
        .HRDATA_S8      (BAD_DATA),
        .HRDATA_S9      (BAD_DATA),
        .HRDATA_NOMAP   (BAD_DATA),         // dummy slave also gives BAD_DATA
        .HRDATA         (master_if.HRDATA),           // read data output to master

        // Connect the ready signals to the ready multiplexer
        .HREADYOUT_S0   (slave_if_s0.HREADYOUT),
        .HREADYOUT_S1   (slave_if_s1.HREADYOUT),
        .HREADYOUT_S2   (slave_if_s2.HREADYOUT),
        .HREADYOUT_S3   (slave_if_s3.HREADYOUT),
        .HREADYOUT_S4   (1'b1),
        .HREADYOUT_S5   (1'b1),
        .HREADYOUT_S6   (1'b1),             // unused inputs must be tied to 1
        .HREADYOUT_S7   (1'b1),
        .HREADYOUT_S8   (1'b1),
        .HREADYOUT_S9   (1'b1),
        .HREADYOUT_NOMAP(dummy_if.HREADYOUT),  // ready signal from dummy slave
        .HREADY         (master_if.HREADY),           // ready output to master and all slaves

        // Connect the response signals to the response multiplexer
        .HRESP_S0    (slave_if_s0.HRESP),    // the ROM and RAM slaves do not have HRESP ports, as they
        .HRESP_S1    (slave_if_s1.HRESP),    // never signal an error, so response is always OKAY
        .HRESP_S2    (slave_if_s2.HRESP),
        .HRESP_S3    (slave_if_s3.HRESP),
        .HRESP_S4    (OKAY),
        .HRESP_S5    (OKAY),
        .HRESP_S6    (OKAY),    // unused reponse inputs should also be OKAY
        .HRESP_S7    (OKAY),
        .HRESP_S8    (OKAY),
        .HRESP_S9    (OKAY),
        .HRESP_NOMAP (dummy_if.HRESP),  // response signal from dummy slave
        .HRESP       (master_if.HRESP)         // reponse output to master
    );

    // ======================= Dummy Slave ======================================
    // Dummy slave only needs the type of transaction to decide how to respond - other signals are ignored
    // The response is OKAY for IDLE and BUSY transactions, otherwise ERROR.

    ahb_intf_s dummy_if();
    ahb_dummy DUMMY(
        .HCLK        (HCLK),            // bus clock
        .HRESETn     (HRESETn),         // bus reset, active low
        .HSEL        (dummy_if.HSEL),      // selects this slave
        .HREADY      (master_if.HREADY),          // indicates previous transaction completing
        .HTRANS      (master_if.HTRANS),          // transaction type (only bit 1 used)
        .HREADYOUT   (dummy_if.HREADYOUT), // ready output
        .HRESP       (dummy_if.HRESP)      // response output
    );
endmodule