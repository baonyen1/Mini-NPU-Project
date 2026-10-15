# Mini-NPU Phase 2 (Weeks 5–9) Implementation Plan: Integration, UVM, Coverage

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project rule (overrides the line above for graded work):** the students write all RTL, golden-model logic, UVM and firmware themselves. Claude reviews against the tests named here. Tasks tagged **[support]** are non-graded tooling that Claude may write on request.

**Goal:** By the end of week 9, `npu_top` (core + ITCM + DTCM + MAC engine) runs firmware, and three self-built UVM environments (`mac_env`, `core_env`, `soc_env`) pass every directed and random test with closed coverage on D0 (SC1, SC2).

**Architecture:** Integration first, with a plain SV testbench, so that interface bugs between the two tracks surface in week 5. The UVM environments are built in parallel and follow CoralNPU's public topology (D13): a passive RVVI agent plus a co-simulation checker that runs our C ISS in lockstep, backdoor program load, end of test on a completion signal or timeout. Directed tests first (weeks 5–6), random and coverage after (weeks 7–9).

**Tech Stack:** SystemVerilog + UVM 1.2 on Siemens QuestaSim (full licence; xsim fallback per Task 0), DPI-C (gcc), Verilator (lint), RISC-V GCC (`-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32`), Python 3.

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` (rev. 2026-10-15, D11–D13). § numbers refer to it. Predecessor plan: `docs/superpowers/plans/2026-10-04-mini-npu-phase1.md` (its Global Constraints apply unchanged and are not repeated).

**Owners:** Track A = Nguyễn Hoàng Công Tấn, Track B = Nguyễn Thế Bảo (Phase 1 owner table).

| Task | Owner | Weeks |
|---|---|---|
| 13 · Firmware base | Tấn | 5 |
| 14 · `npu_top` integration (non-UVM) | both (Tấn: top + firmware; Bảo: engine side) | 5–6 |
| 15 · Shared UVM layer + `run.py` | Claude **[support]** for `run.py`/`manifest.yaml`; Tấn: RVVI agent + cosim checker | 5 |
| 16 · `mac_env` | Bảo | 5–9 |
| 17 · `core_env` | Tấn | 5–9 |
| 18 · `soc_env` | both | 6–9 |
| 19 · Coverage closure, Phase 2 sign-off, report chapter draft | both | 9–10 |

## Global Constraints (Phase 2 additions)

- Entry condition: Phase 1 exit checklist green. If `rv_iss.c` (Task 12) slipped, Task 17 starts with directed tests only and switches to lockstep in week 6 (Phase 1 schedule risk).
- UVM topology and names (D13, §10.1): `npu_rvvi_agent` (passive), `npu_cosim_checker`; packages `mac_env_pkg`, `core_env_pkg`, `soc_env_pkg`; file lists `mac_dv.f`, `core_dv.f`, `soc_dv.f`; soc top `tb/uvm/tb/npu_tb_top.sv`.
- Program/data load: backdoor `$readmemh` (`+ITCM=<file>`, `+DTCM=<file>`) before reset release (D7).
- End of test (§10.1): `SIM_CTRL` write (`0x1` PASS, `0x2` FAIL), or the core's halt/fault indication if W2-1 defines one, or timeout = 10 × expected cycles (default `+TIMEOUT_CYC=1000000`). A timeout is a failure.
- Golden models are oracles only after their own unit tests pass (§10.2). `npu_ref` and `rv_iss` are reached only through `tb/uvm/common/npu_dpi_pkg.sv`.
- Coverage: every bin of §10.5 declared before week 7; 100 % of declared bins on D0 before week 10 (SC2). An exclusion needs a written reason in `docs/coverage_exclusions.md` signed by both students.
- No CoralNPU code is copied (§16). Coral files may be read as references and cited in comments by path.
- Every test runs through `run.py` so that SC6 later needs no new plumbing.

## Review Focus

1. **Lockstep drift under stalls:** a stalled READ_RESULT, FIFO-full stalls and divider stalls in the same window must not make the cosim checker skip or double-count a retire. Test: Task 17 `core_cosim_stall_storm`.
2. **Golden-memory divergence:** a responder or backdoor write that is not mirrored into `npu_ref` or `rv_iss` makes later predictions wrong, and can hide real bugs. Tests: Task 16 `mac_mem_mirror_check` (end-of-test hash of responder memory vs `npu_ref`), Task 18 end-of-test DTCM comparison against the ISS in every soc test.
3. **Hang instead of failure:** a READ_RESULT that never returns must end the test as FAIL by timeout, not run forever or report PASS. Test: Task 17 `core_read_result_hang_times_out` (expected-fail).
4. **Test-error stimulus counted as coverage:** a COMPUTE reading buffer entries never written since reset (§7.2) is a sequence bug; it must raise `UVM_ERROR` and must not count. Test: Task 16 `mac_unwritten_entry_flagged` (expected-fail).
5. **Firmware toolchain drift:** the `.insn` encoding in `npu.h` must match §6.1 for every funct3/funct7 combination, or firmware silently issues the wrong command. Test: Task 13 `npu_h_encodings`.

---

### Task 13: Firmware base — Track A, week 5

**Files:**
- Create: `sw/crt0.S` (set `sp` to the top of DTCM `0x0002_0000`, zero `.bss`, call `main`, write its return value: 0 → `SIM_CTRL=0x1`, else `0x2`)
- Create: `sw/link.ld` (`.text`/`.rodata` in ITCM `0x0000_0000` 16 KB; `.data`/`.bss`/stack in DTCM `0x0001_0000` 64 KB; `.data` starts at `0x0001_DE00`, after the model region of §9.2; words `0x0001_DDF4`–`0x0001_DDFF` are reserved for measurement results written by Phase 3/4 firmware)
- Create: `sw/npu.h`, `sw/sim.h` (`sim_putc(char)`, `sim_pass()`, `sim_fail()`, `sim_meas_start()`, `sim_meas_stop()`, `sim_batch_done()`)
- Create: `sw/Makefile` (`make -C sw TEST=<name>` → `sw/build/<name>/{<name>.elf, itcm.hex, dtcm.hex, <name>.dis}`)
- Create: `sw/tests/hello/main.c`, `sw/tests/npu_h_encodings/main.S`, `sw/tools/check_insn.py`

**Interfaces:**
- Produces (§9.1):
  ```c
  static inline void     npu_load_w(uint32_t addr, uint32_t k);   /* funct3 000, "memory" clobber */
  static inline void     npu_load_i(uint32_t addr, uint32_t k);   /* funct3 001, "memory" clobber */
  static inline void     npu_compute(uint32_t k, uint32_t clr);   /* funct3 010, funct7[0]=clr; clr must be a compile-time constant */
  static inline uint32_t npu_read(uint32_t idx);                  /* funct3 011, no clobber */
  ```
  Hex format: one 32-bit word per line, word-addressed from the region base, as `$readmemh` in `itcm.sv`/`dtcm_dp.sv` expects.

- [ ] **Step 1: Write the failing tests:**
  - `hello`: prints `"OK\n"` via `sim_putc`, returns 0. Expected log: `OK` then `PASS`.
  - `npu_h_encodings`: `main.S` holds, in order, the instructions the wrappers emit with fixed registers: `npu_load_w(a0,a1)`, `npu_load_i(a0,a1)` (rd = x0), `npu_compute(a0,0)`, `npu_compute(a0,1)` (rs2 = rd = x0), `npu_read(a0)` → a2 (rs2 = x0). `check_insn.py` asserts the words, in order: `0x00b5000b`, `0x00b5100b`, `0x0005200b`, `0x0205200b`, `0x0005360b`. It also compiles a C file using the four wrappers and checks the same funct3/funct7 fields in the disassembly.
- [ ] **Step 2:** `make -C sw TEST=hello` and run on Phase 1's `core_tb_top` (`+ITCM=sw/build/hello/itcm.hex +DTCM=sw/build/hello/dtcm.hex`) → FAIL (files missing).
- [ ] **Step 3:** Implement the files above.
- [ ] **Step 4:** `hello` ends with `OK` and `PASS`; `python sw/tools/check_insn.py sw/build/npu_h_encodings/npu_h_encodings.dis` exits 0.
- [ ] **Step 5: Commit** `feat(sw): crt0, linker script, npu.h, sim.h, build`.

---

### Task 14: `npu_top` integration and plain-SV smoke tests — both, weeks 5–6

**Files:**
- Create: `rtl/top/npu_top.sv` (core + `itcm` + `dtcm_dp` + `mac_engine #(GATING_EN)`; core port A → DTCM for `0x0001_xxxx`; core MMIO window `0x0002_xxxx` → top-level `mmio_*` ports; RVVI ports passed through under `` `ifdef RVVI_TRACE ``; halt/fault passed through if W2-1 defines them)
- Create: `tb/directed/npu_top_tb.sv` (implements `SIM_CTRL`/`SIM_PUTC` on `mmio_*`; `+TIMEOUT_CYC`)
- Create: `sw/tests/{t_ldw_ldi_mac,t_read_all,t_errors,t_status_csr,t_war_safe}/main.c`
- Create: `sim/questa/run_npu_top.do`, `rtl/rtl.f` (every synthesizable RTL file, in compile order; reused by all `*_dv.f`)

