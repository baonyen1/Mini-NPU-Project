// mac_env compile list (Phase 2 Task 16). Paths are relative to the repository root. Compile and run it
// through run.py (python run.py --target mac_directed): a plain `vlog -sv -f tb/uvm/mac_env/mac_dv.f` gets
// UVM 1.1d, the mtiUvm of QuestaSim's own modelsim.ini. For UVM 1.2 by hand, do what run.py does: use a copy
// of <questa>/modelsim.ini whose mtiUvm line points to <questa>/uvm-1.2, set MODELSIM to that copy, and add
// +incdir+<questa>/verilog_src/uvm-1.2/src to vlog (the vsim log then shows UVM-1.2).
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
tb/sva/mac_engine_bind.sv
tb/uvm/mac_env/mac_cmd_agent_pkg.sv
tb/uvm/mac_env/mac_dtcm_agent_pkg.sv
tb/uvm/mac_env/mac_env_pkg.sv
tb/uvm/mac_env/mac_test_pkg.sv
tb/uvm/mac_env/mac_tb_top.sv
