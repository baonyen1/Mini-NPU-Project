# Textbook references and reading guide

Two computer-architecture textbooks used as background for the Mini-NPU project.
The PDFs live in this folder for local reading only. They are copyrighted, so
`.gitignore` keeps `docs/references/*.pdf` out of git. **Do not push them to GitHub.**

| Key | Book | File |
|---|---|---|
| **[PH]** | D. A. Patterson, J. L. Hennessy, *Computer Organization and Design: The Hardware/Software Interface, RISC-V Edition*, 2nd ed., Morgan Kaufmann, 2021 | `Patterson_Hennessy_COD_RISC-V_2e.pdf` |
| **[ST]** | W. Stallings, *Computer Organization and Architecture: Designing for Performance*, 11th ed., Pearson, 2019 | `Stallings_COA_11e.pdf` |

Page numbers below are the **printed** page numbers in each book. They differ from
the PDF viewer's page index.

Neither book covers UVM. For verification methodology, use IEEE 1800.2 (proposal ref [8])
and the spec §10.

---

## Track A — scalar core (`rtl/core`)

| Project task (spec §) | Week | Read |
|---|---|---|
| Finish RV32I: `slt/sltu/slti/sltiu`, `sra/srai/slli/srli`, `bltu/bgeu` (§5, rv32i_check baseline) | 3 | [PH] 2.4 Signed and Unsigned Numbers (p.80); 2.5 Representing Instructions (p.87); 2.6 Logical Operations (p.95); 2.7 Instructions for Making Decisions (p.98); 2.10 Wide Immediates and Addresses (p.120). [ST] 11.2 Integer Representation (p.346) |
| ALU structure | 3 | [PH] App. A.5 Constructing a Basic ALU (p.A-26); A.6 Carry Lookahead (p.A-37) |
| M extension: `mul*`, iterative `div/rem` that stalls the pipeline (§5) | 3–4 | [PH] 3.3 Multiplication (p.193); 3.4 Division (p.199). [ST] 11.3 Integer Arithmetic (p.351, Booth's algorithm and division) |
| Pipeline stalls: divider, FIFO full, READ_RESULT stall in MEM (§6.3) | 3–6 | [PH] 4.6 Overview of Pipelining (p.283); 4.7 Pipelined Datapath and Control (p.296); 4.8 Forwarding versus Stalling (p.313); 4.9 Control Hazards (p.325). [ST] 16.4 Instruction Pipelining (p.548); 17.5 RISC Pipelining (p.606) |
| Zicsr, `fence.i`, illegal-instruction policy W2-1 (§4.1, §5) | 2–4 | [PH] 4.10 Exceptions (p.333); 5.14 The Rest of the RISC-V System and Special Instructions (p.486); 2.20 The Rest of the RISC-V Instruction Set (p.167) |
| Hardwired control and decode | 3 | [ST] 19.3 Hardwired Implementation (p.686) |
| Scoreboarding (how CoralNPU tracks dependencies) | optional | [ST] App. G.4 Scoreboarding (p.822) |

## Track B — MAC engine (`rtl/npu`)

| Project task (spec §) | Week | Read |
|---|---|---|
| int8 × int8 → int32, two's-complement wrap (§3.1 D5, §6.3) | 2–5 | [PH] 2.4 (p.80); 3.2 Addition and Subtraction, overflow (p.190). [ST] 11.2–11.3 (pp.346–366) |
| Packed 4×int8 lanes per word (§6.2) | 5 | [PH] 3.6 Subword Parallelism (p.233); 3.8 Subword Parallelism and Matrix Multiply (p.236) |
| Outer-product MAC array, accelerator rationale | 5 | [PH] 6.3 SISD, MIMD, SIMD, SPMD, and Vector (p.527); 6.7 Domain-Specific Architectures (p.549); 6.12 Benchmarking the Google TPUv3 (from p.561) |
| FSM, buffers, SRAM (§7.2) | 5–6 | [PH] App. A.9 SRAMs and DRAMs (p.A-57); A.10 Finite-State Machines (p.A-66). [ST] 12.4 Sequential Circuits (p.414) |
| **Latch-based ICG cell** and gated clock (§8) | 10 | [PH] App. A.7 Clocks (p.A-47); A.8 Flip-Flops, Latches, and Registers (p.A-49) |
| Why switching activity relates to power (§11) | 12 | [PH] 1.7 The Power Wall (p.40): dynamic power ∝ capacitive load × voltage² × switching frequency |
| TCM vs. cache; dual-port / banked DTCM (§4.1) | 2 | [PH] 5.1 Introduction (p.388); 5.2 Memory Technologies (p.392). [ST] 4.1–4.3 Memory Hierarchy (pp.113–128); App. C Interleaved Memory (p.782) |
| DMA (thesis extension, open item 3 background) | thesis | [ST] 8.5 Direct Memory Access (p.265) |

## Joint — firmware, integration, evaluation

| Project task (spec §) | Week | Read |
|---|---|---|
| Calling convention, `crt0.S`, `link.ld`, ELF → hex (§9.1) | 6 | [PH] 2.8 Supporting Procedures (p.104); 2.12 Translating and Starting a Program (p.131). [ST] 15.7 Loading and Linking (p.526) |
| Tiled matmul loop: row tiles reusing IBUF (§9.3) | 13 | [PH] "Going Faster: Matrix Multiply" series: 1.10 (p.49), 2.21 (p.168), 3.8 (p.236), 4.13 (p.363), 5.15 Cache Blocking (p.488), 6.13 (p.580) |
| Performance metrics, cycles, `mcycle`, honest reporting | 12–16 | [PH] 1.6 Performance (p.29); 1.11 Fallacies and Pitfalls (p.50). [ST] 2.3 Amdahl's and Little's Laws (p.45); 2.4 Basic Measures of Performance (p.48) |
| Bus background (AXI-style interconnect, thesis) | thesis | [ST] 3.4 Bus Interconnection (p.92); App. A System Buses (p.768) |

## Suggested reading order by week

- **Weeks 1–2:** [PH] ch. 2 (2.1–2.10), 4.6–4.10; [ST] 11.2–11.3.
- **Weeks 3–4 (A):** [PH] 3.3–3.4, 5.14. **Weeks 3–6 (B):** [PH] 3.6, 3.8, 6.7, App. A.9–A.10.
- **Weeks 10–11:** [PH] 1.7, App. A.7–A.8 (clock gating).
- **Weeks 13–15:** [PH] 2.8, 2.12, 5.15.
