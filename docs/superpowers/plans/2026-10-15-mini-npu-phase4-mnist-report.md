# Mini-NPU Phase 4 (Weeks 13–16) Implementation Plan: MNIST, E4, Reproducibility, Report

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project rule (overrides the line above for graded work):** the students write all RTL, golden-model logic, UVM and firmware themselves. Claude reviews against the tests named here. Tasks tagged **[support]** are non-graded tooling that Claude may write on request.

**Goal:** By the end of week 16, the 784-64-32-10 int8 MLP runs on `npu_top` bit-exact against `golden_int8.py` on 1,000 MNIST test images on D0 and D1 (SC5), the MNIST switching-activity run E4 is done, one command regenerates every result (SC6), and the English report and defence slides are submitted (D12).

**Architecture:** `pack_weights.py` turns the retrained export into DTCM images in the quad layout of §9.2; bare-metal firmware runs the per-layer loop of §9.3 with bit-identical requantization; the testbench drives the batch protocol of §9.4 and compares LOGITS files (D8). E4 reuses the Phase 3 dump/toggle flow on 100 images and is cross-checked against the E2 curve.

**Tech Stack:** Python 3 (numpy), bare-metal C (RISC-V GCC), SystemVerilog/UVM on QuestaSim, the Phase 2/3 tooling (`run.py`, `compare_runs.py`, `toggle_count.py`).

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` §9 (firmware, layout, requant, batch protocol), §11 (E4), §12 (reproducibility), D11, D12, SC5, SC6. Predecessor: `docs/superpowers/plans/2026-10-15-mini-npu-phase3-gating-power.md` (tag `phase3-d1`).

**Owners:** Track A = Nguyễn Hoàng Công Tấn, Track B = Nguyễn Thế Bảo.

| Task | Owner | Weeks |
|---|---|---|
| 25 · `pack_weights.py` + golden files | Bảo | 13 |
| 26 · MNIST firmware + host requant test | Tấn | 13–14 |
| 27 · `soc_mnist`: 1,000 images on D0 and D1 | both | 14 |
| 28 · E4: MNIST switching activity (100 images) | Bảo | 15 |
| 29 · Full 10,000-image run on D0 | both | 15 (cut first if late) |
| 30 · Reproducibility package | Claude **[support]** for `run.py all`; both verify | 15 |
| 31 · English report + slides | both | 13 → 16 |

## Global Constraints (Phase 4 additions)

- Model: 784-64-32-10 from the retrained notebook export (Phase 1 Task 2). The export files' SHA-256 values are recorded in `manifest.yaml`; every generated hex records the export hash it came from.
- DTCM layout exactly as §9.2 (bases, sizes, 16-byte alignment). W3 is padded from 10 to 12 rows with zeros; predicted labels are the argmax over rows 0–9 only.
- Requant (§9.3): `y = clamp((acc * M + 2^(S−1)) >>> S, 0, 127)` with bias inside `acc`; final layer keeps int32. Firmware uses only `mul`, `add`, `srai`, `max`, `min`.
- QP region (§9.2, 16 words at `0x1_CF30`): word 0 = M1, word 1 = S1, word 2 = M2, word 3 = S2, words 4–15 = 0.
- Batch protocol (§9.4) with one extension, recorded in `docs/mnist.md`: MAILBOX = 1 means "next batch ready", MAILBOX = 2 means "no more batches", after which the firmware writes `SIM_CTRL = PASS`.
- Image counts (D11): 1,000 for SC5 on D0 and D1; 100 for E4; 10,000 once on D0.
- Timeout for long runs: `+TIMEOUT_CYC = 10 × 12,000 × batches` (runner computes it); the Phase 2 default of 1M cycles must not apply to MNIST.
- For MNIST runs the lockstep ISS may be disabled with `+COSIM=0`; the oracle is the LOGITS file comparison (D8). Cosim stays on for the 1-batch test.
- Cut order if late (§15): drop Task 29, then reduce E4 to 20 images. SC3 on MNIST and the report are never cut.

## Review Focus

1. **Requant edge cases:** negative accumulators, exact half-way rounding, accumulators near the int32 bound found by `find_ms`. Expected: bit-identical to the notebook's `requant`. Test: Task 26 `requant_host_vectors`.
2. **State leaking across batches:** stale IBUF contents or accumulators from the previous batch must not affect the next one. Test: Task 27 `mnist_batch_order_independent`.
3. **Padding rows counted as classes:** rows 10–11 of W3 must be zero and ignored by argmax. Tests: Task 25 `pack_w3_padding_zero`, Task 27 comparator computes labels over rows 0–9.
4. **Export/hex drift after a retrain:** golden files and DTCM images generated from different exports would give a meaningless comparison. Test: Task 27 `mnist_export_hash_check` (run refuses to start on a hash mismatch).
5. **Long-run timeout and disk:** 1,000 images (≈3M cycles) must not hit the default timeout, and the E4 VCD must stay within the engine scope and window. Tests: Task 27 runs with the computed timeout; Task 28 records VCD size and fails if the dump contains nets outside `u_mac_engine`.

---

### Task 25: `pack_weights.py` and golden files — Track B, week 13

**Files:**
- Create: `model/py/pack_weights.py`, `model/py/tests/test_pack.py`
- Create (generated, not committed if large; hashes in `manifest.yaml`): `build/mnist/dtcm_model.hex`, `build/mnist/x_batch_<b>.hex`, `build/mnist/golden_logits_<N>.hex`, `build/mnist/labels_<N>.txt`, `build/mnist/mnist_cfg.h`
- Create: `docs/mnist.md` (layout table copied from §9.2 with the generated addresses, batch protocol incl. MAILBOX = 2, hashes)

**Interfaces:**
- Consumes: the retrained export in `model/py/export/` and `golden_int8.py`.
- Produces:
  - `pack_weights.py --export model/py/export --n {100,1000,10000} --out build/mnist`
  - `pack_tile(W_rows: np.ndarray[int8, (4, K)]) -> bytes` (quad s, word i = `W[i][4s..4s+3]`, lane t = byte t); `unpack_tile(b: bytes, K: int) -> np.ndarray`
  - `pack_inputs(X: np.ndarray[int8, (4, K)]) -> bytes` (byte offset `16s + 4j` holds `X[j][4s..4s+3]`)
  - `mnist_cfg.h`: region base macros (`W1_BASE` … `MAILBOX_ADDR`) and `N_BATCHES`

- [ ] **Step 1: Write the failing tests** (`test_pack.py`):
  - `pack_roundtrip`: `unpack_tile(pack_tile(W)) == W` for random W with K ∈ {784, 64, 32}
  - `pack_layer1_matches_golden`: layer-1 int32 results computed with numpy from the **packed** bytes equal `golden_int8.py` layer-1 for images 0–3
  - `pack_regions_match_spec`: every base equals the §9.2 address and is 16-byte aligned; total data = 56,816 B
  - `pack_w3_padding_zero` (Review Focus 3): rows 10–11 of W3 and their biases are 0
  - `pack_qp_words`: QP words 0–3 equal M1, S1, M2, S2 from `requant.json`; words 4–15 are 0
- [ ] **Step 2:** `pytest model/py/tests` → FAIL. **Step 3:** Implement. **Step 4:** green.
- [ ] **Step 5: Commit** `feat(model): pack_weights and golden files`.

---

### Task 26: MNIST firmware and host requant test — Track A, weeks 13–14

**Files:**
- Create: `sw/mnist/main.c` (batch loop, §9.4 + MAILBOX = 2), `sw/mnist/mlp.c`, `sw/mnist/mlp.h`, `sw/mnist/requant.c`, `sw/mnist/requant.h`
- Create: `sw/mnist/host/test_requant_host.c` (built with host gcc), `model/py/gen_requant_vectors.py` → `build/mnist/requant_vectors.txt`

**Interfaces:**
- Consumes: `npu.h`, `sim.h`, `mnist_cfg.h` (Task 25).
- Produces:
  ```c
  int32_t requant(int32_t acc, int32_t m, int32_t s);           /* §9.3; returns 0..127 */
  void layer(uint32_t in_addr, uint32_t w_addr, const int32_t *bias,
             uint32_t out_addr, uint32_t k, uint32_t n_out,
             int32_t m, int32_t s, int keep_int32);                /* §9.3 loop */
  ```

- [ ] **Step 1: Write the failing tests:**
  - `requant_host_vectors` (Review Focus 1): `gen_requant_vectors.py` emits ≥ 10,000 `(acc, M, S, y)` lines from the notebook's `requant`, including negative `acc`, `acc` values where `(acc·M) mod 2^S = 2^(S−1)` (half-way), and `|acc|` equal to each layer's `bound`; `test_requant_host` asserts every `y`
  - `mnist_1batch`: firmware on `npu_tb_top` with cosim on (`ISS_FULL`), images 0–3: LOGITS (12 × 4 int32) equal `golden_logits` rows 0–9 of those images
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** both green.
- [ ] **Step 5: Commit** `feat(sw): MNIST firmware with bit-exact requant`.

---

### Task 27: `soc_mnist` — 1,000 images on D0 and D1 — both, week 14

**Files:**
- Create: `tb/uvm/soc_env/soc_mnist_comparator.sv` (on `BATCH_DONE`: read LOGITS by backdoor, compare with `golden_logits_<N>.hex`, compute labels over rows 0–9, load next `x_batch_<b>.hex` by backdoor, write MAILBOX = 1, or 2 after the last batch)
- Modify: `tb/uvm/soc_env/soc_test_pkg.sv` (`soc_mnist` test: `+MNIST_N=<n>`, `+MNIST_DIR=build/mnist`, `+BATCH_ORDER=<file>` optional)
- Modify **[support]**: `run.py --target mnist_<n> [--config d0|d1]` computes `+TIMEOUT_CYC`; `run.py --target eq_mnist_1000`

**Interfaces:**
- Consumes: Tasks 25–26, `compare_runs.py` (Phase 3 Task 21).
- Produces: `out/<date>/<config>/mnist_<n>/{logits.hex, labels.txt, summary.txt}`; `summary.txt` = `images, mismatched_logits, label_matches, wall_s, kcycles_per_s`.

- [ ] **Step 1: Write the failing tests:**
  - `mnist_export_hash_check` (Review Focus 4): with a hex whose recorded export hash differs from `manifest.yaml`, the test stops before reset with `UVM_FATAL "EXPORT_HASH"`
  - `mnist_batch_order_independent` (Review Focus 2): 8 images run in batch order (1, 0) → per-image logits equal to the in-order run
  - `mnist_1000`: 250 batches, 0 mismatched logits, `label_matches` = golden's
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement.
- [ ] **Step 4:** `run.py --target mnist_1000 --config d0` and `--config d1` both 0 mismatches (SC5); `run.py --target eq_mnist_1000` identical including `mcycle` (SC3 on MNIST). Record `kcycles_per_s` in `manifest.yaml` (replaces the Coral-based estimate in §15).
- [ ] **Step 5: Commit** `test: MNIST 1,000 images bit-exact on D0 and D1`.

---

### Task 28: E4 — MNIST switching activity, 100 images — Track B, week 15

**Files:**
- Modify: `sw/mnist/main.c` (`sim_meas_start()` before batch 0, `sim_meas_stop()` after the last batch; reads `mcycle`/`npu_busy_cyc` deltas into `0x0001_DDF4`/`0x0001_DDF8` as in Phase 3 Task 22)
- Modify **[support]**: `run.py --target e4` (`mnist_100`, D0 and D1, `+DUMP_ENGINE`, `toggle_count.py`)
- Create: `power/cross_check.py` (E2 CSV + E4 CSV → interpolated E2 % change at the MNIST idle ratio, E4 % change, difference, and the E2 spread)
- Create: `docs/results/e4.md`

**Interfaces:**
- Consumes: Phase 3 Tasks 23–24 outputs (`e2.csv`), Task 27.
- Produces: `e4.csv` (same columns as `e2.csv`, `workload = mnist_100`), `docs/results/e4.md`.

- [ ] **Step 1: Write the failing test** `cross_check_known`: fabricated E2 points (10 %, 50 %, 90 %) and an E4 row at 30 % → `cross_check.py` reports the linearly interpolated value and the difference exactly as computed in the test.
- [ ] **Step 2:** `pytest power/tests` → FAIL. **Step 3:** Implement `cross_check.py`. **Step 4:** green.
- [ ] **Step 5:** `run.py --target e4` → 2 rows; check the VCD contains only `u_mac_engine` nets (Review Focus 5) and record its size in `docs/results/e4.md`.
- [ ] **Step 6:** Write `docs/results/e4.md`: MNIST idle ratio, M1/M2 for D0/D1, % change, cross-check against E2. All values labelled "switching-activity estimate".
- [ ] **Step 7: Commit** `data: E4 MNIST switching activity`.

---

### Task 29: Full 10,000-image run on D0 — both, week 15 (cut first if late)

**Files:**
- Create: `docs/results/mnist_full.md`

**Interfaces:**
- Consumes: Tasks 25–27 (`pack_weights.py --n 10000`).
- Produces: RTL test accuracy over 10,000 images.

- [ ] **Step 1:** `run.py --target mnist_10000 --config d0`.
- [ ] **Step 2:** Expected: 0 mismatched logits; RTL accuracy = golden int8 accuracy of the retrained model (recorded in spec §3.2 by Phase 1 Task 2). Record wall time, cycles and accuracy in `docs/results/mnist_full.md` and `manifest.yaml`.
- [ ] **Step 3: Commit** `data: MNIST full test set on RTL`.

---

### Task 30: Reproducibility package — Claude [support] for the runner, both verify, week 15

**Files:**
- Modify **[support]**: `run.py all` = `regress_d0`, `regress_d1`, `eq_soc_all`, `eq_synthetic`, `e2`, `mnist_1000` (d0, d1), `eq_mnist_1000`, `e4`; writes `out/<date>/hashes.txt` (SHA-256 of every CSV, figure, LOGITS file and coverage report)
- Modify: `README.md` (section "Reproduce": prerequisites with versions, the single command, expected run time per target, where results land)
- Modify: `manifest.yaml` (tool versions incl. QuestaSim licence type, git hash, seeds, export hashes)

**Interfaces:**
- Produces: SC6 evidence: a clean clone plus `run.py all` regenerates every number in `docs/results/` and the coverage reports.

- [ ] **Step 1: Test** `repro_clean_clone`: the student who did **not** write a given flow clones the repository into a new folder, follows README "Reproduce" only, runs `run.py all`.
- [ ] **Step 2:** Expected: exit 0; every CSV/LOGITS hash in the new `hashes.txt` equals the reference (figures may differ in metadata only; compare their CSV inputs).
- [ ] **Step 3:** Fix any missing step in README or runner; repeat until Step 2 holds.
- [ ] **Step 4: Commit** `chore: reproducibility package (SC6)` and tag `phase4-final`.

---

### Task 31: English report and defence slides — both, weeks 13 → 16 (D12)

**Files:**
- Create/extend: `docs/report/` (Markdown chapter drafts; converted to the faculty's required final format in week 16): `ch1_intro.md`, `ch2_background.md` (RISC-V, CoralNPU, clock gating, UVM), `ch3_architecture.md`, `ch4_core.md`, `ch5_engine.md`, `ch_verification.md` (drafted in Phase 2 Task 19), `ch7_power.md`, `ch8_mnist.md`, `ch9_coral_relation.md` (from spec §16), `ch10_conclusion.md`
- Create: `docs/report/slides/` (defence deck)

**Interfaces:**
- Consumes: `docs/results/{e2,e4,mnist_full}.md`, coverage reports, spec §16, `manifest.yaml`.
- Produces: the submitted report, slides and reproducibility package.

| Chapter | Writer | Draft by |
|---|---|---|
| 1, 2, 3, 9 | both | week 13 |
| 4 core, 8 MNIST | Tấn | 4: week 13; 8: week 15 |
| 5 engine, 7 power | Bảo | 5: week 13; 7: week 14 |
| verification | both (own env each, `soc_env` together) | week 10 (Phase 2) |
| 10 conclusion | both | week 15 |

- [ ] **Step 1 (week 13):** Report skeleton with every chapter heading and a one-paragraph intent each; figures list.
- [ ] **Step 2:** Each chapter drafted by its date. Functional evidence (ch. verification, ch. 8) and power evidence (ch. 7) stay in separate chapters; every power number carries "switching-activity estimate" and links to its CSV.
- [ ] **Step 3 (week 15):** Cross-review: each student reads the other's chapters and lists every claim without a pointer to a test, CSV or spec section; fix all.
- [ ] **Step 4 (week 16):** Slides; one rehearsal where each student answers questions on the **other** student's track (project rule: both can explain every design decision).
- [ ] **Step 5:** Submit report, slides and the reproducibility package; commit the final sources and tag `submitted`.

## Phase 4 exit checklist

- [ ] SC5: `mnist_1000` 0 mismatches on D0 and D1; `eq_mnist_1000` identical
- [ ] E4 done with cross-check (or reduced to 20 images under the cut rule, noted)
- [ ] Full 10,000-image run recorded, or explicitly cut with the reason noted
- [ ] SC6: `repro_clean_clone` passed; tag `phase4-final`
- [ ] Report and slides submitted; Review Focus tests 1–5 behave as stated
