# rv32i_check — RV32I self-check for `rtl/core`

Non-graded support tooling. It runs each test program on the RTL core (Icarus
Verilog) and on a small reference ISS in Python (`run.py`), then compares
x1..x31 and all 256 data-memory words at the end of the run.

## Requirements
- Python 3
- Icarus Verilog (`iverilog`, `vvp`) on PATH
- RISC-V binutils on PATH: any of `riscv64-unknown-elf-`, `riscv-none-elf-` (xPack),
  `riscv32-unknown-elf-`. Or set `RV_PREFIX`, e.g. `set RV_PREFIX=riscv-none-elf-`.

## Run
`run_all.py` exits 0 when every test passes except those listed in
`expected_failures.txt`, and 1 on a regression or when a listed test starts
passing (delete its line in the same commit). CI and `tools/finish_task.*` use
this exit code.

```
python run_all.py          # everything
python tests_isa.py        # one test per RV32I instruction (40)
python tests_hazard.py     # 25 directed hazard/control tests + 300 random programs
```
Artifacts go to `build/` (assembly, objects, binaries, `sim.vvp`).

## Status (2026-10-09, after plan Task 3)
- ISA: 44/44 (40 RV32I instructions + 4 signed/unsigned corner tests).
  `fence ecall ebreak` execute as NOP (no traps yet, decision W2-1 open).
- Hazard/control directed: 25/25. Random (full RV32I ALU/branch/load/store): 300/300.
- `expected_failures.txt` is empty.
- Sanity: injecting a logical `sra` or a signed `bltu` makes both the directed
  and the random suites fail, so the harness detects these bugs.
- History: the Senior Project 1 baseline was 30/40 (10 instructions missing).

## Notes
- Memory model mirrors the current core: Harvard, 256-word IMEM, 256-word DMEM
  addressed by `addr[9:0]`. Update `ISS` in `run.py` when the memory map changes
  to the spec (ITCM 16 KB / DTCM 64 KB).
- The Senior Project 1 DFS coupling (`workload_monitor`, `cpu_en`) is removed; the
  harness builds `rtl/core` with no stub.
- The random generator covers all RV32I ALU, shift, branch, load and store
  instructions. Add new extensions (M, Zbb, …) to `SUP_R` / `SUP_I` / `SUP_SH` /
  the branch list in `tests_hazard.py` as they are implemented.
- This is a quick check, not the UVM environment in the spec (`tb/uvm/core_env`).
