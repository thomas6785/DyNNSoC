`timescale 1ns/1ps

interface ahb_intf_m #( // Signals for connecting a master to the AHB interconnect
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
);
    // Master drives these
    logic [DATA_WIDTH-1:0]  HWDATA;
    logic                   HWRITE;
    logic [2:0]             HSIZE;
    logic [3:0]             HPROT;
    logic [1:0]             HTRANS;
    logic [ADDR_WIDTH-1:0]  HADDR;

    // Interconnect/MUX drives these
    logic [DATA_WIDTH-1:0]  HRDATA;
    logic                   HREADY;
    logic                   HRESP;

    modport master (
        output HADDR,
        output HWDATA, HWRITE, HSIZE, HPROT, HTRANS,
        input HRDATA, HREADY, HRESP
    );

    modport interconn (
        input HADDR,
        input HWDATA, HWRITE, HSIZE, HPROT, HTRANS,
        output HRDATA, HREADY, HRESP
    );
endinterface

interface ahb_intf_s #( // Signals for connecting a slave to the AHB interconnect
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
);
    // Slave drives these
    logic [DATA_WIDTH-1:0]  HRDATA;
    logic                   HREADYOUT;
    logic                   HRESP;

    // Interconnect/MUX drives these
    logic [DATA_WIDTH-1:0]  HWDATA;
    logic                   HWRITE;
    logic [2:0]             HSIZE;
    logic [3:0]             HPROT;
    logic [1:0]             HTRANS;
    logic [ADDR_WIDTH-1:0]  HADDR;
    logic                   HREADY;
    logic                   HSEL;

    modport slave (
        input HSEL, HREADY,
        input HWDATA, HWRITE, HSIZE, HPROT, HTRANS,
        input HADDR,
        output HRDATA, HREADYOUT, HRESP
    );

    modport interconn (
        output HSEL, HREADY,
        output HWDATA, HWRITE, HSIZE, HPROT, HTRANS,
        output HADDR,
        input HRDATA, HREADYOUT, HRESP
    );
endinterface
