`timescale 1ns / 1ps

module ProgramMemory(reset, read_word_addr, instruction_out);

input reset;
input [7:0] read_word_addr;

output [31:0] instruction_out;

integer i;
reg [31:0] memory [0:255];

initial begin
    for (i = 0; i < 256; i = i + 1) begin
        memory[i] = 32'h00000013; // NOP: addi x0, x0, 0
    end

    $readmemh("program.hex", memory);
end

assign instruction_out = (reset) ? 32'h00000013 : memory[read_word_addr];

endmodule
