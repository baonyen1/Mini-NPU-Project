# Scalar core ISA — `rtl/core`

Status: **RV32I base complete** (plan Task 3, 2026-10-09).
Spec: `docs/superpowers/specs/2026-10-04-mini-npu-design.md` §5–§6.

| Extension | Status | Plan task |
|---|---|---|
| RV32I (base, 40 instructions) | ✅ implemented, regression green | 3 |
| M (`mul*`, `div*`, `rem*`) | ⬜ planned | 5 |
| Zicsr + counters, `npu_status`/`npu_busy_cyc` | ⬜ planned | 6 |
| Zifencei, Zbb | ⬜ planned | 7 |
| custom-0 (LOAD_WEIGHT, LOAD_INPUT, COMPUTE, READ_RESULT) | ⬜ planned | 9 |

## 1. Implemented instructions (RV32I)

The `ALU op` column is the 4-bit `alu_operation` that `Control.v` sends to `ALU.v` (§3).
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

## 3. Internal control encodings

| Signal | Width | Encoding |
|---|---|---|
| `alu_operation` | 4 | `0000` AND, `0001` OR, `0010` ADD, `0011` XOR, `0100` SLL, `0101` SRL, `0110` SUB, `0111` SLT, `1000` SLTU, `1001` SRA. **Free: `1010`–`1111`** (M and Zbb will need more codes; widening to 5 bits is likely in Task 7). |
| `alu_branch_control` | 3 | = funct3 of the branch |
| `DataFormat` | 3 | = funct3 of the load/store |
| `ALUSrcA` | 2 | `00` rs1, `01` zero (LUI), `10` PC (AUIPC) |
| `ALUSrc` | 1 | `0` rs2, `1` immediate |
| `WB_sel` | 2 | `00` ALU result, `01` load data, `10` PC+4 (JAL/JALR) |

## 4. Unsupported and illegal instructions (decision W2-1, still open)

Current behaviour: any encoding `Control.v` does not recognise — including `ecall`, `ebreak`, reserved funct3/funct7 values and garbage opcodes — produces no register write, no memory access and no control transfer, so it behaves as a NOP. Misaligned loads/stores are not detected (the low address bits are dropped for `lw`/`sw`).

This is **not** standard RV32I behaviour (the ISA requires an exception). Options and the recommendation are in the spec discussion; the team must record one in spec §4.1 at the week-2 freeze (plan Task 2):

- (a) minimal M-mode trap (`mtvec`, `mepc`, `mcause`, `mret`) — needs Zicsr first;
- **(b) simulation halt** — `ecall`/`ebreak` assert `halt`; illegal or misaligned assert `halt` + `fault` *(recommended for Senior Project 2)*;
- (c) keep NOP — not recommended, hides bugs.

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

Memory model in the harness is still the Senior Project 1 one (1 KB IMEM, 1 KB DMEM). It moves to the spec map (ITCM 16 KB, DTCM 64 KB) in plan Task 8.
