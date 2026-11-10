# Chapter: Verification (draft)

Draft of the verification chapter (plan Phase 2 Task 19 Step 4, decision D12: English). Each student writes
the section of their own environment; `soc_env` is written together. Every number in the `mac_env`
section was measured on 2026-11-10 with QuestaSim 10.7c and UVM 1.2 through `run.py`; the run
directories are named where the numbers come from. `out/` is not committed (CLAUDE.md §5); the SHA-256
of every log is in each run directory's `manifest.yaml`. The few numbers from an earlier session
(2026-11-07, §1.3 and §1.6) are marked as such and name the line of the local work ledger they come
from.

## 1. mac_env: the MAC engine environment (Track B)

### 1.1 Environment

`mac_env` (`tb/uvm/mac_env/`, spec §10.1) verifies `mac_engine` alone, through the ports of spec §7.1.

| Component | Role |
|---|---|
| `cmd_agent` (active) | drives PUSH (the `cmd_*` handshake), READ_RESULT (`rd_req` until `rd_ready`), CSR reads and CSR writes; its monitor turns every clock edge into transactions in the order the golden model must apply them within one cycle: reset, CSR read, READ, CSR write, pop, push |
| `dtcm_agent` (reactive) | the DTCM port-B responder (16,384 words); every write also goes to the golden model, and a write while the engine is not drained is an error (`WAR_RULE`, spec §6.3 rule 5) |
| predictor | calls `npu_ref` through DPI-C; applies each command when the engine pops it (the CHECK cycle), with a CSR write of the same cycle before it (D23), so `npu_status` can be compared at any time |
| scoreboard | compares every READ_RESULT and every `npu_status` read with `npu_ref`, flags X/Z values, and checks the read-only status bits against the ports of the same cycle |
| coverage | the spec §10.5 groups `cg_cmd`, `cg_operand`, `cg_fifo`, `cg_state`, `cg_acc`, `cg_err`, `cg_addr` (`cg_gate` comes with Phase 3) |
| SVA | A-MAC-1..5 (spec §10.6), bound into the engine (`tb/sva/mac_engine_sva.sv`) |

End of test: every test ends with all 16 results and `npu_status` compared once more, and `check_phase`
compares the responder memory with `npu_ref`'s DTCM image over all 16,384 words. A watchdog
(`+TIMEOUT_CYC`, default 1,000,000 cycles) turns a hang into a failure. A run passes when the log has
`UVM_ERROR : 0`, `UVM_FATAL : 0`, no simulator error and the UVM report summary; an expected-fail test
must fail with exactly its listed error IDs (`run.py`, `sim/tests.yaml`).

### 1.2 Golden model and oracle gate

`npu_ref` (`model/c/npu_ref.c`, spec §10.2) is the reference: `npu_ref_reset`, `npu_ref_mem_write`,
`npu_ref_cmd`, `npu_ref_read`, `npu_ref_status`, `npu_ref_csr_write`, `npu_ref_csr_read`. It is untimed: it
executes a command completely when it is called. The predictor therefore calls it at the cycle the RTL
starts the command, which makes its error bits cycle-aligned with the RTL's.

Spec §10.2 allows a golden model to act as an oracle only after its own unit tests pass. On 2026-11-10
`model/c/tests/test_npu_ref.c` (hand-computed 4×4 cases, wrap on overflow, every error case, W1C, CSR
reads) passed 24 of 24 cases, built with the Windows UBSan-trap flags of `model/c/Makefile`
(`npu_ref: all tests passed`).

`npu_busy_cyc` is not modelled by `npu_ref` (spec §10.2 masks it). Its behaviour is checked by the
directed test `mac_busy_cyc` and, since Task 19, by a write-and-read-back step in `mac_rand` (§1.5).

### 1.3 Tests and results

The regression is the suite `mac_regress` = `mac_directed` (24 tests, each run once) + `mac_rand` (seeds
1..200, `-sv_seed N`, 400 random steps per seed):

