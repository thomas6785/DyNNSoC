module dynnsoc (
    input clk,
    input rst_n,

    input btnU,
    input btnD,
    input btnL,
    input btnR,
    input btnC,
    
    input serialRx,
    output serialTx
);
    // Ibex core with a wrapper that provides ROM (and a UART loader) and an AHB interface for data memory
    ibex_wrapper ibex_core (
        .HCLK,
        .HRESETn,

        .HADDR(M2_HADDR),
        .HREADY(M2_HREADY),
        .HWRITE(M2_HWRITE),
        .HTRANS(M2_HTRANS),
        .HSIZE(M2_HSIZE),
        .HWDATA(M2_HWDATA),
        .HRDATA(M2_HRDATA),

        .NMI(NMI), // non-maskable interrupt
        .EXT_IRQ(EXT_IRQ), // interrupt request line
        .IRQ({M2_IRQ[27:16], 4'b0}), // interrupts
        .SYSTICKCLKDIV(8'd100),

        .serialRx(serialRx),
        .loadButton(loadButton),
        .rom_load_status(rom_load_status),
        .rom_load_active(rom_load_active)
    );

    // Arbiter allows both the DMAC and Ibex core to share the bus
    ahb_mux_2m1s ahb_simple_arbiter (
        .HCLK,
        .HRESETn,

        // Port 1
        // input 
        .HADDR_M1(M1_HADDR),
        .HTRANS_M1(M1_HTRANS),
        .HWRITE_M1(M1_HWRITE),
        .HSIZE_M1(M1_HSIZE),
        .HWDATA_M1(M1_HWDATA),
        //output 
        .HREADY_M1(M1_HREADY),  
        .HRDATA_M1(M1_HRDATA),

        // Port 2
        //input 
        .HADDR_M2(M2_HADDR),
        .HTRANS_M2(M2_HTRANS),
        .HWRITE_M2(M2_HWRITE),
        .HSIZE_M2(M2_HSIZE),
        .HWDATA_M2(M2_HWDATA),
        //output 
        .HREADY_M2(M2_HREADY),
        .HRDATA_M2(M2_HRDATA),

        // Master Port
        //input
        .HREADY(HREADY_Sys0),
        .HRDATA(HRDATA_Sys0),
        //OUTPUT
        .HADDR(HADDR_Sys0),
        .HTRANS(HTRANS_Sys0),
        .HWRITE(HWRITE_Sys0),
        .HSIZE(HSIZE_Sys0),
        .HWDATA(HWDATA_Sys0)
    );
endmodule