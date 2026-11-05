`timescale 1ns / 1ps

// MAC engine (spec 7; plan Task 11). Ports exactly as spec 7.1.
//
// Built in the plan's stages (2026-11-05): 1 cmd_fifo; 2 the FSM, the D16 checks, the error bits and
// the CSR block (the plan's stage 5, moved here because the error bits are only visible through
// npu_status); 3 LOAD (port B, WBUF/IBUF); 4 MAC (pe_array, accumulators, READ_RESULT); 6 reset;
// 7 the clock gate. Cycle timing, latencies and the decisions the spec left open: docs/mac_engine.md.
//
// GATING_EN (spec 8, D19): 0 = D0, clk_mac follows clk; 1 = D1, clk_mac runs only in cycles with
// en = !rst_n || fsm != IDLE || !fifo_empty. Nothing else differs between D0 and D1.
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
//            6. otherwise the command executes: LOAD or MAC, K/4 + 1 cycles each
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
#(
    parameter bit GATING_EN = 1'b0                   // 0: D0 (no gating), 1: D1 (spec 8, D19)
) (
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

    logic start_load, start_mac, load_done, mac_done;

    assign start_load = cmd_ok && op_load;
    assign start_mac  = cmd_ok && !op_load;

    always_comb begin
        state_d = state_q;
        unique case (state_q)
            IDLE:    if (!fifo_empty) state_d = CHECK;
            CHECK:   if (start_load)     state_d = LOAD;
                     else if (start_mac) state_d = MAC;
                     else                state_d = IDLE;
            LOAD:    if (load_done)   state_d = IDLE;
            MAC:     if (mac_done)    state_d = IDLE;
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

    // ---- LOAD and MAC sequencing, free clock domain (spec 6.3, 7.1, 7.3) -----------------------
    // CHECK latches the command (only one that will execute, so dropped commands toggle nothing).
    // Both LOAD and MAC walk steps s = 0..S-1, S = K/4, one per cycle, with one cycle of latency:
    //   LOAD  issues port-B read s (b_addr = base + s) in cycle c; b_rdata is valid in c+1 and is
    //         written into WBUF[s] or IBUF[s] at the end of c+1.
    //   MAC   reads WBUF[s] and IBUF[s] (synchronous RAM read) in cycle c; the PE array adds the 16
    //         dot products at the end of c+1. With clr, step 0 loads instead of adding.
    // Each state lasts S+1 cycles and leaves only after its last write, so every buffer write is in
    // LOAD (A-MAC-4), every accumulator update is in MAC, and the clock-gate enable is 1 in all of
    // them (spec 8). Latency: CHECK + S+1 = K/4 + 2 cycles from the pop to IDLE (spec 7.2: <= K/4 + 3).
    localparam int unsigned STEP_W = BUF_IDX_W + 1;      // 9 bits: S = K/4 is 1..256

    logic [STEP_W-1:0]      steps_q;                     // S of the running command
    logic [STEP_W-1:0]      req_cnt_q;                   // steps issued so far (port-B or buffer reads)
    logic [QUAD_ADDR_W-1:0] qbase_q;                     // LOAD: quad index of the first quad
    logic                   load_ibuf_q;                 // LOAD: 0 writes WBUF (LDW), 1 writes IBUF (LDI)
    logic                   clr_q;                       // MAC: clr
    logic                   wr_pend_q;                   // LOAD: b_rdata holds a quad to write this cycle
    logic [BUF_IDX_W-1:0]   wr_idx_q;                    // LOAD: its buffer entry
    logic                   buf_rd;                      // MAC: read WBUF[s] and IBUF[s] this cycle
    logic                   step_q;                      // MAC: the buffer read data are valid this cycle
    logic                   first_q;                     // MAC: ... and they are step 0
    logic [QUAD_ADDR_W-1:0] head_qidx;                   // (head.addr - DTCM_BASE) >> 4

    // Quad index of an executing LOAD: subtracting only the quad-index bits [15:4] is exact because
    // DTCM_BASE is quad aligned (no borrow out of bits [3:0]) and CHECK has put addr inside the DTCM.
    localparam int unsigned QIDX_LSB = $clog2(QUAD_BYTES);   // 4
    assign head_qidx = head.addr[QIDX_LSB +: QUAD_ADDR_W] - DTCM_BASE[QIDX_LSB +: QUAD_ADDR_W];
    assign b_req     = (state_q == LOAD) && (req_cnt_q != steps_q);
    // While b_req, b_addr <= quad 4095 (CHECK's range check). In LOAD's last cycle (b_req = 0) it is
    // base + S, which wraps to 0 for a LOAD that ends at the top of the DTCM; it is unused then.
    assign b_addr    = qbase_q + QUAD_ADDR_W'(req_cnt_q);
    assign load_done = (state_q == LOAD) && wr_pend_q && (req_cnt_q == steps_q);
    assign buf_rd    = (state_q == MAC) && (req_cnt_q != steps_q);
    assign mac_done  = (state_q == MAC) && step_q && (req_cnt_q == steps_q);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            steps_q     <= '0;
            req_cnt_q   <= '0;
            qbase_q     <= '0;
            load_ibuf_q <= 1'b0;
            clr_q       <= 1'b0;
            wr_pend_q   <= 1'b0;
            wr_idx_q    <= '0;
            step_q      <= 1'b0;
            first_q     <= 1'b0;
        end else begin
            if (cmd_ok) begin
                steps_q     <= head.k[2 +: STEP_W];      // K/4; K <= KMAX after CHECK
                req_cnt_q   <= '0;
                qbase_q     <= head_qidx;
                load_ibuf_q <= (head.op == OP_LDI);
                clr_q       <= head.clr;
            end else if (b_req || buf_rd) begin
                req_cnt_q   <= req_cnt_q + 1'b1;
            end
            wr_pend_q <= b_req;
            if (b_req) wr_idx_q <= req_cnt_q[BUF_IDX_W-1:0];
            step_q  <= buf_rd;
            first_q <= buf_rd && (req_cnt_q == '0);
        end
    end

    // ---- WBUF / IBUF and the PE array, gated clock domain (spec 7.2, 7.3) ----------------------
    // 256 x 128 bit each, synchronous single-port RAM style: written in LOAD, read in MAC, never both
    // in one cycle (one command at a time). Not reset (spec 7.2, D18): an entry is read only after a
    // LOAD wrote it (a test rule, spec 7.2), and the read registers are used only while step_q.
    // clk_mac comes from npu_clk_gate through continuous assignments only (latch + AND), so at a
    // common edge the clk_mac flops sample the free-domain registers before those update.
    // Enable (spec 8): every term is registered state or the already synchronised rst_n, so it is
    // stable while the latch is open. A push at cycle t makes fifo_empty 0 at t+1 and the first gated
    // edge comes at the end of t+1, before any clk_mac flop needs one: CHECK uses none, and LOAD's
    // first write and MAC's first read are later. Each LOAD/MAC edge falls in a non-IDLE cycle, so D1
    // takes the same cycles as D0 (SC3). !rst_n keeps clk_mac running during reset (spec 8).
    logic clk_en, clk_mac;

    assign clk_en = !rst_n || (state_q != IDLE) || !fifo_empty;

    npu_clk_gate #(
        .GATING_EN (GATING_EN)
    ) u_clk_gate (
        .clk     (clk),
        .en      (clk_en),
        .test_en (1'b0),
        .gclk    (clk_mac)
    );

    logic [PORT_B_W-1:0] wbuf [BUF_DEPTH];
    logic [PORT_B_W-1:0] ibuf [BUF_DEPTH];
    logic [PORT_B_W-1:0] w_rd_q, x_rd_q;                 // WBUF[s], IBUF[s] read in the previous cycle

    always_ff @(posedge clk_mac) begin
        if (wr_pend_q && !load_ibuf_q) wbuf[wr_idx_q] <= b_rdata;
        if (wr_pend_q &&  load_ibuf_q) ibuf[wr_idx_q] <= b_rdata;
        if (buf_rd) begin
            w_rd_q <= wbuf[req_cnt_q[BUF_IDX_W-1:0]];
            x_rd_q <= ibuf[req_cnt_q[BUF_IDX_W-1:0]];
        end
    end

    logic [PE_ROWS*PE_COLS-1:0][31:0] acc;

    pe_array u_pe (
        .clk    (clk_mac),
        .rst_n  (rst_n),
        .step   (step_q),
        .load   (first_q && clr_q),
        .w_quad (w_rd_q),
        .x_quad (x_rd_q),
        .acc    (acc)
    );

    // ---- result read ---------------------------------------------------------------------------
    assign rd_ready = fifo_empty && (state_q == IDLE);   // spec 7.1, A-MAC-2
    assign rd_data  = acc[rd_idx];                       // READ_RESULT, combinational (spec 7.3)

    // rd_req is never needed: rd_data depends on rd_idx alone and the core qualifies it with rd_ready
    // (spec 7.1).
    logic unused_ok;
    assign unused_ok = rd_req;
endmodule
