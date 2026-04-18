`timescale 1ns/1ps

module ahb_transparent_arbiter (
    input HCLK,
    input HRESETn,

    ahb_intf_m.interconn ahb_if_m1, // first master interface
    ahb_intf_m.interconn ahb_if_m2, // second master interface
    ahb_intf_m.master ahb_if_mi // interconnect master (driven by the arbiter)
);
    // "Transparent" refers to the fact that the masters do not know they are being arbited
    // i.e. there is not BUSREQ and BUSGNT signal
    // Instead we rely on HREADY to delay Masters

    logic m1_wants_bus, m2_wants_bus;
    assign m1_wants_bus = ahb_if_m1.HTRANS != 2'b00; // not IDLE
    assign m2_wants_bus = ahb_if_m2.HTRANS != 2'b00; // not IDLE

    typedef enum logic [1:0] {
        FREE = 2'b00,
        M1 = 2'b01,
        M2 = 2'b10
    } owner_t;
    owner_t control_signals_owner;
    owner_t data_signals_owner, data_signals_owner_next;

    always_ff @ (posedge HCLK) begin
        if (!HRESETn)    data_signals_owner <= FREE;
        else             data_signals_owner <= data_signals_owner_next;
    end

    // TODO known issue: control_signals_owner should be latched to prevent the priority master from 'interrupting' the lower priority master
    //                   AHB standard doesn't allow this, even if READY hasn't been given yet!
    //                   in this case, because we are only using it for a DMA and simple peripherals, we see no bugs
    //                   but this design is not robust!
    assign control_signals_owner   = m2_wants_bus ? M2 : m1_wants_bus ? M1 : FREE; // static priority scheme M2 > M1
    assign data_signals_owner_next = (ahb_if_mi.HREADY) ? control_signals_owner : data_signals_owner; // data owner follows control owner, but only when we are ready to move on

    // HREADY is given if the slave is giving it AND that master has the control signals
    // The slave may have already sampled the data, but we can't tell the master its ready because it is deadlin with the other master's control signals
    // Alternatively, if the master doesn't want the control signals, we can give it the READY from the slave since we are ignoring its control signals anyway
    assign ahb_if_m1.HREADY = ahb_if_mi.HREADY && ((control_signals_owner == M1) | ~m1_wants_bus );
    assign ahb_if_m2.HREADY = ahb_if_mi.HREADY && ((control_signals_owner == M2) | ~m2_wants_bus );
    // i.e. you can move on EITHER:
    // - if you have the bus
    // - if you don't want the bus
    // but if you WANT it and DON'T have it, we can't give you the 'ready' signal
    // because that would imply we have sampled you control signals and we haven't

    // HREADY means:
    // - I have captured the write data or prepared the read data (i.e. the slave is ready)
    // - I have captured the control signals
    // - Not necessarily that I have JUST done those things
    // Example:
    // https://wavedrom.com/editor.html?%7Bsignal%3A%20%5B%0A%20%20%7Bname%3A%20%27HCLK%27%2C%20%20%20%20%20%20wave%3A%20%27p..............................................................%27%7D%2C%0A%20%0A%20%20%7Bname%3A%20%27M1_addr%27%2C%20%20%20wave%3A%20%27%3D3%3D....45..%3D.......6%3D........8%3D..................34...%3D.................%27%7D%2C%0A%20%20%7Bname%3A%20%27M1_data%27%2C%20%20%20wave%3A%20%27%3D.3.%3D...4..5%3D.......6%3D........8...%3D...............3...4....................%27%7D%2C%0A%20%20%7Bname%3A%20%27M1_rdy%27%2C%20%20%20%20wave%3A%20%270101....0.1...................0..1x..............10..1..............%27%7D%2C%0A%20%20%0A%20%20%7Bname%3A%20%27M2_addr%27%2C%20%20%20wave%3A%20%27%3D...................7%3D.......9.%3D.................5..%3D...................%27%7D%2C%0A%20%20%7Bname%3A%20%27M2_data%27%2C%20%20%20wave%3A%20%27%3D....................7%3D........9......%3D.............5..................%27%7D%2C%0A%20%20%7Bname%3A%20%27M2_rdy%27%2C%20%20%20%20wave%3A%20%271............................010.....1x..........0.1..................%27%7D%2C%0A%20%20%0A%20%20%7Bname%3A%20%27S_addr%27%2C%20%20%20%20wave%3A%20%27%3D3%3D....45..%3D.......67%3D.......89...%3D..............35.4.%3D......................%27%7D%2C%0A%20%20%7Bname%3A%20%27S_data%27%2C%20%20%20%20wave%3A%20%27%3D.3.%3D...4..5%3D.......67%3D.......8...9...%3D...........3.5.4.%3D...................%27%7D%2C%0A%20%20%7Bname%3A%20%27S_rdy%27%2C%20%20%20%20%20wave%3A%20%270101....0.1...................0..10..1x..........101..01..............%27%7D%0A%5D%2C%0A%20head%3A%7B%0A%20%20%20tick%3A0%2C%0A%20%20%20every%3A1%0A%20%7D%2C%7D
    // at clock cycle 54, ready is given to M1
    // even though the write data was actually sampled at cycle 52, we put in another transaction inbetween
    // M1 is not aware of this (and doesn't need to be)

    // cycles 82-90 exmplify this more clearly: M1 is a DMA (or similar) which is constantly using theb us
    // M2 has higher priority and arrives with a transaction, forcing the DMA to stall
    // The purple signal actualyl gets sampled at 87, but M1 doesn't know and just waits for 'ready'

    // MUX the control signals from the appropriate owner (control_signals_owner)
    // and the data signals from the appropriate owner (data_signals_owner)
    always_comb begin
        unique case (control_signals_owner)
            M1: begin
                ahb_if_mi.HADDR  = ahb_if_m1.HADDR;
                ahb_if_mi.HWRITE = ahb_if_m1.HWRITE;
                ahb_if_mi.HSIZE  = ahb_if_m1.HSIZE;
                ahb_if_mi.HPROT  = ahb_if_m1.HPROT;
                ahb_if_mi.HTRANS = ahb_if_m1.HTRANS;
            end
            M2: begin
                ahb_if_mi.HADDR  = ahb_if_m2.HADDR;
                ahb_if_mi.HWRITE = ahb_if_m2.HWRITE;
                ahb_if_mi.HSIZE  = ahb_if_m2.HSIZE;
                ahb_if_mi.HPROT  = ahb_if_m2.HPROT;
                ahb_if_mi.HTRANS = ahb_if_m2.HTRANS;
            end
            default: begin
                ahb_if_mi.HADDR  = '0;
                ahb_if_mi.HWRITE = '0;
                ahb_if_mi.HSIZE  = '0;
                ahb_if_mi.HPROT  = '0;
                ahb_if_mi.HTRANS = '0;
            end
        endcase
        unique case (data_signals_owner)
            M1:      ahb_if_mi.HWDATA = ahb_if_m1.HWDATA;
            M2:      ahb_if_mi.HWDATA = ahb_if_m2.HWDATA;
            FREE:    ahb_if_mi.HWDATA = '0;
            default: ahb_if_mi.HWDATA = 32'hBADBAD00; // Should never happen
        endcase
    end

    // Need to capture HRESP and HRDATA when the slave says its ready
    // If we are hiding the ready state from the master, we need to capture that data and hold it until we can give the master the ready signal
    logic m1_hresp_store, m2_hresp_store;
    logic [31:0] m1_hrdata_store, m2_hrdata_store;
    always_ff @ (posedge HCLK) begin
        if (!HRESETn) begin
            m1_hresp_store     <= '0;
            m1_hrdata_store    <= '0;
            m2_hresp_store     <= '0;
            m2_hrdata_store    <= '0;
        end else begin
            if (data_signals_owner == M1) begin
                m1_hresp_store  <= ahb_if_mi.HRESP;
                m1_hrdata_store <= ahb_if_mi.HRDATA;
            end else if (data_signals_owner == M2) begin
                m2_hresp_store  <= ahb_if_mi.HRESP;
                m2_hrdata_store <= ahb_if_mi.HRDATA;
            end
        end
    end

    // If we currently own the data signals (HRDATA and HRESP), pass them through from the slave to the master
    // If we don't currently own the data signals, retain the last values where this master did own them
    // This means we have hidden a transaction from the master
    assign ahb_if_m1.HRESP  = (data_signals_owner == M1) ? ahb_if_mi.HRESP  : m1_hresp_store;
    assign ahb_if_m1.HRDATA = (data_signals_owner == M1) ? ahb_if_mi.HRDATA : m1_hrdata_store;
    assign ahb_if_m2.HRESP  = (data_signals_owner == M2) ? ahb_if_mi.HRESP  : m2_hresp_store;
    assign ahb_if_m2.HRDATA = (data_signals_owner == M2) ? ahb_if_mi.HRDATA : m2_hrdata_store;
endmodule
