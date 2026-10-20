# model/c

C golden models and their unit tests (spec 10.2).

| File | Model | Owner |
|---|---|---|
| `npu_ref.c` | untimed MAC engine (spec 6) | Track B |
| `rv_iss.c` | untimed core ISS: RV32IM + Zicsr + Zifencei + Zbb + custom-0, spec 4.1 memory map, RVVI retire record | Track A |

```
make -C model/c test      # unit tests of both models (self-contained, hand-computed expected values)
make -C model/c xcheck    # run every program of the Python suites through rv_iss; compares registers and the
                          # whole RVVI trace with RefISS (needs python tools/rv32i_check/run_all.py first;
                          # it fails, it does not skip, when the programs are missing)
```
The build uses `-Werror` and `-fsanitize=address,undefined`; if linking fails on Windows (MinGW), run under
WSL/Linux or override `CFLAGS` without the sanitizers.

## rv_iss API (rv_iss.h)
`iss_init(itcm, n, dtcm, n, mode)`, `iss_step(&rec)` (returns 1 after a word write to `SIM_CTRL`), and getters
(`iss_reg`, `iss_pc`, `iss_mem_read`, `iss_cmd_get`, ...). `ISS_STUB` models the core-only testbench stub
(commands are logged, READ_RESULT returns its index, CSR 0x7C0/0x7C1 as in `rtl/top/npu_stub.sv`);
`ISS_FULL` drives `npu_ref` (commands execute, stores to the DTCM are mirrored into its image).
The retire record is defined in `docs/core_isa.md` section 9.2.

Ruled behaviours while decision W2-1 is open: unknown encodings, `fence`, `ecall`, `ebreak` are NOPs; a data
address outside the map reads 0 and ignores writes; a fetch outside the ITCM executes a NOP; writes to
`mcycle`/`minstret` are ignored; `mcycle` counts one per instruction.
