module mvutop_wrapper import mvu_pkg::*;(
    input logic HCLK,
    input logic HRESETn,

    // Outgoing interrupts, one from each MVU
    output logic [NMVU-1:0] irq_flag,

    // AHB Interface
    ahb_intf_s.slave AHB_IF
);

MVU_EXT_INTERFACE mvu_ext_if(); // interface provided by the MVU for accessing internal memory

// Declare the config registers (and their shadow registers)
mvu_pkg::mvu_cfg_signals_t mvu_cfg_shadow [NMVU-1:0];
mvu_pkg::mvu_cfg_signals_t mvu_cfg_live [NMVU-1:0];

// Set up sticky interrupts
logic [NMVU-1:0] irq_pulse;

// Instantiate the MVU array
mvutop mvu(
    .clk(HCLK),
    .rst_n(HRESETn),
    .irq(irq_pulse),
    .mvu_ext(mvu_ext_if.mvu_ext),
    .mvu_cfg(mvu_cfg_live)
);

// Struct to store address parts
localparam REGTYPE_D = 4'b0000; // Data
localparam REGTYPE_W = 4'b0001; // Weight
localparam REGTYPE_B = 4'b0010; // Bias
localparam REGTYPE_S = 4'b0011; // Scaler
localparam REGTYPE_CSR = 4'b0100;

typedef struct packed {
    logic [3:0]  reg_type;   // bits 27-24: 0 for data, 1 for weights, 2 for biases, 3 for scalers, 4 for CSR
    logic [3:0]  mvu_id;     // bits 23-20: which MVU
    logic [1:0]  reserved_1; // bits 19-18
    logic [15:0] addr;       // bits 17-2: interpretation depends on type
    logic [1:0]  byte_sel;   // bits 1-0
} addr_t;

// Registers to hold signals from address phase
addr_t rHADDR;
logic [2:0] rHSIZE;
logic rHWRITE, rActive;

logic [3:0] byteWrite;              // individual byte write enable signals
logic active;   assign active = AHB_IF.HSEL & AHB_IF.HTRANS[1];    // slave selected and transfer in progress
logic write_en; assign write_en = rActive & rHWRITE;      // delayed write enable
logic read_en;  assign read_en = rActive & ~rHWRITE;      // delayed read enable
logic [31:0] rdata_mvu;             // read data from the MVU

// Read-after-write conflict resolution logic
logic [31:0] rWData;             // delayed write data for conflict resolution
logic rConflict;                 // byte conflict signals
logic conflict;                  // write and consecutive read at same address
assign conflict = (rHADDR == AHB_IF.HADDR[27:0])    // address match
                    && write_en                     //  write in progress
                    && active && !AHB_IF.HWRITE;    // next transaction is read

// Capture signals for use later
always_ff @(posedge HCLK) begin
    if(!HRESETn) begin
        rHADDR <= 28'b0;
        rHSIZE <= 3'b0;
        rHWRITE <= 1'b0;
        rActive <= 1'b0;
        rWData <= 32'b0;
        rConflict <= 1'b0;
    end else if(AHB_IF.HREADY) begin
        rHADDR <= AHB_IF.HADDR[27:0];    // capture bus signals from address phase
        rHSIZE <= AHB_IF.HSIZE;          // for use in data phase
        rHWRITE <= AHB_IF.HWRITE;
        rActive <= active;
        rWData <= AHB_IF.HWDATA;         // remember written data (for deconflicting)
        rConflict <= conflict;    // note if there has been a conflict
    end
end

// Decode to CSR, data, weight, bias, or scaler regmap
logic csr_write;         assign csr_write       = write_en && rHADDR.reg_type == REGTYPE_CSR;
logic csr_read;          assign csr_read        = read_en  && rHADDR.reg_type == REGTYPE_CSR;
logic data_write;        assign data_write      = write_en && rHADDR.reg_type == REGTYPE_D;
logic data_read;         assign data_read       = read_en  && rHADDR.reg_type == REGTYPE_D;
logic weight_write;      assign weight_write    = write_en && rHADDR.reg_type == REGTYPE_W;
logic weight_read;       assign weight_read     = read_en  && rHADDR.reg_type == REGTYPE_W;
logic bias_write;        assign bias_write      = write_en && rHADDR.reg_type == REGTYPE_B;
logic bias_read;         assign bias_read       = read_en  && rHADDR.reg_type == REGTYPE_B;
logic scaler_write;      assign scaler_write    = write_en && rHADDR.reg_type == REGTYPE_S;
logic scaler_read;       assign scaler_read     = read_en  && rHADDR.reg_type == REGTYPE_S;