**Interfaces:**
- Consumes: core ports (Phase 1 Task 8, 9), `mac_engine` §7.1 ports (Task 11), `dtcm_dp` (Task 8), `npu.h`/`sim.h` (Task 13).
- Produces:
  ```systemverilog
  module npu_top #(parameter bit GATING_EN = 0) (
    input  logic clk, rst_n,
    output logic        mmio_we,  output logic [31:0] mmio_addr, output logic [31:0] mmio_wdata
    `ifdef RVVI_TRACE , /* the Task 8 rvvi_* ports */ `endif
  );
  ```
  Hierarchical names fixed for later tasks: `npu_top.u_core`, `npu_top.u_itcm`, `npu_top.u_dtcm`, `npu_top.u_mac_engine` (§11 dump scope).

- [ ] **Step 1: Write the failing firmware tests.** Each computes the expected values in C on the core (plain loops over the same DTCM arrays) and compares with `npu_read`, returning non-zero on mismatch:
  - `t_ldw_ldi_mac`: the Task 10 `hand_4x4_k4` data placed at 16-byte-aligned DTCM addresses; COMPUTE K=4 clr=1; all 16 results equal `r0=[10,1,-1280,-4]`, `r1=[-10,-1,1280,4]`, `r2=[127,127,-16256,254]`, `r3=[-128,0,16384,256]`
  - `t_read_all`: K=64 random data (fixed seed in the source), clr=1 then a second COMPUTE clr=0; results equal 2× the first
  - `t_errors`: K=6 → `err_k`; address `0x0001_0004` → `err_align`; `0x0001_FFF0` with K=8 → `err_addr`; funct3 `100` via `.insn` → `err_illegal`; then W1C `0xF00` clears all four
  - `t_status_csr`: `npu_busy_cyc` (0x7C1) increases across a K=1024 COMPUTE by at least 256
  - `t_war_safe`: LDW, COMPUTE, READ_RESULT, then overwrite the weight buffer and repeat; second results use the new data
