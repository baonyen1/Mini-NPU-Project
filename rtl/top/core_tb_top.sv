// Core-only test top (plan Task 8): core + ITCM + DTCM + SIM MMIO + engine stub.
// Simulation only: the SIM MMIO prints to the log and the retire trace goes to a file.
//
// Memory map (spec 4.1)
//   0x0000_0000  16 KB  ITCM            instruction fetch only
//   0x0001_0000  64 KB  DTCM            core data port A (stand-in until dtcm_dp exists)
//   0x0002_0000   4 B   SIM_CTRL        write-only: 0x1 PASS, 0x2 FAIL, 0x10 BATCH_DONE,
//                                       0x20 MEAS_START, 0x21 MEAS_STOP
//   0x0002_0004   4 B   SIM_PUTC        write-only: the low byte is printed
// Any other data address reads 0 and ignores writes (decision W2-1 is still open).
//
// Plusargs: +ITCM=<hex> +DTCM=<hex> (backdoor load), +RVVI_LOG=<file> (retire trace),
//           +PUSH_PEEK (print the DTCM word at the command address at every push),
//           +STUB_READY / +STUB_RDREADY (see npu_stub.sv)
module core_tb_top (
    input  logic clk,
    input  logic reset,          // active high, like the core
    output logic sim_done        // one cycle after a SIM_CTRL PASS/FAIL write
);
    localparam logic [31:0] SIM_CTRL = 32'h0002_0000;
    localparam logic [31:0] SIM_PUTC = 32'h0002_0004;

    // ---- core ports
    logic [31:0] imem_addr, imem_rdata;
    logic        dmem_re;
    logic [3:0]  dmem_we;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        csr_we;
    logic [11:0] csr_addr;
    logic [31:0] csr_wdata, csr_rdata;
    logic        cmd_valid, cmd_ready, cmd_clr, rd_req, rd_ready;
    logic [1:0]  cmd_op;
    logic [31:0] cmd_addr, cmd_k, rd_data;
    logic [3:0]  rd_idx;

    // legacy observation outputs of the core (unused here)
    logic [31:0] obs_if_id, obs_pc_if_id, obs_pc_id_ex, obs_pc_ex_mem, obs_pc_mem_wb, obs_alu, obs_wb;
    logic        obs_jump;

