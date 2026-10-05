`timescale 1ns / 1ps

module Program_Counter(clk, pc_write, reset, PC_in, PC_out);

input clk, reset, pc_write;
input [31:0] PC_in;

output reg [31:0] PC_out;

always @(posedge clk) begin
    if (reset) begin
        PC_out <= 32'b0;
    end
    else if (pc_write) begin
        PC_out <= PC_in;
    end
end

endmodule
