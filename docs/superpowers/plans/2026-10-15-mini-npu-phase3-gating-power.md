# Mini-NPU Phase 3 (Weeks 10–12) Implementation Plan: Clock Gating (D1) and Switching Activity

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project rule (overrides the line above for graded work):** the students write all RTL, golden-model logic, UVM and firmware themselves. Claude reviews against the tests named here. Tasks tagged **[support]** are non-graded tooling that Claude may write on request.

**Goal:** By the end of week 12, D1 (MAC-engine clock gating) is cycle-identical to D0 on every soc test (SC3), and the synthetic idle-ratio sweep E2 has produced M1/M2 switching-activity estimates for D0 and D1 (SC4, synthetic part).

**Architecture:** One `npu_clk_gate` (latch + AND, the pattern of CoralNPU `hdl/verilog/ClockGate.sv`, written by the team) gates `clk_mac`, which clocks WBUF, IBUF, the PE registers and the accumulators (§7.3, §8). D0 and D1 differ only in `GATING_EN`. An equivalence harness proves D1 = D0 before any power number is produced; then a VCD of `u_mac_engine`, taken only inside the firmware's measurement window, is reduced to toggle counts.

**Tech Stack:** SystemVerilog on QuestaSim (one simulator for both configurations, D1a), Python 3 (VCD parsing, CSV, matplotlib), RISC-V GCC.

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` §7.3, §8, §10.4, §10.5 (`cg_gate`), §10.6 (A-GATE-*), §11. Predecessor: `docs/superpowers/plans/2026-10-15-mini-npu-phase2-uvm-integration.md` (tag `phase2-d0` is the D0 baseline).

**Owners:** Track A = Nguyễn Hoàng Công Tấn, Track B = Nguyễn Thế Bảo.

| Task | Owner | Weeks |
|---|---|---|
| 20 · `npu_clk_gate` + D1 + gating SVA/coverage | Bảo | 10 |
| 21 · D0/D1 equivalence harness | Tấn (script), both run | 10–11 |
| 22 · Synthetic idle-ratio firmware | Tấn | 11 |
| 23 · Engine VCD window + `toggle_count.py` | Bảo | 11–12 |
| 24 · E2 runs, CSV, plots | Bảo (`plots.py` may be **[support]**) | 12 |

## Global Constraints (Phase 3 additions)

- Priority (project rule): SC3 before any switching-activity number. Tasks 22–23 may be written in parallel with Task 21, but E2 data (Task 24) is produced only after Task 21 passes.
- D0 = tag `phase2-d0` plus bug fixes only. D0 and D1 use the same binary, the same QuestaSim version and the same dump options (§11 fairness). `GATING_EN` is the only difference.
- Enable (§8): `en = !rst_n_sync || (fsm != IDLE) || !fifo_empty`, from registers only. Gating must add **zero** cycles: the first gated edge after a push arrives exactly when the FSM needs it.
- Metrics (§11): M1 = toggles of net `clk_mac`; M2 = toggles of all other nets in `u_mac_engine` (the clock nets `clk` and `clk_mac` are excluded, since M1 and the cycle count already cover them), split M2-free / M2-gated by clock domain (§7.3); both per 1,000 free-clock cycles inside the window. A toggle is any 0↔1 transition; transitions from or to x/z are not counted.
- Every figure and table states configuration, workload, seed and unit, and carries the label **"switching-activity estimate"**. The words "measured power" never appear.
- Each configuration is run once per workload; a rerun is allowed only after a logged external failure (§11).

## Review Focus

1. **Push in the cycle `en` falls:** a command pushed exactly when the engine has just gone idle must start in the same cycle as on D0. Test: Task 20 `mac_gate_push_on_fall`.
2. **READ_RESULT after a long gated idle:** accumulators are read combinationally while `clk_mac` is stopped (§7.3); the value must be the one computed before the idle period. Test: Task 20 `mac_gate_read_after_long_idle`.
3. **Equivalence harness that cannot fail:** comparing the wrong files, or empty logs, would "prove" equivalence trivially. Test: Task 21 `eq_selftest_detects` (three injected differences, each must be reported).
4. **Missing or wrong measurement window:** without `MEAS_START`/`MEAS_STOP` the tool must refuse, not count the whole run or nothing. Test: Task 23 `toggle_no_window_errors`.
5. **Idle ratio computed outside the window:** setup code before `MEAS_START` must not enter the ratio. Test: Task 22 `synthetic_ratio_in_window` (ratio from counters sampled at the markers).

---

### Task 20: `npu_clk_gate`, D1 configuration, gating assertions and coverage — Track B, week 10

**Files:**
- Modify: `rtl/prim/npu_clk_gate.sv` (latch transparent while `clk` low, then AND; `test_en` input; `/* verilator clock_enable */` on the latch output; `GATING_EN=0` ties `en` to 1 inside the cell, so D0 keeps the instance)
- Modify: `rtl/npu/mac_engine.sv` (`en` per §8; WBUF, IBUF, PE registers and accumulators on `clk_mac`; FIFO, FSM, CSRs, `npu_busy_cyc`, port-B counter on `clk`)
- Create: `tb/sva/gate_sva.sv` (A-GATE-1, A-GATE-2, `bind mac_engine`)
- Modify: `tb/uvm/mac_env/mac_coverage.sv` (`cg_gate`: en rise, en fall, en low exactly 1 cycle, en low ≥ 100 cycles; sampled only when `GATING_EN=1`)
- Create: `tb/directed/npu_clk_gate_tb.sv`
- Modify: `docs/mac_engine.md` (clock-domain table, en timing diagram for a push after idle)

**Interfaces:**
- Consumes: `mac_env` (Phase 2 Task 16), `run.py --config d0|d1` (`+define+GATING_EN=0|1`).
- Produces: `module npu_clk_gate #(parameter bit GATING_EN = 1) (input logic clk, en, test_en, output logic gclk);` and the net `u_mac_engine.clk_mac` (M1 is counted on this exact name).

