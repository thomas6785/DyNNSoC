interface memory_interface #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
);
    logic                  req; // request
    logic                  we;  // write-enable
    logic [ADDR_WIDTH-1:0] addr; // address
    logic [DATA_WIDTH-1:0] wdata; // write data
    logic [DATA_WIDTH-1:0] rdata; // read data

    modport master (
        output req,
        output we,
        output addr,
        output wdata,
        input  rdata
    );

    modport slave (
        input  req,
        input  we,
        input  addr,
        input  wdata,
        output rdata
    );
endinterface