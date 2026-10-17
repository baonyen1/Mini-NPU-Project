# Mini-NPU Phase 1 (Weeks 1–4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project rule (overrides the line above for graded work):** the students write all RTL, golden-model logic, UVM and firmware themselves. Claude reviews against the tests named here. Tasks tagged **[support]** are non-graded tooling that Claude may write on request.

**Goal:** By the end of week 4:
- the week-1 tool gate is closed;
- the core is a clean RV32IM + Zicsr + Zifencei + Zbb pipeline with ITCM/DTCM, an RVVI trace port and custom-0 decode/push (tested against an engine stub);
- the MAC engine (D0) passes directed tests against the C reference model.

**Architecture:** Two tracks share the interfaces frozen in Task 2. Track A grows `rtl/core` in place and checks each step with `tools/rv32i_check` (Python ISS, extended per extension). Track B builds `model/c/npu_ref.c` first, then `rtl/npu/mac_engine.sv` checked by a directed SV testbench that calls `npu_ref` over DPI-C. UVM starts in Phase 2.

**Tech Stack:** Verilog/SystemVerilog (synthesizable subset for RTL), Siemens QuestaSim (full licence; UVM, DPI-C, coverage), Vivado 2024.1 xsim (fallback), Verilator, Icarus Verilog (quick checks only), RISC-V GNU binutils/gcc (`-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32`), C (gcc) for the golden models, Python 3.

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` (approved 2026-10-04). Section numbers (§) below refer to it.

**Working tree:** `SeniorProject2/` (layout in `README.md`). Paths are relative to it.

**Owners (team decision 2026-10-15):** Track A (scalar core, `core_env`) — **Nguyễn Hoàng Công Tấn**. Track B (Matrix/MAC engine, `mac_env`) — **Nguyễn Thế Bảo**. Joint: Tasks 0 and 2, later `soc_env`. Task headings below name the track; this table is the only place that maps tracks to people.

| Task | Owner | Status 2026-10-15 |
|---|---|---|
| 0 · Tool gate | Tấn: S1 UVM, S3 coverage, S5 toolchain, S6 xsim · Bảo: S2 DPI-C, S4 Verilator ICG, S7 VCD by scope | overdue |
| 1 · Core cleanup | Track A | done (`69cd798`) |
| 2 · Week-2 freeze | both (Tấn: `docs/core_isa.md`, W2-1; Bảo: `npu_pkg.sv`, notebook retrain; both sign §6/§7.1) | open |
| 3 · Complete RV32I | Track A (Tấn takes over, handover step below) | done (`c413abd`) |
| 4 · Extend reference ISS | Claude **[support]** | open, blocks 5–7 |
| 5, 6, 7, 9, 12 · M, Zicsr, Zifencei/Zbb, custom-0 push, `rv_iss.c` | Tấn | open |
| 8 · ITCM/DTCM/MMIO/RVVI | Tấn: core LSU, ITCM, SIM MMIO, RVVI · Bảo: `dtcm_dp` (port B is the engine's interface) | open |
| 10, 11 · `npu_ref.c`, `mac_engine` D0 | Bảo | 10 done 2026-10-17, 11 open |

**Handover (Tấn, before Task 5):** the Task 3 RTL was written by Claude and the core history is Bảo's. Tấn reads `docs/core_isa.md` and `docs/core_stall.md`, runs `python tools/rv32i_check/run_all.py` (expected: ISA 44/44, hazard 25/25, random 300/300), then explains each Task 3 change to Bảo. Done when Tấn can trace one `jalr` and one load-use stall through the pipeline without notes.

## Global Constraints

- Custom opcode `custom-0 = 0001011`. funct3: `000` LOAD_WEIGHT, `001` LOAD_INPUT, `010` COMPUTE (`funct7[0]` = clr), `011` READ_RESULT, `100–111` reserved → op ILLEGAL (§6.1).
- Engine op encoding on `cmd_op[1:0]`: `0` LDW, `1` LDI, `2` MAC, `3` ILLEGAL (§7.1).
- Arithmetic: signed int8 × signed int8 → int32, wrap mod 2³² (§3.1 D5).
- Engine geometry N×M×K = 4×4×4 (dot4 PEs, 64 MAC/cycle). `KMAX = 1024` int8 elements; K must be a multiple of 4; WBUF/IBUF = 256 entries × 128 bit. `FIFO_DEPTH = 8`, `DTCM_BASE = 0x0001_0000`, `DTCM_BYTES = 65536`, DTCM = 4 banks × 32 bit, port B 128 bit (§3.1 D10, §4.2).
- Memory map: ITCM `0x0000_0000` 16 KB; DTCM `0x0001_0000` 64 KB; `SIM_CTRL` `0x0002_0000` (`0x1` PASS, `0x2` FAIL, `0x10` BATCH_DONE, `0x20` MEAS_START, `0x21` MEAS_STOP); `SIM_PUTC` `0x0002_0004` (§4.1).
- CSRs: `mcycle/mcycleh` 0xB00/0xB80, `minstret/minstreth` 0xB02/0xB82, read-only aliases 0xC00/0xC02/0xC80/0xC82, `npu_status` 0x7C0, `npu_busy_cyc` 0x7C1 (§5, §6.4).
- `npu_status` bits: 0 busy, 1 fifo_empty, 2 fifo_full, 8 err_k, 9 err_addr, 10 err_illegal, 11 err_align (bits 8–11 sticky, W1C) (§6.4).
- Lane order: lane *t* = bits `[8t+7:8t]`; a quad (16 B) holds word *i* = 4 consecutive elements of row/image *i*; LOAD addresses 16-byte aligned; READ_RESULT index `idx = 4*i + j` (§6.2).
- Custom instructions are pushed to the FIFO in **MEM**; READ_RESULT stalls in MEM until `fifo_empty && fsm==IDLE` and writes back like a load (§6.3).
- Power numbers are "switching-activity estimates", never "measured power" (§1).
- Do not copy CoralNPU RTL or testbench code (§16).

## Review Focus

1. **Overlapping stall/flush sources:** a divider stall, a load-use stall, a FIFO-full or READ_RESULT stall, and a taken-branch flush can be active in the same cycle. Expected: the oldest instruction wins; younger instructions never write back or push. Tests: Task 5 `div_in_branch_shadow`, Task 9 `push_in_branch_shadow`.
2. **x0 as destination of new instructions:** `mul x0,…`, `csrrw x0,…` and `READ_RESULT x0,…` must not write x0. The CSR write and the READ_RESULT drain must still happen. Tests: Task 5 `mul_x0`, Task 6 `csrrw_x0_still_writes_csr`, Task 9 `read_result_x0_still_drains`.
3. **CSR read right after a write:** `csrw` followed immediately by `csrr` of the same CSR, and an ALU instruction consuming a CSR result in the next slot. Expected: the new value, through forwarding. Test: Task 6 `csr_raw_back_to_back`.
4. **Address-range overflow on LOAD:** `a + 4K` can wrap past 2³² (e.g. `a = 0xFFFF_FFF0`, `K = 8`). Expected: `err_addr`, command dropped. The check must not use 32-bit wrapped arithmetic. Tests: Task 10 `load_addr_wraps_32bit`, Task 11 `load_addr_wraps_32bit`.
5. **`COMPUTE` with K = 0 and clr = 1:** K = 0 is a no-op for every op (§6.3), so the accumulator is **not** cleared. Tests: Task 10 `compute_k0_clr_keeps_acc`, Task 11 the same.

---

## Phase roadmap (Phases 2–4 planned in detail on 2026-10-15)

| Phase | Weeks | Plan file | Exit criterion |
|---|---|---|---|
| **1 (this plan)** | 1–4 | `2026-10-04-mini-npu-phase1.md` | Tasks 0–11 done |
| 2 | 5–9 | `2026-10-15-mini-npu-phase2-uvm-integration.md` | `npu_top` integrated; mac/core/soc UVM envs; coverage closed (SC1, SC2) |
| 3 | 10–12 | `2026-10-15-mini-npu-phase3-gating-power.md` | D1 cycle-identical to D0 (SC3); E2 switching data (SC4) |
| 4 | 13–16 | `2026-10-15-mini-npu-phase4-mnist-report.md` | MNIST bit-exact (SC5); E4; reproducibility package (SC6); report |

**Schedule risk (flagged now):** Track A in weeks 3–4 carries Tasks 5, 6, 7, 8, 9 and 12, plus Tấn's handover of a core he did not write. That is the densest stretch of the project. `dtcm_dp` moves to Track B to lighten it. If Task 12 (`rv_iss.c`) slips, it may move into week 5, because Phase 2's `core_env` needs it only from week 5. Track B starts late: Task 10 was due in week 2, so Bảo starts it immediately and Task 11 has no slack. Nothing else may slip past week 4 without re-planning.

---

### Task 0: Week-1 tool gate (S1–S7) — both students, week 1

**Files:**
- Create: `sim/questa/smoke/uvm_hello.sv`, `sim/questa/smoke/dpi_add.c`, `sim/questa/smoke/dpi_tb.sv`, `sim/questa/smoke/cov_tb.sv`, `sim/questa/smoke/vcd_scope.do`, `sim/questa/smoke/run.do`, `sim/verilator/smoke/icg_tb.sv`, `sim/verilator/smoke/count_toggles.py`, `sw/smoke/t.S`
- Create: `docs/smoke/results.md` (one row per check: command, observed output, ✅/❌, log path)

**Interfaces:**
- Produces: confirmation that the team's QuestaSim licence runs UVM with `randomize`/`covergroup` (spec O3), the licence type in `docs/smoke/results.md`, and the exact tool commands later phases reuse.

- [ ] **Step 1 (S1, QuestaSim UVM):** a `hello_test extends uvm_test` whose `run_phase` randomizes a small class (`rand bit [7:0] x; constraint c { x < 10; }`) and prints it with `` `uvm_info("HELLO", ...) ``.
  Run (typical flow): `vlib work`, `vlog -sv uvm_hello.sv` (Questa ships a precompiled UVM; if `uvm_pkg` is not found, add `+incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv`), `vsim -c tb_top +UVM_TESTNAME=hello_test -do "run -all; quit"`.
  Expected: `[HELLO]` line with a value < 10 and `UVM_ERROR :    0`. A "verification license" checkout error means the licence is the FPGA edition (spec O3). ⚠️ Exact flags vary by Questa version; record what worked.
