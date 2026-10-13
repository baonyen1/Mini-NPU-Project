`timescale 1ns / 1ps

module Branch_Comparator(
    regfile_out_0,
    regfile_out_1,
    alu_branch_control,
    alu_branch_response
);

input [31:0] regfile_out_0;
input [31:0] regfile_out_1;
input [2:0] alu_branch_control;

output reg alu_branch_response;

always @(*) begin
    case (alu_branch_control)
        3'b000: alu_branch_response = (regfile_out_0 == regfile_out_1); // BEQ
        3'b001: alu_branch_response = (regfile_out_0 != regfile_out_1); // BNE
        3'b100: alu_branch_response = ($signed(regfile_out_0) < $signed(regfile_out_1)); // BLT
        3'b101: alu_branch_response = ($signed(regfile_out_0) >= $signed(regfile_out_1)); // BGE
        3'b110: alu_branch_response = (regfile_out_0 <  regfile_out_1); // BLTU
        3'b111: alu_branch_response = (regfile_out_0 >= regfile_out_1); // BGEU
        default: alu_branch_response = 1'b0;
    endcase
end

endmodule
