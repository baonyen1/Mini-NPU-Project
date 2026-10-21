# wave/ — waveform for the progress report (non-graded support tooling)

`isa_tour.py` runs one short program with one instruction from each new extension
(M multiply, Zbb `max`/`cpop`, Zicsr `csrr minstret`, Zifencei `fence.i`, custom-0
`LOAD_WEIGHT` and `READ_RESULT`, M divide) and writes a VCD for GTKWave.

```
cd tools/rv32i_check
python3 wave/isa_tour.py             # [PASS] isa_tour + build/isa_tour.vcd
python3 wave/isa_tour.py --listing   # also prints the retire records
gtkwave build/isa_tour.vcd
```

1. **Oracle first.** The program is checked against `RefISS` with the normal harness
   (`run.compare`: registers, DTCM, engine command log, full RVVI trace). No figure from a
   run the oracle does not agree with.
2. **Then the dump.** The same `program.hex` is re-run with `wave/wave_dump.v` compiled as a
   second top module next to `tb_dump.v` (no change to the regression testbench). Only the
   signals the figure needs are dumped: `clk`, `reset`, `rvvi_valid/pc/insn/rd/rd_wdata`,
   `cmd_valid/cmd_ready/cmd_op`, `rd_req/rd_ready/rd_data`, `div_busy`, `imem_addr`.

The engine stub runs with `+STUB_READY=0001 +STUB_RDREADY=0001` (ready one cycle in four)
so the custom-0 waits are visible.

**Before opening the VCD:** write down by hand the value each instruction should put in its
`rd` (and, for `fence.i` and `LOAD_WEIGHT`, what you expect to see instead), then check the
`rvvi_rd_wdata` pulses against your table.