- [ ] **Step 2 (S2, QuestaSim DPI-C):** `int c_add(int a, int b)` in C, `import "DPI-C" function int c_add(input int a, input int b);` in SV, `$display("%0d", c_add(2,3))`.
  Expected output: `5`. Record the compile path used (passing the `.c` file to `vlog`, or a shared library via `vsim -sv_lib`).
- [ ] **Step 3 (S3, coverage report):** a covergroup with one coverpoint and 4 explicit bins. Sample values hitting exactly 2 of the bins.
  Run with `vsim -coverage`, then `coverage save cov.ucdb` and `vcover report cov.ucdb`. Expected: the covergroup shows 50.00 %.
- [ ] **Step 4 (S4, Verilator ICG):** a toy `icg_cell` (latch + AND, §8) driven with `en` low for cycles 10–19.
  Run: `verilator --lint-only -Wall icg_tb.sv`, then `verilator --binary --trace icg_tb.sv`.
  Expected: lint clean, and `count_toggles.py` reports 0 toggles of `gclk` within cycles 11–19 and 2 per cycle elsewhere.
- [ ] **Step 5 (S5, toolchain):** `t.S` contains `max a0, a1, a2` and `.insn r 0x0B, 0, 0, x0, a0, a1`.
  Run: `<prefix>gcc -march=rv32im_zicsr_zifencei_zbb -mabi=ilp32 -c t.S && <prefix>objdump -d t.o`.
  Expected: `max` disassembles, and the `.insn` word is `0x00b5000b`. Then `objcopy -O verilog` produces a hex file that `$readmemh` accepts.
