`timescale 1ns / 1ps

// Command FIFO of the MAC engine (spec 7.1, 7.2; plan Task 11, build stage 1). Free clock domain
// (spec 7.3): it must keep accepting commands while clk_mac is gated.
//
//   push  accepted when push && !full     mac_engine drives cmd_ready = !full (spec 7.1)
//   pop   accepted when pop && !empty     so the FIFO never overflows or underflows (A-MAC-1)
//   head  the oldest entry, read combinationally (first-word fall-through), valid while !empty,
//         so the FSM sees the command in the cycle it pops it in CHECK (spec 7.2)
//
// A push and a pop in the same cycle both take effect and the count stays the same. When the FIFO
// is full a push is refused even if pop is high in that cycle: ready = !full is the frozen 7.1 rule,
// and it keeps cmd_ready a function of registered state only.
// full and empty decode the count register, so they settle while clk is high and are stable when
// the clock-gate latch opens (spec 8, enable term !fifo_empty).
//
// Reset (spec D18): rst_n is active low with asynchronous assert; its release is synchronised in
// npu_top. The pointers and the count are reset. The entry storage is not: head is used only while
// !empty, and an entry is always written before the count makes it readable.
module cmd_fifo
  import npu_pkg::*;
#(
    parameter int unsigned WIDTH = 67,           // mac_engine: op 2 + addr 32 + k 32 + clr 1
    parameter int unsigned DEPTH = FIFO_DEPTH    // >= 2
)(
    input  logic             clk,
    input  logic             rst_n,

    input  logic             push,
    input  logic [WIDTH-1:0] push_data,
    input  logic             pop,

    output logic [WIDTH-1:0] head,
    output logic             full,
    output logic             empty
);
    localparam int unsigned PTR_W = $clog2(DEPTH);
    localparam int unsigned CNT_W = $clog2(DEPTH + 1);
    localparam logic [PTR_W-1:0] LAST_IDX = PTR_W'(DEPTH - 1);
    localparam logic [CNT_W-1:0] COUNT_FULL = CNT_W'(DEPTH);

    // DEPTH = 1 would make the pointers zero bits wide
    if (DEPTH < 2) begin : g_depth_check
        $error("cmd_fifo: DEPTH must be at least 2, got %0d", DEPTH);
    end

    logic [WIDTH-1:0] mem [DEPTH];
    logic [PTR_W-1:0] wr_ptr_q, rd_ptr_q;
    logic [CNT_W-1:0] count_q;

    wire do_push = push && !full;
    wire do_pop  = pop && !empty;

    assign full  = (count_q == COUNT_FULL);
    assign empty = (count_q == '0);
    assign head  = mem[rd_ptr_q];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_q <= '0;
            rd_ptr_q <= '0;
            count_q  <= '0;
        end else begin
            // the pointers wrap explicitly, so DEPTH need not be a power of two
            if (do_push) wr_ptr_q <= (wr_ptr_q == LAST_IDX) ? '0 : wr_ptr_q + 1'b1;
            if (do_pop)  rd_ptr_q <= (rd_ptr_q == LAST_IDX) ? '0 : rd_ptr_q + 1'b1;
            case ({do_push, do_pop})
                2'b10:   count_q <= count_q + 1'b1;
                2'b01:   count_q <= count_q - 1'b1;
                default: ;                                  // none, or both: count unchanged
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (do_push) mem[wr_ptr_q] <= push_data;
    end
endmodule