// CSR Registers
genvar genvar_mvu_id;

generate for (genvar_mvu_id = 0; genvar_mvu_id < NMVU; genvar_mvu_id = genvar_mvu_id+1) begin
    always_ff @ (posedge HCLK) begin : always_ff_block
        // Register write logic
        if (~HRESETn) begin : reset // reset all registers to default values
            mvu_cfg_shadow[genvar_mvu_id]                  <= '{default: '0}; // most registers are set to zero

            // Some default values, TODO remove these, they should really be set by the software
            mvu_cfg_shadow[genvar_mvu_id].shacc_load_sel   <= 32'b00001;
            mvu_cfg_shadow[genvar_mvu_id].zigzag_step_sel  <= 32'b01111;
            mvu_cfg_shadow[genvar_mvu_id].omvusel          <= 32'(1<<genvar_mvu_id); // by default direct MVU output to itself
            mvu_cfg_shadow[genvar_mvu_id].scaler_b         <= 32'b1; // default scaler value of 1.0
            // note mvu_cfg_shadow has a few signals that are not used - they are written instantly to live config on a 'start' kick so shadows are not needed. Synthesis tools should be able to recognise this and strip them out
        end : reset
        else if (csr_write && rHADDR.mvu_id == genvar_mvu_id) begin : write_logic
            unique case (mvu_pkg::mvu_csr_t'({rHADDR.addr[11:0],2'b00}))
                mvu_pkg::CSR_MVUWBASEPTR : mvu_cfg_shadow[genvar_mvu_id].wbaseaddr  <= AHB_IF.HWDATA[BBWADDR-1 : 0] >> (9); // right-shifted because the LSBs are "word-select" bits used by the AHB interface but not used internally (bit widths are wider internally, so address widths are smaller)
                mvu_pkg::CSR_MVUIBASEPTR : mvu_cfg_shadow[genvar_mvu_id].ibaseaddr  <= AHB_IF.HWDATA[BBDADDR-1 : 0] >> (3);
                mvu_pkg::CSR_MVUSBASEPTR : mvu_cfg_shadow[genvar_mvu_id].sbaseaddr  <= AHB_IF.HWDATA[BSBANKA-1 : 0] >> (7);
                mvu_pkg::CSR_MVUBBASEPTR : mvu_cfg_shadow[genvar_mvu_id].bbaseaddr  <= AHB_IF.HWDATA[BBBANKA-1 : 0] >> (8);
                mvu_pkg::CSR_MVUOBASEPTR : mvu_cfg_shadow[genvar_mvu_id].obaseaddr  <= AHB_IF.HWDATA[BBDADDR-1 : 0] >> (3);
                mvu_pkg::CSR_MVUWJUMP_0  : mvu_cfg_shadow[genvar_mvu_id].wjump[0]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUWJUMP_1  : mvu_cfg_shadow[genvar_mvu_id].wjump[1]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUWJUMP_2  : mvu_cfg_shadow[genvar_mvu_id].wjump[2]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUWJUMP_3  : mvu_cfg_shadow[genvar_mvu_id].wjump[3]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUWJUMP_4  : mvu_cfg_shadow[genvar_mvu_id].wjump[4]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUIJUMP_0  : mvu_cfg_shadow[genvar_mvu_id].ijump[0]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUIJUMP_1  : mvu_cfg_shadow[genvar_mvu_id].ijump[1]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUIJUMP_2  : mvu_cfg_shadow[genvar_mvu_id].ijump[2]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUIJUMP_3  : mvu_cfg_shadow[genvar_mvu_id].ijump[3]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUIJUMP_4  : mvu_cfg_shadow[genvar_mvu_id].ijump[4]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUSJUMP_0  : mvu_cfg_shadow[genvar_mvu_id].sjump[0]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUSJUMP_1  : mvu_cfg_shadow[genvar_mvu_id].sjump[1]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUSJUMP_2  : mvu_cfg_shadow[genvar_mvu_id].sjump[2]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUSJUMP_3  : mvu_cfg_shadow[genvar_mvu_id].sjump[3]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUSJUMP_4  : mvu_cfg_shadow[genvar_mvu_id].sjump[4]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUBJUMP_0  : mvu_cfg_shadow[genvar_mvu_id].bjump[0]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUBJUMP_1  : mvu_cfg_shadow[genvar_mvu_id].bjump[1]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUBJUMP_2  : mvu_cfg_shadow[genvar_mvu_id].bjump[2]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUBJUMP_3  : mvu_cfg_shadow[genvar_mvu_id].bjump[3]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUBJUMP_4  : mvu_cfg_shadow[genvar_mvu_id].bjump[4]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUOJUMP_0  : mvu_cfg_shadow[genvar_mvu_id].ojump[0]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUOJUMP_1  : mvu_cfg_shadow[genvar_mvu_id].ojump[1]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUOJUMP_2  : mvu_cfg_shadow[genvar_mvu_id].ojump[2]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUOJUMP_3  : mvu_cfg_shadow[genvar_mvu_id].ojump[3]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUOJUMP_4  : mvu_cfg_shadow[genvar_mvu_id].ojump[4]   <= AHB_IF.HWDATA[BJUMP-1 : 0];
                mvu_pkg::CSR_MVUWLENGTH_1: mvu_cfg_shadow[genvar_mvu_id].wlength[1] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUWLENGTH_2: mvu_cfg_shadow[genvar_mvu_id].wlength[2] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUWLENGTH_3: mvu_cfg_shadow[genvar_mvu_id].wlength[3] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUWLENGTH_4: mvu_cfg_shadow[genvar_mvu_id].wlength[4] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUILENGTH_1: mvu_cfg_shadow[genvar_mvu_id].ilength[1] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUILENGTH_2: mvu_cfg_shadow[genvar_mvu_id].ilength[2] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUILENGTH_3: mvu_cfg_shadow[genvar_mvu_id].ilength[3] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUILENGTH_4: mvu_cfg_shadow[genvar_mvu_id].ilength[4] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUSLENGTH_1: mvu_cfg_shadow[genvar_mvu_id].slength[1] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUSLENGTH_2: mvu_cfg_shadow[genvar_mvu_id].slength[2] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUSLENGTH_3: mvu_cfg_shadow[genvar_mvu_id].slength[3] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUSLENGTH_4: mvu_cfg_shadow[genvar_mvu_id].slength[4] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUBLENGTH_1: mvu_cfg_shadow[genvar_mvu_id].blength[1] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUBLENGTH_2: mvu_cfg_shadow[genvar_mvu_id].blength[2] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUBLENGTH_3: mvu_cfg_shadow[genvar_mvu_id].blength[3] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUBLENGTH_4: mvu_cfg_shadow[genvar_mvu_id].blength[4] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUOLENGTH_1: mvu_cfg_shadow[genvar_mvu_id].olength[1] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUOLENGTH_2: mvu_cfg_shadow[genvar_mvu_id].olength[2] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUOLENGTH_3: mvu_cfg_shadow[genvar_mvu_id].olength[3] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUOLENGTH_4: mvu_cfg_shadow[genvar_mvu_id].olength[4] <= AHB_IF.HWDATA[BLENGTH-1 : 0];
                mvu_pkg::CSR_MVUPRECISION: begin
                    mvu_cfg_shadow[genvar_mvu_id].wprecision <= AHB_IF.HWDATA[BPREC-1 : 0];
                    mvu_cfg_shadow[genvar_mvu_id].iprecision <= AHB_IF.HWDATA[2*BPREC-1 : BPREC];
                    mvu_cfg_shadow[genvar_mvu_id].oprecision <= AHB_IF.HWDATA[3*BPREC-1 : 2*BPREC];
                    mvu_cfg_shadow[genvar_mvu_id].w_signed   <= AHB_IF.HWDATA[24];
                    mvu_cfg_shadow[genvar_mvu_id].d_signed   <= AHB_IF.HWDATA[25];
                end
                mvu_pkg::CSR_MVUSTATUS   : begin
                    // clear the MVU flag if there is a write to this reg; logic for that is elsewhere
                end
                mvu_pkg::CSR_MVUCOMMAND  : begin
                    // CSR_MVUCOMMAND is the only register without shadow regs
                    // because it implicitly kicks off the MVU on write
                    // handled separately below
                end
                mvu_pkg::CSR_MVUQUANT    : begin
                    mvu_cfg_shadow[genvar_mvu_id].quant_msbidx <= AHB_IF.HWDATA[BQMSBIDX-1 : 0];
                end
                mvu_pkg::CSR_MVUSCALER   : begin
                    mvu_cfg_shadow[genvar_mvu_id].scaler_b <= AHB_IF.HWDATA[BSCALERB-1 : 0];
                end
                mvu_pkg::CSR_MVUCONFIG1  : begin
                    mvu_cfg_shadow[genvar_mvu_id].shacc_load_sel  <= AHB_IF.HWDATA[NJUMPS-1 : 0];
                    mvu_cfg_shadow[genvar_mvu_id].zigzag_step_sel <= AHB_IF.HWDATA[2*NJUMPS-1 : NJUMPS];
                end
                mvu_pkg::CSR_MVUOMVUSEL         : mvu_cfg_shadow[genvar_mvu_id].omvusel        <= AHB_IF.HWDATA[NMVU-1:0];
                mvu_pkg::CSR_MVUUSESCALER_MEM   : mvu_cfg_shadow[genvar_mvu_id].usescaler_mem  <= AHB_IF.HWDATA[0];
                mvu_pkg::CSR_MVUUSEBIAS_MEM     : mvu_cfg_shadow[genvar_mvu_id].usebias_mem    <= AHB_IF.HWDATA[0];
            endcase
        end : write_logic
    end : always_ff_block
