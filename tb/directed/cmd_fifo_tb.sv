`timescale 1ns / 1ps

// Directed self-checking unit test of cmd_fifo (plan Task 11, build stage 1). No UVM, no DPI: the
// FIFO is proved on its own before mac_engine uses it. The engine-level t_fifo_full (no command
// lost through the whole engine) is added to mac_engine_tb.sv in stage 2.
// Verdict lines: "RESULT: PASS" or a $fatal with the first mismatch.
//
// Reference model: a SystemVerilog queue. Every step checks empty, full and head against it twice:
// 1 ns after new push/pop values are applied (the state has not changed, so a combinational path from
// push/pop to the outputs shows up as a mismatch) and 1 ns after the edge, with the inputs still held.
// Tests: reset state, t_fifo_full (DEPTH+1 back-to-back pushes, the last is dropped, DEPTH come out in
// order), pop while empty, push+pop when empty / in the middle / when full, wrap-around of the
// pointers, 4000 pseudo-random steps (xorshift32, fixed seed, so every simulator sees the same
// stimulus), asynchronous reset in the middle of a cycle with entries stored.
// DEPTH defaults to npu_pkg::FIFO_DEPTH (8). Run it also with a depth that is not a power of two
// (-GDEPTH=5), because only then does the explicit pointer wrap in cmd_fifo differ from a binary wrap.
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHTRUNC */
module cmd_fifo_tb
  import npu_pkg::*;
#(
    parameter int unsigned DEPTH = FIFO_DEPTH
);
    localparam int unsigned W = 67;              // the width mac_engine uses: op 2 + addr 32 + k 32 + clr 1

    logic           clk = 1'b0;
    logic           rst_n = 1'b0;
    logic           push = 1'b0;
    logic [W-1:0]   push_data = '0;
    logic           pop = 1'b0;
    logic [W-1:0]   head;
    logic           full, empty;

    cmd_fifo #(.WIDTH(W), .DEPTH(DEPTH)) dut (.*);

    initial forever #5 clk = ~clk;

    logic [W-1:0] model [$];
    int checks = 0;
    int seq = 0;                                  // makes every pushed value unique

    function automatic logic [W-1:0] next_value();
        seq++;
        return {3'b101, seq[31:0], ~seq[31:0]};
    endfunction

    task automatic check_outputs(input string where);
        checks++;
        if (empty !== (model.size() == 0))
            $fatal(1, "FAIL %s: empty=%b, model holds %0d", where, empty, model.size());
        if (full !== (model.size() == DEPTH))
            $fatal(1, "FAIL %s: full=%b, model holds %0d", where, full, model.size());
        if (model.size() != 0 && head !== model[0])
            $fatal(1, "FAIL %s: head=%017x, expected %017x", where, head, model[0]);
    endtask

    // Called just after a rising edge. Applies the inputs for one cycle, then advances the model with
    // the rules the DUT must follow: a push is accepted only when not full, a pop only when not empty
    // (A-MAC-1), both judged on the state before the edge.
    task automatic step(input string where, input logic do_push, input logic [W-1:0] d, input logic do_pop);
        bit acc_push, acc_pop;
        push = do_push; push_data = d; pop = do_pop;
        #1 check_outputs({where, " (inputs applied)"});
        acc_push = do_push && model.size() < DEPTH;
        acc_pop  = do_pop  && model.size() > 0;
        @(posedge clk);
        if (acc_pop)  void'(model.pop_front());
        if (acc_push) model.push_back(d);
        #1 check_outputs({where, " (after edge)"});
        push = 1'b0; pop = 1'b0;
    endtask

    function automatic int unsigned xorshift32(input int unsigned x);
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        return x;
    endfunction

    logic [W-1:0] dropped;
    int unsigned  rng = 32'h1234_5678;           // fixed seed

    initial begin
        // ---- reset state --------------------------------------------------------------------
        repeat (2) @(posedge clk);
        #1 check_outputs("in reset");
        rst_n = 1'b1;
        @(posedge clk); #1 check_outputs("after reset");

        // ---- t_fifo_full: 9 back-to-back pushes, no pop ---------------------------------------
        for (int n = 0; n < DEPTH; n++) step($sformatf("t_fifo_full push %0d", n), 1'b1, next_value(), 1'b0);
        if (full !== 1'b1) $fatal(1, "FAIL t_fifo_full: not full after %0d pushes", DEPTH);
        dropped = next_value();
        step("t_fifo_full last push (must be dropped)", 1'b1, dropped, 1'b0);
        for (int n = 0; n < DEPTH; n++) begin
            if (head === dropped) $fatal(1, "FAIL t_fifo_full: the dropped last push came out");
            step($sformatf("t_fifo_full pop %0d", n), 1'b0, '0, 1'b1);
        end
        if (empty !== 1'b1) $fatal(1, "FAIL t_fifo_full: not empty after %0d pops", DEPTH);

        // ---- pop while empty is ignored -------------------------------------------------------
        step("pop while empty", 1'b0, '0, 1'b1);
        step("pop while empty, again", 1'b0, '0, 1'b1);

        // ---- push and pop in the same cycle ---------------------------------------------------
        step("push+pop when empty: push only", 1'b1, next_value(), 1'b1);
        step("fill to 3", 1'b1, next_value(), 1'b0);
        step("fill to 3", 1'b1, next_value(), 1'b0);
        for (int n = 0; n < 5; n++) step("push+pop in the middle", 1'b1, next_value(), 1'b1);
        while (!full) step("fill to full", 1'b1, next_value(), 1'b0);
        dropped = next_value();
        step("push+pop when full: pop only", 1'b1, dropped, 1'b1);
        if (model.size() != DEPTH - 1) $fatal(1, "FAIL push+pop when full: model holds %0d", model.size());
        while (!empty) begin
            if (head === dropped) $fatal(1, "FAIL push+pop when full: the refused push came out");
            step("drain", 1'b0, '0, 1'b1);
        end

        // ---- wrap-around: the pointers pass the end of the array several times ----------------
        for (int n = 0; n < 4 * DEPTH; n++) begin
            step("wrap push", 1'b1, next_value(), 1'b0);
            step("wrap push", 1'b1, next_value(), 1'b0);
            step("wrap pop", 1'b0, '0, 1'b1);
        end
        while (!empty) step("wrap drain", 1'b0, '0, 1'b1);

        // ---- pseudo-random push/pop -----------------------------------------------------------
        for (int n = 0; n < 4000; n++) begin
            rng = xorshift32(rng);
            // bias: phases that lean to push (fill up) and to pop (drain), so full and empty are hit
            if (n % 400 < 200) step("random", rng[3:0] < 11, next_value(), rng[7:4] < 5);
            else               step("random", rng[3:0] < 5,  next_value(), rng[7:4] < 11);
        end

        // ---- asynchronous reset in the middle of a cycle, with entries stored -----------------
        while (model.size() < DEPTH - 1) step("before reset", 1'b1, next_value(), 1'b0);
        #3 rst_n = 1'b0;                          // between edges: an async reset acts at once
        model.delete();
        #1 check_outputs("async reset, before the next edge");
        @(posedge clk); #1 check_outputs("held in reset");
        rst_n = 1'b1;                             // released just after an edge (npu_top synchronises it)
        @(posedge clk); #1 check_outputs("after release");
        step("push after reset", 1'b1, next_value(), 1'b0);
        step("pop after reset", 1'b0, '0, 1'b1);

        $display("cmd_fifo_tb: %0d checks", checks);
        $display("RESULT: PASS");
        $finish;
    end

    // a stuck test must fail, not hang
    initial begin
        #(10 * 100000);
        $fatal(1, "FAIL timeout");
    end
endmodule
