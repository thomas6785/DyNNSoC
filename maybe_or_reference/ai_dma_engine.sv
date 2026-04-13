`timescale 1ns/1ps

// Simple single-channel DMA engine with AHB pipelining.
//
// Configuration is accessed via an AHB slave port (s_bus).
// Memory transfers are performed via an AHB master port (m_bus).
// The AHB address and data phases are overlapped so that a source
// data phase runs concurrently with the next destination address
// phase (and vice-versa), giving one word transferred every two
// bus cycles in the steady state.
//
// FSM states:
//   S_IDLE      – no transfer in progress
//   S_INIT_RD   – first source address phase (no data phase yet)
//   S_RD_WR     – source data phase  +  destination address phase
//   S_WR_RD     – destination data phase  +  source address phase
//   S_FINAL_WR  – final destination data phase (no new address phase)
//
// Register map (word offsets from slave base):
//   0x00  SRC_ADDR   (RW)  Source address
//   0x04  DST_ADDR   (RW)  Destination address
//   0x08  XFER_LEN   (RW)  Number of 32-bit words to transfer
//   0x0C  CONTROL    (RW)  [0] start (write-1-to-start, reads as 0)
//                           [1] src_fixed  (1 = fixed, 0 = incrementing)
//                           [2] dst_fixed  (1 = fixed, 0 = incrementing)
//   0x10  STATUS     (RO)  [1:0] 00=idle  01=busy  10=done  11=error
//
// Address filtering:  before each destination address phase the
// engine checks  (dst_addr & ADDR_SPACE_MASK) == ADDR_SPACE_VALUE.
// A match means the DMA would write into its own register space;
// the destination address phase is suppressed and the transfer
// terminates with the sticky error flag set.
//
// IRQ is active-high level while done_flag or error_flag is set.
// Writing a new start clears both flags and deasserts IRQ.
//
// Both bus ports are assumed to share the same clock domain.

module dma_engine #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter [ADDR_WIDTH-1:0] ADDR_SPACE_MASK  = '0,
    parameter [ADDR_WIDTH-1:0] ADDR_SPACE_VALUE = '1   // defaults disable the filter
)(
    ahb_intf.master m_bus,
    ahb_intf.slave  s_bus,
    output logic    irq
);

    // ----------------------------------------------------------------
    // AHB encodings
    // ----------------------------------------------------------------
    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_BUSY   = 2'b01;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;
    localparam [2:0] HSIZE_WORD    = 3'b010;

    // ----------------------------------------------------------------
    // Configuration register map
    // ----------------------------------------------------------------
    localparam int NUM_REGS   = 5;
    localparam int REG_SRC    = 0;  // 0x00
    localparam int REG_DST    = 1;  // 0x04
    localparam int REG_LEN    = 2;  // 0x08
    localparam int REG_CTRL   = 3;  // 0x0C
    localparam int REG_STATUS = 4;  // 0x10

    localparam int CTRL_START     = 0;
    localparam int CTRL_SRC_FIXED = 1;
    localparam int CTRL_DST_FIXED = 2;

    localparam [1:0] ST_IDLE  = 2'b00;
    localparam [1:0] ST_BUSY  = 2'b01;
    localparam [1:0] ST_DONE  = 2'b10;
    localparam [1:0] ST_ERROR = 2'b11;

    // ----------------------------------------------------------------
    // Config registers (written through s_bus)
    // ----------------------------------------------------------------
    logic [DATA_WIDTH-1:0] cfg_src;
    logic [DATA_WIDTH-1:0] cfg_dst;
    logic [DATA_WIDTH-1:0] cfg_len;
    logic [DATA_WIDTH-1:0] cfg_ctrl;
    logic                  start_pulse;

    // ----------------------------------------------------------------
    // Slave-port address-phase latch
    // ----------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] sa_q;
    logic                  sw_q;
    logic                  sv_q;

    always_ff @(posedge s_bus.hclk or negedge s_bus.hresetn) begin
        if (!s_bus.hresetn) begin
            sa_q <= '0;
            sw_q <= 1'b0;
            sv_q <= 1'b0;
        end else if (s_bus.hready) begin
            sa_q <= s_bus.haddr;
            sw_q <= s_bus.hwrite;
            sv_q <= s_bus.hsel
                    && (s_bus.htrans != HTRANS_IDLE)
                    && (s_bus.htrans != HTRANS_BUSY);
        end
    end

    // Address decode
    localparam int IDX_W = $clog2(NUM_REGS);
    wire [IDX_W-1:0] s_idx = sa_q[2 +: IDX_W];
    wire              s_hit = (sa_q[ADDR_WIDTH-1:2+IDX_W] == '0)
                              && (s_idx < IDX_W'(NUM_REGS));

    // ---- Write path ----
    always_ff @(posedge s_bus.hclk or negedge s_bus.hresetn) begin
        if (!s_bus.hresetn) begin
            cfg_src     <= '0;
            cfg_dst     <= '0;
            cfg_len     <= '0;
            cfg_ctrl    <= '0;
            start_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;                           // default: one-cycle pulse
            if (sv_q && sw_q && s_hit) begin
                case (s_idx)
                    REG_SRC:  cfg_src  <= s_bus.hwdata;
                    REG_DST:  cfg_dst  <= s_bus.hwdata;
                    REG_LEN:  cfg_len  <= s_bus.hwdata;
                    REG_CTRL: begin
                        cfg_ctrl <= s_bus.hwdata;
                        if (s_bus.hwdata[CTRL_START])
                            start_pulse <= 1'b1;
                    end
                    default: ;                             // STATUS is read-only
                endcase
            end
        end
    end

    // ---- Read path ----
    logic [1:0] status;

    always_comb begin
        s_bus.hrdata = '0;
        if (sv_q && !sw_q && s_hit) begin
            case (s_idx)
                REG_SRC:    s_bus.hrdata = cfg_src;
                REG_DST:    s_bus.hrdata = cfg_dst;
                REG_LEN:    s_bus.hrdata = cfg_len;
                REG_CTRL:   s_bus.hrdata = cfg_ctrl & ~(DATA_WIDTH'(1) << CTRL_START);
                REG_STATUS: s_bus.hrdata = {{(DATA_WIDTH-2){1'b0}}, status};
                default:    s_bus.hrdata = '0;
            endcase
        end
    end

    assign s_bus.hreadyout = 1'b1;
    assign s_bus.hresp     = 1'b0;

    // ----------------------------------------------------------------
    // DMA state machine (5 states, pipelined)
    // ----------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_INIT_RD,
        S_RD_WR,
        S_WR_RD,
        S_FINAL_WR
    } dma_state_t;

    dma_state_t state;

    // Working registers
    logic [ADDR_WIDTH-1:0] src_r, dst_r;
    logic [DATA_WIDTH-1:0] remaining;
    logic [DATA_WIDTH-1:0] buffer;
    logic                  src_fixed, dst_fixed;
    logic                  done_flag, error_flag;

    // Address filter: would the next write land in our own register space?
    wire addr_self = (dst_r & ADDR_SPACE_MASK) == ADDR_SPACE_VALUE;

    always_ff @(posedge m_bus.hclk or negedge m_bus.hresetn) begin
        if (!m_bus.hresetn) begin
            state      <= S_IDLE;
            src_r      <= '0;
            dst_r      <= '0;
            remaining  <= '0;
            buffer     <= '0;
            src_fixed  <= 1'b0;
            dst_fixed  <= 1'b0;
            done_flag  <= 1'b0;
            error_flag <= 1'b0;
        end else begin
            case (state)
                // --------------------------------------------------
                // No transfer in progress.  Wait for software to
                // write the start bit.
                // --------------------------------------------------
                S_IDLE: begin
                    if (start_pulse) begin
                        src_r      <= cfg_src;
                        dst_r      <= cfg_dst;
                        remaining  <= cfg_len;
                        src_fixed  <= cfg_ctrl[CTRL_SRC_FIXED];
                        dst_fixed  <= cfg_ctrl[CTRL_DST_FIXED];
                        done_flag  <= 1'b0;
                        error_flag <= 1'b0;
                        if (cfg_len == '0) begin
                            done_flag <= 1'b1;             // zero-length → done immediately
                        end else begin
                            state <= S_INIT_RD;
                        end
                    end
                end

                // --------------------------------------------------
                // First source-read address phase (no overlapping
                // data phase yet).
                // --------------------------------------------------
                S_INIT_RD: begin
                    if (m_bus.hreadyout) begin
                        if (!src_fixed)
                            src_r <= src_r + ADDR_WIDTH'(4);
                        state <= S_RD_WR;
                    end
                end

                // --------------------------------------------------
                // Source data phase  +  destination address phase.
                // Latch read data into buffer.  If the address filter
                // fires, suppress the write address and abort.
                // --------------------------------------------------
                S_RD_WR: begin
                    if (m_bus.hreadyout) begin
                        buffer <= m_bus.hrdata;
                        if (m_bus.hresp || addr_self) begin
                            error_flag <= 1'b1;
                            state      <= S_IDLE;
                        end else begin
                            if (!dst_fixed)
                                dst_r <= dst_r + ADDR_WIDTH'(4);
                            state <= (remaining == 1) ? S_FINAL_WR : S_WR_RD;
                        end
                    end
                end

                // --------------------------------------------------
                // Destination data phase  +  next source address
                // phase.  Write buffer to the bus; start the next
                // read in the same cycle.
                // --------------------------------------------------
                S_WR_RD: begin
                    if (m_bus.hreadyout) begin
                        if (m_bus.hresp) begin
                            error_flag <= 1'b1;
                            state      <= S_IDLE;
                        end else begin
                            remaining <= remaining - 1;
                            if (!src_fixed)
                                src_r <= src_r + ADDR_WIDTH'(4);
                            state <= S_RD_WR;
                        end
                    end
                end

                // --------------------------------------------------
                // Final destination data phase (bus idles on the
                // address lines).  Return to IDLE afterwards.
                // --------------------------------------------------
                S_FINAL_WR: begin
                    if (m_bus.hreadyout) begin
                        remaining <= remaining - 1;
                        if (m_bus.hresp)
                            error_flag <= 1'b1;
                        else
                            done_flag <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                // --------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Master-bus combinational outputs
    // ----------------------------------------------------------------
    always_comb begin
        // Idle defaults
        m_bus.haddr  = '0;
        m_bus.hsize  = HSIZE_WORD;
        m_bus.htrans = HTRANS_IDLE;
        m_bus.hwdata = '0;
        m_bus.hwrite = 1'b0;
        m_bus.hsel   = 1'b0;

        case (state)
            // First read: address phase only
            S_INIT_RD: begin
                m_bus.haddr  = src_r;
                m_bus.htrans = HTRANS_NONSEQ;
                m_bus.hsel   = 1'b1;
            end

            // Read data phase (slave drives hrdata) +
            // Write address phase (if address filter passes)
            S_RD_WR: begin
                if (!addr_self) begin
                    m_bus.haddr  = dst_r;
                    m_bus.htrans = HTRANS_NONSEQ;
                    m_bus.hwrite = 1'b1;
                    m_bus.hsel   = 1'b1;
                end
            end

            // Write data phase  +  next read address phase
            S_WR_RD: begin
                m_bus.hwdata = buffer;
                m_bus.haddr  = src_r;
                m_bus.htrans = HTRANS_NONSEQ;
                m_bus.hsel   = 1'b1;
            end

            // Final write data phase (no new address)
            S_FINAL_WR: begin
                m_bus.hwdata = buffer;
            end

            default: ;
        endcase
    end

    // ----------------------------------------------------------------
    // Status & IRQ
    // ----------------------------------------------------------------
    always_comb begin
        if (state != S_IDLE)
            status = ST_BUSY;
        else if (error_flag)
            status = ST_ERROR;
        else if (done_flag)
            status = ST_DONE;
        else
            status = ST_IDLE;
    end

    assign irq = done_flag || error_flag;

endmodule
