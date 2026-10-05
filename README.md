# Mini-NPU — Senior Project 2 (HCMUTE)

A CoralNPU-inspired RISC-V NPU: power-aware design and UVM-based functional verification.
Design spec: `docs/superpowers/specs/2026-10-04-mini-npu-design.md`.

```
rtl/core/        5-stage core (StageIF, StageDecode, StageExecute, StageMemory, StageWriteBack)   [Track A]
rtl/npu/         MAC engine + clock gating                                                         [Track B]
rtl/mem/         ITCM / dual-port DTCM
rtl/top/         npu_top, npu_pkg
tb/uvm/          common, core_env [A], mac_env [B], soc_env [A+B]
tb/sva/          assertions
model/c/         npu_ref.c, rv_iss.c (+ tests)
model/py/        golden_int8.py, pack_weights.py, gen_matmul.py
sw/              firmware: crt0, link.ld, npu.h, tests/, mnist/, synthetic/
sim/xsim/        xsim scripts         sim/verilator/   Verilator scripts
power/           toggle counting + plots
notebooks/       marimo notebooks
docs/            spec, plans, notes, references/ (textbooks + reading guide)
tools/rv32i_check/  quick RV32I self-check for rtl/core (python tools/rv32i_check/run_all.py)
```