- [ ] **Step 2:** Run each on `npu_top_tb` → FAIL (top not built).
- [ ] **Step 3:** Implement `npu_top.sv` and `npu_top_tb.sv`. Interface mismatches found here are fixed in the owning track's RTL and recorded in the commit message.
- [ ] **Step 4:** All five end with `PASS`; `verilator --lint-only -Wall -f rtl/rtl.f --top-module npu_top` clean.
- [ ] **Step 5: Commit** `feat(top): npu_top integration and firmware smoke tests`.

---

### Task 15: Shared UVM layer, RVVI agent, cosim checker, `run.py` — Tấn + Claude [support], week 5

**Files:**
- Create: `tb/uvm/common/npu_dpi_pkg.sv` (all `import "DPI-C"` for `npu_ref_*` and `iss_*`; nothing else imports DPI)
- Create: `tb/uvm/common/npu_rvvi_if.sv`, `tb/uvm/common/npu_rvvi_agent_pkg.sv` (passive: `npu_rvvi_monitor` → `uvm_analysis_port #(npu_rvvi_item)`)
- Create: `tb/uvm/common/npu_cosim_checker.sv` (subscriber: on each `npu_rvvi_item`, call `iss_step(&rec)` and compare)
- Create: `tb/uvm/common/npu_sim_ctrl_if.sv`, `npu_sim_ctrl_monitor` (ends the test on PASS/FAIL; raises `UVM_FATAL` on timeout)
- Create: `tb/uvm/common/npu_base_test.sv` (backdoor load from plusargs, objection until `sim_ctrl` end or timeout)
- Create **[support]**: `run.py`, `sim/tests.yaml` (test → env, firmware, expected result `pass|fail`, seeds), `manifest.yaml` writer
- Modify (Tấn): `model/c/rv_iss.{h,c}`: add `uint32_t iss_mem_read(uint32_t addr);` (needed by Task 18 end-of-test check)

