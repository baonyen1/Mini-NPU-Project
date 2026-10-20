"""custom-0 tests (plan Task 9): RTL (core + npu_stub) vs RefISS stub mode.

compare() checks registers, data memory and the engine command log: every
`PUSH op addr k clr` line the stub prints must equal RefISS.cmd_log, in order.
Rows needing stub timing patterns pass them as plusargs."""
from run import compare, check_rtl, DM_BASE
from rndgen import rnd_prog, cycles_for, DIV_OPS
import os, json, random
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
# --- tests that need the core to hold its EX stage while the MEM stage waits ------------------
SLOW_RD = ("+STUB_RDREADY=0000000000000001",)      # rd_ready one cycle in 16
SLOW_CMD = ("+STUB_READY=0000000000000001",)       # cmd_ready one cycle in 16
T.update({
 # Review Focus 1: overlapping stall / flush sources. The oldest instruction wins and younger ones never
 # write back or push.
 "overlap_branch_held_behind_read_result": (PRE + " " + rr("x20", "x3") + " beq x0,x0,L\n addi x21,x0,1\n addi x21,x0,2\nL: addi x22,x0,3\n", SLOW_RD),
 "overlap_jal_held_behind_push": (PRE + " " + LDW.format(a="x1", b="x2") + " jal x5,L\n addi x21,x0,1\n addi x21,x0,2\nL: addi x22,x0,3\n", SLOW_CMD),
 "overlap_jalr_held_behind_read_result": (PRE + " auipc x6,0\n " + rr("x20", "x3") + " jalr x5,24(x6)\n addi x21,x0,1\n addi x21,x0,2\n addi x22,x0,3\n", SLOW_RD),
 "overlap_load_use_behind_read_result": (PRE + " sw x3,0(x1)\n " + rr("x20", "x3") + " lw x7,0(x1)\n add x8,x7,x7\n addi x9,x8,1\n", SLOW_RD),
 "overlap_divide_behind_push": (PRE + " li x4,100\n li x5,7\n " + LDW.format(a="x1", b="x2") + " div x6,x4,x5\n rem x7,x4,x5\n add x8,x6,x7\n", SLOW_CMD),
 "overlap_divide_in_branch_shadow_with_stall": (PRE + " li x4,100\n li x5,7\n " + rr("x20", "x3") + " beq x0,x0,L\n div x6,x4,x5\n " + LDW.format(a="x1", b="x2")
                                                + "L: addi x7,x6,1\n", SLOW_RD),
 "overlap_push_after_taken_branch_while_waiting": (PRE + " " + rr("x20", "x3") + " bne x3,x0,L\n " + LDW.format(a="x1", b="x2") + " " + mac("x2", 1) + "L: " + mac("x2", 0), SLOW_RD + SLOW_CMD),
 # B reads a register written by A two instructions earlier; while the READ_RESULT between them
 # waits in MEM, A leaves the pipeline, so B (held in EX) must have captured A's value.
 "mem_stall_stale_operand": (PRE + " li x6,0x21\n addi x7,x0,7\n " + rr("x20", "x3") + " add x8,x7,x7\n sub x9,x6,x7\n", SLOW_RD),
 "mem_stall_stale_operand_push": (PRE + " li x6,0x21\n addi x7,x0,9\n " + LDW.format(a="x1", b="x2") + " add x8,x7,x7\n sub x9,x7,x6\n", SLOW_CMD),
 # a CSR instruction held in EX behind a waiting READ_RESULT must write once and return the OLD value
 "csr_write_once_under_mem_stall": (PRE + " li x5,0x0F\n csrrw x0,0x7c1,x5\n li x6,0xF0\n " + rr("x0", "x3") + " csrrs x10,0x7c1,x6\n csrr x11,0x7c1\n", SLOW_RD),
 # more programs pinning "a held CSR instruction writes once, and reads the old value" (ex_advance):
 # behind a waiting push, with csrrs/csrrc, and with the immediate forms behind a waiting READ_RESULT
 "csr_write_once_behind_push": (PRE + " li x5,0x0F\n csrrw x0,0x7c1,x5\n li x6,0xF0\n " + LDW.format(a="x1", b="x2") + " csrrs x10,0x7c1,x6\n csrr x11,0x7c1\n"
                                " csrrc x12,0x7c1,x5\n csrr x13,0x7c1\n", SLOW_CMD),
 "csr_imm_write_once_behind_read_result": (PRE + " csrrwi x0,0x7c1,5\n " + rr("x0", "x3") + " csrrsi x10,0x7c1,0xA\n csrr x11,0x7c1\n "
                                           + rr("x0", "x3") + " csrrci x12,0x7c1,3\n csrr x13,0x7c1\n", SLOW_RD),
 "custom_minstret_exact": (PRE + " csrr x10,0xB02\n " + LDW.format(a="x1", b="x2") + " " + mac("x2", 0) + " " + rr("x4", "x3") + " csrr x11,0xB02\n sub x12,x11,x10\n", SLOW_RD + SLOW_CMD),
})
fails = []
for k, (v, pa) in T.items():
    if compare(".text\n" + v + E, k, steps=400, cycles=4000, plusargs=pa): fails.append(k)

