`timescale 1ns / 1ps

// npu_top - the Mini-NPU SoC (spec 4; plan Phase 2 Task 14): the RV32 core, the ITCM, the dual-port
// DTCM and the MAC engine. Hierarchical names are fixed for later tasks (spec 11 dump scope):
// u_core, u_itcm, u_dtcm, u_mac_engine.
//
// Memory map (spec 4.1), core data bus:
//   0x0001_0000  64 KB  DTCM       dtcm_dp port A (32-bit R/W, byte enables, 1-cycle read)
//   0x0002_xxxx         SIM MMIO   passed out on mmio_* (SIM_CTRL, SIM_PUTC live in the testbench);
//                                  reads return 0
//   anything else                  reads 0, writes ignored (core policy W2-1 is still open)
// The engine owns dtcm_dp port B (128-bit, read-only). The ITCM is fetch-only.
//
// Reset (D18): rst_n is the board/testbench reset, active low, asynchronous. One two-flop
// synchronizer turns it into rst_n_sync (async assert, sync release), the name spec 8 uses.
// rst_n_sync drives the engine's rst_n and dtcm_read_sel_q; its inverse drives the core's
// active-high synchronous reset. Core and engine therefore leave reset on the same clock edge,
// so the core can never push a command into an engine that is still held in reset.
//
// GATING_EN (spec 8, D19) is passed to mac_engine unchanged: it is the only D0/D1 difference.
module npu_top
  import npu_pkg::*;
#(
    parameter bit GATING_EN = 1'b0                   // 0: D0, 1: D1
) (
    input  logic        clk,
    input  logic        rst_n,                       // active low, asynchronous (synchronised here)

    // SIM MMIO window 0x0002_xxxx: one cycle per store (stores never stall the core)
    output logic        mmio_we,                     // a store (any byte enable) to the window
    output logic [31:0] mmio_addr,
    output logic [31:0] mmio_wdata
`ifdef RVVI_TRACE
    ,
    // retire trace, passed through from the core unchanged (plan Task 8)
    output logic        rvvi_valid,
    output logic [63:0] rvvi_order,
    output logic [31:0] rvvi_pc,
    output logic [31:0] rvvi_insn,
    output logic [4:0]  rvvi_rd,
    output logic [31:0] rvvi_rd_wdata,
    output logic [31:0] rvvi_mem_addr,
    output logic [31:0] rvvi_mem_wdata,
    output logic [3:0]  rvvi_mem_wmask,
    output logic        rvvi_trap