- [ ] **Step 1: Write the failing tests:**
  - `npu_clk_gate_tb`: `en` low for cycles 10–19 → 0 rising edges of `gclk` in cycles 11–19, one per cycle elsewhere; with `GATING_EN=0` one edge every cycle; an `en` glitch while `clk` is high does not reach `gclk`
  - `mac_gate_push_on_fall` (Review Focus 1): idle the engine, then push on the first cycle `en` is low; the command's port-B request cycle (relative to the push) equals the D0 value
  - `mac_gate_read_after_long_idle` (Review Focus 2): COMPUTE, 500 idle cycles (gated), READ all 16 → equal to `npu_ref`
  - `mac_gate_idle_mix`: `mac_rand_seq` with inter-command gaps forced to {0, 1, 2, 150} cycles so that all `cg_gate` bins are hit
- [ ] **Step 2:** `run.py --target mac_gate --config d1` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `run.py --target mac_regress --config d1 --seeds 200 --cov` → 0 mismatches, 0 SVA failures (A-MAC-*, A-GATE-*), `cg_gate` 100 %; the same command with `--config d0` still green. Then `run.py --target regress_d1` (Phase 2 Task 19 suite) → green (SC1 on D1).
- [ ] **Step 5: Commit** `feat(npu): npu_clk_gate and D1 gating with assertions and cg_gate`.

---

### Task 21: D0/D1 equivalence harness — Track A (script), both run, weeks 10–11

**Files:**
- Create: `tools/eq/compare_runs.py`, `tools/eq/tests/test_compare_runs.py` (pytest, fabricated run directories)
- Modify: `tb/uvm/common/npu_rvvi_agent_pkg.sv` (`+RVVI_LOG=<file>`: one line per retire, `order pc insn rd rd_wdata mem_addr mem_wdata mem_wmask trap`, hex, fixed width)
- Modify: `tb/uvm/common/npu_sim_ctrl_monitor` (at end of test write `end.txt`: `mcycle=<dec> minstret=<dec>` read by backdoor from the core CSR registers; the hierarchical path is recorded by Track A in `docs/core_isa.md`)
- Modify **[support]**: `run.py --target eq_<suite>` = run `<suite>` with `--config d0` and `--config d1`, then `compare_runs.py`

