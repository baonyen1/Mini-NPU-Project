# Scalar core ISA — `rtl/core`

Status: **RV32I base complete** (plan Task 3, 2026-10-09). Encodings of the planned extensions (§6), the CSR map (§7) and the `cpu_en` record (§8) were added for the week-2 freeze (plan Task 2, 2026-10-20). **Decision W2-1 is still open** (§4).
Spec: `docs/superpowers/specs/2026-10-04-mini-npu-design.md` §5–§6.

| Extension | Status | Plan task |
|---|---|---|
| RV32I (base, 40 instructions) | ✅ implemented, regression green | 3 |
| M (`mul*`, `div*`, `rem*`) | ✅ implemented, regression green (2026-10-20) | 5 |
| Zicsr + counters, `npu_status`/`npu_busy_cyc` | ✅ implemented, regression green (2026-10-20) | 6 |
| Zifencei, Zbb | ✅ implemented, regression green (2026-10-20) | 7 |
| custom-0 (LOAD_WEIGHT, LOAD_INPUT, COMPUTE, READ_RESULT) | ✅ implemented against the engine stub, regression green (2026-10-20) | 9 |

## 1. Implemented instructions (RV32I)

The `ALU op` column is the base-ALU code, the low 4 bits of the 6-bit `alu_operation` that `Control.v` sends to the execute stage (§3).
**New** marks the 10 instructions added in Task 3.

| Instruction | opcode | funct3 | funct7 / imm[11:5] | ALU op | Notes |
|---|---|---|---|---|---|
| `add` / `sub` | 0110011 | 000 | 0000000 / 0100000 | ADD / SUB | |
| `sll` | 0110011 | 001 | 0000000 | SLL | shift amount = `rs2[4:0]` |
| `slt` **New** | 0110011 | 010 | 0000000 | SLT | signed compare, rd = 0 or 1 |
| `sltu` **New** | 0110011 | 011 | 0000000 | SLTU | unsigned compare |
| `xor` | 0110011 | 100 | 0000000 | XOR | |
| `srl` / `sra` **New** | 0110011 | 101 | 0000000 / 0100000 | SRL / SRA | `sra` fills with the sign bit |
| `or` / `and` | 0110011 | 110 / 111 | 0000000 | OR / AND | |
| `addi` | 0010011 | 000 | — | ADD | |
| `slti` **New** | 0010011 | 010 | — | SLT | |
| `sltiu` **New** | 0010011 | 011 | — | SLTU | imm is **sign-extended first**, then compared unsigned |
| `xori` / `ori` / `andi` | 0010011 | 100 / 110 / 111 | — | XOR / OR / AND | |
| `slli` **New** | 0010011 | 001 | 0000000 | SLL | shamt = `imm[4:0]` |
| `srli` / `srai` **New** | 0010011 | 101 | 0000000 / 0100000 | SRL / SRA | told apart by instruction bit 30 |
| `lui` | 0110111 | — | — | ADD | A = 0 (`ALUSrcA = 01`) |
| `auipc` | 0010111 | — | — | ADD | A = PC (`ALUSrcA = 10`) |
| `lb lh lw lbu lhu` | 0000011 | 000 001 010 100 101 | — | ADD | `data_format = funct3` |
| `sb sh sw` | 0100011 | 000 001 010 | — | ADD | |
| `beq bne blt bge` | 1100011 | 000 001 100 101 | — | (SUB) | resolved in EX by `Branch_Comparator` |
| `bltu` / `bgeu` **New** | 1100011 | 110 / 111 | — | (SUB) | unsigned compare |
| `jal` | 1101111 | — | — | — | rd = PC+4 (`WB_sel = 10`) |
| `jalr` | 1100111 | 000 | — | — | target = (rs1 + imm) & ~1 |
| `fence` | 0001111 | — | — | — | executes as NOP (allowed: single hart, in-order, no cache) |
| `ecall` / `ebreak` | 1110011 | — | — | — | currently NOP, see §4 |

## 2. Design notes for the Task 3 additions

