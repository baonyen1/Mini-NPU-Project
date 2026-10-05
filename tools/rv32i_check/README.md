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
```
python run_all.py          # everything
python tests_isa.py        # one test per RV32I instruction (40)
python tests_hazard.py     # 25 directed hazard/control tests + 300 random programs
```
Artifacts go to `build/` (assembly, objects, binaries, `sim.vvp`).

## Baseline (2026-10-04, core copied unchanged from Senior Project 1)
- ISA: 30/40. Missing: `slt sltu sra slti sltiu slli srli srai bltu bgeu`.
  `fence ecall ebreak` execute as NOP (no traps).
- Hazard/control directed: 25/25. Random (supported subset only): 300/300.
- Sanity: disabling EX/MEM forwarding drops these to 8/25 and 64/300, so the
  harness does detect pipeline bugs.

## Notes
- Memory model mirrors the current core: Harvard, 256-word IMEM, 256-word DMEM
  addressed by `addr[9:0]`. Update `ISS` in `run.py` when the memory map changes
  to the spec (ITCM 16 KB / DTCM 64 KB).
- The Senior Project 1 DFS coupling (`workload_monitor`, `cpu_en`) is removed; the
  harness builds `rtl/core` with no stub.
- The random generator only uses instructions the core already supports. After
  adding the missing instructions, add them to `SUP_R` / `SUP_I` / the branch list
  in `tests_hazard.py`.
- This is a quick check, not the UVM environment in the spec (`tb/uvm/core_env`).
