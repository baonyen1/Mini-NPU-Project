`timescale 1ns / 1ps

// mac_dtcm_if - DTCM port B of mac_engine (spec 7.1): 128-bit read-only, data valid the cycle after
// b_req. The responder in mac_dtcm_agent samples b_req/b_addr just before an edge and drives b_rdata
// 1 ns after it, so the data are stable for the whole next cycle (the same timing as rtl/mem/dtcm_dp.sv).
interface mac_dtcm_if (input logic clk);
    import npu_pkg::*;

    logic                    b_req;
    logic [QUAD_ADDR_W-1:0]  b_addr;
    logic [PORT_B_W-1:0]     b_rdata;

    clocking rsp_cb @(posedge clk);
        default input #1step output #1;
        input  b_req, b_addr;
        output b_rdata;
    endclocking
endinterface
