`timescale 1ns / 1ps

// npu_clk_gate - the only clock-gating cell in the design (spec 8, D19; plan Task 11, build stage 7).
// Latch transparent while clk is low, then AND, the usual integrated clock-gate structure (the same
// pattern as CoralNPU hdl/verilog/ClockGate.sv, default branch; written here, not copied, spec 16).
// The latch holds en for the whole high phase, so a change of en while clk is high cannot cut or
// create a pulse on gclk: an edge of gclk exists exactly when en | test_en was 1 at the end of the
// preceding low phase. This latch is the only one allowed in the design (CLAUDE.md section 5).
//
//   GATING_EN = 0 (D0): the enable is tied to 1, so gclk follows clk; the instance stays, so D0 and
//                       D1 have the same hierarchy and differ only in this tie (spec 8).
//   GATING_EN = 1 (D1): gclk runs only in cycles whose enable was 1.
// test_en forces the clock on (scan/test); mac_engine ties it to 0. A BUFGCE variant behind
// `ifdef FPGA_XILINX belongs to the thesis (spec 8), not to Senior Project 2.
module npu_clk_gate #(
    parameter bit GATING_EN = 1'b1
) (
    input  logic clk,
    input  logic en,
    input  logic test_en,
    output logic gclk
);
    logic en_eff;
    logic en_l /* verilator clock_enable */;

    assign en_eff = GATING_EN ? (en | test_en) : 1'b1;

    always_latch begin
        if (!clk) en_l = en_eff;
    end

    assign gclk = clk & en_l;
endmodule