- [ ] **Step 6 (S6, xsim fallback):** run Step 1's file on Vivado xsim 2024.1 (`xvlog -sv -L uvm`, `xelab -L uvm`, `xsim -R -testplusarg UVM_TESTNAME=hello_test`). Record pass/fail; this is the fallback if the Questa licence is limited.
- [ ] **Step 7 (S7, QuestaSim VCD by scope):** a `.do` script with `vcd file engine.vcd`, `vcd add -r /tb_top/dut/*`, `run 1us`, `vcd flush`.
  Expected: the VCD contains only signals of that scope.
- [ ] **Step 8:** Fill `docs/smoke/results.md`. Record the licence type and close O3 in spec §3.2. If S1–S3 pass, update proposal Tables 1, 3, 9, 11 and 12 (QuestaSim + UVM instead of Verilator/cocotb; marimo instead of PyTorch).
- [ ] **Step 9: Commit:** `git init` (first time only), then `git add -A && git commit -m "chore: week-1 tool gate results"`.

---

### Task 1: Core cleanup (remove Senior Project 1 coupling) — Track A, week 1–2

**Files:**
- Modify: `rtl/core/RISC_V_Top.v` (remove the `workload_monitor` instance and the `workload_*` ports)
- Modify: every `rtl/core/**` file that has a `cpu_en` port (only if the decision is "remove")
- Delete: `rtl/core/RISC_V_Impl_Top.v`. Move `rtl/core/RISC_V_Fixed_Impl_Top.v` to `rtl/fpga/` (thesis).

**Interfaces:**
- Produces: `RISC_V_Top(clk, reset, …)` with no DFS ports. `cpu_en` is either removed or tied to `1'b1` at the top. Record which one in `docs/core_isa.md` (Task 2).

- [ ] **Step 1:** Run `python tools/rv32i_check/run_all.py`. Expected: the baseline ISA 30/40, hazard 25/25, random 300/300.
- [ ] **Step 2:** Remove the instance and the ports. Apply the `cpu_en` decision.
- [ ] **Step 3:** `grep -ri "workload\|q_agent\|dfs" rtl/core` returns nothing. Delete `tools/rv32i_check/stub_workload_monitor.v`.
- [ ] **Step 4:** Re-run `run_all.py`. Expected: the same numbers as Step 1. The harness must now build **without** the stub.
- [ ] **Step 5: Commit** `refactor(core): remove Senior Project 1 DFS coupling`.

---

### Task 2: Week-2 freeze — both students, week 2