**Interfaces:**
- Consumes: soc tests (Phase 2 Task 18), `soc_end_checker` LOGITS dump.
- Produces: `compare_runs.py <d0_dir> <d1_dir>` → exit 0 iff for every test: SHA-256 of `rvvi.log` equal, `end.txt` equal, `logits.hex` equal (if present). On failure prints the test, the first differing RVVI line number, and both counter values.

- [ ] **Step 1: Write the failing tests** (`test_compare_runs.py`, Review Focus 3):
  - `eq_selftest_pass`: two identical fabricated run directories → exit 0
  - `eq_selftest_detects`: three cases, each must exit 1 and name the field: one RVVI line differs; `mcycle` differs by 1; one LOGITS word differs
  - `eq_selftest_missing`: a test present in D0 but absent (or with an empty `rvvi.log`) in D1 → exit 1
- [ ] **Step 2:** `pytest tools/eq` → FAIL. **Step 3:** Implement. **Step 4:** pytest green.
- [ ] **Step 5:** `run.py --target eq_soc_all` → every soc test identical on D0 and D1 (SC3). A difference is a bug: root-cause it before considering the SC3 fallback (result-identical with a written reason in `docs/mac_engine.md`).
- [ ] **Step 6: Commit** `test: D0/D1 equivalence harness, SC3 on soc tests`.

---

### Task 22: Synthetic idle-ratio firmware — Track A, week 11

**Files:**
- Create: `sw/synthetic/main.c` (compile-time `-DIDLE_PCT={10,25,50,75,90}`, `-DBURSTS=20`)
- Modify: `sw/Makefile` (`make -C sw TEST=synthetic IDLE_PCT=50` → `sw/build/synthetic_50/…`)
- Create: `sw/synthetic/README.md` (how the busy-loop length is derived from the measured burst length)

**Interfaces:**
- Consumes: `npu.h`, `sim.h` (Phase 2 Task 13).
- Produces: firmware that, between `sim_meas_start()` and `sim_meas_stop()`, runs `BURSTS` × (LDW K=256 + LDI K=256 + COMPUTE K=256 clr=1 + READ_RESULT idx 0, then a scalar busy loop). It samples `mcycle` and `npu_busy_cyc` immediately after `sim_meas_start()` and before `sim_meas_stop()` and stores the two deltas at DTCM words `0x0001_DDF4` (`d_mcycle`) and `0x0001_DDF8` (`d_busy`) (first free words after §9.2).

- [ ] **Step 1: Write the failing test** `synthetic_ratio_in_window` (Review Focus 5): for each `IDLE_PCT`, the testbench reads the two words by backdoor and checks `|(1 − d_busy/d_mcycle)·100 − IDLE_PCT| ≤ 2`.
- [ ] **Step 2:** Run on D0 → FAIL. **Step 3:** Implement (calibrate the busy loop from one measured burst). **Step 4:** All five ratios within ±2 percentage points; `eq_synthetic` (Task 21 harness) identical on D0/D1.
- [ ] **Step 5: Commit** `feat(sw): synthetic idle-ratio workload`.

---

### Task 23: Engine VCD window and `toggle_count.py` — Track B, weeks 11–12

**Files:**
- Modify: `tb/uvm/tb/npu_tb_top.sv` (under `+DUMP_ENGINE=<file>`: `$dumpfile(<file>)`, `$dumpvars(0, u_dut.u_mac_engine)`, `$dumpoff` at time 0; `$dumpon` on `MEAS_START` (0x20), `$dumpoff` on `MEAS_STOP` (0x21); also dump the free clock `u_dut.u_mac_engine.clk` for cycle counting). SV system tasks, so the same flow works on Verilator if D1a is ever invoked.
- Create: `power/net_domains.yaml` (instance-path prefixes → `free` | `gated`, from §7.3)
- Create: `power/toggle_count.py`, `power/tests/test_toggle_count.py`, `power/tests/vcd/*.vcd` (hand-written)

