# `mac_engine`: microarchitecture notes (Task 11)

Block note for the MAC engine (spec §7, plan Phase 1 Task 11). The spec is normative; this note records how the RTL meets it: the exact cycle timing and latency per op (spec §7.2 asks for them here, for A-MAC-5), and the choices the spec left open. Owner: Track B (Bảo). The RTL was written by Claude at Bảo's request, stage by stage, on 2026-11-05 (plan Task 11 status row).

Files: `rtl/npu/mac_engine.sv` (top, ports exactly spec §7.1), `rtl/npu/cmd_fifo.sv`, `rtl/npu/pe_array.sv`, `rtl/prim/npu_clk_gate.sv`. Constants come from `rtl/top/npu_pkg.sv`.

## 1. Structure and clock domains (spec §7.3)

| Free clock `clk` | Gated clock `clk_mac` (from `npu_clk_gate`) |
|---|---|
| `cmd_fifo` (8 × 67 bit: op, addr, K, clr) | WBUF, IBUF (256 × 128 bit each, not reset) |
| FSM `state_q` (IDLE, CHECK, LOAD, MAC) | buffer read registers `w_rd_q`, `x_rd_q` |
| error bits `err_q`, `npu_busy_cyc` | `pe_array`: 16 dot4 PEs and 16 accumulators |
| step counter, port-B request and address, buffer write strobe and index, MAC step flags | |

`rd_data = acc[rd_idx]` and `csr_rdata` are combinational (spec §7.1, §7.3, D21). `rd_req` is not used: `rd_data` depends on `rd_idx` alone, and the core qualifies it with `rd_ready`.

## 2. FSM

```
            fifo not empty               cmd_ok && LOAD
   IDLE ------------------> CHECK ---------------------> LOAD --(last buffer write)--> IDLE
     ^                        |   cmd_ok && COMPUTE
     |                        +---------------------> MAC  --(last accumulate)-----> IDLE
     +------------------------+  dropped (error), K = 0
```

- **IDLE** goes to CHECK in the cycle after the FIFO becomes non-empty.
- **CHECK** pops the head (FIFO head is first-word fall-through) and decides in the D16 order: ILLEGAL → `err_illegal`; K = 0 → no-op; K > KMAX or K mod 4 ≠ 0 → `err_k`; LOAD with `addr[3:0] ≠ 0` → `err_align`; LOAD with `addr < DTCM_BASE` or `addr + 4K > DTCM_BASE + DTCM_BYTES` → `err_addr`. The range check is computed in 35 bits (`addr + 4K < 2^35` for any 32-bit `addr` and `K`), so it cannot wrap. A command that passes latches S = K/4, the first quad index `(addr − DTCM_BASE) >> 4`, the target buffer and clr.
- **LOAD** walks steps s = 0..S−1, one per cycle: port-B read s in cycle c (`b_addr = base + s`), `b_rdata` valid in c+1, written into WBUF[s] or IBUF[s] at the end of c+1. LOAD lasts S+1 cycles and leaves after its last write.
- **MAC** walks the same steps: WBUF[s] and IBUF[s] are read (synchronous RAM read) in cycle c, and the PE array adds the 16 dot products at the end of c+1; with clr, step 0 loads instead of adding. MAC lasts S+1 cycles and leaves after its last accumulate.

Every buffer write happens in LOAD (A-MAC-4), `b_req` is 1 only in LOAD (A-MAC-3), and every accumulator update happens in MAC. That last-write-inside-the-state rule is what makes D1 cycle-identical to D0 (§4).

## 3. Latency (A-MAC-5)

Latency is counted in busy cycles (`npu_status.busy = 1`), from the CHECK cycle that pops the command to the return to IDLE. Spec §7.2 bounds it by K/4 + 3.

| Command | Busy cycles | K = 4 | K = 8 | K = 1024 |
|---|---|---|---|---|
| LOAD_WEIGHT, LOAD_INPUT | K/4 + 2 (CHECK + S + 1) | 3 | 4 | 258 |
| COMPUTE | K/4 + 2 (CHECK + S + 1) | 3 | 4 | 258 |
| dropped command, K = 0, ILLEGAL | 1 (CHECK) | 1 | 1 | 1 |

Measured by `t_latency` on QuestaSim 10.7c, identical in D0 and D1 (2026-11-05). For the 1-cycle row it pushes COMPUTE K=0, COMPUTE K=6, a misaligned LOAD, a LOAD at address 0, a LOAD with K=1028 and an ILLEGAL, and requires exactly 1 busy cycle each. Between two queued commands the FSM passes one IDLE cycle, so a stream of N commands takes Σ(latency) + N cycles of engine time after the first push.

`npu_busy_cyc` counts exactly the busy cycles: `t_csr_write_semantics` compares it with the busy cycles the testbench sees through `npu_status`.

## 4. Clock gating (spec §8, D19)

`npu_clk_gate` is a latch transparent while `clk` is low, followed by an AND; the only latch in the design. `mac_engine #(.GATING_EN(b))` passes `GATING_EN` to it: with 0 (D0) the enable is tied to 1 inside the cell and the instance stays; with 1 (D1)

`en = !rst_n || (state_q != IDLE) || !fifo_empty`

