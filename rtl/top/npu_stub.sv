// Engine stand-in for core-only tests (plan Task 9; the CSR part arrives with
// Task 6 because the Zicsr tests need an engine-side CSR to talk to).
//
// Port names follow spec 7.1. The CSR behaviour mirrors RefISS in
// tools/rv32i_check/run.py:
//   0x7C0 npu_status : {20'b0, err[3:0], 8'b0000_0010}; the four sticky error
//                      bits (11..8) are set by reset (so tests can clear them)
//                      and are write-1-to-clear (spec 6.4); fifo_empty reads 1.
//   0x7C1 npu_busy_cyc: plain 32-bit read/write register.
// npu_csr_wdata is the core's read-modify-write result (new CSR value) and
// csr_rdata is combinational in csr_addr.
module npu_stub (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        csr_we,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    output logic [31:0] csr_rdata
);
    logic [3:0]  err_q;
    logic [31:0] busy_cyc_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            err_q      <= 4'hF;
            busy_cyc_q <= 32'b0;
        end
        else if (csr_we) begin
            if (csr_addr == 12'h7C0) err_q      <= err_q & ~csr_wdata[11:8];
            if (csr_addr == 12'h7C1) busy_cyc_q <= csr_wdata;
        end
    end

    always_comb begin
        case (csr_addr)
            12'h7C0: csr_rdata = {20'b0, err_q, 8'b0000_0010};
            12'h7C1: csr_rdata = busy_cyc_q;
            default: csr_rdata = 32'b0;
        endcase
    end
endmodule
