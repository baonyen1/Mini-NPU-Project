`timescale 1ns / 1ps

// ============================================================
// RISC_V_Fixed_Impl_Top
//
// Baseline implementation wrapper for power comparison.
// FPGA wrapper (graduation thesis, not part of the Senior Project 2 flow).
// The core runs at the full base clock; there is no DFS block any more.
//
// Use this top as the "RISC-V only / fixed-frequency" power case.
// ============================================================
module RISC_V_Fixed_Impl_Top(
    input  wire       clk,
    input  wire       reset,

    output wire [3:0] debug_led
);

wire [31:0] Instruction_IF_ID;
wire [31:0] Instruction_address_IF_ID;
wire [31:0] Instruction_address_ID_EX;
wire [31:0] Instruction_address_EX_MEM;
wire [31:0] Instruction_address_MEM_WB;
wire [31:0] alu_out_EX_MEM;
wire [31:0] regfile_write_data_WB;
wire        jump_branch_signal;

(* dont_touch = "true" *)
RISC_V_Top CPU_CORE(
    .clk(clk),
    .reset(reset),

    .Instruction_IF_ID(Instruction_IF_ID),
    .Instruction_address_IF_ID(Instruction_address_IF_ID),
    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .Instruction_address_EX_MEM(Instruction_address_EX_MEM),
    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .regfile_write_data_WB(regfile_write_data_WB),
    .jump_branch_signal(jump_branch_signal)
);

assign debug_led = {
    jump_branch_signal,
    Instruction_address_IF_ID[4:2]
};

endmodule
