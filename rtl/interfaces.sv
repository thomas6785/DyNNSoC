`timescale 1ns / 1ns

interface instruction_fetch_if;
    logic [31:0] rdata;
    logic [31:0] addr;
    logic req;
    logic ready;

    modport core (
        output addr, req,
        input rdata, ready
    );

    modport rom (
        input addr, req,
        output rdata, ready
    );
endinterface