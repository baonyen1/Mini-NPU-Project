`timescale 1ns / 1ps

// Plain-SV testbench of npu_top (plan Phase 2 Task 14). No UVM.
//
// Runs one firmware image on the whole SoC and implements the SIM MMIO of spec 4.1 on npu_top's
// mmio_* ports:
//   0x0002_0000  SIM_CTRL  0x1 PASS, 0x2 FAIL (both end the run), 0x10 BATCH_DONE, 0x20 MEAS_START,
//                          0x21 MEAS_STOP (printed); any other value is printed and ignored
//   0x0002_0004  SIM_PUTC  the low byte is printed
// The run ends on SIM_CTRL PASS/FAIL or after +TIMEOUT_CYC cycles; a timeout is a FAIL (CLAUDE.md 5).
// The last line is "RESULT: PASS" or "RESULT: FAIL". PASS needs SIM_CTRL PASS, zero errors from the
// bound checker npu_top_chk (its summary is printed first) and, in D1, at least one clk edge at which
// the engine's clk_mac was gated off. The "npu_top_tb: ... cycles=<n>" line gives the cycle count,
// counted from the first rising edge after rst_n is released to the edge that samples the SIM_CTRL
// store, so the D0 and D1 runs of one program can be compared for cycle identity (SC3).
//
//   +ITCM=<hex> +DTCM=<hex>  backdoor images, read by itcm.sv / dtcm_dp.sv at time 0, i.e. before
//                            rst_n is released (decision D7); +ITCM is required
//   +TIMEOUT_CYC=<n>         cycle limit (default 100000)
//   -GGATING_EN=1            run against D1 (clock gating on); the default 0 is D0
//
// Waived for this testbench only (as in mac_engine_tb): the clock generator and the posedge monitor
// update testbench variables with blocking assignments, which is not sequential logic (BLKSEQ), and
// the monitor tests rst_n as data while npu_top uses it as an asynchronous reset (SYNCASYNCNET).
/* verilator lint_off BLKSEQ */
/* verilator lint_off SYNCASYNCNET */
module npu_top_tb #(
    parameter bit GATING_EN = 1'b0
);
    localparam logic [31:0] SIM_CTRL  = 32'h0002_0000;     // spec 4.1
    localparam logic [31:0] SIM_PUTC  = 32'h0002_0004;
    localparam int unsigned RESET_CYC = 5;                  // rising edges with rst_n low
    localparam time         T_CLK     = 10ns;

    logic        clk   = 1'b0;
    logic        rst_n = 1'b0;
    logic        mmio_we;
    logic [31:0] mmio_addr, mmio_wdata;
`ifdef RVVI_TRACE
    // The retire trace is connected (so the build matches the Task 15 cosim one) but not checked here.
    /* verilator lint_off UNUSEDSIGNAL */
    logic        rvvi_valid, rvvi_trap;
    logic [63:0] rvvi_order;
    logic [31:0] rvvi_pc, rvvi_insn, rvvi_rd_wdata, rvvi_mem_addr, rvvi_mem_wdata;
    logic [4:0]  rvvi_rd;
    logic [3:0]  rvvi_mem_wmask;
    /* verilator lint_on UNUSEDSIGNAL */
`endif

    npu_top #(.GATING_EN(GATING_EN)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .mmio_we    (mmio_we),
        .mmio_addr  (mmio_addr),
        .mmio_wdata (mmio_wdata)
`ifdef RVVI_TRACE
        ,
        .rvvi_valid (rvvi_valid), .rvvi_order (rvvi_order), .rvvi_pc (rvvi_pc), .rvvi_insn (rvvi_insn),
        .rvvi_rd (rvvi_rd), .rvvi_rd_wdata (rvvi_rd_wdata), .rvvi_mem_addr (rvvi_mem_addr),
        .rvvi_mem_wdata (rvvi_mem_wdata), .rvvi_mem_wmask (rvvi_mem_wmask), .rvvi_trap (rvvi_trap)
