// rtl/rtl.f - every synthesizable RTL file of npu_top, in compile order (plan Phase 2 Task 14).
// Paths are relative to the repository root: run the tool from there. Reused by every *_dv.f.
//   verilator --lint-only -Wall -f rtl/rtl.f --top-module npu_top
//   vlog -sv -f rtl/rtl.f
// Not listed: rtl/top/core_tb_top.sv and rtl/top/npu_stub.sv (core-only test harness),
// rtl/fpga/ (parked for the thesis).
// package first: dtcm_dp, the engine files and npu_top import it
rtl/top/npu_pkg.sv
// primitives
rtl/prim/npu_clk_gate.sv
// memories
rtl/mem/itcm.sv
rtl/mem/dtcm_dp.sv
// MAC engine
rtl/npu/cmd_fifo.sv
rtl/npu/pe_array.sv
rtl/npu/mac_engine.sv
// scalar core (Track A, Verilog-2001)
rtl/core/RISC_V_Top.v
rtl/core/StageDecode/Control.v
rtl/core/StageDecode/Controller.v
rtl/core/StageDecode/Hazard_Detection_Unit.v
rtl/core/StageDecode/Hazard_Unit.v
rtl/core/StageDecode/ID_EX_Reg.v
rtl/core/StageDecode/ImmGenerator.v
rtl/core/StageDecode/InstructionDecoder.v
rtl/core/StageDecode/Register.v
rtl/core/StageDecode/StageDecode_Top.v
rtl/core/StageExecute/ALU.v
rtl/core/StageExecute/ALUSrc_Mux.v
rtl/core/StageExecute/BRU.v
rtl/core/StageExecute/BitManip.v
rtl/core/StageExecute/Branch_Comparator.v
rtl/core/StageExecute/CSR_Unit.v
rtl/core/StageExecute/Divider.v
rtl/core/StageExecute/EX_MEM_Reg.v
rtl/core/StageExecute/Flushing_Unit.v
rtl/core/StageExecute/Forwarding_Mux.v
rtl/core/StageExecute/Forwarding_Unit.v
rtl/core/StageExecute/Jump_Target_Unit.v
rtl/core/StageExecute/Multiplier.v
rtl/core/StageExecute/StageExecute_Top.v
rtl/core/StageIF/IF_ID_Reg.v
rtl/core/StageIF/PCMux.v
rtl/core/StageIF/PCplus4.v
rtl/core/StageIF/ProgramCounter.v
rtl/core/StageIF/StageIF_Top.v
rtl/core/StageMemory/LSU.v
rtl/core/StageMemory/MEM_WB_Reg.v
rtl/core/StageMemory/StageMemory_Top.v
rtl/core/StageWriteBack/Address_Adder.v
rtl/core/StageWriteBack/StageWriteBack_Top.v
rtl/core/StageWriteBack/WriteBack_Mux.v
// SoC top
rtl/top/npu_top.sv
