module ahb_1to1_interconnect (
    ahb_intf_m.interconn master,
    ahb_intf_s.interconn slave
);
    logic hready;
    assign hready = slave.hreadyout; // Single-slave: hready follows slave's hreadyout

    // Master-driven signals
    assign slave.haddr      = master.haddr;
    assign slave.hwrite     = master.hwrite;
    assign slave.hsize      = master.hsize;
    assign slave.hburst     = master.hburst;
    assign slave.hprot      = master.hprot;
    assign slave.hmastlock  = master.hmastlock;
    assign slave.htrans     = master.htrans;
    assign slave.hwdata     = master.hwdata;

    // Interconnect-driven signals
    assign slave.hready     = hready;
    assign slave.hsel       = 1'b1; // Always select the sole slave
    assign master.hready    = hready;

    // Slave-driven signals
    assign master.hrdata    = slave.hrdata;
    assign master.hresp     = slave.hresp;
endmodule
