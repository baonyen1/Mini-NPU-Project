`timescale 1ns / 1ps

// npu_dpi_pkg.sv - the only place in tb/ that imports DPI-C (CLAUDE.md section 5, Phase 2 plan).
// Signatures mirror model/c/npu_ref.h one to one; uint32_t maps to int unsigned. A DPI function
// cannot return bit [31:0] on QuestaSim 10.7c (vlog-2572, docs/smoke/results.md S2), so the returns
// are int unsigned. Link model/c/npu_ref.c: QuestaSim -sv_lib <dll>, Verilator on the command line.
// Phase 2 adds the rv_iss imports (iss_init, iss_step) here.
package npu_dpi_pkg;

  import "DPI-C" function void         npu_ref_reset();
  import "DPI-C" function void         npu_ref_mem_write(input int unsigned word_idx, input int unsigned data);
  import "DPI-C" function void         npu_ref_cmd(input int unsigned op, input int unsigned addr,
                                                   input int unsigned k, input int unsigned clr);
  import "DPI-C" function int unsigned npu_ref_read(input int unsigned idx);
  import "DPI-C" function int unsigned npu_ref_status();
  import "DPI-C" function void         npu_ref_csr_write(input int unsigned addr, input int unsigned data);
  import "DPI-C" function int unsigned npu_ref_csr_read(input int unsigned addr);

endpackage : npu_dpi_pkg
