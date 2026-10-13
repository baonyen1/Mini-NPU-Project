# Pipeline stall and flush design — `rtl/core`

Status: **design**. Only the load-use stall exists in RTL today. The other rows are implemented in plan Task 5 (divider) and Task 9 (custom-0 push / READ_RESULT).
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

1. **Divider starts once.** Use a small FSM `IDLE → BUSY → DONE`: `start = div_in_EX && state == IDLE`; DONE returns to IDLE when D leaves EX; `div_stall = div_in_EX && state != DONE`. Using `start = div_in_EX` restarts the divider every cycle.
2. **Load-use and the divider never coincide** (both need EX). The dangerous overlap is **MEM stall + load-use**: `lw` in EX, its consumer in ID, READ_RESULT waiting in MEM. The load-use bubble must be suppressed (`load_use & !stall_ex`) or the `lw` is flushed.
3. **Branch in EX while MEM stalls**: the redirect waits until EX advances (`redirect = … & !stall_ex`), otherwise the PC is redirected while the branch is still held and IF/ID is flushed twice.
4. **Retire accounting needs a `valid` bit** in every pipeline register. Bubbles carry `valid = 0`; only `valid = 1` at WB counts for `minstret` and the RVVI trace.
5. Why a MEM stall bubbles **MEM/WB** but not **EX/MEM**: the instruction in MEM is the one being held, so EX/MEM must keep it (hold), while WB must not retire it a second time (bubble). Bubbling EX/MEM instead would erase the waiting instruction.

## 6. Tests that pin this design (plan Review Focus 1)

| Test | Task | Checks |
|---|---|---|
| `div_back_to_back_dep` | 5 | consumer right after `div` gets the result |
| `div_in_branch_shadow` | 5 | a `div` after a taken branch never writes back |
| `fifo_full_stall` | 9 | 6 pushes with `cmd_ready` 1 cycle in 4: same results as always-ready |
| `push_in_branch_shadow` | 9 | a custom-0 push after a taken branch is never issued |
| `read_result_x0_still_drains` | 9 | READ_RESULT to x0 still waits for the engine |
| `rvvi_order_monotonic` | 8 | exactly one retire per instruction, no gaps after stalls/flushes |