**Files:**
- Create: `docs/core_isa.md`. It holds the encoding table for every instruction the core will support, the CSR map, the W2-1 policy (illegal instruction, out-of-range access) and the `cpu_en` decision.
- Create: `rtl/top/npu_pkg.sv`. It holds the parameters from §4.2, `typedef enum logic [1:0] {OP_LDW=2'd0, OP_LDI=2'd1, OP_MAC=2'd2, OP_ILLEGAL=2'd3} npu_op_e;`, and the CSR addresses as `localparam`.
- Modify: spec §3.2 (record the O1 requant choice, and the O2 formula copied verbatim from `golden_int8.py` into §9.3), spec §4.1 (W2-1), spec status → "frozen §6, §7.1".

**Interfaces:**
- Produces: `npu_pkg` (imported by every SV file in `rtl/npu`, `rtl/top` and `tb/`); frozen spec §6 and §7.1.

- [ ] **Step 1:** Retrain `notebooks/MiniNPU_MLP.py` with `layer_sizes=[784, 64, 32, 10]` (spec model) and export to `model/py/` (weights, biases, `requant.json`, test vectors, accuracy). Check the exported `M`, `S` against the §9.3 formula and record float/int8 accuracy in the spec.
- [ ] **Step 2:** Write `docs/core_isa.md` and `rtl/top/npu_pkg.sv`. `npu_pkg.sv` must compile: run `vlog -sv rtl/top/npu_pkg.sv` on QuestaSim (clean) and `verilator --lint-only -Wall rtl/top/npu_pkg.sv` (clean).
- [ ] **Step 3:** Both students read §6 and §7.1 and sign off in the spec header ("Frozen 2026-10-xx by A, B"). From this point, changes need both signatures.
- [ ] **Step 4: Commit** `docs: freeze ISA and engine interface`.

---

### Task 3: Complete RV32I — Track A, week 3

**Files:**
- Modify: `rtl/core/StageDecode/Control.v`, `rtl/core/StageExecute/ALU.v`, `rtl/core/StageExecute/Branch_Comparator.v`
- Modify **[support]**: `tools/rv32i_check/tests_hazard.py` (add the new instructions to `SUP_R`, `SUP_I` and the branch list)

**Interfaces:**
- Consumes: Task 1's clean `RISC_V_Top`.
- Produces: full RV32I base. New ALU op codes fill the free values of the 4-bit `alu_operation`. Document them in `docs/core_isa.md`.

- [ ] **Step 1:** The failing tests already exist in `tools/rv32i_check/tests_isa.py`: `slt sltu sra slti sltiu slli srli srai bltu bgeu`. Run `python tools/rv32i_check/tests_isa.py`. Expected: `30 / 40`.
- [ ] **Step 2:** Add these corner tests to `tests_isa.py` (each compares RTL and ISS):
  - `slt_vs_sltu_sign`: `x1=0x80000000, x2=1` → `slt`=1, `sltu`=0
  - `sltiu_minus1`: `sltiu x3,x1,-1` → 1 for `x1 ≠ 0xFFFFFFFF`
  - `srai_negative`: `srai` of `0x80000F0F` by 4 → `0xF80000F0`
  - `bltu_bgeu_sign`: `bltu 0x80000000, 1` not taken; `bgeu` taken
- [ ] **Step 3:** Implement the decode, the ALU ops and the unsigned branch compares.
- [ ] **Step 4:** Run `run_all.py`. Expected: ISA **44/44** (40 + 4 corner tests), hazard 25/25, random 300/300 with the extended generator.
- [ ] **Step 5: Commit** `feat(core): complete RV32I base`.

---

### Task 4 [support]: Extend rv32i_check to M, Zicsr, Zifencei, Zbb and the new memory map — week 3

