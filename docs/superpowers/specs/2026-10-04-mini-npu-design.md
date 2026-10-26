# Mini-NPU Design Spec — A CoralNPU-Inspired RISC-V NPU

- **Project:** Senior Project 2 (Đồ án 2), HCMUTE, class 23161FIE, advisor Phạm Văn Khoa
- **Team:** Nguyễn Hoàng Công Tấn (23161064) — Track A, scalar core; Nguyễn Thế Bảo (23144002) — Track B, Matrix/MAC engine (assignment 2026-10-15)
- **Repository:** https://github.com/baonyen1/Mini-NPU-Project
- **Date:** 2026-10-04 (rev. 2026-10-14: QuestaSim, requant formula, model size confirmed; rev. 2026-10-15: engine is N×M×K = 4×4×4 with dot4 PEs and a 128-bit DTCM port B; owners; D11–D13 for Phases 2–4) · **Status:** approved; §6/§7.1 freeze proposed 2026-10-24 after a cross-check against `npu_pkg.sv`, `npu_ref`, `npu_stub.sv`, the core push/CSR path, `rv_iss` and `dtcm_dp` (D17–D19 added). Sign-off: Tấn ☐ · Bảo ☑ (2026-10-26); Task 11 does not wait for Tấn's tick (D20). When both are ticked, replace this with "frozen <date> by Tấn, Bảo"
- **Source documents:** `Proposal_Senior_Project_2_MiniNPU_VI.docx`; CoralNPU repository `google-coral/coralnpu` at commit `382b5c1` (2026-10-02)

This spec turns the proposal into a buildable design. It fixes interfaces and semantics so the two tracks can work in parallel. It says *what* each block must do and *how it will be proven*. It does not contain RTL, UVM code or firmware. The students write those.

---

## 1. Goal and success criteria

Build a small NPU with these parts:

1. The team's existing 5-stage RV32I core, extended to **RV32IM + Zicsr + Zifencei + Zbb**.
2. Four custom instructions: **LOAD_WEIGHT, LOAD_INPUT, COMPUTE, READ_RESULT**. They dispatch through a command FIFO to a decoupled **int8 outer-product MAC engine of N×M×K = 4×4×4** (16 PEs, each a 4-way dot product: 64 MAC/cycle), the same parameterisation CoralNPU uses at 8×8×4.
3. A **64 KB DTCM** of 4 banks × 32 bit, shared by the core (port A, 32 bit) and the engine (port B, 128 bit, read-only).
4. **Module-level clock gating** of the MAC engine. The design is built twice: **D0** without gating and **D1** with gating.

All of it is verified with a self-built **SystemVerilog UVM** environment. It must run a **784-64-32-10 int8 MLP on MNIST** with outputs bit-exact against `golden_int8.py`.

| # | Criterion | Acceptance |
|---|---|---|
| SC1 | Functional integrity | Every defined directed and random test passes with zero scoreboard mismatches and zero assertion failures, on D0 and D1. |
| SC2 | Coverage | The coverage plan in §10.5 is closed on D0 before gating work starts (week 10). |
| SC3 | D0/D1 equivalence | Same program gives an identical retire trace hash, identical `mcycle` and identical outputs (cycle-identical). Fallback: result-identical, with the reason documented. |
| SC4 | Switching activity | Report the % change of D1 vs D0 for metrics M1 and M2 (§11) on synthetic and MNIST workloads. No target % is fixed in advance. |
| SC5 | MNIST | RTL logits and labels match `golden_int8.py` bit-exactly on the first 1,000 MNIST test images, on D0 and D1 (D11). One full 10,000-image run on D0 reports the RTL test accuracy, which must equal the golden accuracy. |
| SC6 | Reproducibility | One command per flow regenerates the regression, coverage and switching-activity data. Tool versions and seeds are recorded in `manifest.yaml`. |

**Evidence boundary.** Power numbers are *switching-activity estimates* from RTL simulation. They are never called "measured power". Functional evidence (UVM) and power evidence (toggles) are reported separately.

## 2. Scope

**In scope:**
- core ISA extensions
- the 4 custom instructions
- the MAC engine (FIFO, operand buffers, PE array, accumulator, CSRs)
- the dual-port DTCM, ITCM and simulation MMIO
- the clock gating cell and the D1 configuration
- three UVM environments, plus a C golden model and a C ISS
- bare-metal firmware and the MNIST pipeline
- the toggle-counting flow

**Out of scope (deferred to the graduation thesis):**
- RVV/Zve32x and the F extension
- DMA, multiple accumulator tiles, a pipelined PE
- FPGA synthesis and board bring-up
- a compiler toolchain (IREE/TFLM)
- frontdoor (bus) loading
- LLM-assisted verification

## 3. Decision log

### 3.1 Decided