# --- RTL-only checks: properties RefISS cannot model -------------------------------------------
def rtl_only(name, src, expect, plusargs=(), stdout_has=(), cycles=4000):
    if check_rtl(".text\n" + src + E, name, expect, cycles=cycles, plusargs=plusargs, stdout_has=stdout_has):
        fails.append(name)
    T[name] = None

# Older stores must be in DTCM when the command is pushed (push happens in MEM, spec 6.3 rule 2).
rtl_only("store_then_load_order",
         " li x1,DM+0x40\n li x2,16\n li x6,0x1234567\n sw x6,0(x1)\n " + LDW.format(a="x1", b="x2"),
         {}, plusargs=("+PUSH_PEEK",), stdout_has=(f"PEEK {DM_BASE + 0x40:08x} 01234567",))
# READ_RESULT with rd = x0 still waits for the engine: with rd_ready one cycle in 16, two of them
# take at least 16 cycles, so the mcycle delta across them is >= 16 (x13 = delta < 16 must be 0).
rtl_only("read_result_x0_still_drains",
         " li x3,5\n csrr x10,0xB00\n " + rr("x0", "x3") + " " + rr("x0", "x3") + " csrr x11,0xB00\n sub x12,x11,x10\n sltiu x13,x12,16\n",
         {13: 0}, plusargs=SLOW_RD)
# COMPUTE and READ_RESULT leave the rs2 field unused (core_isa 6.5): a load whose rd equals that field
# must not cost a load-use stall. Block A has that "dependency" by field, block B has none; the cycle
# counts of the two blocks must be equal (x17 = 1). Found missing by the independent review.
def _rs2_block(ld_rd, c0, c1, d):
    return (f" csrr x{c0},0xB00\n lw x{ld_rd},0(x1)\n .insn r 0x0B,2,0,x0,x2,x5\n .insn r 0x0B,3,0,x0,x3,x5\n"
            f" csrr x{c1},0xB00\n sub x{d},x{c1},x{c0}\n")
rtl_only("no_spurious_stall_compute_rr_rs2",
         " li x1,DM+0x40\n li x2,16\n li x3,5\n sw x3,0(x1)\n" + _rs2_block(5, 10, 11, 12) + _rs2_block(6, 13, 14, 15)
         + " sub x16,x12,x15\n seqz x17,x16\n", {17: 1})
print(f"\nCUSTOM-0: {len(T)-len(fails)}/{len(T)} pass; FAIL={fails}")

# --- random: custom-0, divides, loads, stores and branches mixed, with random ready patterns ---
def custom_line(rng, regs):
    k = rng.random()
    a = rng.choice(regs + [0]); b = rng.choice(regs + [0]); d = rng.choice(regs + [0])
    if k < 0.25: return f" .insn r 0x0B,0,0,x{d},x{a},x{b}"
    if k < 0.45: return f" .insn r 0x0B,1,0,x{d},x{a},x{b}"
    if k < 0.65: return f" .insn r 0x0B,2,{rng.randint(0, 1)},x{d},x{a},x0"
    if k < 0.90: return f" .insn r 0x0B,3,0,x{d},x{a},x0"
    return f" .insn r 0x0B,{rng.randint(4, 7)},{rng.randint(0, 127)},x{d},x{a},x{b}"
PATTERNS = ["1", "01", "0001", "0101", "00000001", "0000000000000001", "1110", "00100001"]
NR = 200
rand_fail = []
for s in range(NR):
    rng = random.Random(9000 + s)
    src = rnd_prog(rng, 60, extra_r=("mul", "mulh", "div", "divu", "rem", "remu"), extra_gen=custom_line, extra_p=0.25)
    pa = (f"+STUB_READY={rng.choice(PATTERNS)}", f"+STUB_RDREADY={rng.choice(PATTERNS)}")
    if compare(src, f"randcustom_{s}", steps=400, cycles=cycles_for(src, base=3000, per_div=45), quiet=True, plusargs=pa):
        rand_fail.append(s)
print(f"RANDOM custom-0 + M + loads/stores/branches, random ready patterns, {NR} seeds: {NR-len(rand_fail)}/{NR} pass; failing seeds={rand_fail[:10]}")

res = {f"custom_{k}": (k not in fails) for k in T}
res.update({f"randcustom_{i}": (i not in rand_fail) for i in range(NR)})
json.dump(res, open("build/results_custom.json", "w"), indent=1)