**Files:**
- Modify: `tools/rv32i_check/run.py`. Rename the class `ISS` → `RefISS`. Add M, Zicsr (`minstret` modelled exactly; `mcycle` reads masked), Zifencei (no-op), Zbb, and custom-0 in stub mode (READ_RESULT → `idx`; LDW/LDI/MAC → record `(op, addr, k, clr)` into `RefISS.cmd_log`). Add a memory-map switch, `MEMMAP = "sp1"` (current 1 KB/1 KB) or `"spec"` (ITCM 16 KB, DTCM 64 KB at `0x0001_0000`).
- Modify: `tools/rv32i_check/tb_dump.v`. Make the hierarchy paths `` `define``-selectable so they can follow Task 8.
- Create: `tools/rv32i_check/tests_m.py`, `tests_csr.py`, `tests_zbb.py`, `tests_custom.py` (the test bodies are listed in Tasks 5–9).

**Interfaces:**
- Produces: `compare(src, tag, steps, cycles, quiet, march="rv32im_zicsr_zifencei_zbb") -> list[str]`, and `RefISS.cmd_log: list[tuple[int,int,int,int]]`.

- [ ] **Step 1:** Unit-check `RefISS` against hand values for every Task 5–7 test vector before using it as the reference.
- [ ] **Step 2: Commit** `test(tools): extend reference ISS`.

---

### Task 5: M extension — Track A, week 3

**Files:**
- Create: `rtl/core/StageExecute/Multiplier.v` (1-cycle, `MUL/MULH/MULHSU/MULHU`), `rtl/core/StageExecute/Divider.v` (iterative radix-2, ~32 cycles, `start/busy/done`)
- Modify: `Control.v`, `StageExecute_Top.v`, `Hazard_Unit.v` (add a `div_busy` stall)
- Test: `tools/rv32i_check/tests_m.py`

**Interfaces:**
- Produces: `Divider(clk, reset, start, is_signed, is_rem, a[31:0], b[31:0], busy, done, result[31:0])`; `Hazard_Unit` input `div_busy`.

- [ ] **Step 1: Write the failing tests** in `tests_m.py` (RTL vs `RefISS`):
  - `mul_corners`: `(0x80000000,0x80000000)`, `(-1,-1)`, `(0x7FFFFFFF,2)` for each of `mul mulh mulhsu mulhu`
  - `div_by_zero`: `div`/`divu` by 0 → `0xFFFFFFFF`; `rem`/`remu` by 0 → dividend
  - `div_overflow`: `div -2^31,-1` → `0x80000000`; `rem` → `0`
  - `div_signs`: `div -7,2` → `-3`; `rem -7,2` → `-1`; `div 7,-2` → `-3`; `rem 7,-2` → `1`
  - `div_back_to_back_dep`: `div x3,…` immediately followed by `add x4,x3,x3`
  - `div_in_branch_shadow`: taken `beq` followed by a `div` that must not write back (Review Focus 1)
  - `mul_x0`: `mul x0,x1,x2` leaves x0 = 0 (Review Focus 2)
  - random: 300 seeds with M instructions mixed in
- [ ] **Step 2:** Run. Expected: FAIL (M is not decoded yet).
- [ ] **Step 3:** Implement. The divider stalls IF/ID/EX while busy. The result enters the pipeline at EX/MEM like an ALU result.
- [ ] **Step 4:** Run `tests_m.py` and `run_all.py`. Expected: all pass, and the base tests stay green.
- [ ] **Step 5: Commit** `feat(core): M extension`.

---

### Task 6: Zicsr and counters — Track A, week 3–4

**Files:**
- Create: `rtl/core/StageExecute/CSR_Unit.v`
- Modify: `Control.v`, `StageExecute_Top.v`, `Forwarding_Unit.v` (forward CSR read data like an ALU result)
- Test: `tools/rv32i_check/tests_csr.py`

**Interfaces:**
- Produces: `CSR_Unit(clk, reset, csr_op[2:0], csr_addr[11:0], wdata[31:0], rdata[31:0], retire, npu_csr_we, npu_csr_addr[11:0], npu_csr_wdata[31:0], npu_csr_rdata[31:0])`. Addresses 0x7C0 and 0x7C1 are forwarded to the `npu_csr_*` port. Task 9 brings that port out of `RISC_V_Top` under the §7.1 names `csr_we`, `csr_addr`, `csr_wdata`, `csr_rdata`.

- [ ] **Step 1: Write the failing tests:**
  - `csr_ops_all6`: `csrrw csrrs csrrc csrrwi csrrsi csrrci` on a scratch CSR. Use 0x7C0 through the stub; the stub implements W1C on bits 8–10 per §6.4.
  - `minstret_delta`: `csrr a,minstret; <N=5 instrs>; csrr b,minstret` → `b-a == 6`
  - `mcycle_ge_minstret`: the `mcycle` delta ≥ the `minstret` delta, checked in-program with `sltu` into a register
  - `cycle_alias_reads`: `rdcycle`/`rdinstret` equal `mcycle`/`minstret` read in the same position (masked compare)
  - `csrrw_x0_still_writes_csr` (Review Focus 2)
  - `csr_raw_back_to_back` (Review Focus 3)
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run `tests_csr.py` and `run_all.py` → PASS.
- [ ] **Step 5: Commit** `feat(core): Zicsr and counters`.

---

### Task 7: Zifencei and Zbb — Track A, week 4

**Files:**
- Create: `rtl/core/StageExecute/BitManip.v` (all Zbb ops in §5)
- Modify: `Control.v`, `StageExecute_Top.v`, the flush path for `fence.i`
- Test: `tools/rv32i_check/tests_zbb.py`

**Interfaces:**
- Produces: `BitManip(a[31:0], b[31:0], op[4:0], result[31:0])`. List the op encoding in `docs/core_isa.md`.

- [ ] **Step 1: Write the failing tests:**
  - `clz_ctz_zero`: `clz 0` = `ctz 0` = 32
  - `cpop_all_ones`: = 32
  - `orc_b`: `0x00010200` → `0x00FFFF00`
  - `rev8`: `0x11223344` → `0x44332211`
  - `sext_b`: `0x80` → `0xFFFFFF80`; `sext_h`, `zext_h` on `0x8001_8001`
  - `rol_ror_0_31`; `rori_31`
  - `max_min_sign`: `max/min` vs `maxu/minu` on `(0x80000000, 1)`
  - `andn_orn_xnor`
  - `fence_i_flush`: `fence.i` followed by dependent ALU ops gives correct results, and the `minstret` delta counts `fence.i` once
  - random: 300 seeds including Zbb
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS, all earlier suites still green.
- [ ] **Step 5: Commit** `feat(core): Zifencei and Zbb`.

---

### Task 8: ITCM/DTCM, SIM MMIO and the RVVI trace — Track A; `dtcm_dp` Track B, week 4

**Files:**
- Create: `rtl/mem/itcm.sv` (16 KB, combinational read, backdoor `$readmemh` from plusarg `+ITCM=<file>`)
- Create: `rtl/mem/dtcm_dp.sv` (64 KB as 4 banks × 32 bit, bank = word address [1:0]; port A 32-bit R/W with byte enables, 1-cycle read; port B 128-bit read-only (one word from each bank), 1-cycle read; backdoor `+DTCM=<file>`)
- Create: `rtl/top/core_tb_top.sv` (core + itcm + dtcm + SIM MMIO decode + engine stub from Task 9)
- Modify: `rtl/core` LSU path (byte-lane formatting stays in the core; the old `Data_Memory.v`/`ProgramMemory.v` are removed); add the RVVI output ports under `` `ifdef RVVI_TRACE ``
- Modify **[support]**: `tools/rv32i_check` → `MEMMAP="spec"`, hierarchy paths updated