**Interfaces:**
- Produces: `toggle_count.py <vcd> --domains power/net_domains.yaml --config d0|d1 --workload <name> --seed <n>` → appends one CSV row to stdout:
  `config,workload,seed,cycles,m1,m2_free,m2_gated,m1_per_kcyc,m2_per_kcyc,label` with `label = "switching-activity estimate"`. `cycles` = rising edges of the free clock inside the window. Streaming parser (line by line), so file size is bounded by disk, not RAM.

- [ ] **Step 1: Write the failing tests:**
  - `toggle_known_counts`: a hand-written VCD with 10 free-clock cycles, `clk_mac` running 6 of them, one gated-domain data net with 3 transitions and one free-domain data net with 4 transitions → `cycles=10, m1=12, m2_gated=3, m2_free=4`
  - `toggle_ignores_x_to_value`: the initial `x→0/1` assignment at the first `$dumpon` is not a toggle
  - `toggle_no_window_errors` (Review Focus 4): a VCD with no `$dumpon` section, or an empty file → exit 2 with message `no measurement window`
  - `toggle_unmapped_net_errors`: a net whose path matches no prefix in `net_domains.yaml` → exit 2 naming the net
- [ ] **Step 2:** `pytest power/tests` → FAIL. **Step 3:** Implement. **Step 4:** pytest green.
- [ ] **Step 5:** Smoke: `synthetic` with `IDLE_PCT=50` on D0 and D1 produces two rows; sanity check documented in the commit message: D0 `m1_per_kcyc` ≈ 2,000 (two edges per cycle), D1 `m1_per_kcyc` within 10 % of 2,000 × busy fraction.
- [ ] **Step 6: Commit** `feat(power): engine VCD window and toggle counter`.

---

### Task 24: E2 data, plots, results table — Track B (plots **[support]** on request), week 12

**Files:**
- Create: `power/plots.py` (CSV → `out/<date>/e2/fig_m1.png`, `fig_m2.png`, `fig_change.png`)
- Modify **[support]**: `run.py --target e2` = 5 ratios × {d0, d1} with `+DUMP_ENGINE`, then `toggle_count.py`, then `plots.py`
- Create: `out/<date>/e2/e2.csv`, `docs/results/e2.md` (table: ratio, M1/M2 per kcycle for D0 and D1, % change; run date, git hash, QuestaSim version, seeds)

**Interfaces:**
- Consumes: Tasks 21–23.
- Produces: `docs/results/e2.md` and figures used by the Phase 4 report chapter; the E2 curve used by the Phase 4 E4 cross-check (§11).

- [ ] **Step 1: Check the gate:** `run.py --target eq_soc_all` and `eq_synthetic` green on the current commit. If not, stop (project priority).
- [ ] **Step 2:** `run.py --target e2` → 10 runs, 10 CSV rows.
- [ ] **Step 3:** Each figure shows configuration, workload, seed, unit and the label "switching-activity estimate"; `% change = (D1 − D0) / D0 × 100` per metric and ratio.
- [ ] **Step 4:** Write `docs/results/e2.md`: numbers only plus one paragraph on what M1 vs M2 show (M1 ≈ busy fraction; M2 reflects data activity, §11). No claim in mW.
- [ ] **Step 5: Commit** `data: E2 synthetic switching-activity sweep` and tag `phase3-d1`.

## Phase 3 exit checklist

- [ ] SC1 on D1: `run.py --target regress_d1` green, 0 SVA failures, `cg_gate` 100 %
- [ ] SC3: `eq_soc_all` and `eq_synthetic` identical (or the documented fallback with root cause)
- [ ] SC4 (synthetic): `docs/results/e2.md` and figures, all labelled "switching-activity estimate"
- [ ] Review Focus tests 1–5 behave as stated
- [ ] Tag `phase3-d1` pushed; `manifest.yaml` updated
