`timescale 1ns / 1ps

module Control_Unit (
    Opcode,
    fun3,
    fun7,
    Branch,
    Memread,
    alu_operation,
    alu_branch_control,
    Memwrite,
    ALUSrc,
    ALUSrcA,
    reg_write,
    Jump,
    JumpTargetSel,
    DataFormat,
    WB_sel
);

input [6:0] Opcode;
input [2:0] fun3;
input [6:0] fun7;

output reg Branch;
output reg Memread;
output reg Memwrite;
output reg ALUSrc;
output reg [1:0] ALUSrcA;
output reg reg_write;
output reg Jump;
output reg JumpTargetSel;
output reg [2:0] DataFormat;
output reg [1:0] WB_sel;
output reg [2:0] alu_branch_control;
output reg [3:0] alu_operation;

localparam ALU_AND = 4'b0000;
localparam ALU_OR  = 4'b0001;
localparam ALU_ADD = 4'b0010;
localparam ALU_XOR = 4'b0011;
localparam ALU_SLL = 4'b0100;
localparam ALU_SRL = 4'b0101;
localparam ALU_SUB = 4'b0110;
localparam ALU_SLT  = 4'b0111;
localparam ALU_SLTU = 4'b1000;
localparam ALU_SRA  = 4'b1001;

always @(*) begin
    // Default NOP / unsupported instruction
    Branch             = 1'b0;
    Memread            = 1'b0;
    Memwrite           = 1'b0;
    ALUSrc             = 1'b0;
    ALUSrcA            = 2'b00;
    reg_write          = 1'b0;
    Jump               = 1'b0;
    JumpTargetSel      = 1'b0;
    DataFormat         = 3'b010;
    WB_sel             = 2'b00;
    alu_branch_control = 3'b000;
    alu_operation      = ALU_ADD;

    case (Opcode)
        7'b0110011: begin // R-type: ADD SUB SLL SLT SLTU XOR SRL SRA OR AND
            case (fun3)
                3'b000: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_ADD;
                    end
                    else if (fun7 == 7'b0100000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_SUB;
                    end
                end
                3'b100: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_XOR;
                    end
                end
                3'b001: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_SLL;
                    end
                end
                3'b010: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_SLT;
                    end
                end
                3'b011: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_SLTU;
                    end
                end
                3'b101: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_SRL;
                    end
                    else if (fun7 == 7'b0100000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_SRA;
                    end
                end
                3'b110: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_OR;
                    end
                end
                3'b111: begin
                    if (fun7 == 7'b0000000) begin
                        reg_write     = 1'b1;
                        alu_operation = ALU_AND;
                    end
                end
                default: begin
                    reg_write = 1'b0;
                end
            endcase
        end

        7'b0010011: begin // I-type: ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
            case (fun3)
                3'b000: begin
                    ALUSrc       = 1'b1;
                    reg_write    = 1'b1;
                    alu_operation = ALU_ADD;
                end
                3'b010: begin // SLTI
                    ALUSrc       = 1'b1;
                    reg_write    = 1'b1;
                    alu_operation = ALU_SLT;
                end
                3'b011: begin // SLTIU: immediate is sign-extended, then compared unsigned
                    ALUSrc       = 1'b1;
                    reg_write    = 1'b1;
                    alu_operation = ALU_SLTU;
                end
                3'b001: begin // SLLI: imm[11:5] (= fun7) must be 0000000
                    if (fun7 == 7'b0000000) begin
                        ALUSrc       = 1'b1;
                        reg_write    = 1'b1;
                        alu_operation = ALU_SLL;
                    end
                end
                3'b101: begin // SRLI (fun7 = 0000000) / SRAI (fun7 = 0100000)
                    if (fun7 == 7'b0000000) begin
                        ALUSrc       = 1'b1;
                        reg_write    = 1'b1;
                        alu_operation = ALU_SRL;
                    end
                    else if (fun7 == 7'b0100000) begin
                        ALUSrc       = 1'b1;
                        reg_write    = 1'b1;
                        alu_operation = ALU_SRA;
                    end
                end
                3'b100: begin
                    ALUSrc       = 1'b1;
                    reg_write    = 1'b1;
                    alu_operation = ALU_XOR;
                end
                3'b110: begin
                    ALUSrc       = 1'b1;
                    reg_write    = 1'b1;
                    alu_operation = ALU_OR;
                end
                3'b111: begin
                    ALUSrc       = 1'b1;
                    reg_write    = 1'b1;
                    alu_operation = ALU_AND;
                end
                default: begin
                    ALUSrc    = 1'b0;
                    reg_write = 1'b0;
                end
            endcase
        end

        7'b0110111: begin // LUI
            ALUSrc       = 1'b1;
            ALUSrcA      = 2'b01;
            reg_write    = 1'b1;
            alu_operation = ALU_ADD;
        end

        7'b0010111: begin // AUIPC
            ALUSrc       = 1'b1;
            ALUSrcA      = 2'b10;
            reg_write    = 1'b1;
            alu_operation = ALU_ADD;
        end

        7'b0000011: begin // LB, LH, LW, LBU, LHU
            if ((fun3 == 3'b000) || (fun3 == 3'b001) ||
                (fun3 == 3'b010) || (fun3 == 3'b100) ||
                (fun3 == 3'b101)) begin
                Memread       = 1'b1;
                ALUSrc        = 1'b1;
                reg_write     = 1'b1;
                DataFormat    = fun3;
                WB_sel        = 2'b01;
                alu_operation = ALU_ADD;
            end
        end

        7'b0100011: begin // SB, SH, SW
            if ((fun3 == 3'b000) || (fun3 == 3'b001) ||
                (fun3 == 3'b010)) begin
                Memwrite      = 1'b1;
                ALUSrc        = 1'b1;
                DataFormat    = fun3;
                alu_operation = ALU_ADD;
            end
        end

        7'b1100011: begin // BEQ, BNE, BLT, BGE, BLTU, BGEU
            if ((fun3 != 3'b010) && (fun3 != 3'b011)) begin
                Branch             = 1'b1;
                alu_operation      = ALU_SUB;
                alu_branch_control = fun3;
            end
        end

        7'b1101111: begin // JAL
            Jump          = 1'b1;
            JumpTargetSel = 1'b0;
            reg_write     = 1'b1;
            WB_sel        = 2'b10;
        end

        7'b1100111: begin // JALR
            if (fun3 == 3'b000) begin
                Jump          = 1'b1;
                JumpTargetSel = 1'b1;
                reg_write     = 1'b1;
                WB_sel        = 2'b10;
            end
        end

        default: begin end
    endcase
end

endmodule