**Interfaces:**
- Consumes: `rv_iss` (`iss_init`, `iss_step`, `rvvi_rec_t`, `ISS_STUB`/`ISS_FULL`, Phase 1 Task 12); RVVI ports (Task 8).
- Produces:
  - `class npu_rvvi_item extends uvm_sequence_item;` fields mirror `rvvi_rec_t` (`order, pc, insn, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask, trap`)
  - `class npu_cosim_checker extends uvm_subscriber #(npu_rvvi_item);` config: `iss_mode` (`ISS_STUB`|`ISS_FULL`), `mask_csr_reads` = {0xB00, 0xB80, 0xC00, 0xC80, 0x7C1} (§10.2). Reports `COSIM_MISMATCH` with the first differing field.
  - `run.py --simulator {questa,xsim} --target <test|suite> [--config d0|d1] [--seeds N] [--cov]` → exit 0 iff every run matches its expected result; logs in `out/<date>/<config>/<test>/<seed>/`.

- [ ] **Step 1: Write the failing tests:**
  - `cosim_selftest_pass`: a 20-instruction ALU program on `core_env` (Task 17 skeleton) → 0 mismatches
  - `cosim_selftest_detects`: same program, with `+COSIM_INJECT=7` making the checker corrupt the ISS `rd_wdata` of retire 7 → test FAILS with `COSIM_MISMATCH` at order 7 (expected-fail in `tests.yaml`)
  - `run_py_selftest` **[support]**: `run.py --target selftest` runs one expected-pass and one expected-fail dummy test and exits 0; flipping either expectation exits 1
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** All three behave as stated; `manifest.yaml` lists Questa version and licence type, Verilator, GCC, Python versions, git hash.
- [ ] **Step 5: Commit** `feat(tb): shared UVM layer, RVVI agent, cosim checker, run.py`.

---

### Task 16: `mac_env` — Track B, weeks 5–9

**Files:**
- Create: `tb/uvm/mac_env/mac_cmd_if.sv`, `mac_dtcm_if.sv`, `mac_cmd_agent_pkg.sv`, `mac_dtcm_agent_pkg.sv`, `mac_predictor.sv`, `mac_scoreboard.sv`, `mac_coverage.sv`, `mac_env_pkg.sv`, `mac_seq_lib.sv`, `mac_test_pkg.sv`, `mac_tb_top.sv`, `mac_dv.f`
- Create: `tb/sva/mac_engine_sva.sv` (A-MAC-1..5, `bind mac_engine`)
- Modify: `model/c/npu_ref.{h,c}`: add `uint32_t npu_ref_mem_read(uint32_t word_idx);` and a unit test for it

