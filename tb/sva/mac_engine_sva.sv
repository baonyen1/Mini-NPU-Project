`timescale 1ns / 1ps

// mac_engine_sva - the spec 10.6 assertions A-MAC-1..5 for mac_engine (Phase 2 Task 16). Bound into
// every mac_engine instance by the env top (bind mac_engine mac_engine_sva u_sva (...)), so its inputs
// are the engine's own internal signals. A failure reports UVM_ERROR with the assertion ID, so a UVM test
// fails on it (CLAUDE.md section 5: zero assertion failures). Each property also has a cover, so a
// property that is never exercised shows up as uncovered rather than as a silent pass.
module mac_engine_sva
  import npu_pkg::*;
(
    input logic                                  clk,
    input logic                                  rst_n,
    input logic [1:0]                            state,          // state_q: 0 IDLE, 1 CHECK, 2 LOAD, 3 MAC
    input logic                                  fifo_do_push,   // cmd_fifo: a push is accepted
    input logic                                  fifo_pop,       // the FSM asks the FIFO for a pop
    input logic                                  fifo_full,
    input logic                                  fifo_empty,
    input logic [$clog2(FIFO_DEPTH + 1)-1:0]     fifo_count,
    input logic                                  rd_ready,
    input logic                                  b_req,
    input logic [QUAD_ADDR_W-1:0]                b_addr,
    input logic                                  buf_we,         // WBUF/IBUF write strobe (wr_pend_q)
    input logic [31:0]                           head_k,         // K of the FIFO head (the command in CHECK)
    input logic [31:0]                           head_addr       // address of the FIFO head
);
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam logic [1:0] S_IDLE = 2'd0, S_CHECK = 2'd1, S_LOAD = 2'd2;

    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    // A-MAC-1: no FIFO push while full, no pop while empty
    a_mac1_push: assert property (fifo_do_push |-> !fifo_full)
        else `uvm_error("A-MAC-1", "a command was pushed into the full FIFO")
    a_mac1_pop: assert property (fifo_pop |-> !fifo_empty)
        else `uvm_error("A-MAC-1", "the FSM popped the empty FIFO")
    a_mac1_count: assert property (fifo_count <= FIFO_DEPTH)
        else `uvm_error("A-MAC-1", $sformatf("FIFO count %0d above FIFO_DEPTH", fifo_count))
    c_mac1_full: cover property (fifo_full);

    // A-MAC-2: rd_ready only when the FIFO is empty and the FSM is idle
    a_mac2: assert property (rd_ready |-> (fifo_empty && state == S_IDLE))
        else `uvm_error("A-MAC-2", "rd_ready while the engine has work")
    c_mac2: cover property (!rd_ready ##1 rd_ready);

    // A-MAC-3: b_req only in LOAD; b_addr inside the DTCM
    a_mac3_state: assert property (b_req |-> state == S_LOAD)
        else `uvm_error("A-MAC-3", $sformatf("b_req in state %0d", state))
    a_mac3_addr: assert property (b_req |-> b_addr <= DTCM_QUADS - 1)
        else `uvm_error("A-MAC-3", $sformatf("b_addr %0d outside the DTCM", b_addr))
    c_mac3: cover property (b_req);

    // A-MAC-3, which quads: the n-th b_req after a CHECK reads quad (addr - DTCM_BASE)/16 + n of that
    // command (spec 6.2, 6.3), so the first read starts at the command's address and the reads are
    // consecutive. exp_qaddr_q is loaded in every CHECK (a dropped command issues no b_req before the
    // next CHECK) and advances by one per b_req. The 12-bit check above alone holds for any b_addr.
    logic [QUAD_ADDR_W-1:0] exp_qaddr_q;
    logic [31:0]            head_off;
    assign head_off = head_addr - DTCM_BASE;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                 exp_qaddr_q <= '0;
        else if (state == S_CHECK)  exp_qaddr_q <= head_off[$clog2(QUAD_BYTES) +: QUAD_ADDR_W];
        else if (b_req)             exp_qaddr_q <= exp_qaddr_q + 1'b1;
    end

    // the action block runs after this edge's updates: print the sampled values the property used
    a_mac3_quad: assert property (b_req |-> b_addr == exp_qaddr_q)
        else `uvm_error("A-MAC-3", $sformatf("b_addr %0d, expected quad %0d (the command's address + reads so far)",
                                             $sampled(b_addr), $sampled(exp_qaddr_q)))
    c_mac3_burst: cover property (b_req ##1 b_req);

    // A-MAC-4: buffers are written only in LOAD
    a_mac4: assert property (buf_we |-> state == S_LOAD)
        else `uvm_error("A-MAC-4", $sformatf("WBUF/IBUF written in state %0d", state))
    c_mac4: cover property (buf_we);

    // A-MAC-5: a popped command is back in IDLE within K/4 + 3 cycles. run_q counts the non-IDLE cycles
    // before the current one; the command's bound is taken from the FIFO head in its CHECK cycle (35 bits,
    // so a large K cannot wrap the bound).
    logic [34:0] run_q, lim_q, lim_now;
    assign lim_now = (state == S_CHECK) ? (35'(head_k) >> 2) + 35'd3 : lim_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_q <= '0;
            lim_q <= '0;
        end else begin
            run_q <= (state != S_IDLE) ? run_q + 35'd1 : '0;
            lim_q <= lim_now;
        end
    end

    a_mac5: assert property ((state != S_IDLE) |-> (run_q + 35'd1 <= lim_now))
        else `uvm_error("A-MAC-5", $sformatf("command busy for %0d cycles, bound K/4+3 = %0d", run_q + 1, lim_now))
    c_mac5: cover property (state == S_CHECK ##1 state != S_IDLE);
endmodule
