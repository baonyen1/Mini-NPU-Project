`timescale 1ns / 1ps

module Control_Unit (
    Opcode,
    fun3,
    fun7,
    rs2_field,
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
    WB_sel,
    csr_op,
    FenceI
);

input [6:0] Opcode;
input [2:0] fun3;
input [6:0] fun7;
input [4:0] rs2_field;   // instruction[24:20]: part of the Zbb unary encodings

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
output reg [2:0] csr_op;   // funct3 of a CSR instruction, 000 for everything else
output reg FenceI;         // fence.i: flush the pipeline and refetch from PC+4
output reg [5:0] alu_operation;

localparam ALU_AND = 6'b000000;
localparam ALU_OR  = 6'b000001;
localparam ALU_ADD = 6'b000010;
localparam ALU_XOR = 6'b000011;
localparam ALU_SLL = 6'b000100;
localparam ALU_SRL = 6'b000101;
localparam ALU_SUB = 6'b000110;
localparam ALU_SLT  = 6'b000111;
localparam ALU_SLTU = 6'b001000;
localparam ALU_SRA  = 6'b001001;

// Zbb operations: alu_operation = {1'b1, op[4:0]}; op numbers as in BitManip.v
localparam BB_ANDN   = 5'd0;
localparam BB_ORN    = 5'd1;
localparam BB_XNOR   = 5'd2;
localparam BB_CLZ    = 5'd3;
localparam BB_CTZ    = 5'd4;
localparam BB_CPOP   = 5'd5;
localparam BB_MAX    = 5'd6;
localparam BB_MAXU   = 5'd7;
localparam BB_MIN    = 5'd8;
localparam BB_MINU   = 5'd9;
localparam BB_SEXT_B = 5'd10;
localparam BB_SEXT_H = 5'd11;
localparam BB_ZEXT_H = 5'd12;
localparam BB_ROL    = 5'd13;
localparam BB_ROR    = 5'd14;
localparam BB_ORC_B  = 5'd15;
localparam BB_REV8   = 5'd16;

// Zbb R-type decode: returns {match, op[4:0]}.
function [5:0] zbb_r_decode;
    input [6:0] f7;
    input [2:0] f3;
    input [4:0] rs2f;
    begin
        zbb_r_decode = 6'b000000;
        case ({f7, f3})
            {7'b0100000, 3'b111}: zbb_r_decode = {1'b1, BB_ANDN};
            {7'b0100000, 3'b110}: zbb_r_decode = {1'b1, BB_ORN};
            {7'b0100000, 3'b100}: zbb_r_decode = {1'b1, BB_XNOR};
            {7'b0000101, 3'b110}: zbb_r_decode = {1'b1, BB_MAX};
            {7'b0000101, 3'b111}: zbb_r_decode = {1'b1, BB_MAXU};
            {7'b0000101, 3'b100}: zbb_r_decode = {1'b1, BB_MIN};
            {7'b0000101, 3'b101}: zbb_r_decode = {1'b1, BB_MINU};
            {7'b0110000, 3'b001}: zbb_r_decode = {1'b1, BB_ROL};
            {7'b0110000, 3'b101}: zbb_r_decode = {1'b1, BB_ROR};
            // zext.h is "pack rd, rs1, x0" on RV32; pack itself is not Zbb, so rs2 must be x0
            {7'b0000100, 3'b100}: if (rs2f == 5'b00000) zbb_r_decode = {1'b1, BB_ZEXT_H};
            default: zbb_r_decode = 6'b000000;
        endcase
    end
endfunction

wire [5:0] zbb_r = zbb_r_decode(fun7, fun3, rs2_field);

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
    csr_op             = 3'b000;
    FenceI             = 1'b0;

    case (Opcode)
        7'b0110011: begin // R-type: ADD SUB SLL SLT SLTU XOR SRL SRA OR AND, and RV32M
            if (fun7 == 7'b0000001) begin // MUL MULH MULHSU MULHU DIV DIVU REM REMU
                reg_write     = 1'b1;
                alu_operation = {3'b010, fun3}; // [5:4] = 01 selects the M unit, [2:0] = funct3
            end
            else if (zbb_r[5]) begin // Zbb: ANDN ORN XNOR MAX MAXU MIN MINU ROL ROR ZEXT.H
                reg_write     = 1'b1;
                alu_operation = {1'b1, zbb_r[4:0]};
            end
            else case (fun3)
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
                    else if (fun7 == 7'b0110000) begin // Zbb unary: CLZ CTZ CPOP SEXT.B SEXT.H, selected by imm[4:0]
                        case (rs2_field)
                            5'b00000: begin ALUSrc = 1'b1; reg_write = 1'b1; alu_operation = {1'b1, BB_CLZ};    end
                            5'b00001: begin ALUSrc = 1'b1; reg_write = 1'b1; alu_operation = {1'b1, BB_CTZ};    end
                            5'b00010: begin ALUSrc = 1'b1; reg_write = 1'b1; alu_operation = {1'b1, BB_CPOP};   end
                            5'b00100: begin ALUSrc = 1'b1; reg_write = 1'b1; alu_operation = {1'b1, BB_SEXT_B}; end
                            5'b00101: begin ALUSrc = 1'b1; reg_write = 1'b1; alu_operation = {1'b1, BB_SEXT_H}; end
                            default: begin end
                        endcase
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
                    else if (fun7 == 7'b0110000) begin // RORI (shamt in imm[4:0], reaches the unit as B)
                        ALUSrc       = 1'b1;
                        reg_write    = 1'b1;
                        alu_operation = {1'b1, BB_ROR};
                    end
                    else if ({fun7, rs2_field} == 12'h287) begin // ORC.B
                        ALUSrc       = 1'b1;
                        reg_write    = 1'b1;
                        alu_operation = {1'b1, BB_ORC_B};
                    end
                    else if ({fun7, rs2_field} == 12'h698) begin // REV8
                        ALUSrc       = 1'b1;
                        reg_write    = 1'b1;
                        alu_operation = {1'b1, BB_REV8};
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

        7'b0001111: begin // MISC-MEM: fence executes as a NOP, fence.i flushes and refetches
            if (fun3 == 3'b001) begin
                FenceI = 1'b1;
            end
        end

        7'b1110011: begin // SYSTEM: CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI (ecall/ebreak stay NOPs)
            if ((fun3 != 3'b000) && (fun3 != 3'b100)) begin
                reg_write = 1'b1;
                csr_op    = fun3;
            end
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