| ID | Decision | Rationale |
|---|---|---|
| D1 | UVM 1.2 (IEEE 1800.2) in SystemVerilog. **Primary simulator: Siemens QuestaSim** (team decision 2026-10-14). Fallback: Vivado xsim 2024.1. Verilator is used for lint and fast full-system runs. | Industry-standard UVM simulator with built-in UVM, DPI-C and coverage. **Requires a full QuestaSim licence:** the free Questa–Intel/Altera FPGA (Starter) editions do not support `randomize`/`covergroup` (Altera forum, see §17), so a UVM bench with constrained random and coverage will not run there. Confirmed or refuted by S1–S3. |
| D1a | Switching-activity VCDs for D0/D1 come from **one** simulator for both configurations: QuestaSim by default; Verilator only if Questa run time for MNIST is too long (decide after the first MNIST run). | D0/D1 fairness (§11) needs identical tooling. |
| D2 | Extend the existing 5-stage pipelined RV32I core. | Already built by the team. |
| D3 | Work is split by subsystem. **Track A** (Tấn): core and `core_env`. **Track B** (Bảo): MAC engine, `dtcm_dp` and `mac_env`. Both tracks share the SoC integration and `soc_env`. | Parallel work with a clean interface. |
| D4 | "Coral, scaled down": the engine fetches operands from DTCM by itself into operand buffers, then accumulates into one 4×4 tile. | Mirrors Coral: `vle8` → vector regs → `vtmms` → tile → `vtmv`. |
| D5 | Signed int8 × signed int8 → int32 accumulate. **Overflow wraps** (two's complement). | Matches `int32_t` in the C golden. ReLU outputs lie in [0,127], so signed covers them. |
| D6 | The whole model lives in a 64 KB DTCM. No DMA. Closes open item 3. | Layout needs 56,816 B (§9.2). |
| D7 | Data is loaded by backdoor `$readmemh` first. Closes open item 4. | Simplest working path. Frontdoor loading is thesis work. |
| D8 | Golden ↔ scoreboard: DPI-C at block and system level; file comparison for MNIST. Closes open item 5. | Random tests need on-the-fly prediction. MNIST already has a Python golden. |
| D10 | Engine geometry **N×M×K = 4×4×4**: each PE computes a dot4 per cycle; WBUF/IBUF entries and DTCM port B are 128 bit; K must be a multiple of 4. Team decision 2026-10-15 (option B). | Matches CoralNPU's N×M×K outer-product engine (8×8×4, VDOT = "4 × 8-bit multiplies reduced into 32-bit accumulators"). About 4× fewer engine cycles than 4×4×1, and the longer idle gaps make the D1 result visible on MNIST. |
| D11 | MNIST image counts: **1,000** test images for the SC5 regression (D0 and D1); **10,000** (the full test set) once on D0 in week 15; **100** images for the E4 switching-activity run. Team decision 2026-10-15. | 1,000 images ≈ 3M cycles per configuration, short enough for regular regression; the full run gives an RTL accuracy figure; 100 images keeps the VCD small. |
| D12 | Final deliverables: report in **English**, defence slides, and the reproducibility package (SC6). Each report chapter is drafted when its phase ends. Team decision 2026-10-15. | Reusable for the graduation thesis; avoids writing everything in week 16. |
| D13 | Follow CoralNPU's public structure wherever it exists (datasheet, developer guides, `google-coral/coralnpu`): UVM topology (passive RVVI agent + co-simulation checker against an ISS), backdoor program load, end of test on a completion signal or timeout, a Python regression runner with `--simulator`/`--target`. Write all code ourselves; record every deliberate deviation in §16. Team decision 2026-10-15. | Keeps the design "CoralNPU-inspired" in a checkable way and gives the report a precise contribution boundary. |
| D9 | Clock gating is gated by hardware-detected idle on the MAC engine only. | Coral gates the whole core on WFI/CSR (`CoreAxi.scala`). Finer granularity is our contribution. |
| D14 | The retrained model export lives in `model/py/export/` and is committed: `fc{1,2,3}_weight.mem`, `fc{1,2,3}_bias.mem`, `requant.json`, `testvec_input.mem`, `testvec_expected.npz`, `manifest.json` (per-file SHA-256). The notebook writes it there. Track B decision 2026-10-21 (Bảo). | One frozen model for `pack_weights.py`, the golden files and the export-hash check (Phase 4 Tasks 25 and 27); matches the `model/py/` tree. |
| D15 | The integer golden for the MLP is `model/py/golden_int8.py` (pure numpy: `quantize_input`, `requant`, `find_ms`, `compute_bound`, `IntModel`, `load_export`). It has its own unit tests and is cross-checked against `npu_ref`; the notebook imports it instead of keeping a copy. Created by Phase 1 Task 2b. Track B decision 2026-10-21 (Bảo). | SC5 names `golden_int8.py` but no task created it. A notebook cannot be imported without marimo and torch, and §10.2 allows an oracle only after its own unit tests pass. |
| D16 | A command with op `ILLEGAL` is decided from `op` alone: the engine sets `err_illegal` and nothing else, even when K = 0, K > KMAX, K is not a multiple of 4 or the address is bad. The check order in `CHECK` is: ILLEGAL, K = 0, K range and multiple of 4, then for LOAD alignment, then address range. Track B decision 2026-10-23 (Bảo, option A); Tấn confirms by signing the §6 freeze. | The core pushes ILLEGAL with whatever `rs1`/`rs2` hold, so K and the address of an ILLEGAL command are arbitrary. If K = 0 won, a reserved `funct3` with `rs2 = 0` would be swallowed silently and the software error would stay hidden. Tests: `npu_ref` `test_illegal_op`, `test_illegal_wins_over_other_checks`; the Task 11 test `t_illegal` must cover K = 0, K = 6, K = 1028 and a bad address. |
| D17 | CSR writes to 0x7C0/0x7C1 carry the **new value the core computed** (`csrrw`: rs1; `csrrs`: old \| rs1; `csrrc`: old & ~rs1; the `i` forms with uimm), and `csr_we` is 1 only when the instruction writes (`csrrw`/`csrrwi` always; `csrrs`/`csrrc`/`csrrsi`/`csrrci` only with a non-zero rs1/uimm). W1C on `npu_status` applies to that value. Firmware clears error bits with `csrw`/`csrrwi`. A `npu_busy_cyc` write in a busy cycle wins over the increment. | Matches the core (`CSR_Unit.v`), `npu_stub.sv`, `rv_iss.c` and RefISS as built; standard Zicsr read-modify-write. Consequence: `csrrs npu_status, t0` with t0 ≠ 0 clears every set error bit, and `csrrc` clears every set error bit outside its mask. |
| D18 | Engine reset: `rst_n` is active low, **asserted asynchronously and released synchronously** to `clk` (the synchronizer sits in `npu_top`, which drives it from the core's active-high `reset`). Reset empties the FIFO, puts the FSM in IDLE, and clears the error bits, `npu_busy_cyc` and all 16 accumulators to 0. WBUF and IBUF are not reset (§7.2). | Project RTL rule (async assert, sync deassert; team decision 2026-10-24). §8's `!rst_n_sync` term keeps `clk_mac` running while reset is released; `npu_ref_reset` and the Task 10 tests already assume acc = 0 after reset. |
| D19 | Engine RTL conventions: the ports keep the §7.1 names (the core and `npu_stub` already use them); internal signals follow the lowRISC style (`_q`/`_d`, CamelCase parameters). The only clock-gating cell is `rtl/prim/npu_clk_gate.sv` (latch + AND in simulation, `BUFGCE` behind `` `ifdef FPGA_XILINX `` later); `mac_engine #(GATING_EN)` passes `GATING_EN` to it, and with 0 it ties its enable to 1. | Team decision 2026-10-24. Renaming the ports would touch Task 9 and the stub just before the freeze; one gating primitive keeps the sim/FPGA choice in one file. |
| D20 | Task 11 (`mac_engine` D0) starts on the proposed §6/§7.1 freeze and does not wait for Tấn's sign-off. Tấn reviews §6/§7.1 against the core in parallel, using the "Next actions" list in the Phase 1 plan, and ticks his box when done; the box stays open until he does. A change to §6/§7.1 before both ticks is recorded here as a dated entry; after both ticks it needs both signatures. Track B decision 2026-10-26 (Bảo). | The interfaces were cross-checked on 2026-10-24 against `npu_pkg.sv`, `npu_ref`, `npu_stub.sv`, the core push/CSR path, `rv_iss` and `dtcm_dp` (header), and Task 11 blocks Phase 2 Tasks 14 and 16. Cost of the risk: if Tấn's review changes §6/§7.1, Task 11 absorbs the change; his review items are D16 (ILLEGAL precedence), D17 (CSR write value) and D18 (reset). |

### 3.2 Open (the team decides; the default is used if no decision is recorded by the end of week 2)

| ID | Question | Options | Default |
|---|---|---|---|
| O1 | Requantization between layers (open item 2) | **A**: multiply + shift + clamp (`mul`, `srai`, `max`/`min`). **B**: shift only. | A, **confirmed 2026-10-23** (the notebook implements it and the committed export uses it) |
| O2 | Exact requant formula | Formula recorded in §9.3 from the notebook. The per-layer `M`, `S` values come from the retrained 784-64-32-10 model (`requant.json`). | **Closed 2026-10-23.** Formula fixed in §9.3. Retrained 784-64-32-10 export (seed 0, 15 epochs, calibration 10,000 images at the 99.99th percentile): FC1 `M` = 768, `S` = 20 (bound 1,608,339); FC2 `M` = 7891, `S` = 21 (bound 249,259); FC3 has no requant (bound 171,847). Accuracy on the 10,000 MNIST test images: float 97.48 %, int8 97.43 % (difference 0.05 percentage points); float and int8 labels agree on 99.81 %; the 100 exported test vectors score 99.00 %. `M`, `S` re-derived from `manifest.json` by `golden_int8.find_ms` (test `export_requant_matches_rule`). The export was produced on Linux with torch 2.14.1 (CPU) and numpy 2.5.4; two runs on that machine give identical SHA-256, but another platform may differ in the last bits, so the committed files are the reference, not a regeneration. |
| O3 | QuestaSim licence available to the team (lab or university licence, not the FPGA Starter edition) | S1–S3 on the actual licence. If `randomize`/`covergroup` fail, fall back to xsim. | QuestaSim. **Closed 2026-10-17**: S1-S3 pass on QuestaSim 10.7c (`docs/smoke/results.md`); xsim fallback verified (S6). |

## 4. System architecture

```
                 ┌──────────────────────── npu_top ─────────────────────────┐
                 │                                                          │
  ITCM 16KB ◄────┤  core (5-stage RV32IM+Zicsr+Zifencei+Zbb + custom-0)     │
  0x0000_0000    │     │ IF │ ID │ EX │ MEM │ WB │                           │
                 │                    │   ▲                                 │
                 │       cmd push ────┘   │ READ_RESULT data                │
                 │       (MEM stage)      │ + CSR 0x7C0/0x7C1               │
                 │                ┌───────┴──────────────────────────┐      │
                 │                │ mac_engine                       │      │
                 │                │  free clk : cmd FIFO(8), FSM,    │      │
                 │                │             CSRs, port-B ctrl    │      │
                 │                │  clk_mac  : WBUF, IBUF 256×128,  │      │
                 │                │             PE 4×4 dot4, acc 4×4 │      │
                 │                │  npu_clk_gate(en) → clk_mac      │      │
                 │                └───────┬──────────────────────────┘      │
                 │   LSU (port A, 32b R/W) │ port B (128b, read-only)       │
                 │          ▼             ▼                                 │
                 │     DTCM 64 KB, 4 banks × 32b, 0x0001_0000             │
                 │   SIM MMIO 0x0002_0000 (SIM_CTRL, SIM_PUTC) — tb only   │
                 └──────────────────────────────────────────────────────────┘
```

### 4.1 Memory map

| Base | Size | Region | Access |
|---|---|---|---|
| `0x0000_0000` | 16 KB | ITCM (firmware) | core IF read; backdoor load |
| `0x0001_0000` | 64 KB | DTCM, 4 banks × 32 bit (bank = word address [1:0]) | port A: core LSU, 32 bit R/W with byte enables; port B: engine, 128 bit (one word from each bank), read-only |
| `0x0002_0000` | 4 B | `SIM_CTRL` (write-only) | `0x1` PASS, `0x2` FAIL, `0x10` BATCH_DONE, `0x20` MEAS_START, `0x21` MEAS_STOP |
| `0x0002_0004` | 4 B | `SIM_PUTC` (write-only) | low byte printed to the simulation log |

Any other address is an access fault. Behaviour is decided by the core's existing policy, which Track A documents in week 2 (W2-1).

### 4.2 Parameters (`npu_pkg.sv`)

| Name | Default | Notes |
|---|---|---|
| `PE_ROWS` (N), `PE_COLS` (M) | 4, 4 | 8×8 only if time allows after SC1–SC3 |
| `K_DOT` (K) | 4 | int8 lanes per PE per cycle (dot4); fixed, not a verified parameter |
| `KMAX` | 1024 | largest K in int8 elements; WBUF/IBUF depth = KMAX/4 = 256 entries × 128 bit |
| `FIFO_DEPTH` | 8 | same depth as Coral's command queue |
| `GATING_EN` | 0 (D0) / 1 (D1) | the only RTL difference between D0 and D1 |
| `DTCM_BASE`, `DTCM_BYTES` | `0x0001_0000`, 65536 | |

## 5. Scalar core extensions (Track A)

- **M.** `MUL`, `MULH`, `MULHSU`, `MULHU` execute in EX in 1 cycle (simulation only). `DIV`, `DIVU`, `REM`, `REMU` use an iterative radix-2 divider of about 32 cycles that stalls the pipeline. Required corner cases from the spec: divide by zero (quotient = all ones, remainder = dividend) and `-2^31 / -1` (quotient = `-2^31`, remainder = 0).
- **Zicsr.** All six CSR instructions. CSRs:
  - `mcycle`/`mcycleh` (0xB00/0xB80)
  - `minstret`/`minstreth` (0xB02/0xB82), incremented at WB on retire
  - user read-only aliases `cycle`/`instret` (0xC00/0xC02/0xC80/0xC82)
  - `npu_status` (0x7C0) and `npu_busy_cyc` (0x7C1), forwarded to the engine (§6.4)
  - CSR results go through the normal forwarding path.
- **Zifencei.** `fence.i` flushes the pipeline and refetches. There is no I-cache. `fence` executes as a NOP.
- **Zbb.** Full set:
  - `andn orn xnor`
  - `clz ctz cpop`
  - `max maxu min minu`
  - `sext.b sext.h zext.h`
  - `rol ror rori`
  - `orc.b rev8`
- **Retire trace.** A retire-trace port in RVVI style for verification. Not synthesized logic in spirit, but kept in RTL under `` `ifdef RVVI_TRACE ``. Fields: `valid, order, pc, insn, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask, trap`.

## 6. Custom ISA (normative)

### 6.1 Encoding

All four instructions use opcode **custom-0 = `0001011`** in R-type format.

| funct3 | Mnemonic | Operands | funct7 |
|---|---|---|---|
| `000` | `LOAD_WEIGHT` | `rs1` = DTCM byte address, `rs2` = K | `0000000` |
| `001` | `LOAD_INPUT` | `rs1` = DTCM byte address, `rs2` = K | `0000000` |
| `010` | `COMPUTE` | `rs1` = K; `funct7[0]` = clr | `000000c` |
| `011` | `READ_RESULT` | `rd` ← acc[`rs1[3:0]`] | `0000000` |
| `100`–`111` | (reserved) | — | — |

`rd` must be `x0` for funct3 000–010; the hardware ignores the field. Non-zero `funct7` bits other than `COMPUTE`'s bit 0 are ignored. Assembler form: `.insn r 0x0B, <funct3>, <funct7>, rd, rs1, rs2`.

### 6.2 Data format

- A DTCM word is 4 int8 lanes. Lane *t* is bits `[8t+7:8t]` (lane 0 = LSB, little-endian).
- A **quad** is 4 consecutive words (16 bytes, 16-byte aligned) = one 128-bit WBUF/IBUF entry = one port-B read.
- K counts int8 elements along the reduction axis; a command with K elements uses S = K/4 quads (steps).
- `WBUF[s]` word *i* (bits `[32i+31:32i]`) = W[r₀+i][4s .. 4s+3]: four consecutive weights of output row r₀+i.
- `IBUF[s]` word *j* = x_j[4s .. 4s+3]: four consecutive inputs of image j (4 images per batch).
- In DTCM, quad *s* of a LOAD at address *a* is at `a + 16s`, and word *i* (or *j*) of that quad at `a + 16s + 4i`.
- After COMPUTE, `acc[i][j]` holds the dot product of output row r₀+i with image j. READ_RESULT index `idx = 4*i + j`.

### 6.3 Semantics

| Instruction | Effect |
|---|---|
| `LOAD_WEIGHT a, K` | for s in 0..K/4-1: `WBUF[s] ← DTCM[a + 16s .. a + 16s + 15]` (one 128-bit port-B read per s) |
| `LOAD_INPUT a, K` | for s in 0..K/4-1: `IBUF[s] ← DTCM[a + 16s .. a + 16s + 15]` |
| `COMPUTE K, clr` | `acc[i][j] ← (clr ? 0 : acc[i][j]) + Σ_{s<K/4} Σ_{t<4} sext(WBUF[s].word_i.lane_t) · sext(IBUF[s].word_j.lane_t)`, arithmetic mod 2³² |
| `READ_RESULT rd, idx` | `rd ← acc[idx/4][idx%4]` |

**Ordering rules:**
1. LOAD_WEIGHT, LOAD_INPUT and COMPUTE are pushed to the command FIFO in program order and executed in order, one at a time.
2. The push happens when the instruction is in **MEM**. Every older store has therefore already written DTCM, so a RAW dependency through DTCM is safe without extra logic.
3. A full FIFO stalls the pipeline at MEM.
4. **READ_RESULT** stalls in MEM until `fifo_empty && fsm == IDLE`. It then returns data in WB like a load and reuses the load-use hazard logic. It is the only barrier.
5. **Software rule (WAR):** firmware must not store to a DTCM word that a LOAD still queued or running will read. Satisfy this by issuing READ_RESULT, which drains the engine, before overwriting buffers. The rule is checked by assertion A-SOC-1 (§10.6).
6. LOAD addresses must be 16-byte aligned (quad-aligned); see the error table.

**Error handling.** A command that violates a rule is dropped and sets a sticky bit in `npu_status`. Execution continues.

| Condition | Effect |
|---|---|
| K = 0 (LDW, LDI or MAC; not ILLEGAL, see D16) | no operation, no error |
| K > KMAX, or K not a multiple of 4 | dropped, `err_k` ← 1 |
| LOAD with `a[3:0] ≠ 0` | dropped, `err_align` ← 1 |
| LOAD with `a < DTCM_BASE` or `a + 4K > DTCM_BASE + DTCM_BYTES` (computed without 32-bit wrap) | dropped, `err_addr` ← 1 |
| funct3 ∈ {100..111} | the core pushes op `ILLEGAL`; the engine sets `err_illegal` ← 1 and nothing else, whatever K, `cmd_addr` and clr the command carries (D16) |
| READ_RESULT with `rs1[31:4] ≠ 0` | upper bits ignored, no error |

### 6.4 CSRs

The CSRs are implemented in the engine and accessed by the core's CSR unit over the CSR port (§7.1).

`npu_status` (0x7C0):

| Bits | Name | Access | Meaning |
|---|---|---|---|
| 0 | `busy` | RO | `fsm != IDLE` |
| 1 | `fifo_empty` | RO | |
| 2 | `fifo_full` | RO | |
| 8 | `err_k` | W1C, sticky | |
| 9 | `err_addr` | W1C, sticky | |
| 10 | `err_illegal` | W1C, sticky | |
| 11 | `err_align` | W1C, sticky | |
| others | — | RO 0 | |

`npu_busy_cyc` (0x7C1): a 32-bit counter of cycles with `fsm != IDLE`. It runs on the free clock. A CSR write sets its value; a write in a busy cycle wins over the increment (D17).

CSR writes use the value the core computed for the CSR instruction (D17). Clear error bits with `csrw npu_status, <bits>` or `csrrwi`. `csrrs`/`csrrc` with a non-zero mask also write and, through W1C, clear more than their mask suggests. `csrr` does not write.

## 7. MAC engine microarchitecture (Track B)

### 7.1 Interfaces (freeze state: see the status line in the header)

```
// command push (core MEM stage → engine), free clock domain
input  cmd_valid; output cmd_ready;          // ready = !fifo_full
input  [1:0] cmd_op;                          // 0 LDW, 1 LDI, 2 MAC, 3 ILLEGAL
input  [31:0] cmd_addr; input [31:0] cmd_k; input cmd_clr;
// result read (core MEM stage)
input  rd_req; input [3:0] rd_idx;
output rd_ready;                              // fifo_empty && fsm==IDLE
output [31:0] rd_data;                        // valid when rd_req && rd_ready
// CSR port
input  csr_we; input [11:0] csr_addr; input [31:0] csr_wdata; output [31:0] csr_rdata;
                                              // csr_wdata = new value computed by the core; csr_we only when the instruction writes (D17)
// DTCM port B (read-only, 1-cycle latency)
output b_req; output [11:0] b_addr;           // quad index within DTCM (4096 quads)
input  [127:0] b_rdata;                       // 4 words (bank 0 = bits [31:0]), valid the cycle after b_req
// clocks
input clk, rst_n;                             // free clock; rst_n active low, async assert / sync deassert (D18)
```

### 7.2 Behaviour

- **FSM states:** `IDLE`, `CHECK`, `LOAD`, `MAC`. In `CHECK` the head command is popped and validated (§6.3 error table). A valid LOAD goes to `LOAD`: it streams K/4 quad reads on port B and writes WBUF or IBUF. A valid MAC goes to `MAC`: it reads `WBUF[s]` and `IBUF[s]` and updates all 16 accumulators each cycle (64 MACs).
- **Latency:** each command must finish within K/4 + 3 cycles of being popped. The exact count is documented by Track B in `docs/mac_engine.md`. The UVM scoreboard checks values, not latency. Latency is only constrained by the timeout assertion A-MAC-5.
- **PE (dot4):** one cycle per step (no pipelining in Senior Project 2): `acc_ij <= acc_ij + Σ_{t<4} sext8(a_i[t]) * sext8(b_j[t])`, i.e. 4 multipliers and a 3-adder tree per PE, 64 multipliers in total. When clr is set, the first step loads the dot product instead of adding it.
- **Buffers:** synchronous single-port RAM arrays, written in `LOAD` and read in `MAC`. They are never accessed at the same time because only one command runs at a time.
  - Buffers are **not reset** and keep their contents between commands.
  - COMPUTE reads entries 0..K/4-1 whatever the last LOAD's K was.
  - Reading an entry never written since reset is a test error, not a DUT error. Random sequences are constrained so that COMPUTE's K/4 never exceeds the smallest number of entries written since reset in WBUF or IBUF. The predictor raises `UVM_ERROR` if a sequence breaks this rule.

### 7.3 Clock domains

| Free clock `clk` | Gated clock `clk_mac` |
|---|---|
| cmd FIFO, FSM, CSRs, `npu_busy_cyc`, port-B request and address counter | WBUF, IBUF, PE datapath registers, the 16 accumulators |

READ_RESULT reads the accumulators combinationally. They hold their value while gated.

## 8. Clock gating (D0/D1)

- `npu_clk_gate` (`rtl/prim/npu_clk_gate.sv`, the only clock-gating cell in the design, D19): a latch transparent while `clk` is low, followed by an AND gate.
  ```
  always_latch if (!clk) en_l = en | test_en;
  assign gclk = clk & en_l;
  ```
  The team writes it themselves. It follows the same pattern as CoralNPU `hdl/verilog/ClockGate.sv`, default branch. Add the `/* verilator clock_enable */` pragma on the latch output. For the thesis FPGA, a `BUFGCE` variant goes behind `` `ifdef FPGA_XILINX ``.
- **Enable:** `en = !rst_n_sync || (fsm != IDLE) || !fifo_empty`.
  - The `!rst_n_sync` term keeps the clock running during reset, so synchronous resets in the gated domain still take effect.
  - The other terms come straight from registers, so `en` is glitch-free at the latch. A push at cycle *t* makes `fifo_empty` low at *t+1*. The latch opens during the low phase of *t+1*, and the first gated edge arrives at *t+2*, exactly when the FSM first needs the datapath. **Gating therefore adds no cycles, so cycle-identical D0/D1 is achievable (SC3).**
- **D0:** `GATING_EN = 0`, so `en` is tied to 1 inside `npu_clk_gate` (D19) and the instance stays. D0 and D1 have the same hierarchy and the same netlist apart from that tie.
- **Safety invariant (assertion A-GATE-1):** `(fsm != IDLE || !fifo_empty) |-> en`.

## 9. Firmware and MNIST pipeline

### 9.1 Build

- Bare-metal C with `crt0.S` and `link.ld` (ITCM for `.text`; DTCM for `.data`, `.bss` and the stack).
- Flags: `-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32 -O2`.
- Toolchain candidate: xPack `riscv-none-elf-gcc` (Zbb support to be confirmed in S5).
- `npu.h` exposes `npu_load_w(addr,k)`, `npu_load_i(addr,k)`, `npu_compute(k,clr)` and `npu_read(idx)` as `.insn` inline-assembly wrappers. All except `npu_read` carry a `"memory"` clobber.
- ELF → `itcm.hex` / `dtcm.hex` for `$readmemh`.

### 9.2 DTCM layout (4-image batch)

| Symbol | Content | Words | Bytes | Address range |
|---|---|---|---|---|
| W1 | 16 tiles × 784 (packed per §6.2) | 12,544 | 50,176 | `0x1_0000–0x1_C3FF` |
| W2 | 8 tiles × 64 | 512 | 2,048 | `0x1_C400–0x1_CBFF` |
| W3 | 3 tiles × 32 (10 rows padded to 12 with zeros) | 96 | 384 | `0x1_CC00–0x1_CD7F` |
| B1, B2, B3 | int32 bias, 64 + 32 + 12 | 108 | 432 | `0x1_CD80–0x1_CF2F` |
| QP | requant parameters | 16 | 64 | `0x1_CF30–0x1_CF6F` |
| X | layer-1 input, 784 words × 4 images | 784 | 3,136 | `0x1_CF70–0x1_DBAF` |
| ACT1 | layer-1 output, 64 words | 64 | 256 | `0x1_DBB0–0x1_DCAF` |
| ACT2 | layer-2 output, 32 words | 32 | 128 | `0x1_DCB0–0x1_DD2F` |
| LOGITS | int32, 12 rows × 4 images | 48 | 192 | `0x1_DD30–0x1_DDEF` |
| MAILBOX | TB→FW "next batch ready" flag | 1 | 4 | `0x1_DDF0–0x1_DDF3` |
| free / stack | | | 8,716 | `0x1_DDF4–0x1_FFFF` |

The data region totals 56,816 B. Every region base is 16-byte aligned, as quad LOADs require. Weight tiles are stored quad by quad: word `16s + 4i` (byte offset within the tile) holds W[4t+i][4s..4s+3]; X and the activation buffers hold, at byte offset `16s + 4j`, the four values 4s..4s+3 of image j. Model is **784-64-32-10** (decision 2026-10-14); the retrained export is committed in `model/py/export/` (2026-10-23, D14), and `pack_weights.py` must not generate this image from any other export. `pack_weights.py` generates this image and its linker symbols. The exact symbol addresses are taken from the linker map, not hard-coded.

### 9.3 Per-layer loop (reference algorithm)

```
npu_load_i(IN, K)                              // once per layer; IBUF reused across tiles
for t in 0 .. N_out/4 - 1:
    npu_load_w(W + t*4K, K)                    // a tile is 4 rows × K bytes = 4K bytes
    npu_compute(K, clr=1)
    for i in 0..3, j in 0..3:
        v = npu_read(4*i + j) + B[4t + i]
        out[i][j] = requant(v)                 // final layer keeps int32
    for j in 0..3: OUT[16t + 4j] = pack(out[0][j], out[1][j], out[2][j], out[3][j])
                                               // neurons 4t..4t+3 of image j = next layer's quad t, word j
```

`requant()` must be **bit-identical** to the golden model. Formula (from `model/py/golden_int8.py`, functions `requant` and `find_ms`):

```
acc = Σ x·w + b_q                       // bias added before requant (int32)
y   = clamp((acc * M + 2^(S-1)) >>> S, 0, 127)   // arithmetic shift; clamp 0 also acts as ReLU
```

`find_ms` chooses the largest `S` with `M ≥ 1` and `bound·M + 2^(S−1) ≤ 2³¹−1`, where `bound = max_j (Σ|w_q[j]|·127 + |b_q[j]|)`. The product therefore never overflows int32, so firmware needs only `mul` (low 32 bits), `add`, `srai`, `max`, `min`; `mulh` is not required. Weights are quantised to ±127 (−128 never occurs). Per-layer `M`, `S` live in the QP region of DTCM. The final layer writes int32 logits to LOGITS. Argmax is computed by both the testbench and the golden.

### 9.4 Batch protocol

1. The firmware runs one batch.
2. It writes `SIM_CTRL = BATCH_DONE`.
3. The testbench reads LOGITS by backdoor, compares them with the golden file, loads the next X by backdoor, and sets MAILBOX = 1.
4. The firmware polls MAILBOX, clears it and continues.

The last READ_RESULT has already drained the engine before step 2, so the backdoor write of X cannot violate the WAR rule.

## 10. Verification architecture

### 10.1 Environments

| Env | DUT | Owner | Agents and components |
|---|---|---|---|
| `mac_env` | `mac_engine` | B | `cmd_agent` (active: push, read, CSR); `dtcm_agent` (reactive responder holding a 16K-word memory model); predictor calling `npu_ref` (DPI-C); scoreboard; coverage; SVA bound to the DUT |
| `core_env` | core + ITCM + DTCM, engine replaced by a stub (always ready, logs commands, returns `rd_data = idx`, CSR reads return 0) | A | `npu_rvvi_agent` (passive); `npu_cosim_checker` running `rv_iss` in lockstep (DPI-C), the counterpart of Coral's `coralnpu_rvvi_agent` + `coralnpu_cosim_checker` (D13); instruction-stream sequences that backdoor-load ITCM; per-extension covergroups |
| `soc_env` | `npu_top` | A+B | `npu_rvvi_agent` + `npu_cosim_checker` with lockstep `rv_iss` (whose custom instructions call `npu_ref`, so the whole system is predicted); `fifo_monitor`; `sim_ctrl_monitor`; MNIST file comparator; D0/D1 equivalence harness |

**Common structure (D13):** every env lives in a package (`mac_env_pkg`, `core_env_pkg`, `soc_env_pkg`); `tb/uvm/tb/npu_tb_top.sv` instantiates the DUT for `soc_env`; each env has a compile file list (`*_dv.f`). Programs and data are loaded by backdoor before reset is released. **End of test:** a `SIM_CTRL` PASS/FAIL write, or the core's halt/fault indication if the W2-1 policy defines one, or a timeout (default 10× the expected cycle count). A timeout is a failure.

### 10.2 Golden models (C, compiled for DPI-C and as standalone unit-test executables)

**`npu_ref.c`:**
- `npu_ref_reset()`
- `npu_ref_mem_write(word_idx, data)`
- `npu_ref_cmd(op, addr, k, clr)`
- `npu_ref_read(idx)`
- `npu_ref_status()`
- `npu_ref_csr_write(addr, data)`
- `npu_ref_csr_read(addr)`: returns `npu_status` for 0x7C0, the stored value for 0x7C1, 0 for any other address (needed by `ISS_FULL` to serve CSR reads)

The reference keeps its own DTCM image. Every sequence that writes the responder memory also calls `npu_ref_mem_write`.

**`golden_int8.py`** (`model/py/`, pure numpy, decision D15): `quantize_input`, `requant`, `find_ms`, `compute_bound`, `IntModel` and `load_export`. It is the integer oracle for SC5 and `pack_weights.py`. **Gate:** `python -m pytest model/py/tests -v` must pass, including the cross-check of a K = 784 tile against `npu_ref`, before it is used.

**`rv_iss.c`:** an RV32IM + Zicsr + Zifencei + Zbb + custom-0 instruction-set simulator.
- API: `iss_init(itcm, dtcm)` and `iss_step(&rec)`, which returns the expected retire record.
- Not modelled: `mcycle` values (the comparison masks CSR reads of 0xB00/0xB80/0xC00/0xC80 and `npu_busy_cyc`).
- Modes: `ISS_STUB` (for `core_env`; custom instructions mirror the stub, so READ_RESULT returns `idx` and reads of 0x7C0/0x7C1 return 0) and `ISS_FULL` (for `soc_env`; custom instructions call `npu_ref`).

**Gate before use:** each golden model must pass its own unit tests before it is used as an oracle. For `npu_ref` these include hand-computed 4×4 cases, wrap on overflow and every error case. For `rv_iss` they include the instruction corner cases and riscv-arch-test signatures where available.

### 10.3 Test list (minimum)

| Env | Directed | Random |
|---|---|---|
| mac | single LDW/LDI/MAC with K=4; K=KMAX; K=0; K=KMAX+4; K=6 (not a multiple of 4); misaligned address (`a[3:0]=4`); out-of-range address; illegal op; clr vs accumulate; forced wrap (repeated accumulate with ±128·±128 operands); FIFO fill to full with back-to-back pushes; READ while busy; W1C clear of error bits | `mac_rand_seq`: random op mix, K ∈ weighted bins, random operands with corner-value bias, random inter-command gaps (0–20 cycles), ≥ 200 seeds |
| core | per instruction: every M/Zbb/Zicsr/Zifencei instruction including div corners; hazard distance 1/2/3 for each forwarding path; load-use; custom-instruction decode and push timing (with stub); FIFO-full stall (stub with `ready = 0`) | `core_rand_seq`: random ALU/M/Zbb streams with controlled dependency distance, then streams with branches; ≥ 200 seeds |
| soc | one firmware test per custom instruction; WAR-violation negative test (expects A-SOC-1 to fire); 4×4×K matmul vs `npu_ref`; full layer-sized matmul (784×64); MNIST 1,000 images (D11) | `soc_rand_matmul`: Python generates random M×K×N int8 matrices plus firmware data from a seed |

### 10.4 D0/D1 equivalence harness

Run the identical test with the same binary and seed on `GATING_EN=0` and on `GATING_EN=1`. Compare:
- the SHA-256 of the RVVI retire log
- final `mcycle` and `minstret`
- the LOGITS dump

Every soc test and every MNIST run is executed in both configurations. Any difference is a failure (SC3).

### 10.5 Coverage plan (all bins declared before week 7; closure required before week 10)

| Group | Bins |
|---|---|
| `cg_cmd` | op {LDW, LDI, MAC, ILLEGAL} × K {0, 4, 8–60, 64–KMAX-4, KMAX, >KMAX} × K mod 4 {0, 1, 2, 3}; MAC × clr {0, 1} × acc-nonzero-before {0, 1} |
| `cg_operand` | per lane (16 lanes per quad), value ∈ {-128, -1, 0, 1, 127, other} for WBUF and IBUF |
| `cg_fifo` | occupancy at push {0, 1, 2–6, 7, 8=full}; push-while-full (stall) observed |
| `cg_state` | transitions IDLE→CHECK, CHECK→LOAD, CHECK→MAC, CHECK→IDLE (dropped), LOAD→IDLE, MAC→IDLE; READ arriving while busy |
| `cg_acc` | accumulate result wraps positive→negative and negative→positive |
| `cg_err` | each error bit set; set while already set; W1C clear |
| `cg_addr` | LOAD touching the first DTCM quad, the last DTCM quad, one quad past the end; `a[3:0]` ∈ {0, 4, 8, 12, other} |
| `cg_gate` (D1 only) | en rise, en fall, en low for 1 cycle, en low for ≥ 100 cycles |
| core `Cvgrp_*` | per extension: every opcode; rd = x0 and rd ≠ x0; rs1 = rs2; forwarding source {EX/MEM, MEM/WB, none}; DIV {÷0, overflow, normal}; CSR {rw, rs, rc, imm variants} × {0xB00, 0xB02, 0x7C0, 0x7C1} |

### 10.6 Assertions (SVA)

| ID | Property |
|---|---|
| A-MAC-1 | no FIFO push while full; no pop while empty |
| A-MAC-2 | `rd_ready |-> (fifo_empty && fsm==IDLE)` |
| A-MAC-3 | `b_req` only in `LOAD`; `b_addr` stays within DTCM |
| A-MAC-4 | buffers are never written outside `LOAD` |
| A-MAC-5 | every popped command returns to IDLE within K/4 + 3 cycles |
| A-GATE-1 | `(fsm != IDLE || !fifo_empty) |-> en` (never gate pending work) |
| A-GATE-2 | when `GATING_EN = 1` and `en_l = 0`, `clk_mac` stays low |
| A-SOC-1 | a port-A store to word *w* while a queued or running LOAD covers *w* is a WAR violation (error) |
| A-CORE-1 | while READ_RESULT stalls in MEM, no younger instruction writes back |

## 11. Switching-activity methodology

**Workloads:**
- **Synthetic** firmware that alternates NPU bursts (LDW + LDI + MAC with K=256) with scalar busy-loops. Idle ratios are 10, 25, 50, 75 and 90 % (measured by `npu_busy_cyc / mcycle`).
- **MNIST**, 100 images = 25 batches (E4, D11). Cross-check: the MNIST idle ratio (`npu_busy_cyc / mcycle`) placed on the synthetic E2 curve should predict the E4 result to within the spread of the E2 points.

**Window:** firmware writes `SIM_CTRL = MEAS_START` and `MEAS_STOP`. VCD/FST dumping is enabled only inside the window and only for the scope `npu_top.u_mac_engine`.

**Metrics:**
- **M1:** toggle count on the net `clk_mac`.
- **M2:** sum of toggle counts over all nets in `u_mac_engine`, split into M2-free and M2-gated.
- Both are reported per 1,000 cycles. Note that M1 is roughly proportional to the busy fraction, while M2 reflects real data activity.

**Fairness:** D0 and D1 use the same binary, the same simulator version and the same dump options. Each configuration is run once; reruns happen only after a logged external failure.

**Tooling:** `power/toggle_count.py` reads the VCD, writes CSV, and `power/plots.py` produces the figures. Every figure states the configuration, workload, seed and unit, and is labelled "switching-activity estimate". If a run is ever taken on Verilator (D1a), one QuestaSim VCD run of the same workload cross-checks the counts.

## 12. Tools, repository and reproducibility

```
mini-npu/
  rtl/{core,npu,mem,top,prim}/   rtl/prim/npu_clk_gate.sv   rtl/top/npu_pkg.sv
  tb/uvm/{common,mac_env,core_env,soc_env,tb}/   tb/sva/
  model/c/{npu_ref.c,rv_iss.c,tests/}   model/py/{golden_int8.py,pack_weights.py,gen_matmul.py}
  sw/{crt0.S,link.ld,npu.h,tests/,mnist/,synthetic/}
  sim/questa/   sim/verilator/   power/   notebooks/   docs/
  manifest.yaml   Makefile (or run.py)
```

- `manifest.yaml` records the QuestaSim (and licence type), Vivado, Verilator, GCC and Python versions, the git hash, seeds and the test list.
- The regression entry point `run.py --simulator {questa,xsim} --target <test|suite> [--config d0|d1] [--seeds N]` (same interface style as Coral's `utils/run_uvm_regression.py`, D13) prints pass/fail per test × seed and merges coverage. `run.py all` regenerates every SC1–SC5 artefact and the E2/E4 data (SC6).
- Raw logs and VCDs are kept under `out/<date>/<config>/`. Large files are not committed; their hashes are recorded instead.

## 13. Week-1 smoke-test gate

Each item is answered "works / does not work, with evidence (log)". The proposal (Tables 1, 3, 9, 11 and 12) is updated after this gate.

| ID | Check |
|---|---|
| S1 | QuestaSim compiles and runs a minimal `uvm_test` with a class that calls `randomize()`, and `` `uvm_info `` prints (this is the check that fails on the FPGA Starter edition) |
| S2 | QuestaSim calls a C function through DPI-C (`import "DPI-C"`), passing ints and a `bit [31:0]` |
| S3 | QuestaSim functional coverage (a covergroup) produces a report (`vcover report`) |
| S4 | Verilator lints a toy design; simulates an `icg_cell` with a latch and dumps VCD in which `gclk` stops while `en = 0` |
| S5 | the GCC toolchain assembles a Zbb instruction (`max`) and a `.insn r 0x0B, ...`; objcopy produces a `$readmemh` hex |
| S6 | Vivado xsim runs the same S1 test (fallback check, 15 minutes) |
| S7 | QuestaSim dumps a VCD for a chosen scope over a chosen time window (`vcd file`, `vcd add`) |

## 14. Ownership and schedule outline

| Weeks | Track A (core) — Tấn | Track B (MAC engine) — Bảo | Joint |
|---|---|---|---|
| 1 | S1–S7 (split) | S1–S7 (split) | gate review |
| 2 | ISA and encoding doc, CSR map, trap/fault policy | engine interface freeze (§7.1), `npu_ref` + unit tests | sign off §6 and §7.1 |
| 3–4 | M, Zicsr, Zifencei, Zbb, custom decode/push; `rv_iss` + unit tests | `mac_engine` RTL (D0); `dtcm_dp`; `mac_env` skeleton | |
| 5–6 | `core_env` + directed tests | `mac_env` directed tests | `npu_top` integration, first soc test |
| 7–9 | core random + coverage | mac random + coverage | soc tests, coverage closure (SC2) |
| 10–11 | — | `npu_clk_gate`, D1 | equivalence harness, D1 regression (SC3) |
| 12 | synthetic firmware | `toggle_count.py` | E2 data |
| 13–14 | MNIST firmware | `pack_weights.py`, golden files | MNIST 1,000 images bit-exact on D0/D1 (SC5); report skeleton |
| 15 | | E4 MNIST toggles (100 images) | full 10,000-image run (D0); `run.py all` on a clean clone (SC6) |
| 16 | | | English report, slides, reproducibility package (D12) |

Report chapters are drafted at phase ends: verification (week 10), power (week 13), MNIST and conclusions (week 15).

The detailed task-level plan (with "done" tests per task) is written next in `docs/superpowers/plans/`.

## 15. Risks

| Risk | Mitigation |
|---|---|
| No full QuestaSim licence, or it lacks a feature (UVM/DPI/coverage) | Found in week 1 (S1–S3). Fallback: xsim (S6). Last resort: Verilator UVM or pyuvm. |
| Questa run time too long for MNIST batches | Measure in week 14. For scale only: Coral reports its RTL Verilator model at about 15 kcycles/s (a different, larger design), which would put 1,000 images (≈3M cycles) at a few minutes. If too slow: long runs on Verilator with a Questa cross-check (D1a). Cut order if late: drop the 10,000-image run, then reduce E4 to 20 images; SC3 on MNIST and the report are never cut. |
| `rv_iss` is late, blocking `core_env` | Keep the ISS minimal and test it first. Interim: riscv-arch-test self-checking signatures as directed tests. |
| Interface churn between tracks | Freeze §6 and §7.1 at the end of week 2. Changes after that need both students' sign-off and a spec update. |
| DTCM WAR bugs in firmware | Software rule plus A-SOC-1, and a negative test that proves the assertion fires. |
| Requant mismatch with golden | Formula fixed in §9.3; unit-test the firmware `requant()` on the host against `golden_int8.requant` with the retrained `M`, `S`. |
| Schedule pressure | Protect the order D0 correct → D1 equivalent → switching activity → MNIST. 8×8 and pipelining are dropped first. |

## 16. Relation to CoralNPU (contribution boundary)

| Aspect | CoralNPU (`VmeCoreMini`, commit `382b5c1`) | Mini-NPU |
|---|---|---|
| Scalar core | 4-lane superscalar, in-order, Chisel | the team's 5-stage pipeline, Verilog/SV |
| ISA | RV32IMF_Zba_Zbb_Zicsr_Zifencei + RVV 1.0 + Zvt (experimental) | RV32IM_Zicsr_Zifencei_Zbb + 4 custom-0 instructions |
| Command path | scalar dispatch → 8-entry command queue → decoupled backend | MEM-stage push → 8-entry FIFO → decoupled engine |
| Operand staging | `vle8` from DTCM into a 32×128-bit vector register file | engine LOAD from DTCM into WBUF/IBUF |
| Matrix compute | outer-product engine N×M×K (docs: typical 8×8×4 = 256 MAC/cycle, VDOT dot4 per PE); repo VME: 16 tiles `mt0..mt15`, INT8/FP32/BF16 | N×M×K = 4×4×4 = 64 MAC/cycle, int8 dot4 PEs, 1 tile |
| Result path | `vtmv.v.t` then `vse32` | READ_RESULT to a scalar register |
| Memory | datasheet: 8 KB ITCM, 32 KB DTCM, single-cycle SRAM; repo: banked DTCM (4 × 32 b) + crossbar, 128-bit DBus | ITCM 16 KB; DTCM 4 banks × 32 b, 64 KB (the model needs 56.8 KB, D6); port A 32 b (core), port B 128 b (engine) |
| Clock gating | whole-core gate on WFI/CSR (`CoreAxi.scala`) | MAC-engine gate on hardware-detected idle |
| Verification | cocotb suites; UVM on VCS/Verilator with `coralnpu_rvvi_agent` (passive) and `coralnpu_cosim_checker` against the MPACT simulator (`tests/uvm/env/coralnpu_env_pkg.sv`, main branch, read 2026-10-15); backdoor ELF load; end on `halted`/`fault` or timeout | self-built SV UVM only; `npu_rvvi_agent` + `npu_cosim_checker` against our own `rv_iss`; own C NPU model; backdoor `$readmemh`; end on `SIM_CTRL`, halt/fault or timeout |
| Power evidence | power targets in the guides ("10 mW power envelope"); cocotb VCS split flow kept "for gate-level power analysis" | RTL switching-activity estimates only (no synthesis in Senior Project 2) |
| Workload | MobileNet via LiteRT; RVV matmul examples (`tests/cocotb/rvv/ml_ops/`) | 784-64-32-10 int8 MLP on MNIST, bare-metal C |

**Matrix-engine status.** The developer-guide introduction still says the matrix execution unit is planned for a future release, while the repository at `382b5c1` contains an experimental VME (Zvt) implementation. Mini-NPU follows the documented semantics (outer product, N×M×K, dot4 into int32) and does not depend on the experimental RTL.

No CoralNPU RTL or testbench code is reused. CoralNPU is cited as the architectural inspiration, and its source files are cited where a pattern was studied (`ClockGate.sv`, `tests/uvm` structure, `vme_matmul_test_program.cc`).

## 17. References

- Proposal references [1]–[12] apply.
- Google, `google-coral/coralnpu`, commit `382b5c1`: `doc/overview.md`, `doc/microarch/*.md`, `hdl/verilog/ClockGate.sv`, `hdl/chisel/src/coralnpu/CoreAxi.scala`, `hdl/verilog/rvv/design/Zvt/`, `tests/uvm/README.md`, `tests/cocotb/vme_test/vme_matmul_test_program.cc`.
- Google, Coral NPU developer guides (developers.google.com/coral/guides): Introduction to Coral NPU (`intro-coralNPU`); Datasheet (`hardware/datasheet`); ML inferencing (`hardware/arch_ml`); Decode and dispatch (`hardware/decode-dispatch`); IP evaluation guide (`hardware/evaluation`); Performance and power (`power`); Bare-metal programming (`software/bare-metal-prog`); Matrix multiplication examples (`software/examples-matmuls`). Read 2026-10-15.
- Google, `google-coral/coralnpu` main branch (read 2026-10-15): `tests/uvm/README.md`, `tests/uvm/env/coralnpu_env_pkg.sv`, `tests/cocotb/README.md`.
- [PH] D. A. Patterson, J. L. Hennessy, *Computer Organization and Design: The Hardware/Software Interface, RISC-V Edition*, 2nd ed., Morgan Kaufmann, 2021.
- [ST] W. Stallings, *Computer Organization and Architecture: Designing for Performance*, 11th ed., Pearson, 2019.
- Chapter-to-task reading guide: `docs/references/README.md`.
- Altera, *Questa–Intel FPGA Edition Simulation User Guide*, "Simulator versions and licensing" (Starter edition: free, reduced performance). Altera Community, "Questa Starter Edition 25.1 – svverification license checkout fails" (staff answer: FPGA editions do not support `randomize`/`covergroup`; full QuestaSim needed).