**Interfaces:**
- Consumes: `mac_engine` §7.1 ports, `npu_dpi_pkg`, `npu_pkg`.
- Produces:
  - `class mac_cmd_item extends uvm_sequence_item;` `rand npu_op_e op; rand bit [31:0] addr, k; rand bit clr;` plus `kind` ∈ {PUSH, READ, CSR_RD, CSR_WR}, `idx`, `csr_addr`, `csr_wdata`, response `rdata`
  - `mac_dtcm_agent`: reactive responder on `b_req/b_addr/b_rdata` holding `bit [127:0] mem[4096]`; every write goes through `write_word(idx, data)`, which also calls `npu_ref_mem_write`
  - `mac_predictor` → `mac_scoreboard`: compares each READ result and each `npu_status` read with `npu_ref`; raises `UVM_ERROR "UNWRITTEN_ENTRY"` when a COMPUTE's K/4 exceeds the entries written since reset (§7.2)
  - Covergroups exactly as §10.5: `cg_cmd`, `cg_operand`, `cg_fifo`, `cg_state`, `cg_acc`, `cg_err`, `cg_addr` (`cg_gate` is added in Phase 3)

- [ ] **Step 1 (weeks 5–6): Write the failing directed tests** (one `uvm_test` each, every §10.3 mac row):
  - `mac_single_k4` (hand data), `mac_k_kmax`, `mac_k0`, `mac_k_too_big` (1028), `mac_k_mod4` (6), `mac_misaligned` (`a[3:0]=4`), `mac_addr_oob`, `mac_addr_wraps_32bit` (`0xFFFF_FFF0`, K=8), `mac_illegal`
  - `mac_clr_vs_accum`, `mac_forced_wrap` (repeat COMPUTE clr=0 with all lanes −128 until `acc` wraps; expected value from `npu_ref`)
  - `mac_fifo_full` (8 back-to-back pushes + 1 more while busy; `cmd_ready` low observed), `mac_read_while_busy` (`rd_ready` low until drained), `mac_w1c`
  - `mac_mem_mirror_check` (Review Focus 2): every test's `report_phase` compares a hash of the responder memory with `npu_ref_mem_read` over all 16,384 words
  - `mac_unwritten_entry_flagged` (Review Focus 4, expected-fail): COMPUTE K=8 after reset with only one quad loaded → `UVM_ERROR UNWRITTEN_ENTRY`
- [ ] **Step 2:** `run.py --target mac_directed` → FAIL. **Step 3:** Implement env, agents, predictor, scoreboard, SVA. **Step 4:** All pass; expected-fail test fails for the stated reason only.
- [ ] **Step 5: Commit** `feat(tb): mac_env directed`.
- [ ] **Step 6 (weeks 7–9): Write `mac_rand_seq`** (§10.3): op mix weights LDW 30 / LDI 30 / MAC 30 / ILLEGAL 2 / READ 8; K bins as `cg_cmd` with 5 % illegal K; addresses 90 % in range and aligned; operand lanes biased 20 % to {−128, −1, 0, 1, 127}; inter-command gap 0–20 cycles. Constraint: no COMPUTE beyond written entries (§7.2). Test `mac_rand` with ≥ 200 seeds.
- [ ] **Step 7:** `run.py --target mac_rand --seeds 200 --cov` → 0 mismatches, 0 SVA failures; covergroups declared in full by end of week 7 (closure is Task 19).
- [ ] **Step 8: Commit** `feat(tb): mac_env random and coverage`.

---

### Task 17: `core_env` — Track A, weeks 5–9

