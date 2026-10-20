`timescale 1ns / 1ps

// Zicsr unit, in the EX stage (plan Task 6, spec 5, 6.4).
//
// Core CSRs (64-bit counters, read through the low/high word addresses):
//   mcycle/mcycleh   0xB00/0xB80 and read-only aliases cycle/cycleh   0xC00/0xC80
//   minstret/minstreth 0xB02/0xB82 and aliases instret/instreth      0xC02/0xC82
// Engine CSRs 0x7C0 (npu_status) and 0x7C1 (npu_busy_cyc) are forwarded to the
// engine through the npu_csr_* port (spec 7.1 names csr_we/csr_addr/csr_wdata/
// csr_rdata). Any other address reads 0 and ignores writes; writes to the
// counters and their aliases are ignored (decision W2-1 is still open).
//
// csr_op is the instruction's funct3 for a CSR instruction and 000 otherwise:
//   [1:0] = 01 CSRRW, 10 CSRRS, 11 CSRRC; [2] = 1 means wdata is a zimm.
// A CSR instruction executes in one cycle in EX and an instruction in EX is
// never on a wrong path, so the write may happen at the end of that cycle.
//
// minstret is exact: the value read is the number of instructions older than
// the reader. Retired ones are in `minstret`; the ones still in MEM and WB are
// supplied in older_in_flight (0..2) and added on the read side.
//
// The engine CSR port carries the read-modify-write result as npu_csr_wdata,
// and npu_csr_rdata is read combinationally in the same cycle.
module CSR_Unit(
    clk,
    reset,
    csr_op,
    csr_addr,
    wdata,
    rs1_nonzero,
    rdata,
    retire,
    older_in_flight,
    npu_csr_we,
    npu_csr_addr,
    npu_csr_wdata,
    npu_csr_rdata
);

input clk, reset;
input [2:0] csr_op;
input [11:0] csr_addr;
input [31:0] wdata;          // rs1 value, or zimm for the immediate forms
input rs1_nonzero;           // rs1/zimm field is not x0/0: CSRRS/CSRRC then write
input retire;                // one instruction leaves WB this cycle
input [1:0] older_in_flight; // valid instructions in MEM and WB

output [31:0] rdata;

output npu_csr_we;
output [11:0] npu_csr_addr;
output [31:0] npu_csr_wdata;
input [31:0] npu_csr_rdata;

reg [63:0] mcycle;
reg [63:0] minstret;

wire csr_en = (csr_op[1:0] != 2'b00);
wire [63:0] minstret_arch = minstret + {62'b0, older_in_flight};

wire is_npu_csr = (csr_addr == 12'h7C0) || (csr_addr == 12'h7C1);

reg [31:0] read_value;
always @(*) begin
    case (csr_addr)
        12'hB00, 12'hC00: read_value = mcycle[31:0];
        12'hB80, 12'hC80: read_value = mcycle[63:32];
        12'hB02, 12'hC02: read_value = minstret_arch[31:0];
        12'hB82, 12'hC82: read_value = minstret_arch[63:32];
        12'h7C0, 12'h7C1: read_value = npu_csr_rdata;
        default:          read_value = 32'b0;
    endcase
end

assign rdata = read_value;

reg [31:0] new_value;
always @(*) begin
    case (csr_op[1:0])
        2'b01:   new_value = wdata;
        2'b10:   new_value = read_value | wdata;
        default: new_value = read_value & ~wdata;
    endcase
end

wire do_write = csr_en && ((csr_op[1:0] == 2'b01) || rs1_nonzero);

assign npu_csr_we    = do_write && is_npu_csr;
assign npu_csr_addr  = csr_addr;
assign npu_csr_wdata = new_value;

always @(posedge clk) begin
    if (reset) begin
        mcycle   <= 64'b0;
        minstret <= 64'b0;
    end
    else begin
        mcycle <= mcycle + 64'd1;
        if (retire) minstret <= minstret + 64'd1;
    end
end

endmodule
