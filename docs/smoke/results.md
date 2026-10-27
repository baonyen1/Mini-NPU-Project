# Week-1 tool gate results (Task 0, S1-S7)

Run on 2026-10-17 on the Windows machine of Nguyen The Bao. Scripts: `sim/questa/smoke/run_smoke.sh`
(S1, S2, S3, S7), `sim/verilator/smoke/` (S4), `sw/smoke/t.S` (S5). Raw logs are written to
`sim/questa/smoke/out/` (not committed).

## Tools and licence

| Item | Observed |
|---|---|
| QuestaSim | `Questa Sim-64 vsim 10.7c Simulator 2018.08 Aug 18 2018` (`C:\questasim64_10.7c`) |
| Licence | `MGLS_LICENSE_FILE=C:\questasim64_10.7c\win64\LICENSE.txt`, a local node file (`SERVER bao ... 27001`, `VENDOR mgcld`). `randomize` and `covergroup` both ran (S1, S3), which the FPGA Starter edition rejects. |
| Vivado xsim | 2024.1 (`C:\Xilinx\Vivado\2024.1\bin`); **no longer on Bảo's machine** (`C:\Xilinx` was found empty on 2026-10-26), S6 below was run before that |
| RISC-V binutils/gcc | `riscv64-unknown-elf-gcc` 12.2.0 from Vitis 2024.1 (`C:\Xilinx\Vitis\2024.1\gnu\riscv\nt\riscv64-unknown-elf\bin`); gone since 2026-10-26, the regression now runs in WSL with `binutils-riscv64-unknown-elf` (Ubuntu 24.04) |
| Verilator | `Verilator 5.020 2024-01-01 rev (Debian 5.020-1)` in WSL Ubuntu 24.04, installed by Bảo on 2026-10-27; not available natively on Windows |

## Results

| ID | Check | Result | Command / observed output |
|---|---|---|---|
| S1 | Questa UVM + `randomize()` | ✅ | `vlib work`; `vlog -sv uvm_hello.sv`; `vsim -c work tb_top +UVM_TESTNAME=hello_test -do "run -all; quit -f"`. Output: `[HELLO] Questa UVM ok, x=6`, `UVM_ERROR :    0`, `UVM_FATAL :    0`. UVM comes precompiled with Questa, no `uvm_pkg.sv` path needed. |
| S2 | Questa DPI-C | ✅ | `gcc -shared -I"$QUESTA_HOME/include" -o out/dpi_add.dll dpi_add.c`; `vsim ... -sv_lib out/dpi_add`. Output: `c_add(2,3)=5`, `c_xor32=f0f00f0f`. **Gotcha:** a `bit [31:0]` cannot be a DPI return value (`vlog-2572: illegal DPI function return value`). Pass it as an `output` argument (`svBitVecVal *`). `int` and `int unsigned` returns are fine. |
| S3 | Covergroup report | ✅ | `vsim -c -coverage ... -do "coverage save -onexit out/cov.ucdb; run -all; quit -f"`, then `vcover report -details out/cov.ucdb`. Output: `bin b0/b1 Covered`, `b2/b3 ZERO`, `TOTAL COVERGROUP COVERAGE: 50.00%`. **Gotcha:** `$finish` ends the run before a later `coverage save`; use `-onexit`. |
| S4 | `icg_cell` latch+AND, `gclk` stops while `en=0` | ✅ with caveats (run 2026-10-27; first skipped 2026-10-18) | Verilator 5.020 under WSL. `verilator --lint-only -Wall --timing --top-module icg_tb icg_tb.sv`: no LATCH or COMBDLY warning, but 3 testbench style warnings (DECLFILENAME: the cell lives in `icg_tb.sv`; UNUSEDSIGNAL: `gclk`; BLKSEQ: `always #5 clk = ~clk`), so it exits 1 under `-Wall`; the plan's command without `--timing` fails with NEEDTIMINGOPT. `verilator --binary --trace --top-module icg_tb -Wno-fatal icg_tb.sv` builds, `./obj_dir/Vicg_tb` writes `icg.vcd`, and `count_toggles.py icg.vcd gclk` prints 0 toggles in cycles 11..19, 2 per steady cycle, 1 in each boundary cycle (10, 20), `RESULT: PASS`. The `gclk` edges equal QuestaSim's. Verilator also records the final falling edge at `$finish` (t = 300) and Questa does not, so `count_toggles.py` skips a last cycle that the end of the run cuts short; with the window moved to cycles 5..15 it still prints `RESULT: FAIL`. This tests the toy cell, not `npu_clk_gate` (Task 11). |
| S5 | `max` and `.insn` assemble; `$readmemh` hex | ✅ | `riscv64-unknown-elf-gcc -march=rv32im_zicsr_zifencei_zbb -mabi=ilp32 -c t.S`: `0ac5e533 max a0,a1,a2`, `00b5000b` (the expected word). Word-wide hex for `$readmemh`: `objcopy -O verilog -j .text --verilog-data-width=4 --reverse-bytes=4 t.o t.hex` gives `0AC5E533 00B5000B`. **Gotcha:** without `-j .text` objcopy fails on `.riscv.attributes`; without `--reverse-bytes=4` the words come out byte-swapped. `$readmemh` itself was not run. |
| S6 | xsim runs the S1 test | ✅ | `xvlog -sv -L uvm uvm_hello.sv`; `xelab tb_top -L uvm -s hello`; `xsim hello -R -testplusarg "UVM_TESTNAME=hello_test"` (the quotes matter when started through `cmd`). Output: `[HELLO] ... x=2`, `UVM_ERROR :    0`, `UVM_FATAL :    0`. |
| S7 | VCD of one scope | ✅ | `vsim -c -voptargs=+acc ... -do vcd_scope.do` with `vcd file engine.vcd; vcd add -r /tb_vcd/dut/*; run 1us; vcd flush`. VCD contains only `clk` and `q` of `dut`; `other` from the parent scope is absent. **Gotcha:** without `-voptargs=+acc` the scope `dut` is optimised away and `vcd add` fails with `vsim-3561`. |

