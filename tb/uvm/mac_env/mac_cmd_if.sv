`timescale 1ns / 1ps

// mac_cmd_if - the mac_engine command, result-read and CSR ports (spec 7.1) plus the reset, as seen by
// mac_env's cmd_agent (Phase 2 Task 16).
//
// csr_re is verification-only: the 7.1 CSR port has no read strobe (D21: csr_rdata is valid in every
// cycle and reads have no side effects), so the driver raises csr_re for one cycle when it performs a
// CSR read, to tell the monitor that this cycle's csr_rdata is an observed read. It is not connected
// to the DUT.
//
// Timing: the driver drives 1 ns after a rising edge (drv_cb output #1); both clocking blocks sample
// just before the edge (#1step), so the DUT and the testbench see the same values at every edge.
interface mac_cmd_if (input logic clk);
    import npu_pkg::*;

    logic                  rst_n;
    logic                  cmd_valid;
    logic                  cmd_ready;
    logic [1:0]            cmd_op;
    logic [31:0]           cmd_addr;
    logic [31:0]           cmd_k;
    logic                  cmd_clr;
    logic                  rd_req;
    logic [RD_IDX_W-1:0]   rd_idx;
    logic                  rd_ready;
    logic [31:0]           rd_data;
    logic                  csr_we;
    logic [11:0]           csr_addr;
    logic [31:0]           csr_wdata;
    logic [31:0]           csr_rdata;
    logic                  csr_re;        // verification only, see above

    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output cmd_valid, cmd_op, cmd_addr, cmd_k, cmd_clr, rd_req, rd_idx, csr_we, csr_addr, csr_wdata, csr_re;
        input  rst_n, cmd_ready, rd_ready, rd_data, csr_rdata;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, cmd_valid, cmd_ready, cmd_op, cmd_addr, cmd_k, cmd_clr, rd_req, rd_idx, rd_ready, rd_data,
              csr_we, csr_addr, csr_wdata, csr_rdata, csr_re;
    endclocking
endinterface
