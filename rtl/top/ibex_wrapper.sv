module ibex_wrapper (
  input  wire         HCLK,							// System clock
  input  wire         HRESETn,						// System Reset, active low

  // AHB-LITE MASTER PORT for Instructions
  ahb_intf_m.master AHB_IF,

  // MISCELLANEOUS
  input  wire         NMI,				// Non-maskable interrupt input
  input  wire         EXT_IRQ,				// Interrupt request line
  input wire [14:0]   IRQ,
  input  wire [23:0]	SYSTICKCLKDIV,
  output wire         core_sleep_o,

  // Memory interface for instruction fetches
  instruction_fetch_if.core instr_if
);
  wire alert_minor_o;
  wire alert_major_o;

  reg [2:0] data_hsize;
  reg [1:0] data_addr_off;

  wire instr_rvalid_i;

  wire [3:0] data_be_o;
  wire [31:0] data_addr_o;
  wire data_rvalid_i;
  wire data_req_o;
  wire data_gnt_i;
  wire data_we_o;

  /* AHB Prot */
  assign AHB_IF.HPROT = 4'b0011; // Non-cacheable, non-bufferable, privileged, data access
  // This is the recommended "default" for managers without a specific protection implementation
  // See AHB standard page 45

  /* SYSTICK */
  wire div;
	reg  [23:0]  clkdiv;
	reg 		systickclk;
  assign div = (clkdiv == SYSTICKCLKDIV);
  // TODO KNOWN ISSUE: the systick IRQ is only one cycle long, which Ibex will consistently 'miss'. Need a sticky flag, and a mechanism for clearing it. Ibex doesn't have a hardware mechanism for clearing it, so we would need to rely on the software to clear it. As it happens I have no use case for systick so I'm leaving this bug for now

  always @(posedge HCLK or negedge HRESETn)
    if(!HRESETn) clkdiv <= 24'd0;
		else if(div)
				clkdiv <= 24'h0;
			else
				clkdiv <= clkdiv + 24'h1;

  always @(posedge HCLK or negedge HRESETn)
    if(!HRESETn) systickclk <= 1'b1;
		else if(div)
				systickclk <= 1'b1;
			else
				systickclk <= 1'b0;

  // Instantiate the core
  // Connect instruction interface to ROM
  // Connect data interface to AHB bus
  ibex_core core (
    // Clock and Reset
    .clk_i(HCLK),
    .rst_ni(HRESETn),

    .test_en_i(1'b0),     // enable all clock gates for testing

    .hart_id_i(32'b0),  //???
    .boot_addr_i(32'b0), //???

    // Instruction memory interface (connects to ROM)
    .instr_req_o(instr_if.req),
    .instr_gnt_i(instr_if.ready),
    .instr_rvalid_i(instr_if.ready),
    .instr_addr_o(instr_if.addr),
    .instr_rdata_i(instr_if.rdata),
    .instr_err_i(1'b0),

    // Data memory interface
    .data_req_o(data_req_o),
    .data_gnt_i(data_gnt_i),
    .data_rvalid_i(data_rvalid_i),
    .data_we_o(data_we_o),
    .data_be_o(data_be_o),
    .data_addr_o(data_addr_o),
    .data_wdata_o(AHB_IF.HWDATA),
    .data_rdata_i(AHB_IF.HRDATA),
    .data_err_i(1'b0),

    // Interrupt inputs
    .irq_software_i(1'b0),
    .irq_timer_i(systickclk),
    .irq_external_i(EXT_IRQ),
    .irq_fast_i(IRQ),
    .irq_nm_i(NMI),       // non-maskeable interrupt

    // Debug Interface
    .debug_req_i(1'b0),

    // CPU Control Signals
    .fetch_enable_i(1'b1),
    .alert_minor_o(alert_minor_o),
    .alert_major_o(alert_major_o),
    .core_sleep_o(core_sleep_o)
  );

  // The AHB-memory interface is designed to share the AHB bus for instructions and data
  // It has been modified to only handle data, with instructions using a dedicated ROM memory bus
  // For this reason these signals are tied off
  // The synthesis tool should strip away the unused logic
  // but at some point it would be best to clean up this FSM (it wasn't well-designed to begin with anyway)
  // TODO instr_rvalid_i should be removed and the state machine removed

  reg [4:0] state, nstate;
  localparam [4:0] S0 = 1;
  localparam [4:0] S1 = 2;
  localparam [4:0] S2 = 4;
  localparam [4:0] S3 = 8;
  localparam [4:0] S4 = 16; // dev, why did you bother enumerating the states if you weren't going to name them!!!

  always @(posedge HCLK or negedge HRESETn)
    if(!HRESETn) state <= S0;
    else state <= nstate;

  always @* begin
    nstate = S0;
    case (state)
      S0  : if(data_req_o) nstate = S3; else if(1'b0) nstate = S1; else nstate = S0;
      S1  : nstate = S2;
      S2  : if(instr_rvalid_i) nstate = S0; else nstate = S2;
      S3  : nstate = S4;
      S4  : if(data_rvalid_i) nstate = S0; else nstate = S4;
    endcase
  end

  assign instr_rvalid_i = (state == S2) ? AHB_IF.HREADY : 0;

  assign data_gnt_i = (state == S3);
  assign data_rvalid_i = (state == S4) ? AHB_IF.HREADY : 0;

  assign AHB_IF.HADDR =  (state == S1) ? 31'b0  :
                  (state == S3) ? {data_addr_o | data_addr_off}  :   32'b0;

  assign AHB_IF.HTRANS = (state == S1) ? 2'b10 :
                  (state == S3) ? 2'b10 : 2'b00;

  assign AHB_IF.HSIZE =  (state == S1) ? 3'b010 :
                  (state == S3) ? data_hsize : 3'b0;

  assign AHB_IF.HWRITE = (state == S3) ? data_we_o : 0 ;

  always_comb begin
    data_hsize = 3'b0;
    case(data_be_o)
      4'b0001 : data_hsize = 3'b000;
      4'b0010 : data_hsize = 3'b000;
      4'b0100 : data_hsize = 3'b000;
      4'b1000 : data_hsize = 3'b000;
      4'b0011 : data_hsize = 3'b001;
      4'b1100 : data_hsize = 3'b001;
      4'b1111 : data_hsize = 3'b010;
      default : data_hsize = 3'b000; // should never happen
    endcase
  end

  always_comb begin
    data_addr_off = 2'b0;
    case(data_be_o)
      4'b0001 : data_addr_off = 2'b00;
      4'b0010 : data_addr_off = 2'b01;
      4'b0100 : data_addr_off = 2'b10;
      4'b1000 : data_addr_off = 2'b11;
      4'b0011 : data_addr_off = 2'b00;
      4'b1100 : data_addr_off = 2'b10;
      4'b1111 : data_addr_off = 2'b00;
      default : data_addr_off = 2'b00; // should never happen
    endcase
  end


endmodule