## Decisions

- **O3 closed (2026-10-17):** QuestaSim runs UVM with `randomize` and `covergroup`; it is the primary simulator. xsim 2024.1 is a verified fallback (S6).
- **D1a stays open.** It depends on the first MNIST run time. S4 ran on Verilator on 2026-10-27 and the toy clock-gate cell behaves there as on Questa; `npu_clk_gate` itself is untested under Verilator until Task 11.
- Proposal Tables 1, 3, 9, 11, 12 (docx, not in the repo): update by hand with "QuestaSim + UVM; marimo instead of PyTorch".

## Re-run on 2026-10-27 (Verilator installed, checks run in WSL on a clean LF clone of `2b1ed05`)

- `make -C sim/verilator lint`: exit 0, no warnings (`npu_pkg.sv` + `dtcm_dp.sv`, `-Wall`).
- `make -C sim/verilator test_dtcm_dp`: `RESULT: PASS` twice (107 checks with empty memory, 172 with `+DTCM=dtcm_init.hex`).
- `tools/rv32i_check`: the 8 suites ran one per WSL session (see the note below); merged with the logic of `run_all.py`: `total 1291, passed 1291, known failures 0`, `RESULT: PASS`.
- `make -C model/c test` (ASan + UBSan, `-Werror`): `npu_ref: all tests passed`, `all rv_iss tests passed`. `make -C model/c xcheck`: `xcheck: 1263 programs, 516600 retire records identical to RefISS`.
- Not run in WSL: `pytest model/py/tests` (no numpy there). On Windows with the committed (LF) bytes it gives `13 passed`.

Note on WSL: on 2026-10-26 `wsl.exe` crashed (`0xC00000FD`) about 30 s into every session while the host had 0.4 GB RAM free and the WSL VM held 4.7 GB (probable cause, not proven). On 2026-10-27 the host had 4.4 GB RAM free again and sessions of up to ~26 s ran reliably; longer ones were not tried.
