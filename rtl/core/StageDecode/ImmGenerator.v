`timescale 1ns / 1ps

module ImmGenerator(instruction, Imm_out);

input [31:0] instruction;

output reg [31:0] Imm_out;

wire [6:0] Opcode;

assign Opcode = instruction[6:0];

localparam OPCODE_I_ALU  = 7'b0010011;
localparam OPCODE_LOAD   = 7'b0000011;
localparam OPCODE_STORE  = 7'b0100011;
localparam OPCODE_BRANCH = 7'b1100011;
localparam OPCODE_JAL    = 7'b1101111;
localparam OPCODE_JALR   = 7'b1100111;
localparam OPCODE_LUI    = 7'b0110111;
localparam OPCODE_AUIPC  = 7'b0010111;

always @(*) begin
    case (Opcode)
        OPCODE_I_ALU,
        OPCODE_LOAD,
        OPCODE_JALR: begin
            Imm_out = {{20{instruction[31]}}, instruction[31:20]};
        end

        OPCODE_STORE: begin
            Imm_out = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
        end

        OPCODE_BRANCH: begin
            Imm_out = {{19{instruction[31]}},
                       instruction[31],
                       instruction[7],
                       instruction[30:25],
                       instruction[11:8],
                       1'b0};
        end

        OPCODE_JAL: begin
            Imm_out = {{11{instruction[31]}},
                       instruction[31],
                       instruction[19:12],
                       instruction[20],
                       instruction[30:21],
                       1'b0};
        end

        OPCODE_LUI,
        OPCODE_AUIPC: begin
            Imm_out = {instruction[31:12], 12'b0};
        end

        default: begin
            Imm_out = 32'b0;
        end
    endcase
end

endmodule
