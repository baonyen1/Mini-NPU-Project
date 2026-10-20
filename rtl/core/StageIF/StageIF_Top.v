`timescale 1ns / 1ps

module StageIF_TOP (
    clk,
    reset,
    pc_write,
    stall,
    flush,
    jump_branch_signal,
    jump_branch_destination,

    Instruction_IF_ID,
    Instruction_address_IF_ID,
    valid_IF_ID,

    // instruction memory (ITCM), combinational read
    imem_addr,
    imem_rdata
);

input clk, reset;
input pc_write;
input stall, flush;
input jump_branch_signal;
input [31:0] jump_branch_destination;

output [31:0] Instruction_IF_ID;
output [31:0] Instruction_address_IF_ID;
output valid_IF_ID;
output [31:0] imem_addr;
input [31:0] imem_rdata;

wire [31:0] next_instruction_address;
wire [31:0] Instruction_address_IF;
wire [31:0] pc_plus4_IF;
wire [31:0] Instruction_IF;

PCMux PCMUX(
    .pc_sel(jump_branch_signal),
    .PC_plus4(pc_plus4_IF),
    .Branch_target(jump_branch_destination),
    .PC_out(next_instruction_address)
);

Program_Counter PC(
    .clk(clk),
    .pc_write(pc_write),
    .reset(reset),
    .PC_in(next_instruction_address),
    .PC_out(Instruction_address_IF)
);

PCplus4 PC_ADD4(
    .fromPC(Instruction_address_IF),
    .toPC(pc_plus4_IF)
);

assign imem_addr = Instruction_address_IF;
assign Instruction_IF = reset ? 32'h00000013 : imem_rdata;   // NOP while in reset

IF_ID_Reg IF_ID(
    .clk(clk),
    .reset(reset),
    .stall(stall),
    .flush(flush),

    .Instruction_address_IF(Instruction_address_IF),
    .Instruction_IF(Instruction_IF),

    .Instruction_address_IF_ID(Instruction_address_IF_ID),
    .Instruction_IF_ID(Instruction_IF_ID),
    .valid_IF_ID(valid_IF_ID)
);

endmodule
