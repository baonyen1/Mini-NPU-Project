# Pipeline stall and flush design — `rtl/core`

Status: **all four stall sources are in RTL** (load-use and divider in Task 5, FIFO-full and READ_RESULT wait in Task 9, 2026-10-20). `Hazard_Unit.v` builds the stall vector of section 3.
Chosen approach: **A — per-stage stall vector computed centrally in `Hazard_Unit.v`** (alternatives B "valid/ready elastic pipeline" and C "global freeze" were rejected: B rewrites every pipeline register in the busiest weeks; C freezes older instructions for no reason and is the old `cpu_en` idea).

## 1. Principle

> Stall propagates towards **younger** instructions (to the left).
> A bubble is inserted towards **older** instructions (to the right), in the register right after the oldest stalled stage.

Older instructions are never blocked by a younger one. A bubble is a NOP: `reg_write = 0`, `mem_we = 0`, `mem_re = 0`, `valid = 0`.

## 2. Stall sources

| Source | Detected in | Condition | Hold (do not load) | Bubble into | PC | Task |
|---|---|---|---|---|---|---|
| Load-use | ID | load in EX writes a register the ID instruction reads | PC, IF/ID | ID/EX | hold | exists |
| Divider busy | EX | `div*`/`rem*` in EX and divider not done | PC, IF/ID, ID/EX | EX/MEM | hold | 5 |
| FIFO full | MEM | custom-0 push in MEM and `!cmd_ready` | PC, IF/ID, ID/EX, EX/MEM | MEM/WB | hold | 9 |
| READ_RESULT wait | MEM | READ_RESULT in MEM and `!rd_ready` | PC, IF/ID, ID/EX, EX/MEM | MEM/WB | hold | 9 |

## 3. Equations

```
stall_mem = mem_busy                       // fifo_full_push | read_result_wait
stall_ex  = stall_mem | div_stall
stall_id  = stall_ex  | load_use

hold IF/ID   = stall_id          hold ID/EX = stall_ex          hold EX/MEM = stall_mem
bubble ID/EX  = load_use  & !stall_ex
bubble EX/MEM = div_stall & !stall_mem
bubble MEM/WB = stall_mem
pc_write      = !stall_id | redirect
redirect      = (branch_taken | jump) & !stall_ex     // a held branch must not redirect
```

Implementation note: `Hazard_Unit` exports `mem_wb_bubble = stall_mem`, but `RISC_V_Top` leaves that output unconnected; `StageMemory_Top` bubbles MEM/WB with `mem_busy` directly, which is the same signal. The behaviour is as in the table; only the wiring differs from "computed centrally".

The `& !stall_<older stage>` terms are the important part. Without them a younger stage's bubble overwrites an instruction that an older stall is holding, and that instruction is lost.

## 4. Worked example: divider in EX

Program `add (A), sub (B), div (D), or (E), and (F), xor (G)`; the divider needs k cycles.

| Cycle | IF | ID | EX | MEM | WB |
|---|---|---|---|---|---|
| t | F | E | D (start) | B | A |
| t+1 | F | E | D | bubble | B |
| t+2 … t+k−1 | F | E | D | bubble | bubble |
| t+k (done) | F | E | D → result | bubble | bubble |
| t+k+1 | G | F | E | D | bubble |
| t+k+2 | … | G | F | E | D |

Without the EX/MEM bubble, D would be copied into MEM every cycle and retire about k times, writing intermediate (wrong) values to its `rd` and over-counting `minstret`. The final register value can still look right, which is why the RVVI trace check (one retire per instruction, `order` without gaps) is needed to catch it.

## 5. Pitfalls and rules

1. **Divider starts once.** As built, one flag `div_started` (in `StageExecute_Top.v`) replaces the `IDLE → BUSY → DONE` FSM that was first proposed: `div_start = is_div_op & ~div_started`; the flag is set at the start and cleared when the instruction leaves EX (`~ex_stall`); `div_busy = is_div_op & ~(div_started & div_done)`. Using `start = div_in_EX` would restart the divider every cycle. The divider samples its operands at `start`.
2. **Load-use and the divider never coincide** (both need EX). The dangerous overlap is **MEM stall + load-use**: `lw` in EX, its consumer in ID, READ_RESULT waiting in MEM. The load-use bubble must be suppressed (`load_use & !stall_ex`) or the `lw` is flushed.
3. **Branch in EX while MEM stalls**: the redirect waits until EX advances (`redirect = … & !stall_ex`), otherwise the PC is redirected while the branch is still held and IF/ID is flushed twice.
4. **Retire accounting needs a `valid` bit** in every pipeline register. Bubbles carry `valid = 0`; only `valid = 1` at WB counts for `minstret` and the RVVI trace.
5. Why a MEM stall bubbles **MEM/WB** but not **EX/MEM**: the instruction in MEM is the one being held, so EX/MEM must keep it (hold), while WB must not retire it a second time (bubble). Bubbling EX/MEM instead would erase the waiting instruction.

6. **A held EX stage loses its forwarding sources.** When MEM stalls, the instruction in EX is held for many cycles, and the older instruction that was forwarding a value to it leaves WB after one cycle. The operand registers in ID/EX still contain the value read in ID (stale). Fix (Task 9): while ID/EX is held it reloads its operand registers with the value EX sees (`held_operand_*`). Tests `mem_stall_stale_operand`, `mem_stall_stale_operand_push` (they failed before the fix: `x8 = 0` instead of 14).
7. **Side effects of the instruction in EX happen when it leaves EX.** A CSR instruction held behind a waiting READ_RESULT must write once; writing every held cycle also changes the value it reads (`CSR_Unit.ex_advance`). Test `csr_write_once_under_mem_stall`. The divider has the same issue and solves it with `div_started`.
8. **`EX_MEM_Reg` gives `stall` priority over `bubble`.** The `& !stall_mem` in the bubble equation is therefore redundant in this implementation; it stays in the equation for clarity.

## 6. Tests that pin this design (plan Review Focus 1)

| Test | Task | Checks |
|---|---|---|
| `div_back_to_back_dep` | 5 | consumer right after `div` gets the result |
| `div_in_branch_shadow` | 5 | a `div` after a taken branch never writes back |
| `fifo_full_stall` | 9 | 6 pushes with `cmd_ready` 1 cycle in 4: same results as always-ready |
| `push_in_branch_shadow` | 9 | a custom-0 push after a taken branch is never issued |
| `read_result_x0_still_drains` | 9 | READ_RESULT to x0 still waits for the engine |
| `rvvi_order_monotonic` | 8 | exactly one retire per instruction, no gaps after stalls/flushes |
| `minstret_across_divide`, `custom_minstret_exact` | 6, 9 | the retire count is exact across divider and engine stalls (a missing bubble would count an instruction twice) |
| `overlap_*` (7 tests) | 9 | branch / jump held behind a waiting READ_RESULT or push, load-use behind READ_RESULT, divide behind a push, divide in a branch shadow while MEM waits |
| `randcustom_*` | 9 | 200 random programs mixing custom-0, M, loads, stores, branches with random ready patterns |
