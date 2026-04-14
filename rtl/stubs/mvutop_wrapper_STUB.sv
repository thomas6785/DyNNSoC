`timescale 1ns/1ps

module mvutop_wrapper (
    input logic HCLK,
    input logic HRESETn,
    output logic [7:0] irq_flag,
    ahb_intf_s.slave AHB_IF
);
    always @ (posedge HCLK) begin
        if (AHB_IF.HSEL && AHB_IF.HTRANS[1] && ~HRESETn) begin
            $error("Unexpectedly got transaction to MVU top wrapper when stub version was instantiated!");
        end
    end
    assign AHB_IF.HRESP = 1'b1; // error all transactions
    assign AHB_IF.HREADYOUT = 1'b1; // always ready
    assign AHB_IF.HRDATA = 32'b0; // return zeros on reads
endmodule