Every term is registered state or the already synchronised `rst_n` (D18), so `en` is stable while the latch is open. A push at cycle t makes `fifo_empty` 0 at t+1, so the first gated edge comes at the end of t+1, before any `clk_mac` flop needs one (CHECK uses none). Because each LOAD/MAC write lands in a non-IDLE cycle (§2), D1 executes in the same cycles as D0. `t_clock_gate` checks the edges: in D1, 0 `clk_mac` edges in idle cycles and exactly busy + 1 edges for one command (the IDLE cycle with a non-empty FIFO, then every busy cycle); in D0, one edge per cycle.

This is functional evidence only. The switching-activity estimate and the D0/D1 equivalence run (SC3) are Phase 3 work.

## 5. Reset (D18)

`rst_n` is active low with asynchronous assert; its release is synchronised in `npu_top` (Phase 2 Task 14). Every flop except the FIFO entries, WBUF, IBUF and the buffer read registers is reset asynchronously: FIFO pointers and count, FSM, error bits, `npu_busy_cyc`, the step counter and flags, and the 16 accumulators. The unreset storage is only read under a valid qualifier (FIFO count, `step_q`) or after a LOAD wrote it (spec §7.2). `t_reset_state` asserts `rst_n` 1 ns after an edge, in a LOAD cycle with commands queued, and reads both CSRs, `cmd_ready`, `rd_ready`, `b_req` and all 16 results before the next clock edge.

## 6. Choices the spec left open, and recorded deviations

Where the spec is silent, the RTL does this:

| Behaviour the spec does not define | What the RTL does | Alternative |
|---|---|---|
| Flop reset style (D18 fixes the `rst_n` signal; CLAUDE.md §10 listed the flop style as open) | asynchronous reset flops, read from D18's "asserted asynchronously"; **Bảo to confirm** | synchronous reset on the synchronised `rst_n` |
| FIFO head | first-word fall-through, so CHECK pops and decides in one cycle | registered head, one more cycle per command |
| CHECK → next command | always back through IDLE (one cycle per command) | CHECK → CHECK directly, one cycle less per queued command, more FSM logic |
| `b_addr` while `b_req = 0` | not forced to 0. It is `qbase_q + req_cnt_q`: it holds between commands, steps through base + 0..S during every COMPUTE too (CHECK latches `qbase_q` from any executing command, and COMPUTE's `cmd_addr` is ignored by §6.3), and wraps to 0 in the last cycle of a LOAD that ends at the top of the DTCM | gate it with `b_req`, or latch `qbase_q` only for LOAD: fewer toggles on the port, which matters for the Phase 3 estimate |

Already fixed elsewhere, listed so that a reader of the RTL finds them:

| Item | Where it is fixed | What the RTL does |
|---|---|---|
| Error bit set by CHECK in the same cycle as its W1C clear | D23 (decided by Bảo 2026-11-05; §6 is frozen, so it waits for Tấn's signature) | set wins |
| A push while the FIFO is full and CHECK pops in the same cycle | spec §7.1, `cmd_ready = !fifo_full` (frozen) | the push is refused |
| Where the CSR block was built | plan Task 11 build order puts it in stage 5 | built with CHECK (stage 2), because the error bits are only visible through `npu_status` |
| **Parameter names (deviation from D19)** | D19: "CamelCase parameters" | UPPER_CASE (`GATING_EN`, `WIDTH`, `DEPTH` and the localparams), as in `npu_pkg`, the plan and D19's own `GATING_EN`. D19 contradicts itself here; the students either amend D19 with a dated entry (keep UPPER_CASE) or rename in every engine file and `npu_pkg` |

## 7. Verification (Task 11 Step 4)

| Check | Command | Result (2026-11-05) |
|---|---|---|
| Directed DPI suite, D0 | `bash sim/questa/run_mac_directed.sh` (Questa on PATH) | 21/21 PASS, `RESULT: PASS` |
| Directed DPI suite, D1 | `GATING=1 bash sim/questa/run_mac_directed.sh` | 21/21 PASS, `RESULT: PASS` |
| `cmd_fifo` unit test | `bash sim/questa/run_cmd_fifo.sh`, `make -C sim/verilator test_cmd_fifo` | `RESULT: PASS` at DEPTH 8 and 5 |
| Lint | `make -C sim/verilator lint` (WSL) | clean, `mac_engine` in D0 and D1 |

The suite (`tb/directed/mac_engine_tb.sv`) mirrors every command into `npu_ref` through `tb/uvm/common/npu_dpi_pkg.sv` and, at each `compare()` checkpoint (after the engine has drained), compares `npu_status` and all 16 results; it also checks hand-computed values, the port-B read count (K/4 per executed LOAD), a WBUF/IBUF shadow (white-box), the latency bounds, A-MAC-3/A-MAC-4 (white-box) and the `clk_mac` edges. Hand-made mutants, each of which the suite must fail: 10 of `cmd_fifo`, 18 of CHECK and the CSRs, 12 of LOAD, 18 of MAC, the PE array, reset and the clock gate; all fail. Three more turned out to be equivalent to the RTL and are not counted.

An independent review on 2026-11-05 also ran D0 and D1 in lockstep from a scratch testbench (random command mix with random resets, several seeds of 200 000 cycles each) and compared the engine's outputs every cycle: no difference (its report: 0 mismatches per seed). That is supporting evidence, not the SC3 equivalence run, which is Phase 3 work.

The Verilator simulation build of `mac_engine_tb` (`make -C sim/verilator test_mac_engine`) did not finish within one WSL session on Bảo's machine from stage 3 on (g++ on one large generated file); at stage 2 it gave the same counts as QuestaSim. QuestaSim is the reference for the suite, as the Phase 1 exit checklist asks.