**Files:**
- Create: `tb/uvm/core_env/core_env_pkg.sv`, `core_instr_item.sv`, `core_seq_lib.sv`, `core_coverage.sv`, `core_test_pkg.sv`, `core_uvm_tb_top.sv` (core + ITCM + DTCM + `npu_stub` from Phase 1 Task 9), `core_dv.f`
- Create: `tb/sva/core_sva.sv` (A-CORE-1)

**Interfaces:**
- Consumes: `npu_rvvi_agent`, `npu_cosim_checker` in `ISS_STUB` mode (Task 15); `npu_stub` plusargs `+STUB_READY=<bits>` and new `+STUB_RDREADY=<bits>` (add to `npu_stub.sv`, same pattern).
- Produces:
  - `class core_instr_item extends uvm_sequence_item;` rand opcode class ∈ {ALU, ALUI, M, ZBB, LOAD, STORE, BRANCH, CSR, CUSTOM}, `rd, rs1, rs2, imm`; `function bit [31:0] encode();` (encodings as `docs/core_isa.md`)
  - `core_rand_seq`: emits N items with controlled dependency distance (`dep_dist` ∈ {1, 2, 3, ≥4}), writes them into ITCM by backdoor, appends the `SIM_CTRL` PASS store
  - Covergroups `Cvgrp_rv32i`, `Cvgrp_m`, `Cvgrp_zbb`, `Cvgrp_csr`, `Cvgrp_fwd` with the bins of §10.5 (core row)

- [ ] **Step 1 (weeks 5–6): Directed tests.** Reuse the Phase 1 programs (`tools/rv32i_check` builds → `.hex`) as `uvm_test`s driven through `core_env` with cosim: `core_isa_<suite>` for each of rv32i/m/zbb/csr/custom; plus
  - `core_fifo_full_stall` (`+STUB_READY=0001`)
  - `core_cosim_stall_storm` (Review Focus 1): DIV chains + 6 pushes with `+STUB_READY=0001` + READ_RESULT with `+STUB_RDREADY=00000001`, all within 40 instructions → 0 mismatches, `order` gap-free
  - `core_read_result_hang_times_out` (Review Focus 3, expected-fail): `+STUB_RDREADY=0` → test FAILS by timeout, never PASS
- [ ] **Step 2:** `run.py --target core_directed` → FAIL. **Step 3:** Implement. **Step 4:** All pass as stated.
- [ ] **Step 5: Commit** `feat(tb): core_env directed with cosim`.
- [ ] **Step 6 (weeks 7–9):** `core_rand_alu` (ALU/M/Zbb streams, `dep_dist` uniform over its bins) and `core_rand_branch` (adds branches/jumps with targets inside the program), ≥ 200 seeds each; A-CORE-1 bound.
- [ ] **Step 7:** `run.py --target core_rand --seeds 200 --cov` → 0 mismatches.
- [ ] **Step 8: Commit** `feat(tb): core_env random and coverage`.

---

### Task 18: `soc_env` — both, weeks 6–9

**Files:**
- Create: `tb/uvm/tb/npu_tb_top.sv` (`npu_top #(GATING_EN) u_dut` + `npu_rvvi_if` + `npu_sim_ctrl_if`; `GATING_EN` from `+define+GATING_EN=0|1`; the instance name `u_dut` is fixed, Phase 3 dumps `u_dut.u_mac_engine`)
- Create: `tb/uvm/soc_env/soc_env_pkg.sv` (`npu_rvvi_agent`, `npu_cosim_checker` in `ISS_FULL`, `soc_fifo_monitor`, `npu_sim_ctrl_monitor`, `soc_end_checker`), `soc_test_pkg.sv`, `soc_dv.f`
- Create: `tb/sva/soc_sva.sv` (A-SOC-1)
- Create: `model/py/gen_matmul.py` (seed → random int8 A[M×K], B[K×N], packed DTCM image per §6.2/§9.2 alignment, and expected int32 C)
- Create: `sw/tests/{t_matmul_4x4xk,t_layer_784x64,t_war_violation}/main.c`, `sw/tests/soc_rand_matmul/main.c` (reads sizes and addresses from a header generated by `gen_matmul.py`)