- **`srli` vs `srai`.** Both have funct3 = 101. The only difference is instruction bit 30 (`imm[10]`, which `InstructionDecoder` exposes as `fun7[5]`). `Control.v` checks the whole `fun7`: `0000000` → SRL, `0100000` → SRA, anything else is not decoded. The immediate that reaches the ALU still contains bit 30 (`srai x1,x1,4` gives `B = 0x404`). This is harmless because the ALU only uses `B[4:0]` for shifts.
- **`slli` with `fun7 ≠ 0000000`** (for example RV64's `shamt[5]`) is not decoded and therefore becomes a NOP (§4).
- **`sltiu x, rs1, -1`** compares against `0xFFFFFFFF`, so it returns 1 for every `rs1` except `0xFFFFFFFF`. This comes for free because `ImmGenerator` sign-extends every I-type immediate.
- **Branch decode** now accepts every funct3 except the two reserved values `010` and `011`.
- Arithmetic shift in Verilog: `$signed(A) >>> B[4:0]`. Plain `>>` on an unsigned operand would fill with zeros (this is exactly the bug the mutation check in §5 injects).

### 2.1 M extension (Task 5)

- **Decode.** R-type with `funct7 = 0000001`; `Control.v` sends `{3'b010, funct3}` as `alu_operation`. All other `funct7` values on those `funct3` still decode as before.
- **Multiplier** (`StageExecute/Multiplier.v`): one combinational signed 33 x 33 product. The extension bit of each operand is its sign bit when the operand is signed for that operation, else 0. `MUL` returns the low word, the other three the high word.
- **Divider** (`StageExecute/Divider.v`): restoring, one quotient bit per cycle, absolute values with the signs fixed at the end. `DIV`/`REM` by zero return all ones / the dividend; `-2^31 / -1` returns `-2^31` / 0. Those two cases skip the loop (one stall cycle). A normal divide occupies EX for 34 cycles (1 start + 32 iterations + the cycle that hands over the result).
- **Stall.** `div_busy = divide in EX and not done` freezes PC, IF/ID and ID/EX and loads a bubble into EX/MEM every cycle (`docs/core_stall.md` section 3). The divider samples its operands in the first EX cycle (`div_started` marks that this has happened), because the forwarding sources vanish while the instruction waits.
- **Result.** The M result enters EX/MEM like an ALU result, so the normal forwarding path serves it.

### 2.2 Zicsr and counters (Task 6)

- **Where.** CSR instructions execute in EX (`CSR_Unit.v`): read and write in one cycle. An instruction in EX is never on a wrong path (a branch redirects from EX and flushes only younger instructions), so the write may happen at the end of that cycle. The old value goes down the pipe as an ALU result, so the normal forwarding path serves it. `Control.v` sends `csr_op` (= funct3 for CSR instructions, 000 otherwise); the CSR address is `Imm[11:0]` (`ImmGenerator` treats SYSTEM as I-type); for `csrr*i` the operand is `zimm = rs1 field`.
- **Write rule.** `csrrw`/`csrrwi` always write; `csrrs`/`csrrc` (and the immediate forms) write only when the `rs1` field / `zimm` is not zero. Writing does not depend on `rd`, so `csrrw x0, csr, rs1` still writes.
- **Counters.** `mcycle` (64-bit) counts every cycle from reset. `minstret` (64-bit) counts instructions leaving WB. A `valid` bit travels with every instruction (IF/ID, ID/EX, EX/MEM, MEM/WB); bubbles (reset, flush, load-use, divider wait) carry `valid = 0` and are not counted.
- **Exact `minstret`.** A CSR read happens in EX, when the two older instructions in MEM and WB have not retired yet. The value read is `minstret + valid(EX/MEM) + valid(MEM/WB)`, which is exactly the number of instructions older than the reader, whatever bubbles or flushes precede it. `RefISS` models it the same way, so raw `minstret` values can be compared between RTL and ISS. `mcycle` is cycle-accurate in the RTL and ideal in `RefISS`, so tests only use derived booleans of cycle reads.
- **Provisional rulings (until W2-1 is recorded and Track B confirms section 7).** Writes to `mcycle`/`minstret` and to the read-only aliases are ignored; an unknown CSR address reads 0 and ignores writes.

### 2.3 Zifencei and Zbb (Task 7)

- **`fence.i`** (`MISC-MEM`, funct3 = 001) executes in EX as a jump to PC+4 (`Control` raises `FenceI`; `StageExecute_Top` sets the jump flag and forces the immediate to 4). It flushes IF/ID and ID/EX and refetches the next instruction, so two bubbles separate the instructions around it. There is no I-cache and the ITCM is read-only, so the refetch always returns the same instructions; the flush matters architecturally only for self-modifying code. `fence` (funct3 = 000) stays a NOP.
- **Zbb** is a combinational unit (`BitManip.v`) in EX, selected by `alu_operation[5] = 1`; the operation is `alu_operation[4:0]`:

| op | name | op | name | op | name |
|---|---|---|---|---|---|
| 0 | `andn` | 6 | `max` | 12 | `zext.h` |
| 1 | `orn` | 7 | `maxu` | 13 | `rol` |
| 2 | `xnor` | 8 | `min` | 14 | `ror` (also `rori`, shamt as operand B) |
| 3 | `clz` | 9 | `minu` | 15 | `orc.b` |
| 4 | `ctz` | 10 | `sext.b` | 16 | `rev8` |
| 5 | `cpop` | 11 | `sext.h` | | |

- **Decode** needs more than `funct3`/`funct7` for the unary operations: `Control.v` now also receives the `rs2` field (`instruction[24:20]`). `zext.h` requires `rs2 = x0` (it is `pack rd, rs1, x0`; `pack` with another `rs2` is not Zbb and executes as a NOP). `slli` keeps `funct7 = 0000000`; `funct7 = 0110000` on funct3 001 selects `clz ctz cpop sext.b sext.h` by `rs2`.

### 2.4 custom-0 push and READ_RESULT (Task 9)

- **Decode.** Opcode `0001011`. `Control` raises `custom_ctl = {1, funct7[0], funct3}` and sends `alu_operation = ADD` with `ALUSrc = 1`; `ImmGenerator` returns 0 for this opcode, so `rs1` leaves EX as the ALU result and `rs2` as the store-data value. Only READ_RESULT (funct3 = 011) writes `rd` (writeback select 01, like a load). `rd` is ignored for the other funct3 values even when it is not `x0`.
- **Push in MEM** (`StageMemory_Top`). `cmd_valid` is high for LOAD_WEIGHT, LOAD_INPUT, COMPUTE and the reserved funct3 values `100`-`111` (op `ILLEGAL` = 3). `cmd_op` = funct3 for 000/001/010. LOAD commands carry `cmd_addr = rs1`, `cmd_k = rs2`; COMPUTE carries `cmd_k = rs1`, `cmd_addr = 0` and `cmd_clr = funct7[0]` (`cmd_clr` is 0 for every other op). `cmd_valid` and the operands stay unchanged until `cmd_ready`; the stub checks this. Because the push is in MEM, every older store has written the DTCM first.
- **READ_RESULT.** `rd_req` is raised in MEM with `rd_idx = rs1[3:0]` (upper bits ignored) and the instruction waits for `rd_ready`. `rd_data` is captured into MEM/WB (`rd_data_MEM_WB`) and reaches the register file and the forwarding network through the load-data path. It also joins the load-use detector (a consumer right behind it waits one cycle), and `rd = x0` still waits and drains (the wait does not depend on `rd`).
- **Stall.** `mem_busy = (push and !cmd_ready) or (READ_RESULT and !rd_ready)` joins the stall vector (`docs/core_stall.md`): PC, IF/ID, ID/EX and EX/MEM hold, MEM/WB takes a bubble.
- **Held EX.** While EX is held, an older instruction can leave the pipeline and with it the forwarding source of the instruction in EX. `ID_EX_Reg` therefore reloads its operand registers with the value EX sees (`held_operand_0/1`) in every held cycle. A CSR instruction held in EX writes only in the cycle it leaves (`ex_advance`), so it writes once and returns the old value.
- **Stub.** `rtl/top/npu_stub.sv` models the engine: `+STUB_READY=<bits>` and `+STUB_RDREADY=<bits>` give `cmd_ready` / `rd_ready` patterns (character *i* applies in cycle *i* mod length), `rd_data = {28'b0, rd_idx}`, every accepted push prints `PUSH op addr k clr`, and `STUB_ERROR` is printed when `cmd_valid` / `rd_req` drops or changes before the handshake.

## 3. Internal control encodings

| Signal | Width | Encoding |
|---|---|---|
| `alu_operation` | 6 | Widened from 4 bits in Task 5 (M has 8 operations, Zbb 17, the base ALU 10: 35 codes do not fit in 5 bits). `[5:4] = 00` base ALU, `[3:0]`: `0000` AND, `0001` OR, `0010` ADD, `0011` XOR, `0100` SLL, `0101` SRL, `0110` SUB, `0111` SLT, `1000` SLTU, `1001` SRA. `[5:4] = 01` M unit, `[2:0]` = funct3: `000` MUL, `001` MULH, `010` MULHSU, `011` MULHU (combinational multiplier), `100` DIV, `101` DIVU, `110` REM, `111` REMU (iterative divider). `[5] = 1` is reserved for Zbb (Task 7), operation in `[4:0]`. |
| `alu_branch_control` | 3 | = funct3 of the branch |
| `DataFormat` | 3 | = funct3 of the load/store |
| `ALUSrcA` | 2 | `00` rs1, `01` zero (LUI), `10` PC (AUIPC) |
| `ALUSrc` | 1 | `0` rs2, `1` immediate |
| `WB_sel` | 2 | `00` ALU result, `01` load data, `10` PC+4 (JAL/JALR) |

## 4. Unsupported and illegal instructions (decision W2-1, still open)

Current behaviour: any encoding `Control.v` does not recognise — including `ecall`, `ebreak`, reserved funct3/funct7 values and garbage opcodes — produces no register write, no memory access and no control transfer, so it behaves as a NOP. Misaligned loads/stores are not detected (the low address bits are dropped for `lw`/`sw`).

This is **not** standard RV32I behaviour (the ISA requires an exception). The team must record one option in spec §4.1 and in the decision log (§3) at the week-2 freeze (plan Task 2), with the date and both signatures. The choice belongs to the students.

| Option | Mechanism | Cost | Verdict |
|---|---|---|---|
| (a) M-mode trap | `mtvec`, `mepc`, `mcause`, `mret`; the faulting instruction redirects the fetch | needs Zicsr first; new CSR state and a pipeline redirect; `RefISS`, `rv_iss.c` and the cosim checker must model it; more coverage bins. No firmware in this project wants to trap. | not needed |
| **(b) simulation halt** | `ecall`/`ebreak` assert `halt`; illegal, misaligned or access fault assert `halt` + `fault` | two output ports; the ISS must stop at the same instruction; Phase 2 end-of-test already anticipates "the core's halt/fault indication if W2-1 defines one" | **recommended for Senior Project 2** |
| (c) keep NOP | nothing | none, but a wrong encoding in Tasks 5–7 or in firmware runs silently on; only the cosim diff against the ISS would show it, and only if the ISS also skips | not recommended, hides bugs |

Events the chosen policy must cover, and what option (b) would do:

| Event | Today | Under (b) |
|---|---|---|
| Unknown or reserved encoding (reserved funct3/funct7, branch funct3 `010`/`011`, `slli` with `funct7 ≠ 0`, Zbb look-alikes, see §6.6) | NOP | `halt` + `fault` |
| `ecall`, `ebreak` | NOP | `halt` |
| Misaligned `lh`/`lw`/`sh`/`sw` | low address bits dropped | `halt` + `fault` |
| Load, store or fetch outside the spec §4.1 map | depends on the harness memory | `halt` + `fault` |
| CSR access to an unimplemented address, or a write to a read-only alias (§7) | not applicable yet | **spec is silent: decide** |

The custom-0 reserved funct3 values `100`–`111` are **not** an event of this table. The core pushes them with op `ILLEGAL` and the engine sets `err_illegal` (spec §6.3).

Where the decision lands:

- Task 4: `RefISS` must model the same policy.
- Task 8: if (b) is chosen, `halt` and `fault` are new core ports. They are in neither the Task 8 port list nor spec §7.1, so the plan, the spec and the RTL change in the same commit.
- Task 12 and Task 15: `rv_iss.c` stops at the same instruction as the RTL; the end-of-test logic reads `halt`/`fault`. The RVVI `trap` field has to be given a meaning too (set on the faulting instruction or not).
- Task 17: `core_read_result_hang_times_out` stays a timeout failure either way.

**Decision: open.** Record here, in spec §4.1 and in the §3 decision log: option, date, both signatures.

## 5. Verification

`python tools/rv32i_check/run_all.py` (Icarus Verilog + reference ISS in Python), result on 2026-10-09:

| Suite | Result |
|---|---|
| ISA: one test per instruction (40) + 4 signed/unsigned corner tests | **44/44** |
| Directed hazard/control (forwarding, load-use, flush, loops, calls) | **25/25** |
| Random programs, full RV32I ALU/branch/load/store mix, 300 seeds × ~60 instructions | **300/300** |

Corner tests added in Task 3: `slt_vs_sltu_sign` (`0x80000000` vs `1`), `sltiu_minus1`, `srai_negative`, `bltu_bgeu_sign`.

Mutation sanity check (the suite must fail when the RTL is wrong):

| Injected bug | Detected by |
|---|---|
| `sra` implemented as logical shift | 3 directed + 34 random seeds fail |
| `bltu` implemented as signed compare | 2 directed + 31 random seeds fail |

Since plan Task 8 the harness runs the core in `rtl/top/core_tb_top.sv` on the spec memory map (ITCM 16 KB, DTCM 64 KB); see section 9.

## 6. Planned instructions: encodings (week-2 freeze)

The instruction list comes from spec §5 and §6.1. Every example word was produced by `riscv64-unknown-elf-as` 2.42 (`-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32`; custom-0 through `.insn`) on 2026-10-20, with `rd = x3`, `rs1 = x1`, `rs2 = x2` unless a row says otherwise. They are also usable as hand-check vectors for the decoder tests.

### 6.1 M extension (Task 5)

Opcode `0110011`, `funct7 = 0000001`. Base `add` and `sub` use `funct7 = 0000000` / `0100000`, so `funct7` is what separates M from the base ALU.

| Instruction | funct3 | Example word |
|---|---|---|
| `mul` | 000 | `022081b3` |
| `mulh` | 001 | `022091b3` |
| `mulhsu` | 010 | `0220a1b3` |
| `mulhu` | 011 | `0220b1b3` |
| `div` | 100 | `0220c1b3` |
| `divu` | 101 | `0220d1b3` |
| `rem` | 110 | `0220e1b3` |
| `remu` | 111 | `0220f1b3` |

### 6.2 Zicsr (Task 6)

Opcode `1110011`. `imm[11:0]` is the CSR address. In the immediate forms the `rs1` field holds `zimm[4:0]`. `funct3 = 000` is `ecall`/`ebreak` (§6.3) and `100` is reserved. Example words use CSR `0x7C0`, `rs1 = x1` (immediate forms: `zimm = 5`).

| Instruction | funct3 | Example word |
|---|---|---|
| `csrrw` | 001 | `7c0091f3` |
| `csrrs` | 010 | `7c00a1f3` |
| `csrrc` | 011 | `7c00b1f3` |
| `csrrwi` | 101 | `7c02d1f3` |
| `csrrsi` | 110 | `7c02e1f3` |
| `csrrci` | 111 | `7c02f1f3` |

### 6.3 Zifencei, `fence`, `ecall`, `ebreak` (Task 7)

| Instruction | opcode | funct3 | imm[11:0] | Example word |
|---|---|---|---|---|
| `fence` | 0001111 | 000 | `fm/pred/succ` (not decoded) | `0ff0000f` (`fence iorw,iorw`) |
| `fence.i` | 0001111 | 001 | 0 | `0000100f` |
| `ecall` | 1110011 | 000 | `0x000` | `00000073` |
| `ebreak` | 1110011 | 000 | `0x001` | `00100073` |

`fence.i` flushes the pipeline and refetches; there is no I-cache (spec §5). Its `funct3` is what separates it from `fence`. `ecall`/`ebreak` follow decision W2-1 (§4).

### 6.4 Zbb, RV32 subset of spec §5 (Task 7)

For the unary rows, `imm[11:0]` is fixed, so the `rs2` field is part of the encoding. For `rori`, `imm[4:0]` is the shift amount.

| Instruction | opcode | funct3 | funct7 / imm[11:5] | rs2 field / imm[4:0] | Example word |
|---|---|---|---|---|---|
| `andn` | 0110011 | 111 | 0100000 | rs2 | `4020f1b3` |
| `orn` | 0110011 | 110 | 0100000 | rs2 | `4020e1b3` |
| `xnor` | 0110011 | 100 | 0100000 | rs2 | `4020c1b3` |
| `clz` | 0010011 | 001 | 0110000 | 00000 | `60009193` |
| `ctz` | 0010011 | 001 | 0110000 | 00001 | `60109193` |
| `cpop` | 0010011 | 001 | 0110000 | 00010 | `60209193` |
| `sext.b` | 0010011 | 001 | 0110000 | 00100 | `60409193` |
| `sext.h` | 0010011 | 001 | 0110000 | 00101 | `60509193` |
| `max` | 0110011 | 110 | 0000101 | rs2 | `0a20e1b3` |
| `maxu` | 0110011 | 111 | 0000101 | rs2 | `0a20f1b3` |
| `min` | 0110011 | 100 | 0000101 | rs2 | `0a20c1b3` |
| `minu` | 0110011 | 101 | 0000101 | rs2 | `0a20d1b3` |
| `zext.h` | 0110011 | 100 | 0000100 | 00000 | `0800c1b3` |
| `rol` | 0110011 | 001 | 0110000 | rs2 | `602091b3` |
| `ror` | 0110011 | 101 | 0110000 | rs2 | `6020d1b3` |
| `rori` (shamt 5) | 0010011 | 101 | 0110000 | shamt | `6050d193` |
| `orc.b` | 0010011 | 101 | 0010100 | 00111 | `2870d193` |
| `rev8` | 0010011 | 101 | 0110100 | 11000 | `6980d193` |

`zext.h` on RV32 is the encoding of `pack rd, rs1, x0`. `pack` itself is not in Zbb, so the decoder must require `rs2 = 00000`; any other `rs2` is not a Zbb instruction (§4).

### 6.5 custom-0 (Task 9)

Opcode `0001011`, R-type. Normative text: spec §6.1. Example words use `rs1 = x1`, `rs2 = x2` (`rd = x3` for READ_RESULT); the `sw/npu.h` wrappers (Task 13) put `x0` in every unused register field.

| Instruction | funct3 | funct7 | rd | rs1 | rs2 | Example word |
|---|---|---|---|---|---|---|
| `LOAD_WEIGHT` | 000 | 0000000 | ignored (`x0`) | DTCM byte address | K | `0020800b` |
| `LOAD_INPUT` | 001 | 0000000 | ignored (`x0`) | DTCM byte address | K | `0020900b` |
| `COMPUTE` clr = 0 | 010 | 0000000 | ignored (`x0`) | K | unused (`x0`) | `0000a00b` |
| `COMPUTE` clr = 1 | 010 | 0000001 | ignored (`x0`) | K | unused (`x0`) | `0200a00b` |
| `READ_RESULT` | 011 | 0000000 | destination | `idx` (`rs1[3:0]`) | unused (`x0`) | `0000b18b` |
| reserved | 100–111 | — | — | — | — | pushed as op `ILLEGAL` (not a core fault) |

Hardware consequences:

- "Ignored `rd`" means **no register write**, even when the field is not `x0`.
- The hazard logic must not treat the unused `rs2` field of `COMPUTE`/`READ_RESULT` as a source register: a dummy source would cause spurious load-use stalls or forwarding. Check it in Task 9.
- `LOAD_WEIGHT`/`LOAD_INPUT` read both `rs1` and `rs2` in **MEM** (the push stage, spec §6.3 rule 2), one stage later than an ALU instruction does. How those operands get there is a Task 9 design question.

### 6.6 Decode collisions with the RV32I decoder

`Control.v` today tests `fun7` in every R-type case and in the shift-immediate cases, and treats any value it does not know as not decoded (§2). That rule has to change in Task 5 and Task 7:

- OP-IMM `funct3 = 001`: `slli` needs `imm[11:5] = 0000000`; `clz ctz cpop sext.b sext.h` use `imm[11:5] = 0110000` and select the operation with `imm[4:0]`. These share the opcode and `funct3` with `slli`.
- OP-IMM `funct3 = 101`: `srli` (`0000000`), `srai` (`0100000`), `rori` (`0110000`); `orc.b` and `rev8` need the full `imm[11:0]` (`0x287`, `0x698`).
- OP: `funct7` `0000000`/`0100000` base, `0000001` M, `0000101` `min`/`max`, `0000100` `zext.h`, `0110000` `rol`/`ror`, and `0100000` also covers `andn`/`orn`/`xnor` (`funct3` 111/110/100, while `sub` and `sra` keep 000/101).
- Anything left unmatched is a W2-1 event (§4).
- `alu_operation` had six free codes (`1010`–`1111`); Task 5 widened it to 6 bits to fit M and Zbb (final table in §3).

## 7. CSR map

Spec §5 and §6.4. All CSRs are 32 bit.

| CSR | Address | Access | Where | Notes |
|---|---|---|---|---|
| `mcycle` / `mcycleh` | `0xB00` / `0xB80` | R (writes ignored, item 3 below) | core | low / high word of a 64-bit cycle counter |
| `minstret` / `minstreth` | `0xB02` / `0xB82` | R (writes ignored, item 3 below) | core | incremented at WB on retire |
| `cycle` / `cycleh` | `0xC00` / `0xC80` | RO alias | core | read of `mcycle` / `mcycleh` |
| `instret` / `instreth` | `0xC02` / `0xC82` | RO alias | core | read of `minstret` / `minstreth` |
| `npu_status` | `0x7C0` | bits per spec §6.4 | engine | RO bits 0–2, W1C sticky bits 8–11 |
| `npu_busy_cyc` | `0x7C1` | RW | engine | counts cycles with `fsm != IDLE`; a write sets the value |

`time` / `timeh` (`0xC01` / `0xC81`) are not implemented. The core forwards `0x7C0` and `0x7C1` to the engine over the CSR port (spec §7.1; `CSR_Unit` ports in plan Task 6).

Open points to settle with Track B before both sign §7.1, because they fix what `csr_*` means. Task 6 was implemented with the provisional answers below (marked **Ruling**); Track B must confirm or change them, and the engine's CSR port must then follow:

1. **`csr_wdata` for `csrrs`/`csrrc` on a W1C register.** If the core sends the read-modify-write result, `csrrs` (`old | mask`) clears every error bit that is currently set, and `csrrc` (`old & ~mask`) clears the bits that are *not* in the mask. If it sends the raw `rs1`/`zimm` operand, the two instructions are indistinguishable. Spec §6.4 does not say. **Ruling:** `csr_wdata` is the read-modify-write result (the new CSR value), which keeps plain read/write registers such as `npu_busy_cyc` standard-compliant. For `npu_status`, software must use `csrrw`/`csrrwi` to clear error bits; `csrrs`/`csrrc` have the quirks above. Cost if wrong: the engine's CSR port semantics.
2. **`csr_rdata` timing.** Spec §7.1 declares only `output [31:0] csr_rdata`. **Ruling:** combinational in `csr_addr`, because a CSR read forwards like an ALU result from EX. Cost if wrong: a registered read would need one extra stall cycle for engine CSRs.
3. **Unimplemented address and writes to read-only aliases or to `mcycle`/`minstret`.** Spec silent. Part of W2-1 (§4). **Ruling:** reads return 0 and writes are ignored (the `npu_ref` model already returns 0 for an unknown address in `npu_ref_csr_read`).
4. **`npu_status` is not a barrier.** A CSR read executes in EX in the same cycle in which the previous instruction can be pushing its command in MEM, so `COMPUTE; csrr t0,npu_status` may read `busy = 0` and `fifo_empty = 1`. Only `READ_RESULT` drains the engine (spec §6.3 rule 5); firmware must not poll `npu_status` to wait for a command to finish.
5. **Test stub.** `rtl/top/npu_stub.sv` models the engine side for the core-only tests: `0x7C0` reads `{err[3:0], 8'b0000_0010}` with the four sticky bits set by reset and W1C on bits 11..8 (spec §6.4 lists bits 8-11; the plan text says 8-10); `0x7C1` is a plain read/write register.

## 8. `cpu_en` record

`cpu_en` was the Senior Project 1 DFS clock-enable. It was **removed** in Task 1 (`69cd798`, 2026-10-05), not tied to `1'b1` at the top. Checked 2026-10-20: `grep -rn cpu_en rtl tools/rv32i_check` finds nothing.

## 9. Memory interface and RVVI retire trace (Task 8)

### 9.1 Core ports and memory map

The memories are outside the core. `RISC_V_Top` has:

| Port | Dir | Meaning |
|---|---|---|
| `imem_addr[31:0]`, `imem_rdata[31:0]` | out / in | instruction fetch, **combinational** read (the PC is `imem_addr`) |
| `dmem_re`, `dmem_we[3:0]`, `dmem_addr[31:0]`, `dmem_wdata[31:0]` | out | data bus; `dmem_we` are byte enables, `dmem_wdata` is lane-aligned |
| `dmem_rdata[31:0]` | in | the whole word, **one cycle after** `dmem_re` |

The load/store unit (`StageMemory/LSU.v`) stays in the core: `sb` replicates the byte and `sh` the half-word into every lane and sets the byte enables of the lane addressed; loads pick and extend the lane with the format and offset registered together with the request. A half-word store ignores address bit 0 and a word store ignores bits 1:0 (misaligned accesses are not detected until W2-1 is recorded).

`rtl/top/core_tb_top.sv` decodes the bus (spec 4.1): ITCM `0x0000_0000` 16 KB (fetch only, `rtl/mem/itcm.sv`, a fetch outside returns a NOP), DTCM `0x0001_0000` 64 KB (`rtl/mem/dtcm_dp.sv` port A, since 2026-10-29; port B is idle in the core-only top), `SIM_CTRL` `0x0002_0000` and `SIM_PUTC` `0x0002_0004`. Any other data address, including the ITCM seen as data, reads 0 and ignores writes (W2-1 open). Open question for Task 13: spec 4.1 makes the ITCM fetch-only, but the Phase 2 plan puts `.rodata` in the ITCM; a load from the ITCM would then read 0.

`SIM_CTRL` accepts word writes only: `0x1` prints `PASS` and ends the run, `0x2` prints `FAIL` and ends the run, `0x10`, `0x20`, `0x21` print `BATCH_DONE`, `MEAS_START`, `MEAS_STOP`. `SIM_PUTC` prints the low byte.

### 9.2 Retire trace (`ifdef RVVI_TRACE`)

One record per instruction leaving WB, so stalls and flushes never repeat or skip one. The fields and their meaning are the contract for `model/c/rv_iss.c` (Task 12):

| Field | Meaning |
|---|---|
| `rvvi_valid` | a record is present this cycle |
| `rvvi_order[63:0]` | retired instructions before this one, counted from reset (0, 1, 2, ...) |
| `rvvi_pc`, `rvvi_insn` | address and encoding of the retired instruction |
| `rvvi_rd`, `rvvi_rd_wdata` | destination and the value written; both 0 when nothing (or `x0`) is written |
| `rvvi_mem_addr` | effective address of a load or store, else 0 |
| `rvvi_mem_wdata`, `rvvi_mem_wmask` | the lane-aligned word and the byte enables on the write bus; 0 for loads and non-memory instructions |
| `rvvi_trap` | 0 until decision W2-1 defines traps |

`core_tb_top` writes the records to the file given by `+RVVI_LOG=<file>`, one hex line per retire: `order pc insn rd rd_wdata mem_addr mem_wdata mem_wmask trap`. `tools/rv32i_check` compares this whole trace with `RefISS` for every test, which also closes the blind spot noted in `docs/core_stall.md` section 4 (a missing EX/MEM bubble shows as a repeated record). `mcycle`/`cycle` reads are the one value that is masked in that comparison, because the RTL counts real cycles and `RefISS` counts one per instruction.
