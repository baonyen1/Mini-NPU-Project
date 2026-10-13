# Mini-NPU — Senior Project 2 (HCMUTE)

A CoralNPU-inspired RISC-V NPU: power-aware design and UVM-based functional verification.
Repository: https://github.com/baonyen1/Mini-NPU-Project
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

## Team workflow

Both students push to `main`. Every push and pull request runs the regression on GitHub Actions
(`.github/workflows/regression.yml`, results under the repo's **Actions** tab).

When a task is done, finish it with one command. It runs the regression, commits, rebases on the
teammate's latest commits, re-runs the regression and pushes. Nothing is pushed if a test fails.

```powershell
.\tools\finish_task.ps1 -Message "feat(core): complete RV32I base"     # Windows
tools/finish_task.sh "feat(core): complete RV32I base"                 # Linux/macOS
```

- Use the commit message given for the task in `docs/superpowers/plans/`.
- Docs-only changes: add `-SkipTests` (PowerShell) or `SKIP_TESTS=1` (bash).
- A test that is allowed to fail for now goes in `tools/rv32i_check/expected_failures.txt`.
  When you fix it, delete its line in the same commit, or the regression fails.
