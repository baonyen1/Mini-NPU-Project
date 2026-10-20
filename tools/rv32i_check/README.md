# rv32i_check — core self-check for `rtl/core`

Non-graded support tooling. It runs each test program on the RTL core (Icarus
Verilog) and on a reference ISS in Python (`RefISS` in `run.py`), then compares
x1..x31, the data memory and, for custom-0, the engine command log.

`RefISS` models RV32IM + Zicsr + Zifencei + Zbb + custom-0 (stub mode). It is
cycle-free: `mcycle` is the instruction count (ideal 1 CPI), so tests keep only
derived booleans of cycle reads. `minstret` is exact (instructions executed
before the reader).

## Requirements
- Python 3
- Icarus Verilog (`iverilog`, `vvp`) on PATH
- RISC-V binutils on PATH: any of `riscv64-unknown-elf-`, `riscv-none-elf-` (xPack),
  `riscv32-unknown-elf-`. Or set `RV_PREFIX`, e.g. `set RV_PREFIX=riscv-none-elf-`.

## Run
`run_all.py` exits 0 when every test passes except those listed in
`expected_failures.txt`, and 1 on a regression or when a listed entry matches no
failing test any more (delete its line in the same commit). CI and
`tools/finish_task.*` use this exit code. Entries are test names or `fnmatch`
patterns, each with a dated reason.

```
python run_all.py          # everything
python test_refiss.py      # RefISS against hand-computed values (the oracle's own test)
python tests_isa.py        # one test per RV32I instruction + corner tests
python tests_hazard.py     # directed hazard/control tests + 300 random programs
python tests_m.py          # RV32M directed + 300 random programs with M mixed in
python tests_csr.py        # Zicsr, counters, scratch CSR 0x7C1, W1C status 0x7C0
python tests_zbb.py        # Zbb, fence.i directed + 300 random programs with Zbb
python tests_custom.py     # custom-0 push / READ_RESULT against the engine stub log
```
Artifacts go to `build/` (assembly, objects, binaries, `sim.vvp`, and for every
`compare()` a `<tag>.ref.txt` with RefISS's final registers, used by
`model/c` `rv_iss` tests).

## Memory map switch
`MEMMAP=sp1` (default until plan Task 8) is the Senior Project 1 model: 256-word
IMEM and DMEM addressed by `addr[9:0]`. `MEMMAP=spec` is spec 4.1 (ITCM 16 KB,
DTCM 64 KB at `0x0001_0000`, `SIM_CTRL`, `SIM_PUTC`). Test sources use the
assembler symbol `DM` as the data base (`li x5,DM+0x40`); `run.py` defines it per
map, so one source runs under both.

## Engine CSR stub (tests only)
`0x7C1` is a plain 32-bit RW register (the scratch CSR for `csr_ops_all6`).
`0x7C0` reads `{err[3:0], 8'b0000_0010}` with all four sticky error bits set at
reset, and bits 11..8 are write-1-to-clear (spec 6.4). The same behaviour is
modelled in `RefISS` and (from plan Task 6) in the RTL testbench stub.

## Notes
- The Senior Project 1 DFS coupling (`workload_monitor`, `cpu_en`) is removed; the
  harness builds `rtl/core` with no stub.
- `rndgen.py` is the random-program generator for `tests_m.py` and `tests_zbb.py`.
- This is a quick check, not the UVM environment in the spec (`tb/uvm/core_env`).
