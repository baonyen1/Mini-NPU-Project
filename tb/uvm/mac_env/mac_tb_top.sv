`timescale 1ns / 1ps

// mac_tb_top - top of mac_env (Phase 2 Task 16): clock, reset, interfaces, the DUT, the bound SVA and
// coverage probe, and run_test(). Select the test with +UVM_TESTNAME=<test>; D1 with -GGATING_EN=1.
// Reset: rst_n low for 5 cycles, released 1 ns after an edge (in the SoC, npu_top synchronises it, D18).
module mac_tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import npu_pkg::*;
    import mac_test_pkg::*;

    parameter bit GATING_EN = 1'b0;

    logic clk = 1'b0;
    always #5 clk = ~clk;                                  // 100 MHz, 10 ns per cycle (+TIMEOUT_CYC)

    mac_cmd_if  cmd_if  (clk);
    mac_dtcm_if dtcm_if (clk);

    initial begin
        cmd_if.rst_n = 1'b0;
        repeat (5) @(posedge clk);
        #1 cmd_if.rst_n = 1'b1;
    end

    mac_engine #(.GATING_EN(GATING_EN)) dut (
        .cmd_valid (cmd_if.cmd_valid),
        .cmd_ready (cmd_if.cmd_ready),
        .cmd_op    (cmd_if.cmd_op),
        .cmd_addr  (cmd_if.cmd_addr),
        .cmd_k     (cmd_if.cmd_k),
        .cmd_clr   (cmd_if.cmd_clr),
        .rd_req    (cmd_if.rd_req),
        .rd_idx    (cmd_if.rd_idx),
        .rd_ready  (cmd_if.rd_ready),
        .rd_data   (cmd_if.rd_data),
        .csr_we    (cmd_if.csr_we),
        .csr_addr  (cmd_if.csr_addr),
        .csr_wdata (cmd_if.csr_wdata),
        .csr_rdata (cmd_if.csr_rdata),
        .b_req     (dtcm_if.b_req),
        .b_addr    (dtcm_if.b_addr),
        .b_rdata   (dtcm_if.b_rdata),
        .clk       (clk),
        .rst_n     (cmd_if.rst_n)
    );

    // spec 10.6 assertions and the coverage probe, on the engine's internal signals
    bind mac_engine mac_engine_sva u_sva (
        .clk          (clk),
        .rst_n        (rst_n),
        .state        (state_q),
        .fifo_do_push (u_fifo.do_push),
        .fifo_pop     (fifo_pop),
        .fifo_full    (fifo_full),
        .fifo_empty   (fifo_empty),
        .fifo_count   (u_fifo.count_q),
        .rd_ready     (rd_ready),
        .b_req        (b_req),
        .b_addr       (b_addr),
        .buf_we       (wr_pend_q),
        .head_k       (head.k),
        .head_addr    (head.addr)
    );

    // the pop marker of mac_cmd_if: the engine pops the FIFO head in CHECK (see mac_probe_if)
    localparam logic [1:0] FSM_CHECK = 2'd1;               // mac_engine state_e encoding of CHECK
    assign cmd_if.eng_pop = (dut.u_probe.state == FSM_CHECK);

    bind mac_engine mac_probe_if u_probe (
        .clk        (clk),
        .rst_n      (rst_n),
        .state      (state_q),
        .fifo_count (u_fifo.count_q),
        .fifo_full  (fifo_full)
    );

    initial begin
        uvm_config_db #(virtual mac_cmd_if)::set(null, "*", "cmd_vif", cmd_if);
        uvm_config_db #(virtual mac_dtcm_if)::set(null, "*", "dtcm_vif", dtcm_if);
        uvm_config_db #(virtual mac_probe_if)::set(null, "*", "probe_vif", dut.u_probe);
        `uvm_info("TOP", $sformatf("mac_env on mac_engine, configuration D%0d (GATING_EN = %0d)", GATING_EN, GATING_EN), UVM_LOW)
        run_test();
    end
endmodule
