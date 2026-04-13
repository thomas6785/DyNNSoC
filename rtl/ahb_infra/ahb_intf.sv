`timescale 1ns/1ps

interface ahb_intf_m #( // Signals for connecting a master to the AHB interconnect
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic hclk,
    input logic hresetn
);

    // Master drives these
    logic [ADDR_WIDTH-1:0] haddr;
    logic                  hwrite;
    logic [2:0]            hsize;
    logic [2:0]            hburst;
    logic [3:0]            hprot;
    logic [1:0]            htrans;
    logic                  hmastlock;
    logic [DATA_WIDTH-1:0] hwdata;

    // Interconnect/MUX drives these
    logic [DATA_WIDTH-1:0] hrdata;
    logic                  hready;
    logic                  hresp;

    modport master (
        input hclk, hresetn,
        output haddr, hwrite, hsize, hburst, hprot, htrans, hmastlock, hwdata,
        input hrdata, hready, hresp
    );

    modport interconn (
        input hclk, hresetn,
        input haddr, hwrite, hsize, hburst, hprot, htrans, hmastlock, hwdata,
        output hrdata, hready, hresp
    );
endinterface

interface ahb_intf_s #( // Signals for connecting a slave to the AHB interconnect
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic hclk,
    input logic hresetn
);
    // Slave drives these
    logic [DATA_WIDTH-1:0] hrdata;
    logic                  hreadyout;
    logic                  hresp;

    // Interconnect/MUX drives these
    logic                  hsel;
    logic [ADDR_WIDTH-1:0] haddr;
    logic                  hwrite;
    logic [2:0]            hsize;
    logic [2:0]            hburst;
    logic [3:0]            hprot;
    logic                  hmastlock;
    logic [1:0]            htrans;
    logic                  hready;
    logic [DATA_WIDTH-1:0] hwdata;

    modport slave (
        input hclk, hresetn,
        input hsel, haddr, hwrite, hsize, hburst, hprot, hmastlock, htrans, hready, hwdata,
        output hrdata, hreadyout, hresp
    );

    modport interconn (
        input hclk, hresetn,
        output hsel, haddr, hwrite, hsize, hburst, hprot, hmastlock, htrans, hready, hwdata,
        input hrdata, hreadyout, hresp
    );
endinterface