```
python run.py --target mac_regress --config d0 --cov     # out/2026-11-10/d0/223537-mac_regress
python run.py --target mac_regress --config d1           # out/2026-11-10/d1/223540-mac_regress
```

Both ended `224/224 runs as expected` and `RESULT: PASS`. The dv-verifier reproduced both in the same
session with the same commands: `out/2026-11-10/d0/225639-mac_regress` (D0, `--cov`) and
`out/2026-11-10/d1/231112-mac_regress` (D1); the `manifest.yaml` of each of the four run directories has
224 entries with `matches_expectation: true` and none with `false`. The table below is from the first two.
"Comparisons" are the scoreboard's checks against `npu_ref` and the ports (`[SCB]` line of each log); the
counts are identical in D0 and D1.

| Test | What it shows (spec §10.3 row or reason) | Expect | D0 | D1 | Comparisons |
|---|---|---|---|---|---|
| `mac_single_k4` | hand-computed 4×4 case, K = 4 | pass | pass | pass | 64 |
| `mac_k_kmax` | K = KMAX, random and all −128 operands | pass | pass | pass | 87 |
| `mac_k0` | K = 0 is a no-op for LDW, LDI, MAC | pass | pass | pass | 387 |
| `mac_k_too_big` | K > KMAX: err_k, command dropped | pass | pass | pass | 753 |
| `mac_k_mod4` | K not a multiple of 4: err_k | pass | pass | pass | 936 |
| `mac_misaligned` | a[3:0] ≠ 0: err_align; K checked first (D16) | pass | pass | pass | 570 |
| `mac_addr_oob` | out-of-range LOADs and the legal edges | pass | pass | pass | 687 |
| `mac_addr_wraps_32bit` | a + 4K beyond 2^32 is err_addr | pass | pass | pass | 387 |
| `mac_illegal` | ILLEGAL sets err_illegal only (D16) | pass | pass | pass | 1,485 |
| `mac_clr_vs_accum` | clr vs accumulate, clr over several steps | pass | pass | pass | 175 |
| `mac_forced_wrap` | accumulator wrap in both directions (D5) | pass | pass | pass | 208 |
| `mac_fifo_full` | FIFO fills, the tenth push waits | pass | pass | pass | 48 |
| `mac_read_while_busy` | READ_RESULT waits for the drain | pass | pass | pass | 44 |
| `mac_w1c` | W1C of each error bit; set while set | pass | pass | pass | 102 |
| `mac_w1c_inflight` | a W1C before CHECK does not clear a queued error | pass | pass | pass | 33 |
| `mac_d23` | set wins over a same-cycle W1C (D23) | pass | pass | pass | 49 |
| `mac_busy_cyc` | `npu_busy_cyc` counts busy cycles; a write wins (D17) | pass | pass | pass | 2,618 |
| `mac_addr_cov_dropped` | self-check of `cg_addr` first_quad | pass | pass | pass | 28 |
| `mac_mem_mirror_check` | DTCM-wide workload; end-of-test mirror check | pass | pass | pass | 65 |
| `mac_mem_mirror_inject` | self-test of the mirror check | fail `MEM_MIRROR` | as expected | as expected | 66 |
| `mac_war_inject` | self-test of the WAR check | fail `WAR_RULE` | as expected | as expected | 23 |
| `mac_unwritten_entry_flagged` | a COMPUTE reading unwritten entries is a test error | fail `UNWRITTEN_ENTRY` | as expected | as expected | 5 |
| `mac_k_cross` | every op × K bin × K mod 4 cell, error bits checked (Task 19) | pass | pass | pass | 898 |
| `mac_reset_midrun` | reset during a LOAD: no spurious `cg_state` transition (Task 19) | pass | pass | pass | 82 |
| `mac_rand`, 200 seeds | random mix (below) | pass | 200/200 | 200/200 | 71,532 |
| **Total** | 224 runs | | 224/224 | 224/224 | **81,332, 0 mismatches** |