end endgenerate

// Handling for live registers
// Special handling for 'start' field: self-clearing
genvar i;
generate for(i=0; i < NMVU; i = i+1) begin
    always_ff @(posedge HCLK) begin
        if (~HRESETn) begin
            mvu_cfg_live[i] <= '{default: '0}; // reset to all zeros
        end else begin
            // If a write to the MVUCOMMAND register occurs for this MVU, copy the shadow register to the live config signals and set the start bit
            // (the start signal will be delayed one cycle to allow the other config signals to propagate first)
            if (csr_write && (mvu_pkg::mvu_csr_t'({rHADDR.addr[11:0],2'b00}) == mvu_pkg::CSR_MVUCOMMAND) && (i==rHADDR.mvu_id)) begin
                mvu_cfg_live[i] <= mvu_cfg_shadow[i]; // update live config on start
                mvu_cfg_live[i].start <= 1'b1; // send start signal

                mvu_cfg_live[i].countdown <= AHB_IF.HWDATA[BCNTDWN-1 : 0];
                mvu_cfg_live[i].mul_mode  <= AHB_IF.HWDATA[31:30];
            end else begin
                mvu_cfg_live[i].start <= 1'b0;
            end
        end
    end
end endgenerate

// CSR read MUX
logic [31:0] csr_read_data;
always_comb begin // only the status register is readable
    unique case (mvu_pkg::mvu_csr_t'({rHADDR.addr[11:0],2'b00})) // align to word addresses
        mvu_pkg::CSR_MVUSTATUS             : csr_read_data = {31'b0, irq_flag[rHADDR.mvu_id]}; // show the interrupt flag for the selected MVU. DOES NOT CLEAR ON READ, write one to clear
        default : csr_read_data = '0; // invalid register address
    endcase
end

// Make the interrupt pulse stick
always_ff @ (posedge HCLK) begin
    if (!HRESETn) begin
        irq_flag <= '0;
    end else begin
        if (csr_write && ((mvu_pkg::mvu_csr_t'({rHADDR.addr[11:0],2'b00})) == mvu_pkg::CSR_MVUSTATUS)) begin
            irq_flag <= irq_flag & ~(AHB_IF.HWDATA[0] << rHADDR.mvu_id);
            // clear the flag for this MVU if there is a write to the status register with bit 0 set
        end else begin
            irq_flag <= irq_flag | irq_pulse;
            // set flag when we see a pulse, and keep it there until cleared by a write to CSR_MVUSTATUS
        end
    end
