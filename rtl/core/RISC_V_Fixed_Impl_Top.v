`timescale 1ns / 1ps

// ============================================================
// RISC_V_Fixed_Impl_Top
//
// Baseline implementation wrapper for power comparison.
// This is the same RISC_V_Top core, but without the Q-learning DFS block.
// The CPU runs at the full base clock because cpu_en is tied high.
//
// Use this top as the "RISC-V only / fixed-frequency" power case.
// ============================================================
module RISC_V_Fixed_Impl_Top(
    input  wire       clk,
    input  wire       reset,

    output wire       cpu_en,
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

assign cpu_en = 1'b1;

(* dont_touch = "true" *)
RISC_V_Top CPU_CORE(
    .clk(clk),
    .reset(reset),
    .cpu_en(cpu_en),

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