`ifdef RVVI_TRACE
    logic        rvvi_valid, rvvi_trap;
    logic [63:0] rvvi_order;
    logic [31:0] rvvi_pc, rvvi_insn, rvvi_rd_wdata, rvvi_mem_addr, rvvi_mem_wdata;
    logic [4:0]  rvvi_rd;
    logic [3:0]  rvvi_mem_wmask;
`endif

    RISC_V_Top u_core (
        .clk(clk), .reset(reset),
        .Instruction_IF_ID(obs_if_id), .Instruction_address_IF_ID(obs_pc_if_id),
        .Instruction_address_ID_EX(obs_pc_id_ex), .Instruction_address_EX_MEM(obs_pc_ex_mem),
        .Instruction_address_MEM_WB(obs_pc_mem_wb), .alu_out_EX_MEM(obs_alu),
        .regfile_write_data_WB(obs_wb), .jump_branch_signal(obs_jump),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_re(dmem_re), .dmem_we(dmem_we), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .csr_we(csr_we), .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_rdata(csr_rdata),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_op(cmd_op), .cmd_addr(cmd_addr),
        .cmd_k(cmd_k), .cmd_clr(cmd_clr), .rd_req(rd_req), .rd_idx(rd_idx),
        .rd_ready(rd_ready), .rd_data(rd_data)
`ifdef RVVI_TRACE
        ,
        .rvvi_valid(rvvi_valid), .rvvi_order(rvvi_order), .rvvi_pc(rvvi_pc), .rvvi_insn(rvvi_insn),
        .rvvi_rd(rvvi_rd), .rvvi_rd_wdata(rvvi_rd_wdata), .rvvi_mem_addr(rvvi_mem_addr),
        .rvvi_mem_wdata(rvvi_mem_wdata), .rvvi_mem_wmask(rvvi_mem_wmask), .rvvi_trap(rvvi_trap)
`endif
    );

    itcm u_itcm (.addr(imem_addr), .rdata(imem_rdata));

    // ---- data bus decode
    logic sel_dtcm, dtcm_read_sel_q;
    logic [31:0] dtcm_rdata;
    assign sel_dtcm = (dmem_addr[31:16] == 16'h0001);

    core_tb_dtcm u_dtcm (
        .clk(clk),
        .re(dmem_re && sel_dtcm),
        .we(sel_dtcm ? dmem_we : 4'b0000),
        .addr(dmem_addr[15:2]),
        .wdata(dmem_wdata),
        .rdata(dtcm_rdata)
    );

    // The DTCM answers one cycle after a read request; remember whether that request was ours.
    always_ff @(posedge clk) begin
        if (dmem_re) dtcm_read_sel_q <= sel_dtcm;
    end
    assign dmem_rdata = dtcm_read_sel_q ? dtcm_rdata : 32'b0;

    // ---- engine stand-in
    npu_stub u_npu (
        .clk(clk), .rst_n(~reset),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_op(cmd_op), .cmd_addr(cmd_addr),
        .cmd_k(cmd_k), .cmd_clr(cmd_clr), .rd_req(rd_req), .rd_idx(rd_idx),
        .rd_ready(rd_ready), .rd_data(rd_data),
        .csr_we(csr_we), .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_rdata(csr_rdata)
    );

    // ---- SIM MMIO (a store is on the bus for exactly one cycle: stores never stall)
    always @(posedge clk) begin
        sim_done <= 1'b0;
        if (!reset && (dmem_we == 4'b1111) && (dmem_addr == SIM_CTRL)) begin
            case (dmem_wdata)
                32'h1:   begin $display("PASS"); sim_done <= 1'b1; end
                32'h2:   begin $display("FAIL"); sim_done <= 1'b1; end
                32'h10:  $display("BATCH_DONE");
                32'h20:  $display("MEAS_START");
                32'h21:  $display("MEAS_STOP");
                default: $display("SIM_CTRL: unknown value %h ignored", dmem_wdata);
            endcase
        end
        if (!reset && (dmem_we != 4'b0000) && (dmem_addr == SIM_PUTC))
            $write("%c", dmem_wdata[7:0]);
    end

    // ---- +PUSH_PEEK: DTCM word at the command address when a command is accepted
    logic peek_en;
    initial peek_en = $test$plusargs("PUSH_PEEK");
    always @(posedge clk) begin
        if (!reset && peek_en && cmd_valid && cmd_ready)
            $display("PEEK %08x %08x", cmd_addr, u_dtcm.mem[cmd_addr[15:2]]);
    end

`ifdef RVVI_TRACE
    // ---- +RVVI_LOG=<file>: one line per retired instruction, fixed-width hex:
    //      order pc insn rd rd_wdata mem_addr mem_wdata mem_wmask trap
    integer rvvi_f;
    logic [8*256-1:0] rvvi_name;
    initial begin
        rvvi_f = 0;
        if ($value$plusargs("RVVI_LOG=%s", rvvi_name)) rvvi_f = $fopen(rvvi_name, "w");
    end
    always @(posedge clk) begin
        if (rvvi_f != 0 && !reset && rvvi_valid) begin
            $fwrite(rvvi_f, "%h %h %h %h %h %h %h %h %h\n", rvvi_order, rvvi_pc, rvvi_insn, rvvi_rd,
                    rvvi_rd_wdata, rvvi_mem_addr, rvvi_mem_wdata, rvvi_mem_wmask, rvvi_trap);
            $fflush(rvvi_f);
        end
    end
`endif
endmodule
