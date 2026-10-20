# Track A, Phase 1: implementation and verification report

Date: 2026-10-20 · Branch: `main` (merged from `claude/confident-sagan-wz5k2j`) · Author: Claude, at Tấn's request (graded-code permission, `CLAUDE.md` section 1) · Independent reviewer: a separate subagent (section 7)

> **For Tấn.** Everything below was written by Claude. The project is graded on you being able to explain and defend it. Section 9 lists what you should be able to answer; sections 4 to 6 give the reasoning. Read the code with this report beside it, run the commands in section 2, and break something on purpose (the mutation scripts in section 8 show how).

## 1. Scope and result

Phase 1 plan tasks of Track A (`docs/superpowers/plans/2026-10-04-mini-npu-phase1.md`), executed in this order: 4, 5, 6, 7, 9, 8, 12 (Task 9 before Task 8 because Task 8's top level instantiates Task 9's engine stub; ledger ruling).

| Task | What | Commit | Evidence |
|---|---|---|---|
| 2 (Track A part) | `docs/core_isa.md`: encodings, CSR map, W2-1 options, `cpu_en` record. **W2-1 itself is still open** (your and Bảo's decision) | `19be01d` | encodings cross-checked against the assembler (41 words, 94 field cells) |
| 4 [support] | `RefISS` (Python oracle) extended to M/Zicsr/Zifencei/Zbb/custom-0, test suites, `expected_failures` patterns | `0d7b38c` | oracle pinned by hand-computed vectors, 8 mutations caught |
| 5 | M extension: `Multiplier.v`, `Divider.v`, stall vector in `Hazard_Unit.v` | `040e81c` | 15 directed + 300 random, 7 mutations caught |
| 6 | Zicsr + counters: `CSR_Unit.v`, valid bit, exact `minstret` | `ef773fc` | 15 tests, 8 mutations caught |
| 7 | Zifencei + Zbb: `BitManip.v`, `fence.i` | `3d4fede` | 26 directed + 300 random, 10 mutations caught |
| 9 | custom-0 decode, MEM-stage push, `READ_RESULT`, `mem_busy` stall | `95e5091` | 26 directed (7 stall-overlap) + 200 random with random ready patterns, 11 mutations caught |
| 8 (Track A part) | memories out of the core, `itcm.sv`, SIM MMIO, RVVI retire trace | `6280c97` | 20 checks; full RVVI trace compared in every test; 8 mutations caught |
| 12 | `model/c/rv_iss.{h,c}` | `fbc3fd5` | 19 unit tests; 1256 programs / 514,900 retire records identical to `RefISS`; 10 mutations caught |
| cleanup | Verilator-clean new SV, status sync | `976420b` | lint: 0 warnings in the new `.sv` files |

Final state before the independent review (section 7 gives the state after it): `python tools/rv32i_check/run_all.py` gives `total 1283, passed 1283, known failures 0, RESULT: PASS`; `make -C model/c test` passes; `make -C model/c xcheck` reports `1256 programs, 514900 retire records identical to RefISS`. `tools/rv32i_check/expected_failures.txt` is empty.

**Not done, by design:** Phase 2-4 Track A tasks (13, 15, 17, 21, 22, 26) need `npu_top`, the engine, UVM and MNIST assets that do not exist yet. Task 8's `dtcm_dp` and its test `dtcm_port_b_quad` belong to Bảo. Decision W2-1 and the freeze signatures belong to both of you.

## 2. How to reproduce

```
python3 tools/rv32i_check/run_all.py      # 7 suites, about 2 minutes; exit 0 = PASS
make -C model/c test                      # npu_ref + rv_iss unit tests (ASan + UBSan, -Werror)
make -C model/c xcheck                    # C ISS vs the Python oracle on every program of the suites
verilator --lint-only -Wall -DRVVI_TRACE --top-module core_tb_top rtl/top/core_tb_top.sv rtl/top/core_tb_dtcm.sv rtl/top/npu_stub.sv rtl/mem/itcm.sv $(find rtl/core -name '*.v')
```
Tools needed (installed in the cloud container with `apt`): Icarus Verilog 12, Verilator, `binutils-riscv64-unknown-elf`, gcc, Python 3.

## 3. The core after this work

```
 imem_addr/rdata                                          dmem bus (re, we[3:0], addr, wdata / rdata)
       |                                                          ^        |
  IF --- IF/ID --- ID --- ID/EX --- EX ---------- EX/MEM --- MEM ---------+--- MEM/WB --- WB
  PC     valid     decode  held       ALU, Multiplier,       |  LSU lane logic        |   regfile write
                   hazard  operands   Divider (iterative),    |  custom-0 push --> cmd_* port (engine)
                   detect  insn word  BitManip, CSR_Unit,     |  READ_RESULT  <-- rd_req/rd_ready/rd_data
                                      fence.i (jump to PC+4)  |  mem_busy ------> Hazard_Unit
```
Stall vector (`Hazard_Unit.v`, `docs/core_stall.md` section 3): `stall_mem = mem_busy`; `stall_ex = stall_mem | div_busy`; `stall_id = stall_ex | load_use`; a branch redirects only when EX is not held; the divider puts bubbles into EX/MEM, a MEM wait puts bubbles into MEM/WB. Every pipeline register carries a `valid` bit, the instruction word and (in MEM/WB) the memory access of the instruction.

## 4. Task by task: what was built and why

**Task 4 (oracle and test infrastructure).** `RefISS` (class in `tools/rv32i_check/run.py`) is cycle-free. `minstret` is exact, `mcycle` counts one per instruction, so tests only use derived booleans of cycle reads. A model that every later test trusts must itself be tested: `test_refiss.py` pins it with values worked out by hand (for example `mulhsu(-1, 0xFFFFFFFF) = 0xFFFFFFFF`, `-7 / 2 = -3 r -1`, `rori 0x1,31 = 2`); eight deliberate corruptions of `RefISS` are all caught.

**Task 5 (M).** The multiplier is one combinational 33x33 signed product (the extension bit is the sign bit only when the operand is signed for that operation). The divider is restoring radix 2, 34 cycles in EX, with the two spec corner cases handled before the loop. Operands are **sampled in the first EX cycle** because forwarding sources disappear while the instruction waits. `alu_operation` grew from 4 to 6 bits: M (8) + Zbb (17) + base (10) = 35 codes do not fit in 5 bits.

**Task 6 (Zicsr).** CSR instructions execute in EX; an instruction in EX is never on a wrong path, so the write can happen at the end of that cycle. `minstret` is exact: the read adds the valid instructions still in MEM and WB (they are older and will retire). This needed the valid bit in every pipeline register. Provisional rulings that **Bảo must confirm** (section 6): `csr_wdata` is the read-modify-write result, `csr_rdata` is combinational.

**Task 7 (Zbb, fence.i).** `BitManip.v` is a 17-way combinational unit. The unary operations are selected by the `rs2` field (`clz`/`ctz`/`cpop`/`sext.b`/`sext.h`) or by the whole 12-bit immediate (`orc.b` `0x287`, `rev8` `0x698`), so `Control.v` got the `rs2` field as a new input. `zext.h` is `pack rd, rs1, x0`; `pack` itself is not Zbb, so `rs2 = x0` is part of the decode (test `zbb_pack_not_decoded`). `fence.i` is a jump to PC+4 in EX: two bubbles, and a refetch that always returns the same bytes because the ITCM is read-only.

**Task 9 (custom-0).** Rs1 reaches MEM as the ALU result (`rs1 + 0`) and rs2 as the store-data value, so no new datapath was needed. `READ_RESULT` returns data through the load path (writeback select 01), so the existing load-use and forwarding logic apply. The command is pushed in MEM: every older store has already written the DTCM (test `store_then_load_order` shows the DTCM word at the push). While MEM waits, MEM/WB takes bubbles. The stub checks that `cmd_valid` and the operands stay put until `cmd_ready`.

**Task 8 (memory map, RVVI).** The core no longer contains memories: `imem_*` (combinational ITCM read) and a data bus whose read answers one cycle later. The LSU keeps the byte-lane logic in the core. `core_tb_top.sv` decodes the bus (ITCM / DTCM stand-in / `SIM_CTRL` / `SIM_PUTC`). The retire record is produced from MEM/WB (one record per instruction leaving WB), and its field semantics are written down in `docs/core_isa.md` section 9.2 as the contract for `rv_iss.c` and the future cosim checker.

**Task 12 (C ISS).** Same semantics as `RefISS`, written in C99 with `uint32_t` arithmetic and `int64_t` for signed operations (no undefined behaviour under UBSan). `ISS_FULL` drives `npu_ref` and mirrors core stores into its DTCM image.

## 5. Defects and gaps found while working (all fixed, each with a test)

| # | Found by | What | Fix and test |
|---|---|---|---|
| 1 | analysis of `core_stall.md` + mutation | A divide that is not bubbled out of EX/MEM re-enters MEM every stall cycle, and **register compare cannot see it** (the final value is right) | `minstret_across_divide` (Task 6); later the full RVVI trace comparison in every test |
| 2 | new test `mem_stall_stale_operand` (RED on purpose before the fix) | A held EX instruction used a stale operand once the older producer had left the pipeline (`add x8,x7,x7` computed `0` instead of `14`) | ID/EX reloads its operand registers with the forwarded value while held; tests `mem_stall_stale_operand`, `..._push` |
| 3 | new test `csr_write_once_under_mem_stall` | A CSR instruction held in EX wrote on every held cycle and then read its own write (`0xFF` instead of `0x0F`) | `CSR_Unit.ex_advance`; same test |
| 4 | surviving mutants of the Task 8 tests | the tests could not see a dropped DTCM address bit, or stale read data on an unmapped load | `dtcm_no_aliasing`, `unmapped_load_after_dtcm_read` |
| 5 | first full run on the new harness | trace compare flagged `mcycle` values (RTL counts real cycles, the oracle one per instruction) | only the value of cycle-counter reads is masked; one test that does arithmetic on raw cycles opts in with `cycle_dependent=True` |
| 6 | designing the C/Python cross-check | the Python oracle decoded `jalr` with `funct3 != 0`; the RTL (and the C ISS) treat it as a NOP | test `jalr_funct3_is_nop` RED, then the oracle was fixed |
| 7 | running the first vectors | several of **my own hand-computed expectations** were wrong (a counter position, a halfword lane, a `jal` target) | corrected after tracing by hand; the lesson is why oracles get their own tests |
| 8 | review of passing tests | `csr_unknown_reads_zero` passed on an RTL that did not implement CSRs at all | made non-vacuous (added a read with a non-zero result) |
| 9 | harness review | `run_rtl` could read a stale `rtl_state.txt` from a previous run | the file is deleted before each run |

## 6. Decisions taken on your behalf ("rulings"; each has a cost if wrong)

| Ruling | Cost if wrong | Needs |
|---|---|---|
| `alu_operation` widened to 6 bits (`[5]` Zbb, `[5:4]=01` M) | one rename | none |
| `csr_wdata` = read-modify-write result; so `csrrs`/`csrrc` on the W1C `npu_status` clear bits unexpectedly, software must use `csrrw` | engine CSR port semantics | **Bảo** (section 7 of `docs/core_isa.md`) |
| `csr_rdata` combinational in `csr_addr` | one stall cycle for engine CSR reads | **Bảo** |
| `mcycle`/`minstret` writes and writes to the read-only aliases are ignored; unknown CSR reads 0 | firmware cannot reset counters (it uses deltas) | W2-1 |
| `minstret` read in EX = retired + valid in MEM and WB | off by at most 2 under bubbles | none |
| unknown encodings, `ecall`, `ebreak` stay NOPs; `rvvi_trap` = 0 | the whole W2-1 policy | **Tấn + Bảo decision** |
| unmapped data addresses (and the ITCM as data) read 0 and ignore writes; a fetch outside the ITCM executes a NOP | policy W2-1; also **the Phase 2 plan puts `.rodata` in the ITCM, which the LSU cannot read** (question for Task 13) | W2-1 / spec 4.1 |
| Task 8 on a port-A stand-in DTCM; `dtcm_port_b_quad` not run | port-B coverage waits for Bảo | **Bảo** |
| Task 9 before Task 8 | none | none |
| SP1 memory model (`MEMMAP=sp1`) removed from the harness | the old 256-word model is gone with `ProgramMemory`/`Data_Memory` | none |

## 7. Independent review

A separate subagent (no shared context with the author, on the most capable model) reviewed the whole branch in a scratch copy: it re-ran the regression and the C checks, linted the RTL, wrote 35 new directed programs and 4,515 phase-shifted stall runs, a new random generator (400 programs) and 12 mutants of its own. **Verdict: no Critical finding, no RTL bug found; ship after fixing one Important harness gap and some doc and spec drift.** Numbers in this section marked *(reviewer)* are the reviewer's own; I did not re-run its scratch scripts. Everything marked *(re-run)* I ran myself in this session.

| # | Finding | Grade | What I did |
|---|---|---|---|
| I1 | `compare()` passed when the RTL never reached the end of the program: it compared only `min(len(rtl), len(ref))` retire records and the register state, so a deadlock on a trailing `READ_RESULT x0` (the drain idiom of spec 6.3 rule 5) or a lost trailing CSR write passed. | Important | **Fixed.** Reproduced first (*re-run*): tests `harness_detects_deadlock_on_read_result` and `harness_detects_deadlock_before_csr_write` were RED (compare returned no differences), plus a no-false-alarm control. `rvvi_diffs` now requires the RTL trace to contain the model's first `end: j end` retire. `tb_dump.v` also dumps the engine-stub CSRs (`npu_err`, `npu_busy_cyc`) and `compare()` checks them; tests `csr_trailing_write_no_readback` and `csr_trailing_w1c_no_readback` were not caught by the old compare under a stub mutant that drops the write (*re-run*), and each is now killed. |
| 9a | Mutant `spurious_rs2_for_compute_rr` survived: `docs/core_isa.md` 6.5 says to check that COMPUTE/READ_RESULT leave the `rs2` field unused, but no test did. The RTL is correct. | Minor, cheap | **Test added** (`no_spurious_stall_compute_rr_rs2`, mcycle delta with and without a load-use "dependency" by field); it passes on the RTL and kills the mutant (*re-run*). |
| 9b | `csr_write_every_held_cycle` was killed by one test only. | Minor, cheap | Two more programs pin `ex_advance` (`csr_write_once_behind_push`, `csr_imm_write_once_behind_read_result`); the mutant (`do_write` without `ex_advance`) now fails 3 tests (*re-run*). |
| 3 | `core_tb_dtcm.sv` wrote `mem` and `rdata` both in `initial` and in `always_ff`, which IEEE 1800 9.2.2.4 does not allow; QuestaSim (the primary simulator) likely rejects it. | Minor, but it would bite on the first Questa run | Changed to a plain `always @(posedge clk)` with a comment. Behaviour is unchanged (full regression green). **⚠️ unverified under QuestaSim**: I have no Questa here; the Questa error is the reviewer's expectation. |
| 7 | Stale docs: `core_isa.md` listed `mcycle`/`minstret` as RW and still talked about a 4-/5-bit `alu_operation`; `core_stall.md` 5.1 described an FSM the code does not have; two READMEs were out of date; `hazard_mem_wb_bubble` is unused. | Minor | Fixed in the docs (this commit). The unused Hazard_Unit output is documented, not removed (no behaviour change). |
| 5 | A CSR read in EX can see the engine before the previous push has landed (`COMPUTE; csrr t0,npu_status` may show idle). | Minor | Documented in `core_isa.md` section 7 item 4: only `READ_RESULT` is a barrier. |
| 8 | Harness polish: `assemble()` crashes without `build/` (reproduced). Others: `program.hex` / `rtl_state.txt` in the working directory (no parallel runs), `dtcm_read_sel_q` not reset, the stub divides by zero on an empty ready pattern, dead code in `tests_mem.py`. | Minor | `assemble()` fixed (creates `build/`). A missing RVVI log now fails the end-of-program check. The rest is **deferred**. |
| 1 | `csr_wdata` is the read-modify-write result, so `csrs`/`csrc` on the W1C `npu_status` clear the wrong bits. | Minor (known) | Already ruling #2 in section 6; Bảo must settle it before spec 7.1 freezes, or `sw/npu.h` allows `csrrw` only. |
| 2 | Spec drift: spec 10.1 (line 344) and 10.2 (line 365) say the stub / `ISS_STUB` return 0 for reads of `0x7C0`/`0x7C1`, but `npu_stub.sv` and `rv_iss` implement a W1C status and a read/write `npu_busy_cyc` (which plan Task 6 asks for). | Minor | **Not changed**: both students own the spec (`CLAUDE.md` section 2). Open item 6 below. |
| 6 | `cmd_addr`/`cmd_k`/`rd_idx` and `csr_addr`/`csr_wdata` toggle every cycle with unrelated instructions; spec 11 metric M2 counts toggles on every net in the engine, so this inflates the free-clock part in D0 and D1 equally and shrinks D1's relative gain. | Minor, **design decision** | **Deferred to you and Bảo**: gate these with `valid`, or document the effect when the toggle counts are reported. |
| 10 | `npu_pkg.sv` does not exist; `npu_stub.sv` hard-codes `0x7C0`/`0x7C1` and the core hard-codes opcode 3. | Minor | Deferred to Task 2. |

Reviewer results that support the verdict *(reviewer)*: `run_all.py` 1283/1283, `make -C model/c test` and `xcheck` green, Verilator lint 6 warnings (all unused signals or pins; no latch, no combinational loop, no width error), 35 directed programs and 4,515 stall-phase runs with 0 failures, 400 new random programs 0 failures, 64-cycle stalls (222 runs) 0 failures. Two of its 12 mutants survived (9a, 9b above); the rest were killed. *Declined to judge:* W2-1 policy, the engine side (Review Focus 4 and 5), `dtcm_dp` port B, `.rodata` in the ITCM, divider latency, the parked `rtl/fpga` wrapper.

State after the fixes *(re-run)*: `run_all.py` gives `total 1291, passed 1291, known failures 0, RESULT: PASS` (1283 + 8 new tests); `make -C model/c test` passes; `make -C model/c xcheck` reports `1263 programs, 516600 retire records identical to RefISS`. Verilator on the new SV: no warning (the 12 warnings printed are in the existing `rtl/core` files: unused signals and file names).

## 8. Verification method and its limits

- **Test first, watch it fail.** Every suite was committed or run RED before the RTL that makes it pass (Task 4 committed ~650 expected failures with dated reasons; each later task removed its own lines).
- **Two oracles that must agree.** The RTL is compared with `RefISS`; `rv_iss.c` is compared with `RefISS`; `RefISS` itself is pinned by hand values. All three agree on 1263 programs and 516,600 retire records (1256 and 514,900 before the review fixes).
- **Mutation checks.** About 64 deliberate corruptions of the RTL, the oracle and the C ISS were run against the suites; all were caught except two *equivalent* mutants (the `-2^31 / -1` special case in the Python oracle, and `& ~stall_mem` in the EX/MEM bubble equation, which `EX_MEM_Reg` makes redundant). Two mutants survived the Task 8 tests at first; that exposed test gaps (#4 above), now closed.
- **Limits.** `compare()` now also fails an RTL that never reaches the end of the program (review finding I1); before that, a deadlock on a trailing `READ_RESULT` passed. Everything is simulation with a stub engine and a port-A-only DTCM. Nothing here proves the real `mac_engine` handshake; `dtcm_dp` port B, the UVM cosim checker and `npu_top` integration are untested. Random programs are only as good as their generators (small register pool, corner-value preload).

## 9. Defence guide for Tấn

Be able to answer, with the code open:
1. Trace a `jalr` and a load-use stall through IF/ID/EX/MEM/WB (the plan's handover requirement). Where is the target computed, who flushes what, and which signals hold the PC?
2. Why does `alu_operation` have 6 bits, and how does `Control.v` choose between the base ALU, the M unit and `BitManip`?
3. Why does the divider sample its operands in the first cycle, what is `div_started` for, and what happens to the EX/MEM register while it runs?
4. What is the valid bit for? Why is `minstret` exact even after a flush, and why does the CSR read add the valid bits of MEM and WB?
5. The "held EX" problem: show the program that failed (`mem_stall_stale_operand`), say why the operand was stale, and explain the fix in `ID_EX_Reg.v`.
6. Why does a held CSR instruction write only when it leaves EX? What would the divider do wrong without `div_started`?
7. Why is the command pushed in MEM, and what guarantees that an older `sw` is visible to the engine's `LOAD`?
8. Why does `READ_RESULT x0, ...` still wait? How does it reach the register file and forwarding network?
9. Explain `csr_wdata` = read-modify-write and the W1C quirk. What is the safe way to clear an error bit?
10. How is the RVVI record built, and which fields would the cosim checker compare? Why is `mcycle` masked and nothing else?
11. What do the tests prove, and name two things they cannot (the original EX/MEM-bubble blind spot is the example).

## 10. Open items for you and Bảo

1. Record decision **W2-1** (spec 4.1 and decision log) and sign the §6/§7.1 freeze. Options and consequences are in `docs/core_isa.md` section 4.
2. Bảo confirms the CSR port rulings (`csr_wdata`, `csr_rdata`) and replaces `core_tb_dtcm.sv` with `dtcm_dp`; add `dtcm_port_b_quad`.
3. Decide how firmware reads constants: spec 4.1 makes the ITCM fetch-only, the Phase 2 plan puts `.rodata` there.
4. `rtl/fpga/RISC_V_Fixed_Impl_Top.v` (parked) still uses the old core ports.
5. Task 4's `RefISS`, `rv_iss.c` and the RVVI field list are the contract for Phase 2's cosim checker (Task 15, 17).
6. Spec 10.1 (line 344) and 10.2 (line 365) say the core-only stub returns 0 for reads of `0x7C0`/`0x7C1`; the stub, `rv_iss` and plan Task 6 implement a W1C status and a read/write `npu_busy_cyc`. Fix the spec sentence in one commit both of you sign.
7. Decide about the engine-port toggling (review finding 6) before the toggle counts are reported.
