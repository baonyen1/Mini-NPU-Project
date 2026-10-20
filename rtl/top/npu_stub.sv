// Engine stand-in for core-only tests (plan Task 9). Port names follow spec 7.1.
//
// Command path: cmd_ready follows the plusarg pattern +STUB_READY=<bits>
// (default always ready). Character i of the pattern is the value in cycle
// i mod len, counted from reset release, so "0001" is ready one cycle in four.
// Every accepted push is logged as   PUSH <op> <addr> <k> <clr>   (hex).
//
// Result path: rd_ready follows +STUB_RDREADY=<bits> the same way (default
// always ready); rd_data = {28'b0, rd_idx}, so READ_RESULT returns its index
// (this is what RefISS stub mode models). Accepted reads are logged as RD <idx>.
//
// Protocol checks (a violation prints STUB_ERROR, which the harness reports):
// once cmd_valid/rd_req is raised it must stay raised, with unchanged
// operands, until the handshake completes.
//
// CSR path (mirrors RefISS):
//   0x7C0 npu_status : {20'b0, err[3:0], 8'b0000_0010}; the four sticky error
//                      bits (11..8) are set by reset so tests can clear them,
//                      and are write-1-to-clear (spec 6.4); fifo_empty reads 1.
//   0x7C1 npu_busy_cyc: plain 32-bit read/write register.
// csr_wdata is the core's read-modify-write result (new CSR value) and
// csr_rdata is combinational in csr_addr.
module npu_stub (
    input  logic        clk,
    input  logic        rst_n,
    // command push (core MEM stage -> engine)
    input  logic        cmd_valid,
    output logic        cmd_ready,
    input  logic [1:0]  cmd_op,
    input  logic [31:0] cmd_addr,
    input  logic [31:0] cmd_k,
    input  logic        cmd_clr,
    // result read
    input  logic        rd_req,
    input  logic [3:0]  rd_idx,
    output logic        rd_ready,
    output logic [31:0] rd_data,
    // CSR port
    input  logic        csr_we,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    output logic [31:0] csr_rdata
);
    // ---- ready patterns from plusargs ------------------------------------
    logic [511:0] ready_str, rd_str;
    logic [63:0]  ready_bits, rd_bits;
    integer       ready_len, rd_len;
    integer       cyc;

    function automatic integer str_len(input logic [511:0] s);
        integer j;
        begin
            str_len = 0;
            for (j = 0; j < 64; j = j + 1)
                if (s[8*j +: 8] != 8'h00) str_len = j + 1;
        end
    endfunction

    task automatic parse_pattern(input logic [511:0] s, output logic [63:0] bits, output integer len);
        integer i;
        begin
            len  = str_len(s);
            bits = 64'b0;
            for (i = 0; i < len; i = i + 1)
                bits[i] = (s[8*(len-1-i) +: 8] == "1");
        end
    endtask

    initial begin
        ready_str = "1";
        rd_str    = "1";
        void'($value$plusargs("STUB_READY=%s", ready_str));
        void'($value$plusargs("STUB_RDREADY=%s", rd_str));
        parse_pattern(ready_str, ready_bits, ready_len);
        parse_pattern(rd_str, rd_bits, rd_len);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) cyc <= 0;
        else        cyc <= cyc + 1;
    end

    assign cmd_ready = ready_bits[cyc % ready_len];
    assign rd_ready  = rd_bits[cyc % rd_len];
    assign rd_data   = {28'b0, rd_idx};

    // ---- logging and protocol checks --------------------------------------
    logic        cmd_wait_q, rd_wait_q;
    logic [66:0] cmd_q;
    logic [3:0]  rd_idx_q;

    // plain always: this block only prints (test code, not synthesizable by intent)
    always @(posedge clk) begin
        if (!rst_n) begin
            cmd_wait_q <= 1'b0;
            rd_wait_q  <= 1'b0;
        end
        else begin
            if (cmd_valid && cmd_ready)
                $display("PUSH %h %h %h %h", cmd_op, cmd_addr, cmd_k, cmd_clr);
            if (rd_req && rd_ready)
                $display("RD %h", rd_idx);
            if (cmd_wait_q && !cmd_valid)
                $display("STUB_ERROR cmd_valid dropped before cmd_ready");
            if (cmd_wait_q && cmd_valid && ({cmd_op, cmd_addr, cmd_k, cmd_clr} != cmd_q))
                $display("STUB_ERROR command changed while waiting for cmd_ready");
            if (rd_wait_q && !rd_req)
                $display("STUB_ERROR rd_req dropped before rd_ready");
            if (rd_wait_q && rd_req && (rd_idx != rd_idx_q))
                $display("STUB_ERROR rd_idx changed while waiting for rd_ready");
            cmd_wait_q <= cmd_valid && !cmd_ready;
            cmd_q      <= {cmd_op, cmd_addr, cmd_k, cmd_clr};
            rd_wait_q  <= rd_req && !rd_ready;
            rd_idx_q   <= rd_idx;
        end
    end

    // ---- CSRs --------------------------------------------------------------
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
