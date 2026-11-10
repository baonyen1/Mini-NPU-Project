`timescale 1ns / 1ps

// Passive checker bound into npu_top (plan Phase 2 Task 14, DV extension). Plain SV, no UVM.
//   bind npu_top npu_top_chk ... (below) connects it to the nets of the core/engine boundary.
// Checks, all sampled at the rising edge of clk (the values the flops see):
//   R1  reset release: the core's reset input and the engine's rst_n (taken from the port
//       connections of u_core and u_mac_engine, not from npu_top's own helper nets) are always
//       opposite, and the engine's rst_n is released exactly once, so both leave reset on the same
//       clock edge (spec 8, D18). R1 is the reset check that carries the evidence.
//   R2  no cmd_valid, rd_req or csr_we while the engine's rst_n is low OR the core is in reset.
//       R2 is a backstop only: with R1 holding, "core in reset" and "engine in reset" are the same
//       cycles, and a core in reset drives nothing. Even with R1 broken (the core released from the
//       raw rst_n, i.e. 2 synchroniser cycles before the engine) a command, read or CSR write first
//       has to travel from fetch to the MEM stage, which takes longer than that skew, so R2 is not
//       expected to fire in any run. r2_edges in the summary only counts the edges at which R2 was
//       evaluated; it is not evidence that R2 can detect anything.
//   P1  command hold: a command not accepted (cmd_valid && !cmd_ready) is still presented, with
//       the same op/addr/k/clr, at the next edge (spec 6.3 rule 3: the pipeline stalls at MEM).
//       The same for READ_RESULT: rd_req && !rd_ready must be followed by rd_req with the same
//       rd_idx (the core waits at MEM for rd_ready, spec 6.3 rule 4, 7.1).
//   S1  with +EXPECT_STALL the run must contain at least one stall cycle on cmd_ready (the test
//       would otherwise not exercise the full FIFO)
// The first SETTLE edges are not checked: the synchroniser flops are X until rst_n has been low
// at one edge. Every violation prints one "npu_top_chk: ERROR" line. The testbench calls
// final_check() once at the end of the run, after the last edge has been fully evaluated: it adds
// the end-of-run checks (S1, the R1 release count), prints "npu_top_chk: summary" and returns the
// error count, which the testbench folds into its RESULT line. run_npu_top.sh also fails a run
// without the summary or with an ERROR line. The counters show how often each check was exercised.
module npu_top_chk (
    input logic        clk,
    input logic        core_reset,       // u_core.reset (active high)
    input logic        eng_rst_n,        // u_mac_engine.rst_n (active low)
    input logic        cmd_valid,
    input logic        cmd_ready,
    input logic [1:0]  cmd_op,
    input logic [31:0] cmd_addr,
    input logic [31:0] cmd_k,
    input logic        cmd_clr,
    input logic        rd_req,
    input logic [3:0]  rd_idx,
    input logic        rd_ready,
    input logic        csr_we
);
    localparam int unsigned SETTLE = 2;

    int unsigned edges           = 0;
    int unsigned errors          = 0;
    int unsigned rel_edges       = 0;    // edges at which the engine's rst_n rises
    int unsigned rst_low_edges   = 0;
    int unsigned r2_edges        = 0;    // edges at which R2 was evaluated (core or engine in reset)
    int unsigned pushes          = 0;    // accepted commands
    int unsigned stall_cycles    = 0;    // cmd_valid && !cmd_ready
    int unsigned max_stall       = 0;
    int unsigned stall_run       = 0;
    int unsigned rd_stall_cycles = 0;    // rd_req && !rd_ready
    bit          expect_stall    = 1'b0;
    bit          prev_stall      = 1'b0;
    bit          prev_rd_stall   = 1'b0;
    bit          done            = 1'b0;
    logic        prev_rst_n      = 1'b0;
    logic [1:0]  p_op;
    logic [31:0] p_addr, p_k;
    logic        p_clr;
    logic [3:0]  p_idx;

    initial expect_stall = $test$plusargs("EXPECT_STALL");

    function automatic void err(input string msg);
        errors++;
        $display("npu_top_chk: ERROR t=%0t edge %0d: %s", $time, edges, msg);
    endfunction

    always @(posedge clk) begin
        edges++;
        if (edges > SETTLE) begin
            // R1
            if (core_reset !== ~eng_rst_n)
                err($sformatf("R1 core reset=%b but engine rst_n=%b (must be opposite)", core_reset, eng_rst_n));
            if (eng_rst_n === 1'b1 && prev_rst_n === 1'b0) rel_edges++;
            if (eng_rst_n === 1'b0) rst_low_edges++;
            // R2 (backstop, see the header)
            if (eng_rst_n !== 1'b1 || core_reset !== 1'b0) begin
                r2_edges++;
                if (cmd_valid !== 1'b0)
                    err($sformatf("R2 cmd_valid=%b while engine rst_n=%b, core reset=%b", cmd_valid, eng_rst_n, core_reset));
                if (rd_req !== 1'b0)
                    err($sformatf("R2 rd_req=%b while engine rst_n=%b, core reset=%b", rd_req, eng_rst_n, core_reset));
                if (csr_we !== 1'b0)
                    err($sformatf("R2 csr_we=%b while engine rst_n=%b, core reset=%b", csr_we, eng_rst_n, core_reset));
            end
            // P1
            if (prev_stall) begin
                if (cmd_valid !== 1'b1 || cmd_op !== p_op || cmd_addr !== p_addr ||
                    cmd_k !== p_k || cmd_clr !== p_clr)
                    err($sformatf("P1 stalled command changed: valid=%b op=%0d addr=%h k=%0d clr=%b (was op=%0d addr=%h k=%0d clr=%b)",
                                  cmd_valid, cmd_op, cmd_addr, cmd_k, cmd_clr, p_op, p_addr, p_k, p_clr));
            end
            if (prev_rd_stall) begin
                if (rd_req !== 1'b1 || rd_idx !== p_idx)
                    err($sformatf("P1 stalled READ_RESULT changed: rd_req=%b rd_idx=%0d (was rd_idx=%0d)",
                                  rd_req, rd_idx, p_idx));
            end
            if (eng_rst_n === 1'b1) begin
                prev_stall    <= (cmd_valid === 1'b1) && (cmd_ready === 1'b0);
                prev_rd_stall <= (rd_req === 1'b1) && (rd_ready === 1'b0);
                if (cmd_valid === 1'b1 && cmd_ready === 1'b1) pushes++;
                if (cmd_valid === 1'b1 && cmd_ready === 1'b0) begin
                    stall_cycles++;
                    stall_run++;
                    if (stall_run > max_stall) max_stall = stall_run;
                end else begin
                    stall_run = 0;
                end
                if (rd_req === 1'b1 && rd_ready === 1'b0) rd_stall_cycles++;
            end else begin
                prev_stall    <= 1'b0;
                prev_rd_stall <= 1'b0;
            end
            p_op <= cmd_op; p_addr <= cmd_addr; p_k <= cmd_k; p_clr <= cmd_clr; p_idx <= rd_idx;
            prev_rst_n <= eng_rst_n;
        end
    end

    // Called by the testbench when the run ends (npu_top_tb, task finish): the end-of-run checks,
    // the summary line, and the total error count for the testbench's verdict. A second call only
    // returns the count.
    function automatic int unsigned final_check();
        if (!done) begin
            done = 1'b1;
            if (expect_stall && stall_cycles == 0)
                err("S1 +EXPECT_STALL but the core never stalled on cmd_ready");
            if (rel_edges != 1)
                err($sformatf("R1 engine rst_n released %0d times (expected exactly 1)", rel_edges));
            $display("npu_top_chk: summary edges=%0d rst_low_edges=%0d release_edges=%0d r2_edges=%0d pushes=%0d stall_cycles=%0d max_stall_run=%0d rd_stall_cycles=%0d expect_stall=%0b errors=%0d",
                     edges, rst_low_edges, rel_edges, r2_edges, pushes, stall_cycles, max_stall,
                     rd_stall_cycles, expect_stall, errors);
        end
        return errors;
    endfunction
endmodule

// Elaborated as a second top (vsim ... npu_top_tb npu_top_chk_bind): a bind in the compilation unit
// scope is not picked up without vlog -cuname.
module npu_top_chk_bind;
  bind npu_top npu_top_chk u_chk (
    .clk        (clk),
    .core_reset (u_core.reset),
    .eng_rst_n  (u_mac_engine.rst_n),
    .cmd_valid  (cmd_valid),
    .cmd_ready  (cmd_ready),
    .cmd_op     (cmd_op),
    .cmd_addr   (cmd_addr),
    .cmd_k      (cmd_k),
    .cmd_clr    (cmd_clr),
    .rd_req     (rd_req),
    .rd_idx     (rd_idx),
    .rd_ready   (rd_ready),
    .csr_we     (csr_we)
  );
endmodule