**Interfaces:**
- Consumes: `npu_top` (Task 14), shared layer (Task 15), `iss_mem_read` (Task 15).
- Produces: `soc_end_checker` — at end of every soc test compares all 16,384 DTCM words (`npu_top.u_dtcm` backdoor) with `iss_mem_read`, and dumps LOGITS if the test defines them. `gen_matmul.py --seed S --m M --k K --n N --out <dir>` writes `dtcm.hex`, `matmul_cfg.h`, `expected.hex`.

- [ ] **Step 1: Write the failing tests** (§10.3 soc row):
  - `soc_t_ldw_ldi_mac`, `soc_t_read_all`, `soc_t_errors`, `soc_t_status_csr` (Task 14 firmware, now with cosim)
  - `soc_matmul_4x4xk` for K ∈ {4, 64, 1024}
  - `soc_layer_784x64` (one full layer-1 shaped matmul, 16 tiles)
  - `soc_war_violation` (expected-fail): firmware stores into a buffer while its LOAD is queued → A-SOC-1 fires
  - `soc_rand_matmul`: `gen_matmul.py` sizes M, N ∈ {4, 8, 12, 16}, K ∈ multiples of 4 up to 256, ≥ 50 seeds
  - every test: `soc_end_checker` DTCM comparison passes (Review Focus 2)
- [ ] **Step 2:** `run.py --target soc_all` → FAIL. **Step 3:** Implement. **Step 4:** All pass; `soc_war_violation` fails only on A-SOC-1.
- [ ] **Step 5: Commit** `feat(tb): soc_env with full-system cosim`.

---

### Task 19: Coverage closure, Phase 2 sign-off, report chapter — both, weeks 9–10

**Files:**
- Create: `docs/coverage_exclusions.md` (empty table if none: bin, reason, signed A/B)
- Create: `docs/report/ch_verification.md` (English draft, D12): environments, golden models, test list with pass counts, coverage table, assertions, CoralNPU comparison row from §16
- Modify **[support]**: suites in `sim/tests.yaml`: `mac_regress` = `mac_directed + mac_rand`; `core_regress` = `core_directed + core_rand`; `regress_d0` = `mac_regress + core_regress + soc_all` with `--config d0`, merging UCDBs into `out/<date>/d0/cov/merged.ucdb`; `regress_d1` = the same suites with `--config d1` (used from Phase 3)

**Interfaces:**
- Produces: the D0 baseline that Phase 3 compares against: `out/<date>/d0/` logs, merged coverage, and the RVVI logs of every soc test.

- [ ] **Step 1:** `run.py --target regress_d0 --cov` → list uncovered bins (`vcover report -details`).
- [ ] **Step 2:** For each hole: add a directed test or a constraint tweak in the owning env; a bin may be excluded only with a written reason.
- [ ] **Step 3:** Re-run → 0 failures (SC1), 100 % of declared bins (SC2).
- [ ] **Step 4:** Draft `ch_verification.md`; each student writes the section of their own env, `soc_env` together.
- [ ] **Step 5: Commit** `test: Phase 2 D0 regression and coverage closed` and tag `phase2-d0`.

## Phase 2 exit checklist

- [ ] Tasks 13–18 green in `run.py`, including Review Focus tests 1–5 behaving as stated
- [ ] SC1 on D0: 0 scoreboard mismatches, 0 assertion failures, every expected-fail test failing for its stated reason only
- [ ] SC2: 100 % of §10.5 bins (minus signed exclusions) on D0, report in `out/<date>/d0/cov/`
- [ ] `manifest.yaml` up to date; tag `phase2-d0` pushed
- [ ] `docs/report/ch_verification.md` drafted
