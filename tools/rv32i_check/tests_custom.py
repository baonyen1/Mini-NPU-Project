"""custom-0 tests (plan Task 9): RTL (core + npu_stub) vs RefISS stub mode.

compare() checks registers, data memory and the engine command log: every
`PUSH op addr k clr` line the stub prints must equal RefISS.cmd_log, in order.
Rows needing stub timing patterns pass them as plusargs."""
from run import compare
import os, json
os.makedirs("build", exist_ok=True)
E = "\nend: j end\n"
LDW = ".insn r 0x0B,0,0,x0,{a},{b}\n"
LDI = ".insn r 0x0B,1,0,x0,{a},{b}\n"
def mac(k, clr): return f".insn r 0x0B,2,{clr},x0,{k},x0\n"
def rr(rd, idx): return f".insn r 0x0B,3,0,{rd},{idx},x0\n"
PRE = " li x1,DM+0x40\n li x2,16\n li x3,0x55\n"

T = {
 # plan Task 9 tests
 "push_each_op": (PRE + " " + LDW.format(a="x1", b="x2") + " " + LDI.format(a="x1", b="x2") + " " + mac("x2", 0) + " " + mac("x2", 1), ()),
 "illegal_funct3": (PRE + " .insn r 0x0B,4,0,x0,x1,x2\n .insn r 0x0B,5,0,x0,x1,x2\n .insn r 0x0B,6,1,x0,x1,x2\n .insn r 0x0B,7,0x7f,x0,x1,x2\n", ()),
 "read_result_returns_idx": (PRE + "".join(f" li x4,{i}\n " + rr(f"x{10+i}", "x4") for i in range(16)), ()),
 "fifo_full_stall": (PRE + "".join(" " + LDW.format(a="x1", b="x2") for _ in range(3)) + "".join(" " + mac("x2", i & 1) for i in range(3))
                     + " " + rr("x10", "x3"), ("+STUB_READY=0001",)),
 "push_in_branch_shadow": (PRE + " beq x0,x0,L\n " + LDW.format(a="x1", b="x2") + " " + mac("x2", 1) + "L: addi x4,x0,1\n bne x0,x0,M\n "
                           + LDI.format(a="x1", b="x2") + "M: addi x5,x0,2\n", ()),
 # extra directed tests
 "read_result_idx_upper_bits_ignored": (PRE + " li x4,0xFFFFFFF7\n " + rr("x10", "x4") + " li x4,0x10\n " + rr("x11", "x4"), ()),
 "custom_rd_ignored_no_writeback": (PRE + " li x7,0x77\n .insn r 0x0B,0,0,x7,x1,x2\n .insn r 0x0B,1,0,x7,x1,x2\n .insn r 0x0B,2,0,x7,x2,x0\n add x8,x7,x7\n", ()),
 "read_result_forwarded": (PRE + " li x4,9\n " + rr("x10", "x4") + " add x11,x10,x10\n " + rr("x12", "x11") + " sub x13,x12,x10\n", ()),
 "read_result_load_use_like": (PRE + " li x4,3\n " + rr("x10", "x4") + " addi x11,x10,1\n " + rr("x12", "x4") + " nop\n add x13,x12,x12\n", ()),
 "push_operands_from_alu_and_load": (" li x1,DM+0x40\n li x6,16\n sw x6,0(x1)\n lw x2,0(x1)\n " + LDW.format(a="x1", b="x2")
                                      + " addi x3,x2,16\n " + LDI.format(a="x1", b="x3") + " " + mac("x3", 1), ()),
 "push_stream_slow_ready": (PRE + "".join(" " + LDW.format(a="x1", b="x2") + " " + mac("x2", 0) for _ in range(4)) + " " + rr("x10", "x3"), ("+STUB_READY=00010001",)),
 "read_result_slow_ready": (PRE + " " + mac("x2", 1) + " li x4,2\n " + rr("x10", "x4") + " addi x11,x10,5\n " + rr("x12", "x2"), ("+STUB_RDREADY=00000001",)),
 "mixed_stalls": (PRE + " li x4,100\n li x5,7\n " + mac("x2", 0) + " div x6,x4,x5\n " + rr("x10", "x5") + " add x11,x10,x6\n " + LDW.format(a="x1", b="x2")
                  + " rem x7,x4,x5\n " + rr("x12", "x7"), ("+STUB_READY=0101", "+STUB_RDREADY=00010001")),
}
fails = []
for k, (v, pa) in T.items():
    if compare(".text\n" + v + E, k, steps=400, cycles=4000, plusargs=pa): fails.append(k)
print(f"\nCUSTOM-0: {len(T)-len(fails)}/{len(T)} pass; FAIL={fails}")
json.dump({f"custom_{k}": (k not in fails) for k in T}, open("build/results_custom.json", "w"), indent=1)
