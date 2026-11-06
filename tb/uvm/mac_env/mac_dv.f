// mac_env compile list (Phase 2 Task 16). Paths are relative to the repository root; run from there:
//   vlog -sv -f tb/uvm/mac_env/mac_dv.f      (QuestaSim; UVM 1.2 comes precompiled, docs/smoke/results.md S1)
// The DPI library is model/c/npu_ref.c (run.py builds it). Package order matters: npu_pkg first.
+incdir+tb/uvm/mac_env
rtl/top/npu_pkg.sv
rtl/prim/npu_clk_gate.sv
rtl/npu/cmd_fifo.sv
rtl/npu/pe_array.sv
rtl/npu/mac_engine.sv
tb/uvm/common/npu_dpi_pkg.sv
tb/sva/mac_engine_sva.sv
tb/uvm/mac_env/mac_cmd_if.sv
tb/uvm/mac_env/mac_dtcm_if.sv
tb/uvm/mac_env/mac_probe_if.sv
tb/uvm/mac_env/mac_cmd_agent_pkg.sv
tb/uvm/mac_env/mac_dtcm_agent_pkg.sv
tb/uvm/mac_env/mac_env_pkg.sv
tb/uvm/mac_env/mac_test_pkg.sv
tb/uvm/mac_env/mac_tb_top.sv
