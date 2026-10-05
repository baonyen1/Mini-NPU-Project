`timescale 1ns / 1ps

module IF_ID_Reg(
    clk,
    reset,
    stall,
    flush,

    Instruction_address_IF,
    Instruction_IF,

    Instruction_address_IF_ID,
    Instruction_IF_ID
);

input clk, reset;
input stall, flush;

input [31:0] Instruction_address_IF;
input [31:0] Instruction_IF;

output reg [31:0] Instruction_address_IF_ID;
output reg [31:0] Instruction_IF_ID;

always @(posedge clk) begin
    if (reset) begin
        Instruction_address_IF_ID <= 32'b0;
        Instruction_IF_ID         <= 32'h00000013; // NOP: addi x0, x0, 0
    end
    else if (flush) begin
        Instruction_address_IF_ID <= 32'b0;
        Instruction_IF_ID         <= 32'h00000013; // NOP
    end
    else if (!stall) begin
        Instruction_address_IF_ID <= Instruction_address_IF;
        Instruction_IF_ID         <= Instruction_IF;
    end
end

endmodule