**Interfaces:**
- Produces, core ports:
  - `imem_addr[31:0]`, `imem_rdata[31:0]`
  - `dmem_re`, `dmem_we[3:0]`, `dmem_addr[31:0]`, `dmem_wdata[31:0]`, `dmem_rdata[31:0]`
  - `rvvi_valid`, `rvvi_order[63:0]`, `rvvi_pc[31:0]`, `rvvi_insn[31:0]`, `rvvi_rd[4:0]`, `rvvi_rd_wdata[31:0]`, `rvvi_mem_addr[31:0]`, `rvvi_mem_wdata[31:0]`, `rvvi_mem_wmask[3:0]`, `rvvi_trap`
- Produces, `dtcm_dp` ports:
  - port A: `a_re`, `a_we[3:0]`, `a_addr[13:0]`, `a_wdata[31:0]`, `a_rdata[31:0]`
  - port B (exactly §7.1): `b_req`, `b_addr[11:0]` (quad index), `b_rdata[127:0]` (bank 0 in bits [31:0])

- [ ] **Step 1: Failing tests:**
  - every earlier suite re-run with `MEMMAP="spec"`
  - `dtcm_last_word`: store and load at `0x0001_FFFC`
  - `dtcm_port_b_quad`: after port-A stores to `0x0001_0010..0x0001_001C`, a port-B read of quad 1 returns those 4 words in bank order
  - `sim_ctrl_pass`: a write of `0x1` to `0x0002_0000` ends the simulation with "PASS"
  - `sim_putc`: `"OK\n"` appears in the log
  - `rvvi_order_monotonic`: the trace's `order` increments by 1 per retire, with no gaps after stalls or flushes (checked by a small Python script over a trace dump)
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat(mem,core): ITCM/DTCM, SIM MMIO, RVVI trace`.

---

### Task 9: Custom-0 decode and push with the engine stub — Track A, week 4

**Files:**
- Create: `rtl/top/npu_stub.sv` (always ready, or ready following plusarg pattern `+STUB_READY=<bitstring>`; logs each push as `PUSH op addr k clr`; `rd_ready=1`, `rd_data={28'b0,rd_idx}`; CSR reads return 0)
- Modify: `Control.v` (decode §6.1), `StageMemory_Top.v` (push in MEM; stall on `!cmd_ready`; READ_RESULT stall on `!rd_ready`; WB from `rd_data`), `Hazard_Unit.v`
- Test: `tools/rv32i_check/tests_custom.py`

**Interfaces:**
- Consumes: `npu_pkg::npu_op_e` (Task 2); the core ports of Task 8.
- Produces, core engine ports (exactly §7.1): `cmd_valid`, `cmd_ready`, `cmd_op[1:0]`, `cmd_addr[31:0]`, `cmd_k[31:0]`, `cmd_clr`, `rd_req`, `rd_idx[3:0]`, `rd_ready`, `rd_data[31:0]`, `csr_we`, `csr_addr[11:0]`, `csr_wdata[31:0]`, `csr_rdata[31:0]`

- [ ] **Step 1: Failing tests:** each compares the stub's `PUSH` log with `RefISS.cmd_log`, and registers with `RefISS`:
  - `push_each_op`: one LDW, one LDI, one MAC clr=0, one MAC clr=1
  - `illegal_funct3`: funct3 `100` pushes op 3
  - `read_result_returns_idx`: idx 0..15
  - `fifo_full_stall`: `+STUB_READY=0001` (ready 1 cycle in 4), 6 pushes in a row → same log and registers as with always-ready
  - `store_then_load_order`: `sw` data to `addr`, then LDW `addr`; at push time the testbench reads `dtcm[addr]` by backdoor and it equals the stored value
  - `push_in_branch_shadow`: a LDW after a taken branch is never pushed (Review Focus 1)
  - `read_result_x0_still_drains` (Review Focus 2)
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS, all earlier suites green.
- [ ] **Step 5: Commit** `feat(core): custom-0 decode, MEM-stage push, READ_RESULT`.

---

### Task 10: `npu_ref.c` golden model and its unit tests — Track B, week 2

**Files:**
- Create: `model/c/npu_ref.h`, `model/c/npu_ref.c`
- Create: `model/c/tests/test_npu_ref.c` (plain C asserts, built by `model/c/Makefile` target `test`)

**Interfaces:**
- Produces (spec §10.2):
  ```c
  void     npu_ref_reset(void);
  void     npu_ref_mem_write(uint32_t word_idx, uint32_t data);   /* word_idx 0..16383 */
  void     npu_ref_cmd(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr);
  uint32_t npu_ref_read(uint32_t idx);                           /* uses idx & 0xF */
  uint32_t npu_ref_status(void);
  void     npu_ref_csr_write(uint32_t addr, uint32_t data);       /* 0x7C0 W1C, 0x7C1 set */
  uint32_t npu_ref_csr_read(uint32_t addr);                       /* 0x7C0 status, 0x7C1 stored value, else 0 */
  ```
  `npu_ref_status()` returns the §6.4 layout with busy = 0, fifo_empty = 1, fifo_full = 0 (the model is untimed).

- [ ] **Step 1: Write the failing tests** in `test_npu_ref.c`:
  - `hand_4x4_k4` (K=4, one quad): rows r0=[1,2,3,4], r1=[−1,−2,−3,−4], r2=[127,0,0,0], r3=[0,0,0,−128]; images x0=[1,1,1,1], x1=[1,0,0,0], x2=[−128,−128,−128,−128], x3=[2,−2,2,−2] → acc rows (j=0..3): r0 = [10, 1, −1280, −4]; r1 = [−10, −1, 1280, 4]; r2 = [127, 127, −16256, 254]; r3 = [−128, 0, 16384, 256]
  - `hand_k8_accumulate`: COMPUTE K=4 (clr=1) on quad 0 then K=4 (clr=0) on quad 1 equals one COMPUTE K=8 over both quads
  - `extremes`: all lanes −128 × −128, K=1024 → each acc = 16,777,216
  - `wrap`: 129 × COMPUTE(K=1024, clr=0) of −128 × −128 → each acc = `(uint32_t)(129 * 16777216)`
  - `k0_noop`: K=0 for each op leaves state and status unchanged
  - `compute_k0_clr_keeps_acc` (Review Focus 5)
  - `k_too_big`: K=1028 → `err_k` set; buffers and acc unchanged
  - `k_not_multiple_of_4`: K=6 for each op → `err_k`, command dropped
  - `addr_out_of_range`: `addr = 0x0000_FFF0` with K=4, and `addr = 0x0001_FFF0` with K=8 → `err_addr`
  - `load_addr_wraps_32bit`: `addr=0xFFFF_FFF0, K=8` → `err_addr` (Review Focus 4)
  - `last_quad_ok`: `addr=0x0001_FFF0, K=4` → no error
  - `illegal_op`: op 3 → `err_illegal`
  - `w1c`: write `0xF00` to 0x7C0 clears all four error bits; write `0x100` clears only `err_k`
  - `addr_misaligned`: `addr=0x0001_0004` (and `0x0001_0001`) with K=4 → `err_align`, command dropped
- [ ] **Step 2:** Run `make -C model/c test` → FAIL (not implemented).
- [ ] **Step 3:** Implement. Check order in `npu_ref_cmd`: K==0 → no-op; K>KMAX or K%4 → `err_k`; for loads `a[3:0]≠0` → `err_align`, then range in 64-bit arithmetic `(uint64_t)a + 4ull*k > DTCM_BASE + DTCM_BYTES` → `err_addr`. Record this order in the spec if the team changes it.
- [ ] **Step 4:** Run `make -C model/c test` → all asserts pass.
- [ ] **Step 5: Commit** `feat(model): npu_ref golden model with unit tests`.

---

### Task 11: `mac_engine` RTL (D0) with a directed DPI testbench — Track B, weeks 3–4

**Files:**
- Create: `rtl/npu/mac_engine.sv`, `rtl/npu/cmd_fifo.sv`, `rtl/npu/pe_array.sv` (16 dot4 PEs), `rtl/npu/icg_cell.sv` (with `GATING_EN=0` it ties `en` to 1, §8)
- Create: `tb/directed/mac_engine_tb.sv`, `tb/directed/dtcm_model.sv` (behavioural 128-bit port-B memory backed by the same contents written to `npu_ref_mem_write`)
- Create: `sim/questa/run_mac_directed.do` (and a `.bat`/`.sh` wrapper); `sim/verilator/Makefile` target `lint` (`verilator --lint-only -Wall rtl/npu/*.sv rtl/top/npu_pkg.sv`)
- Create: `docs/mac_engine.md` (FSM diagram, exact latency per op for A-MAC-5)

**Interfaces:**
- Consumes: `npu_pkg` (Task 2); `npu_ref` (Task 10) through `import "DPI-C"` with the same signatures.
- Produces: `module mac_engine #(parameter GATING_EN = 0)` with exactly the §7.1 ports. Phase 2's `mac_env` and `npu_top` bind to these names.

- [ ] **Step 1: Write the failing directed tests** in `mac_engine_tb.sv`. Each test drives commands through the §7.1 push port, mirrors them into `npu_ref`, then compares all 16 READ_RESULT values and `npu_status` (`$fatal` on mismatch):
  - `t_single_k4` (Task 10's `hand_4x4_k4`)
  - `t_k_kmax` (K=1024)
  - `t_k0`
  - `t_k_too_big` (1028), `t_k_mod4` (K=6)
  - `t_addr_oob`, `t_addr_misaligned`
  - `load_addr_wraps_32bit`
  - `compute_k0_clr_keeps_acc`
  - `t_illegal`
  - `t_clr_vs_acc`
  - `t_wrap` (repeated accumulate as in Task 10)
  - `t_fifo_full`: 9 back-to-back pushes; `cmd_ready` drops at 8 entries and no command is lost
  - `t_read_while_busy`: `rd_ready` stays 0 until idle, then the data matches
  - `t_w1c`
- [ ] **Step 2:** Run `sim/questa/run_mac_directed` → FAIL (engine missing).
- [ ] **Step 3:** Implement per §7.2–§7.3: FSM `IDLE/CHECK/LOAD/MAC`; free-clock and `clk_mac` domains; `en = !rst_n_sync || (fsm != IDLE) || !fifo_empty`.
- [ ] **Step 4:** Run the directed suite → all PASS. Run `make -C sim/verilator lint` → clean. Record measured latencies in `docs/mac_engine.md`. Each must be ≤ K/4 + 3.
- [ ] **Step 5: Commit** `feat(npu): mac_engine D0 with directed DPI testbench`.

---

### Task 12: `rv_iss.c` reference ISS — Track A, week 4 (may slip to week 5, see Schedule risk)

**Files:**
- Create: `model/c/rv_iss.h`, `model/c/rv_iss.c`, `model/c/tests/test_rv_iss.c`

**Interfaces:**
- Consumes: `npu_ref` (Task 10) for `ISS_FULL` mode.
- Produces (spec §10.2):
  ```c
  typedef struct { uint32_t valid, pc, insn, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask, trap; uint64_t order; } rvvi_rec_t;
  enum { ISS_STUB = 0, ISS_FULL = 1 };
  void iss_init(const uint32_t *itcm, uint32_t itcm_words, const uint32_t *dtcm, uint32_t dtcm_words, int mode);
  int  iss_step(rvvi_rec_t *rec);   /* returns 0 normally, 1 after a SIM_CTRL write */
  ```

- [ ] **Step 1: Failing tests:** `test_rv_iss.c` runs the same programs as the Python suites (Tasks 3, 5, 6, 7, 9), loaded from the `.bin` files that `tools/rv32i_check/build/` produces. It asserts final registers equal to `RefISS`'s dump (`build/<tag>.ref.txt`, written by `run.py` **[support]**).
- [ ] **Step 2:** Run `make -C model/c test` → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS for every program.
- [ ] **Step 5: Commit** `feat(model): rv_iss reference ISS`.

---

## Phase 1 exit checklist

- [ ] Task 0: `docs/smoke/results.md` complete; licence type recorded, O3 closed; proposal updated if S1–S3 passed
- [ ] Tasks 1–9: `python tools/rv32i_check/run_all.py` (with `MEMMAP="spec"`) runs all suites green, including Review Focus tests 1–3
- [x] Task 10: `make -C model/c test` green, including Review Focus 4–5 (22/22, 2026-10-17)
- [ ] Task 11: directed engine suite green on QuestaSim; Verilator lint clean
- [ ] Task 12: green, or explicitly moved to week 5 with the reason noted
- [ ] Spec frozen (§6, §7.1) and O1/O2 recorded