end

// Connect weights for writing
assign mvu_ext_if.wrw_word = '{default: AHB_IF.HWDATA};         // write the same data to all MVUs
assign mvu_ext_if.wrw_addr = '{default: rHADDR.addr};           // and write the same address on all MVUs
assign mvu_ext_if.wrw_en   = (weight_write << rHADDR.mvu_id);   // but only ENABLE the chosen MVU

// Connect bias for writing
assign mvu_ext_if.wrb_word = AHB_IF.HWDATA;                     // write the same data to all MVUs
assign mvu_ext_if.wrb_addr = rHADDR.addr;                       // and write the same address on all MVUs
assign mvu_ext_if.wrb_en   = (bias_write << rHADDR.mvu_id);     // but only ENABLE the chosen MVU

// Connect scaler for writing
assign mvu_ext_if.wrs_word = AHB_IF.HWDATA;                     // write the same data to all MVUs
assign mvu_ext_if.wrs_addr = rHADDR.addr;                       // and write the same address on all MVUs
assign mvu_ext_if.wrs_en   = (scaler_write << rHADDR.mvu_id);   // but only ENABLE the chosen MVU

// Connect data for writing
assign mvu_ext_if.wrc_word = {32'b0, AHB_IF.HWDATA};            // write the same data to all MVUs
assign mvu_ext_if.wrc_addr = rHADDR.addr[15:1];                 // and write the same address on all MVUs
assign mvu_ext_if.wrc_en   = (data_write << rHADDR.mvu_id);     // but only ENABLE the chosen MVU

// Connect data for reading
// Data is stored in 64-bit words, not 32
// so take the last bit of the address to select half of what is returned
// when writing, pad with zeros
logic read_data_ready,write_data_ready;
assign mvu_ext_if.rdc_en = (data_read << rHADDR.mvu_id);     // ENABLE the chosen MVU for reading
assign mvu_ext_if.rdc_addr = '{default: rHADDR.addr[15:1]};  // read the same address on all MVUs
assign write_data_ready = mvu_ext_if.wrc_grnt[rHADDR.mvu_id]; // data is written when the chosen MVU grants the write

// There is a two-cycle latency for data reads, so flop it here
logic read_data_ready_delay;
always_ff @ (posedge HCLK) begin
    if (!HRESETn) begin
        read_data_ready       <= 1'b0;
        read_data_ready_delay <= 1'b0;
    end else begin
        read_data_ready       <= read_data_ready_delay; // delay the ready signal by one cycle to align with data
        read_data_ready_delay <= mvu_ext_if.rdc_grnt[rHADDR.mvu_id];
    end
end

// Select the correct word based on the last bit of the address
assign rdata_mvu = rHADDR.addr[0] ?
                    mvu_ext_if.rdc_word[rHADDR.mvu_id][63:32] :
                    mvu_ext_if.rdc_word[rHADDR.mvu_id][31:0];

// Ready and response
assign AHB_IF.HREADYOUT =   data_read ? read_data_ready :
                            data_write? write_data_ready :
                            1'b1; // other transactions are never delayed
assign AHB_IF.HRESP = (0 ||
    (rHSIZE != 3'b010) ||           // only support word (32-bit) accesses
    (rHADDR.byte_sel != 2'b00) ||   // only support word-aligned accesses
    weight_read ||                  // MVU does not allow reading this
    scaler_read ||                  // MVU does not allow reading this
    bias_read ||                    // MVU does not allow reading this
    (data_write && rHADDR.addr[0] != 0) // due to internal limitations of the MVU we can only write to addresses ending 000 (and read from address ending x00)
);
assign AHB_IF.HRDATA = rConflict ? rWData :
                        csr_read ? csr_read_data :
                        data_read ? rdata_mvu :
                        32'b0;

endmodule
