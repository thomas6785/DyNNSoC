module ahb_1to1_interconnect (
    ahb_intf_m.interconn master,
    ahb_intf_s.interconn slave
);
    logic HREADY;
    assign HREADY = slave.HREADYOUT; // Single-slave: HREADY follows slave's HREADYOUT

    // Master-driven signals
    assign slave.HADDR      = master.HADDR;
    assign slave.HWRITE     = master.HWRITE;
    assign slave.HSIZE      = master.HSIZE;
    assign slave.HPROT      = master.HPROT;
    assign slave.HTRANS     = master.HTRANS;
    assign slave.HWDATA     = master.HWDATA;

    // Interconnect-driven signals
    assign slave.HREADY     = HREADY;
    assign slave.HSEL       = 1'b1; // Always select the sole slave
    assign master.HREADY    = HREADY;

    // Slave-driven signals
    assign master.HRDATA    = slave.HRDATA;
    assign master.HRESP     = slave.HRESP;
endmodule
