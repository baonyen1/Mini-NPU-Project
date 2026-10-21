"""Non-graded support tooling: the "ISA tour" program for the progress-report waveform.

One instruction from each new extension (M, Zbb, Zicsr, Zifencei, custom-0), run on the RTL
core (tb_dump.v + core_tb_top) with a VCD dump of the retire port and the engine handshakes.

Step 1 checks the program against RefISS with the normal harness (registers, DTCM, engine
command log and the full RVVI retire trace), so the figure only shows a run the oracle agrees
with. Step 2 re-runs the same program with a VCD dump for GTKWave.

    cd tools/rv32i_check
    python3 wave/isa_tour.py             # PASS/FAIL + build/isa_tour.vcd
    python3 wave/isa_tour.py --listing   # also print the retire records (pc, insn, rd, value)

Fill in the expected values by hand BEFORE you look at --listing or the VCD.
"""
import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.dirname(HERE)                  # tools/rv32i_check
os.chdir(CHECK)                                # run.py uses build/, program.hex, tb_dump.v relative to here
sys.path.insert(0, CHECK)
import run  # noqa: E402  (harness: assemble, RefISS, compare, read_rvvi)

TAG = "isa_tour"
WAVE_CYCLES = 58                               # ends just after the divide retires and `end: j end` retires once

# Slow engine-stub handshakes so the waits are visible on the waveform:
# cmd_ready one cycle in four, rd_ready one cycle in four (pattern repeats from reset release).
PLUSARGS = ("+STUB_READY=0001", "+STUB_RDREADY=0001")

# Each line: instruction, then the extension it exercises. `DM` = DTCM base (0x0001_0000).
SRC = """.text
    addi x1, x0, -7                 # setup
    addi x2, x0, 3                  # setup
    mul  x3, x1, x2                 # M: multiply (1 cycle)
    max  x4, x1, x2                 # Zbb: signed max
    cpop x5, x1                     # Zbb: population count
    csrr x6, minstret               # Zicsr: instructions retired before this one
    fence.i                         # Zifencei: refetch from PC+4 (no rd)
    li   x8, DM+0x40                # custom-0 operands: DTCM address (16-byte aligned)
    li   x9, 4                      #                    K = 4 int8 elements
    .insn r 0x0B, 0, 0, x0, x8, x9  # custom-0: LOAD_WEIGHT  (push in MEM, waits for cmd_ready)
    li   x11, 5                     # READ_RESULT index
    .insn r 0x0B, 3, 0, x10, x11, x0  # custom-0: READ_RESULT x10, idx 5 (waits for rd_ready)
    div  x7, x1, x2                 # M: divide (34 cycles in EX, stalls the pipeline)
end: j end
"""


def build_wave_sim():
    """Same sources and defines as run.build_sim(), plus wave/wave_dump.v as a second top."""
    srcs = glob.glob(os.path.join(run.CORE, "**", "*.v"), recursive=True)
    srcs += [os.path.join(run.ROOT, "rtl", "top", f) for f in ("core_tb_top.sv", "core_tb_dtcm.sv", "npu_stub.sv")]
    srcs += [os.path.join(run.ROOT, "rtl", "mem", "itcm.sv")]
    cmd = ["iverilog", "-g2012", "-DRVVI_TRACE", f"-DMEM_WORDS={run.CMP_WORDS}",
           "-o", "build/wave.vvp", "tb_dump.v", os.path.join("wave", "wave_dump.v")] + srcs
    subprocess.run(cmd, check=True)


def main():
    # Step 1: oracle check with the normal harness.
    diffs = run.compare(SRC, TAG, steps=200, cycles=600, plusargs=PLUSARGS)
    if diffs:
        print("RTL and RefISS disagree on the ISA tour; fix that before making a figure.")
        return 1

    # Step 2: same program (program.hex was written by compare), now with the VCD dump.
    build_wave_sim()
    vcd = os.path.join("build", f"{TAG}.vcd")
    subprocess.run(["vvp", "-n", "build/wave.vvp", f"+CYCLES={WAVE_CYCLES}", "+ITCM=program.hex",
                    f"+VCD={vcd}", f"+RVVI_LOG=build/{TAG}_wave.rvvi"] + list(PLUSARGS),
                   check=True, capture_output=True, text=True)
    print(f"VCD written: tools/rv32i_check/{vcd}")

    if "--listing" in sys.argv:
        print("\norder  pc        insn      rd  rd_wdata")
        seen = set()
        for rec in run.read_rvvi(f"build/{TAG}_wave.rvvi"):
            order, pc, insn, rd, wdata = rec[:5]
            if pc in seen:                 # `end: j end` loops; show it once
                break
            seen.add(pc)
            print(f"{order:5d}  {pc:08x}  {insn:08x}  x{rd:<2d} {wdata:08x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
