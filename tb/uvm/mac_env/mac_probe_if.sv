`timescale 1ns / 1ps

// mac_probe_if - white-box view of mac_engine state for coverage (spec 10.5 cg_fifo, cg_state). Bound
// into mac_engine by mac_tb_top (bind), so it reads the engine's internal names directly; nothing here
// drives the DUT. mac_coverage gets it through uvm_config_db as "probe_vif"; mac_tb_top also derives
// mac_cmd_if.eng_pop (state CHECK) from it, so the predictor applies each command when it is popped.
interface mac_probe_if (
    input logic       clk,
    input logic       rst_n,
    input logic [1:0] state,              // mac_engine state_q: 0 IDLE, 1 CHECK, 2 LOAD, 3 MAC
    input logic [$clog2(npu_pkg::FIFO_DEPTH + 1)-1:0] fifo_count,   // cmd_fifo count_q, 0..FIFO_DEPTH
    input logic       fifo_full
);
endinterface