`mac_rand` draws LDW 30 / LDI 30 / MAC 30 / ILLEGAL 2 / READ 8 (the plan's mix), CSR reads 3 and CSR
writes 2, and since Task 19 two targeted steps of weight 2 each:

- **D23 step:** drain, push one erroneous command, write `npu_status` (W1C, including that command's bit)
  in exactly its CHECK cycle, read `npu_status` in the next cycle. The set must win (D23) and every other
  named bit must clear. Over the 200 seeds there were 1,427 such steps (1 to 13 per seed); every seed had
  at least one, and the predictor saw a W1C meet the CHECK edge of the command it named 1,434 times
  (the extra 7 come from the ordinary random CSR writes). Source: the `[MAC_RAND] D23 steps` line and
  the `[PRED]` line (`W1C of an error bit at the CHECK edge that sets it (D23)`) of the 200 logs
  `out/2026-11-10/d0/223537-mac_regress/mac_rand/<seed>/sim.log`. For comparison only: on the
  `mac_rand` stimulus of 2026-11-07 (Task 16b, before the D23 step existed), a D23 hit occurred in
  about 5 % of the seeds (10 of the 200 gate seeds, 11 hits), measured then and recorded in the local,
  uncommitted work ledger `.superpowers/sdd/2026-10-15-mini-npu-phase2-uvm-integration/progress.md`
  (Task 16b ruling on the clear-wins mutant) and its `task-16b-report.md`. That stimulus differs from
  today's, so the two rates are not a like-for-like measurement.
- **BUSY_WR step:** write a random value to `npu_busy_cyc` at a random point and read it in the next
  cycle; it must read back exactly (D17: the write wins over that cycle's increment). 1,369 steps over
  the 200 seeds (1 to 16 per seed; the `[MAC_RAND]` line of the same logs). How many of these writes
  fall in a busy cycle, where the write-vs-increment priority matters, was not measured per seed.

In all 200 seeds the start-of-test measurement put the CHECK cycle 1 cycle after a push into the drained
engine (`[D23] CHECK cycle:` line of each log); the D23 step relies on that measurement (§1.7 (a)).

### 1.4 Functional coverage

The 224 UCDBs of the D0 run were merged and reported with

```
vcover merge -suppress 6854 -out out/2026-11-10/d0/223537-mac_regress/cov/merged.ucdb out/2026-11-10/d0/223537-mac_regress/*/*/cov.ucdb
vcover report -details out/2026-11-10/d0/223537-mac_regress/cov/merged.ucdb
```

(`-suppress 6854`: all seeds of `mac_rand` share one test name; ⚠️ unverified whether this loses per-test
attribution, the totals are unaffected.) Result: `TOTAL COVERGROUP COVERAGE: 100.00%  COVERGROUP TYPES: 7`.
The dv-verifier repeated the merge (same flags, 224 UCDBs) on its own D0 run
`out/2026-11-10/d0/225639-mac_regress` and got the same `TOTAL COVERGROUP COVERAGE` line; both merges
end `Errors: 0, Warnings: 0` (`cov/merge.log`).

SC2 evidence. The files are under `out/` and not committed, so their SHA-256 (`sha256sum`, 2026-11-10)
is recorded here; a UCDB holds a time stamp, so a new merge of the same inputs gives a new hash.

| File | SHA-256 |
|---|---|
| `out/2026-11-10/d0/223537-mac_regress/cov/merged.ucdb` | `52710332a756af0719ca87b593c2deba54dc6f8dc164d0bd2030ec1a39e2a869` |
| `out/2026-11-10/d0/223537-mac_regress/cov/report_details.txt` | `d278a2cf06529dcc7b6d46a3a22d1d1593da267e0e9de1de4bea9eeaa5553fb8` |
| `out/2026-11-10/d0/223537-mac_regress/cov/rand_only.ucdb` | `c583cccdb3e2f0c31b80060b6c52223829e5564e0502027c734d2ff5873eccfb` |
| `out/2026-11-10/d0/225639-mac_regress/cov/merged.ucdb` | `a5022968025c2a044cfe7e486383e92abd44c83ff7fa3751340e61d985d67afc` |
| `out/2026-11-10/d0/225639-mac_regress/cov/report_details.txt` | `445b0fbaf7213598a3f711eda27af3c00586bbcc501c5a972dbb63f3534db9fb` |

(The dv-verifier wrote its merge and report to a scratch directory; they were copied unchanged, same
SHA-256, into `225639-mac_regress/cov/` next to the run they merge.)

| Group (spec §10.5) | Bins covered / declared | Coverage | Closed by |
|---|---|---|---|
| `cg_cmd` (op × K bin × K mod 4; MAC × clr × acc non-zero) | 94 / 94 | 100 % | `mac_k_cross` closes the whole op × K × mod cross deterministically; random adds the rest |
| `cg_operand` (buffer × lane × value) | 216 / 216 | 100 % | random (corner-biased operands) |
| `cg_fifo` | 6 / 6 | 100 % | random, `mac_fifo_full` |
| `cg_state` | 7 / 7 | 100 % | random, directed |
| `cg_acc` (wrap positive→negative, negative→positive) | 2 / 2 | 100 % | `mac_forced_wrap` only (below) |
| `cg_err` (bit × set / set while set / W1C clear) | 19 / 19 | 100 % | random, `mac_w1c` |
| `cg_addr` | 8 / 8 | 100 % | random, `mac_addr_oob` |
| `cg_gate` (D1 only) | — | — | declared in Phase 3 |

The only zero-count line in the detailed report is `cg_cmd`'s `ignore_bins fixed` (K = 0 or K = KMAX
with K mod 4 ≠ 0, which no K can produce). `docs/coverage_exclusions.md` lists no exclusion.

**`cg_acc`.** It is sampled by the predictor after every executed COMPUTE without clr whose result
crosses zero the wrong way for the sign of the value added. One COMPUTE adds at most
1024 · 128 · 128 = 2^24, so a wrap needs at least 128 COMPUTEs of K = KMAX with extreme operands and no
clr in between; with clr drawn 50 % of the time, random stimulus practically never gets there. A merge
of the 200 `mac_rand` UCDBs alone (`out/2026-11-10/d0/223537-mac_regress/cov/rand_only.ucdb`) gives
`cg_acc` 0 % and every other group 100 % (`cg_cmd` included, with the caveat of §1.7 (d)). `mac_forced_wrap` drives both directions (16 hits each, one per
accumulator) and is part of `mac_regress`, so the merged figure is 100 %. The earlier "0 %" was a
merge of the random seeds only, not a sampling defect.

**Reset and `cg_state`.** A covergroup keeps its transition history across samples. Before Task 19 no
sample was taken during reset, so the last state before a reset and IDLE after it formed a transition
(for example a LOAD cut by reset counted as LOAD→IDLE). `mac_coverage` now samples a reset marker that
no bin uses while `rst_n` is low; `mac_reset_midrun` failed before this change (`cg_state.cp_tr 50.00%,
expected 33.33%`) and passes after it.

### 1.5 Assertions

| ID | Property (spec §10.6) | How it is checked |
|---|---|---|
| A-MAC-1 | no FIFO push while full; no pop while empty | `a_mac1_push`, `a_mac1_pop`, plus `a_mac1_count` (count never above `FIFO_DEPTH`) |
| A-MAC-2 | `rd_ready \|-> (fifo_empty && fsm == IDLE)` | `a_mac2` |
| A-MAC-3 | `b_req` only in LOAD; `b_addr` within the DTCM | `a_mac3_state`, `a_mac3_addr`, plus `a_mac3_quad`: the n-th read of a LOAD is quad (addr − DTCM_BASE)/16 + n |
| A-MAC-4 | buffers are never written outside LOAD | `a_mac4` on the WBUF/IBUF write strobe |
| A-MAC-5 | every popped command returns to IDLE within K/4 + 3 cycles | `a_mac5`, bound taken from the FIFO head in CHECK |

Every assertion reports `UVM_ERROR` with its ID, so any failure fails the test under the pass rule.
`tb/sva/mac_engine_sva.sv` has 9 assertions and 6 `cover property` directives: not every assertion has a
cover of its own, but each A-MAC ID has at least one (`c_mac1_full`, `c_mac2`, `c_mac3` and
`c_mac3_burst`, `c_mac4`, `c_mac5`). An A-MAC ID whose behaviour is never exercised therefore shows up
as an uncovered directive; an individual assertion without a cover of its own (for example `a_mac1_pop`
or `a_mac3_addr`) is not checked for vacuity this way.

In the merged D0 database (`vcover report -details -assert -directive`, saved as
`out/2026-11-10/d0/223537-mac_regress/cov/report_assert.txt`): the 9 `a_mac*` assertions
have failure count 0 (the tenth assertion the tool counts is an immediate assertion inside `uvm_pkg`,
also 0 failures; `vcover report -details -assert` of the same database, without `-directive`, prints
`TOTAL ASSERTION COVERAGE: 100.00%  ASSERTIONS: 10`, re-run on 2026-11-10), and all 6 cover directives are covered
(`TOTAL DIRECTIVE COVERAGE: 100.00%  COVERS: 6`), for example `c_mac1_full` (FIFO full) 2,239,247 cycles
and `c_mac5` (a command leaves CHECK for LOAD or MAC) 56,280 times.

### 1.6 Evidence that the checks can fail

A check that cannot fail proves nothing. Each check added in Task 19 was run against a deliberately
broken copy. The `mac_engine` mutants were run by the dv-verifier on scratch copies of
`rtl/npu/mac_engine.sv` on 2026-11-10; the two testbench rows on scratch copies of the named testbench
files the same day. None of these copies or their logs is committed; the committed RTL is unchanged.

| Mutant (scratch copy) | Run | Result |
|---|---|---|
| `mac_engine`: W1C wins over a same-cycle set, `err_q <= (err_set \| err_q) & ~err_clr` (violates D23) | `mac_rand`, seeds 1..20 | 20/20 seeds fail (`D23`, `MISMATCH`) |
| `mac_engine`: increment wins over a write in a busy cycle (violates D17) | `mac_rand`, seeds 1..20 | 20/20 seeds fail (`BUSY_CYC`) |
| `mac_engine`: K = 0 checked before ILLEGAL (violates D16) | `mac_rand`, seeds 1..20; `mac_k_cross` | `mac_rand`: 4/20 seeds fail; `mac_k_cross` fails (`ERRBITS`, `MISMATCH`) |
| `mac_engine`: K = KMAX + 4 accepted as legal | `mac_rand`, seeds 1..20; `mac_k_cross` | `mac_rand`: 8/20 seeds fail; `mac_k_cross` fails |
| `mac_engine`: err_addr checked before err_align (violates the D16 order) | `mac_rand`, seeds 1..20 | 19/20 seeds fail |
| `mac_seq_lib`: the D23 step's W1C one cycle late | `mac_rand`, seeds 1..2 | both fail (`D23`: busy earlier than measured, bit clear) |
| `mac_coverage` before the reset-marker fix | `mac_reset_midrun` | fails (`COV_STATE`, 50 % instead of 33.33 %) |

Three mutants survive in part of the random seeds. K = 0 before ILLEGAL (16 of 20 seeds) and
K = KMAX + 4 (12 of 20) are rare corners of the random K mix; the directed `mac_k_cross` catches both
every time and is part of `mac_regress` for that reason. err_addr before err_align survives in 1 of 20
seeds; no directed test was run against that mutant.

Before Task 19, on the `mac_rand` stimulus of 2026-11-07 (measured then; local, uncommitted ledger
`.superpowers/sdd/2026-10-15-mini-npu-phase2-uvm-integration/progress.md`, Task 16b entries, with
`task-16b-verify.md` and `task-16b-report.md` in the same directory): in the dv-verifier's 33 seeds,
`mac_rand` caught neither the W1C-wins (D23) nor the increment-wins (D17) mutant, while the directed
`mac_d23` and `mac_busy_cyc` caught both; after the Task 16b fix (an `npu_status` read right after a
W1C), `mac_rand` caught the W1C-wins mutant in 9 of its 200 gate seeds, which were 9 of the 10 seeds
with a D23 hit. No figure for the increment-wins mutant over the 200 seeds was recorded then. That
stimulus differs from today's, so these figures describe the earlier sequence only.

### 1.7 Limitations of the random stimulus

These are known gaps of `mac_rand` as it stands; none is closed by changing the stimulus here, because
any change of a weight or constraint would change every seed and invalidate the 200-seed results above.

- **(a) The D23 step starts from an empty FIFO.** It drains (a READ) before its push, so a W1C that
  meets the CHECK edge while other commands are queued behind the erroneous one is never exercised by
  the step. The CHECK delay it measures at the start of each seed (1 cycle in all 200 seeds, §1.3) is
  valid for one command pushed into an empty FIFO; spec §6.4 does not fix CHECK to one cycle after a
  push, so the step depends on this RTL's timing and fails (`D23`) rather than passing silently if the
  timing changes.
- **(b) Biased "random" values in the targeted steps.** The D23 and BUSY_WR steps are drawn by the same
  `randomize()` call as every step, so `csr_addr` and `w1c_all` are drawn for them too, although they do
  not use `csr_addr`. Constraint `c_csr` then forces `csr_wdata = ST_ERR_MASK` (`0x0000_0F00`) whenever
  `csr_addr` is `npu_status` (weight 70 of 100 outside CSR writes) and `w1c_all` is 1 (25 %), that is in
  about 17.5 %, roughly a sixth, of those steps. In a D23 step the W1C then names all four error bits; in
  a BUSY_WR step the value written to `npu_busy_cyc` is `0x0000_0F00` instead of a random value.
- **(c) The summary line does not count the D23 pushes.** Each D23 step pushes one command (a quarter of
  them ILLEGAL), but `n_push`, the K-bin counts and the illegal-K percentage of the `[MAC_RAND]` summary
  line count only the ordinary command steps, so the mix those numbers show is not the whole mix pushed.
- **(d) "Random-only `cg_cmd` 100 %" slightly overstates random reach.** `measure_check_delay` pushes
  one COMPUTE with K = 0 at the start of every seed, and `cg_cmd` samples it like any command, so the
  cells it hits are covered in `rand_only.ucdb` whatever the random steps do. `mac_k_cross` closes those
  cells deterministically anyway, so the merged 100 % does not depend on it.
- **(e) `npu_busy_cyc` after reset is not checked.** Spec §6.4 does not specify the reset value of
  `npu_busy_cyc`, so `mac_reset_midrun` does not check it.

## 2. core_env (Track A)

> **Placeholder, to be written by Tấn (Task 17).** Environment, `rv_iss` and its oracle gate, test list
> with pass counts, `Cvgrp_*` coverage, A-CORE-1.

## 3. soc_env (joint)

> **Placeholder, to be written by both students (Task 18).** Full-system co-simulation with `rv_iss` in
> `ISS_FULL`, A-SOC-1, the matmul and layer tests, and the D0/D1 equivalence harness (spec §10.4).

## 4. Relation to CoralNPU

> **Placeholder, to be written by both students** from the spec §16 table (the verification row).
