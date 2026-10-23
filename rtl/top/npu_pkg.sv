`timescale 1ns / 1ps

// npu_pkg.sv - shared parameters, engine op codes and CSR addresses.
//
// Spec: docs/superpowers/specs/2026-10-04-mini-npu-design.md
//   4.2 parameters, 6.1 custom-0 ops, 6.4 CSRs, 7.1 engine interface.
// C mirror: model/c/npu_ref.h (NPU_KMAX, NPU_DTCM_BASE, NPU_OP_*, NPU_ST_*, NPU_CSR_*).
// Imported by every SV file in rtl/npu, rtl/top and tb/. Change a value here
// only together with the spec, npu_ref.h and docs/glossary.md.
//
// GATING_EN is NOT in this package: it must differ between the D0 and D1
// builds, so it is a module parameter of mac_engine / npu_top (plan Task 11).

package npu_pkg;

  // A package is a library: any one consumer uses only some of its constants, so Verilator's
  // UNUSEDPARAM is waived here (the only waiver in this file).
  /* verilator lint_off UNUSEDPARAM */

  // ---- 4.2 parameters --------------------------------------------------------
  localparam int unsigned PE_ROWS    = 4;      // N: output rows per tile
  localparam int unsigned PE_COLS    = 4;      // M: images per batch
  localparam int unsigned K_DOT      = 4;      // int8 lanes per PE per cycle (dot4); fixed
  localparam int unsigned KMAX       = 1024;   // largest K in int8 elements
  localparam int unsigned FIFO_DEPTH = 8;      // command FIFO entries

  localparam logic [31:0] DTCM_BASE  = 32'h0001_0000;
  localparam int unsigned DTCM_BYTES = 65536;

  // ---- derived geometry (6.2, 7.1) -------------------------------------------
  localparam int unsigned QUAD_BYTES  = 16;                    // 4 words x 4 lanes = one 128-bit entry
  localparam int unsigned PORT_B_W    = 8 * QUAD_BYTES;        // 128: DTCM port B and WBUF/IBUF entry width
  localparam int unsigned BUF_DEPTH   = KMAX / K_DOT;          // 256 quads per WBUF / IBUF
  localparam int unsigned BUF_IDX_W   = $clog2(BUF_DEPTH);     // 8
  localparam int unsigned DTCM_QUADS  = DTCM_BYTES / QUAD_BYTES; // 4096
  localparam int unsigned WORD_ADDR_W = $clog2(DTCM_BYTES / 4); // 14: DTCM port A word index a_addr[13:0]
  localparam int unsigned QUAD_ADDR_W = $clog2(DTCM_QUADS);    // 12: b_addr[11:0]
  localparam int unsigned RD_IDX_W    = $clog2(PE_ROWS * PE_COLS); // 4: rd_idx[3:0], idx = 4*i + j

  // ---- 7.1 command op, cmd_op[1:0] -------------------------------------------
  typedef enum logic [1:0] {
    OP_LDW     = 2'd0,   // LOAD_WEIGHT
    OP_LDI     = 2'd1,   // LOAD_INPUT
    OP_MAC     = 2'd2,   // COMPUTE
    OP_ILLEGAL = 2'd3    // reserved custom-0 funct3, engine sets err_illegal
  } npu_op_e;

  // ---- 6.4 CSR addresses, csr_addr[11:0] -------------------------------------
  localparam logic [11:0] CSR_NPU_STATUS   = 12'h7C0;
  localparam logic [11:0] CSR_NPU_BUSY_CYC = 12'h7C1;

  // ---- 6.4 npu_status bit positions ------------------------------------------
  localparam int unsigned ST_BUSY        = 0;    // RO
  localparam int unsigned ST_FIFO_EMPTY  = 1;    // RO
  localparam int unsigned ST_FIFO_FULL   = 2;    // RO
  localparam int unsigned ST_ERR_K       = 8;    // W1C, sticky
  localparam int unsigned ST_ERR_ADDR    = 9;    // W1C, sticky
  localparam int unsigned ST_ERR_ILLEGAL = 10;   // W1C, sticky
  localparam int unsigned ST_ERR_ALIGN   = 11;   // W1C, sticky

  // The four sticky error bits; the only writable bits of npu_status.
  localparam logic [31:0] ST_ERR_MASK =
      (32'd1 << ST_ERR_K) | (32'd1 << ST_ERR_ADDR) |
      (32'd1 << ST_ERR_ILLEGAL) | (32'd1 << ST_ERR_ALIGN);

  /* verilator lint_on UNUSEDPARAM */

endpackage : npu_pkg
