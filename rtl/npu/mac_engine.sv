`timescale 1ns / 1ps

// MAC engine (spec 7; plan Task 11). Ports exactly as spec 7.1.
//
// Build stage 2 (2026-11-05): command FIFO, the FSM with IDLE and CHECK, the D16 command checks, the
// sticky error bits and the CSR block (spec 6.4, D17, D21, D23; the plan's stage 5, moved here because
// the error bits are only visible through npu_status). Not yet built: LOAD (stage 3: port B, WBUF/IBUF),
// MAC (stage 4: PE array, accumulators, READ_RESULT data), the clock gate and GATING_EN (stage 7).
// Until then a command that passes CHECK goes back to IDLE without effect, b_req stays 0 and rd_data is 0.
//
// Cycle behaviour (free clock domain, spec 7.3):
//   IDLE   leaves for CHECK in the cycle after the FIFO becomes non-empty.
//   CHECK  pops the head and decides, in the D16 order (spec 6.3 error table, npu_ref_cmd):
//            1. op ILLEGAL                       -> err_illegal, whatever K, address and clr hold
//            2. K = 0                            -> no-op, no error (clr ignored)
//            3. K > KMAX or K mod 4 != 0         -> err_k
//            4. LOAD with addr[3:0] != 0         -> err_align
//            5. LOAD with addr < DTCM_BASE or addr + 4K > DTCM_BASE + DTCM_BYTES, computed in 35 bits
//               so it cannot wrap                -> err_addr
//            6. otherwise the command executes (LOAD / MAC, stages 3 and 4)
//          A dropped command takes one CHECK cycle; the error bit is set at the edge that ends it.
//
// CSRs (spec 6.4):
//   npu_status   0x7C0  [0] busy = (fsm != IDLE), [1] fifo_empty, [2] fifo_full (RO);
//                       [11:8] err_k, err_addr, err_illegal, err_align (sticky, W1C on csr_wdata, D17).
//                       A bit set by CHECK in the same cycle as a W1C of that bit stays 1 (D23).
//   npu_busy_cyc 0x7C1  counts cycles with fsm != IDLE, wraps mod 2^32; a write sets it and wins over
//                       the increment of that cycle (D17).
//   csr_rdata is a function of csr_addr and registered state only (D21); other addresses read 0 and
//   their writes are ignored.
//
// Reset (D18): rst_n active low, asynchronous assert; the release is synchronised in npu_top.
module mac_engine
  import npu_pkg::*;
(
    // command push (core MEM stage -> engine)
    input  logic                    cmd_valid,
    output logic                    cmd_ready,
    input  logic [1:0]              cmd_op,
    input  logic [31:0]             cmd_addr,
    input  logic [31:0]             cmd_k,
    input  logic                    cmd_clr,

    // result read (core MEM stage)
    input  logic                    rd_req,
    input  logic [RD_IDX_W-1:0]     rd_idx,
    output logic                    rd_ready,
    output logic [31:0]             rd_data,

    // CSR port
    input  logic                    csr_we,
    input  logic [11:0]             csr_addr,
    input  logic [31:0]             csr_wdata,
    output logic [31:0]             csr_rdata,

    // DTCM port B (read-only, 1-cycle latency)
    output logic                    b_req,
    output logic [QUAD_ADDR_W-1:0]  b_addr,
    input  logic [PORT_B_W-1:0]     b_rdata,

    // clocks
    input  logic                    clk,
    input  logic                    rst_n
);
    // ---- command FIFO --------------------------------------------------------------------------
    typedef struct packed {
        logic [1:0]  op;          // npu_op_e value
        logic [31:0] addr;
        logic [31:0] k;
        logic        clr;
    } cmd_t;

    cmd_t head;
    logic fifo_pop, fifo_full, fifo_empty;

    cmd_fifo #(
        .WIDTH ($bits(cmd_t)),
        .DEPTH (FIFO_DEPTH)
    ) u_fifo (
        .clk       (clk),
        .rst_n     (rst_n),
        .push      (cmd_valid),                       // cmd_fifo refuses it while full
        .push_data ({cmd_op, cmd_addr, cmd_k, cmd_clr}),
        .pop       (fifo_pop),
        .head      (head),
        .full      (fifo_full),
        .empty     (fifo_empty)
    );

    assign cmd_ready = !fifo_full;                    // spec 7.1

    // ---- FSM -----------------------------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE  = 2'd0,
        CHECK = 2'd1,
        LOAD  = 2'd2,                                 // stage 3
        MAC   = 2'd3                                  // stage 4
    } state_e;

    state_e state_q, state_d;

    // CHECK decode. head is meaningful only in CHECK (the FIFO is never empty there: IDLE enters
    // CHECK only when it is not, and only CHECK pops), so every use below is qualified by that state.
    localparam logic [34:0] DTCM_END = 35'(DTCM_BASE) + 35'(DTCM_BYTES);

    logic        in_check;
    logic        op_illegal, op_load, k_zero, k_bad, addr_misaligned, addr_oob;
    logic [34:0] load_end;                            // addr + 4K, cannot wrap in 35 bits
    logic        set_k, set_addr, set_illegal, set_align;
    logic        cmd_ok;                              // passed every check, K != 0

    assign in_check        = (state_q == CHECK);
    assign op_illegal      = (head.op == OP_ILLEGAL);
    assign op_load         = (head.op == OP_LDW) || (head.op == OP_LDI);
    assign k_zero          = (head.k == 32'd0);
    assign k_bad           = (head.k > KMAX) || (head.k[1:0] != 2'b00);
    assign addr_misaligned = (head.addr[3:0] != 4'h0);
    assign load_end        = {3'b000, head.addr} + {1'b0, head.k, 2'b00};
    assign addr_oob        = (head.addr < DTCM_BASE) || (load_end > DTCM_END);

    always_comb begin
        set_illegal = 1'b0;
        set_k       = 1'b0;
        set_align   = 1'b0;
        set_addr    = 1'b0;
        cmd_ok      = 1'b0;
        if (in_check) begin
            if (op_illegal)                    set_illegal = 1'b1;
            else if (k_zero)                   ;                       // no-op, no error
            else if (k_bad)                    set_k       = 1'b1;
            else if (op_load && addr_misaligned) set_align = 1'b1;
            else if (op_load && addr_oob)      set_addr    = 1'b1;
            else                               cmd_ok      = 1'b1;
        end
    end

    assign fifo_pop = in_check;

    always_comb begin
        state_d = state_q;
        unique case (state_q)
            IDLE:    if (!fifo_empty) state_d = CHECK;
            CHECK:   state_d = IDLE;                  // stages 3/4: cmd_ok goes to LOAD or MAC
            LOAD:    state_d = IDLE;                  // not reachable before stage 3
            MAC:     state_d = IDLE;                  // not reachable before stage 4
            default: state_d = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= IDLE;
        else        state_q <= state_d;
    end

    // ---- CSRs ----------------------------------------------------------------------------------
    localparam int unsigned ERR_LSB = ST_ERR_K;       // the error bits are npu_status[ST_ERR_ALIGN:ST_ERR_K]
    localparam int unsigned ERR_W   = ST_ERR_ALIGN - ST_ERR_K + 1;

    logic [ERR_W-1:0] err_q, err_set, err_clr;
    logic [31:0]      busy_cyc_q;
    logic             busy, status_we, busy_cyc_we;
    logic [31:0]      status;

    assign busy        = (state_q != IDLE);
    assign status_we   = csr_we && (csr_addr == CSR_NPU_STATUS);
    assign busy_cyc_we = csr_we && (csr_addr == CSR_NPU_BUSY_CYC);

    always_comb begin
        err_set = '0;
        err_set[ST_ERR_K       - ERR_LSB] = set_k;
        err_set[ST_ERR_ADDR    - ERR_LSB] = set_addr;
        err_set[ST_ERR_ILLEGAL - ERR_LSB] = set_illegal;
        err_set[ST_ERR_ALIGN   - ERR_LSB] = set_align;
    end
    assign err_clr = status_we ? csr_wdata[ST_ERR_ALIGN:ST_ERR_K] : '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_q      <= '0;
            busy_cyc_q <= '0;
        end else begin
            err_q <= err_set | (err_q & ~err_clr);    // D23: a set wins over a same-cycle clear
            if (busy_cyc_we) busy_cyc_q <= csr_wdata; // D17: the write wins over the increment
            else if (busy)   busy_cyc_q <= busy_cyc_q + 32'd1;
        end
    end

    always_comb begin
        status = '0;
        status[ST_BUSY]                 = busy;
        status[ST_FIFO_EMPTY]           = fifo_empty;
        status[ST_FIFO_FULL]            = fifo_full;
        status[ST_ERR_ALIGN:ST_ERR_K]   = err_q;
    end

    always_comb begin
        unique case (csr_addr)
            CSR_NPU_STATUS:   csr_rdata = status;
            CSR_NPU_BUSY_CYC: csr_rdata = busy_cyc_q;
            default:          csr_rdata = 32'd0;
        endcase
    end

    // ---- result read and port B ----------------------------------------------------------------
    assign rd_ready = fifo_empty && (state_q == IDLE);   // spec 7.1, A-MAC-2
    assign rd_data  = 32'd0;                             // stage 4: acc[rd_idx], combinational
    assign b_req    = 1'b0;                              // stage 3
    assign b_addr   = '0;                                // stage 3

    // rd_req is never needed: rd_data depends on rd_idx alone and the core qualifies it with rd_ready
    // (spec 7.1). rd_idx, b_rdata, head.clr and cmd_ok are used from stages 3 and 4.
    logic unused_ok;
    assign unused_ok = ^{rd_req, rd_idx, b_rdata, head.clr, cmd_ok};
endmodule