`endif
);
    // Region decode. DTCM: DTCM_BASE is DTCM_BYTES-aligned, so comparing the bits above the DTCM
    // offset selects it exactly. SIM MMIO: spec 4.1 puts SIM_CTRL/SIM_PUTC at 0x0002_0000/4; the
    // plan (Task 14) routes the whole 0x0002_xxxx window to mmio_*. The base is not in npu_pkg.
    localparam int unsigned DTCM_OFS_W = $clog2(DTCM_BYTES);         // 16
    localparam logic [31:0] MMIO_BASE  = 32'h0002_0000;              // spec 4.1
    localparam int unsigned MMIO_OFS_W = 16;                         // the 0x0002_xxxx window

    // sel_dtcm below is exact only if DTCM_BYTES is a power of two and DTCM_BASE a multiple of it;
    // npu_pkg could be edited without noticing that, so stop elaboration instead (IEEE 1800-2017
    // 20.11 elaboration system task; no hardware is generated).
    if (((DTCM_BASE % DTCM_BYTES) != 0) || ((32'd1 << DTCM_OFS_W) != DTCM_BYTES)) begin : g_dtcm_map_check
        $error("npu_top: DTCM_BASE (%h) must be a multiple of DTCM_BYTES (%0d), a power of two",
               DTCM_BASE, DTCM_BYTES);
    end

    // ---- reset bridge (D18) -------------------------------------------------------------------
    logic [1:0] rst_sync_q;
    logic       rst_n_sync;
    logic       core_reset;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rst_sync_q <= 2'b00;
        else        rst_sync_q <= {rst_sync_q[0], 1'b1};
    end
    assign rst_n_sync = rst_sync_q[1];
    assign core_reset = ~rst_n_sync;

    // ---- core ---------------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] imem_addr;                          // bits 1:0 are not used by the ITCM
    /* verilator lint_on UNUSEDSIGNAL */
    logic [31:0] imem_rdata;
    logic        dmem_re;
    logic [3:0]  dmem_we;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        csr_we;
    logic [11:0] csr_addr;
    logic [31:0] csr_wdata, csr_rdata;
    logic        cmd_valid, cmd_ready, cmd_clr, rd_req, rd_ready;
    logic [1:0]  cmd_op;
    logic [31:0] cmd_addr, cmd_k, rd_data;
    logic [RD_IDX_W-1:0] rd_idx;

    // legacy observation outputs of the core (kept for the parked FPGA wrapper; unused here)
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] obs_if_id, obs_pc_if_id, obs_pc_id_ex, obs_pc_ex_mem, obs_pc_mem_wb, obs_alu, obs_wb;
    logic        obs_jump;
    /* verilator lint_on UNUSEDSIGNAL */

    RISC_V_Top u_core (
        .clk(clk), .reset(core_reset),
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

    // ---- ITCM (fetch only) --------------------------------------------------------------------
    itcm u_itcm (.addr(imem_addr[31:2]), .rdata(imem_rdata));

    // ---- core data bus decode -----------------------------------------------------------------
    logic sel_dtcm, sel_mmio;
    logic dtcm_read_sel_q;
    logic [31:0] dtcm_a_rdata;

    assign sel_dtcm = (dmem_addr[31:DTCM_OFS_W] == DTCM_BASE[31:DTCM_OFS_W]);
    assign sel_mmio = (dmem_addr[31:MMIO_OFS_W] == MMIO_BASE[31:MMIO_OFS_W]);

    // engine port B
    logic                   b_req;
    logic [QUAD_ADDR_W-1:0] b_addr;
    logic [PORT_B_W-1:0]    b_rdata;

    dtcm_dp u_dtcm (
        .clk    (clk),
        .a_re   (dmem_re && sel_dtcm),
        .a_we   (sel_dtcm ? dmem_we : 4'b0000),
        .a_addr (dmem_addr[DTCM_OFS_W-1:2]),
        .a_wdata(dmem_wdata),
        .a_rdata(dtcm_a_rdata),
        .b_req  (b_req),
        .b_addr (b_addr),
        .b_rdata(b_rdata)
    );

    // The DTCM answers one cycle after a read request; remember whether that request was the
    // DTCM's, so a load from MMIO or an unmapped address returns 0 (same policy as core_tb_top).
    // Reset to 0 so dmem_rdata is defined before the first load.
    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync)  dtcm_read_sel_q <= 1'b0;
        else if (dmem_re) dtcm_read_sel_q <= sel_dtcm;
    end
    assign dmem_rdata = dtcm_read_sel_q ? dtcm_a_rdata : 32'b0;

    // ---- SIM MMIO window ----------------------------------------------------------------------
    // dmem_we carries byte enables; the window only needs "a store happened" (SIM_CTRL takes a
    // full word, SIM_PUTC its low byte), so the enables are reduced to one bit.
    assign mmio_we    = sel_mmio && (dmem_we != 4'b0000);
    assign mmio_addr  = dmem_addr;
    assign mmio_wdata = dmem_wdata;

    // ---- MAC engine (spec 7.1) ----------------------------------------------------------------
    mac_engine #(
        .GATING_EN (GATING_EN)
    ) u_mac_engine (
        .cmd_valid (cmd_valid),
        .cmd_ready (cmd_ready),
        .cmd_op    (cmd_op),
        .cmd_addr  (cmd_addr),
        .cmd_k     (cmd_k),
        .cmd_clr   (cmd_clr),
        .rd_req    (rd_req),
        .rd_idx    (rd_idx),
        .rd_ready  (rd_ready),
        .rd_data   (rd_data),
        .csr_we    (csr_we),
        .csr_addr  (csr_addr),
        .csr_wdata (csr_wdata),
        .csr_rdata (csr_rdata),
        .b_req     (b_req),
        .b_addr    (b_addr),
        .b_rdata   (b_rdata),
        .clk       (clk),
        .rst_n     (rst_n_sync)
    );
endmodule