`endif
    );

    always #(T_CLK / 2) clk = ~clk;

    int unsigned timeout_cyc = 100000;
    int unsigned cyc         = 0;          // rising edges since rst_n was released
    int unsigned mac_edges   = 0;          // rising edges of the engine's clk_mac in the same window
    logic [8*256-1:0] itcm_file;

    // clk_mac (mac_engine's npu_clk_gate output) is counted so that a D1 run proves the gate really
    // stopped it: otherwise D0 == D1 cycle identity (SC3) could hold trivially. Same window as cyc
    // (rst_n high); clk_mac rises a few deltas after clk, before the falling edge finish() waits for.
    always @(posedge dut.u_mac_engine.clk_mac) begin
        if (rst_n) mac_edges = mac_edges + 1;
    end

    // ---- end of run -------------------------------------------------------------------------------
    // The verdict includes the bound checker (npu_top_chk, instance u_chk in npu_top): the falling
    // edge is awaited first so that the checker has evaluated the last rising edge (the one that
    // sampled the SIM_CTRL store) before its final_check() counts the errors. Without the bind,
    // elaboration fails on dut.u_chk, so a run cannot pass with the checker missing.
    task automatic finish(input bit pass, input string why);
        int unsigned chk_errors;
        int          gated;
        @(negedge clk);
        chk_errors = dut.u_chk.final_check();
        gated      = int'(cyc) - int'(mac_edges);
        $display("npu_top_tb: GATING_EN=%0d %s, cycles=%0d", GATING_EN, why, cyc);
        $display("npu_top_tb: clk_mac rising edges=%0d of %0d clk edges, gated_off=%0d", mac_edges, cyc, gated);
        if (chk_errors != 0) begin
            $display("npu_top_tb: npu_top_chk reported %0d error(s)", chk_errors);
            pass = 1'b0;
        end
        if (GATING_EN && gated <= 0) begin
            $display("npu_top_tb: GATING_EN=1 but clk_mac was never gated off");
            pass = 1'b0;
        end
        if (pass) begin
            $display("PASS");
            $display("RESULT: PASS");
            $finish;
        end else begin
            $display("FAIL");
            $display("RESULT: FAIL");
            $fatal(1, "npu_top_tb: %s, npu_top_chk errors=%0d, clk_mac gated_off=%0d", why, chk_errors, gated);
        end
    endtask

    // ---- reset: rst_n is released away from a rising edge; npu_top synchronises it (D18) ---------
    initial begin
        void'($value$plusargs("TIMEOUT_CYC=%d", timeout_cyc));
        if (!$value$plusargs("ITCM=%s", itcm_file)) finish(1'b0, "no +ITCM=<hex> given");
        $display("npu_top_tb: GATING_EN=%0d, +ITCM=%0s, TIMEOUT_CYC=%0d", GATING_EN, itcm_file, timeout_cyc);
        repeat (RESET_CYC) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
    end

    // ---- SIM MMIO, cycle count, timeout (sampled at the rising edge, like the DTCM would) ----------
    always @(posedge clk) begin
        if (rst_n) begin
            cyc = cyc + 1;                 // blocking: this edge is counted before it is reported
            if ($isunknown(mmio_we)) begin
                finish(1'b0, "mmio_we is X after reset");
            end else if (mmio_we) begin
                if ($isunknown(mmio_addr) || $isunknown(mmio_wdata)) begin
                    finish(1'b0, $sformatf("X on an MMIO store: addr %h data %h", mmio_addr, mmio_wdata));
                end else if (mmio_addr == SIM_CTRL) begin
                    case (mmio_wdata)
                        32'h1:   finish(1'b1, "SIM_CTRL PASS");
                        32'h2:   finish(1'b0, "SIM_CTRL FAIL");
                        32'h10:  $display("BATCH_DONE");
                        32'h20:  $display("MEAS_START");
                        32'h21:  $display("MEAS_STOP");
                        default: $display("SIM_CTRL: unknown value %h ignored", mmio_wdata);
                    endcase
                end else if (mmio_addr == SIM_PUTC) begin
                    $write("%c", mmio_wdata[7:0]);
                end else begin
                    $display("npu_top_tb: store to unused MMIO address %h ignored", mmio_addr);
                end
            end
            if (cyc >= timeout_cyc) finish(1'b0, "TIMEOUT");
        end
    end
endmodule
