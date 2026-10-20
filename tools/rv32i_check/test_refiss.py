"""Unit check of RefISS against hand-computed values (plan Task 4, Step 1).

RefISS is the oracle for tests_m / tests_csr / tests_zbb / tests_custom, so its
own results are pinned here with constants worked out by hand from the RISC-V
ISA manual (not produced by RefISS). Only then may the RTL be compared to it."""
import os, json
from run import assemble, RefISS, M32
os.makedirs("build", exist_ok=True)
results = {}

def run(src, tag, steps):
    prog = assemble(".text\n" + src + "\nend: j end\n", tag)
    s = RefISS(prog)
    for _ in range(steps): s.step()
    return s

def check(name, src, steps, regs, cmd_log=None):
    s = run(src, "refiss_" + name, steps)
    bad = [f"x{r}: got {s.x[r]:08x} want {v:08x}" for r, v in regs.items() if s.x[r] != v]
    if cmd_log is not None and s.cmd_log != cmd_log:
        bad.append(f"cmd_log: got {s.cmd_log} want {cmd_log}")
    results["refiss_" + name] = not bad
    print(f"[{'PASS' if not bad else 'FAIL'}] refiss_{name}")
    for b in bad[:6]: print("       ", b)
    return s

# ---- M: (0x80000000,0x80000000), (-1,-1), (0x7FFFFFFF,2) x mul mulh mulhsu mulhu
check("mul_corners",
  "li x1,0x80000000\n li x2,0x80000000\n mul x10,x1,x2\n mulh x11,x1,x2\n mulhsu x12,x1,x2\n mulhu x13,x1,x2\n"
  "li x3,-1\n li x4,-1\n mul x14,x3,x4\n mulh x15,x3,x4\n mulhsu x16,x3,x4\n mulhu x17,x3,x4\n"
  "li x5,0x7FFFFFFF\n li x6,2\n mul x18,x5,x6\n mulh x19,x5,x6\n mulhsu x20,x5,x6\n mulhu x21,x5,x6\n", 24,
  {10: 0x00000000, 11: 0x40000000, 12: 0xC0000000, 13: 0x40000000,    # (-2^31)^2 = 2^62
   14: 0x00000001, 15: 0x00000000, 16: 0xFFFFFFFF, 17: 0xFFFFFFFE,    # (2^32-1)^2 = 2^64 - 2^33 + 1
   18: 0xFFFFFFFE, 19: 0x00000000, 20: 0x00000000, 21: 0x00000000})

# ---- M: divide by zero, overflow, sign rules, unsigned
check("div_cases",
  "li x1,5\n li x2,0\n div x10,x1,x2\n divu x11,x1,x2\n rem x12,x1,x2\n remu x13,x1,x2\n"
  "li x3,-7\n div x14,x3,x2\n rem x15,x3,x2\n"
  "li x4,0x80000000\n li x5,-1\n div x16,x4,x5\n rem x17,x4,x5\n"
  "li x6,2\n div x18,x3,x6\n rem x19,x3,x6\n"
  "li x7,7\n li x8,-2\n div x20,x7,x8\n rem x21,x7,x8\n"
  "divu x22,x3,x6\n remu x23,x3,x6\n", 26,
  {10: 0xFFFFFFFF, 11: 0xFFFFFFFF, 12: 5, 13: 5,                    # x/0: quotient all ones, remainder = dividend
   14: 0xFFFFFFFF, 15: 0xFFFFFFF9,                                  # -7/0
   16: 0x80000000, 17: 0,                                           # -2^31 / -1
   18: 0xFFFFFFFD, 19: 0xFFFFFFFF,                                  # -7/2 = -3 r -1
   20: 0xFFFFFFFD, 21: 1,                                           # 7/-2 = -3 r 1
   22: 0x7FFFFFFC, 23: 1})                                          # 0xFFFFFFF9 / 2 unsigned

# ---- Zbb unary
check("zbb_unary",
  "li x1,0\n li x2,1\n li x3,0x80000000\n li x4,0xFFFFFFFF\n li x5,0x80000F0F\n li x6,0x00010200\n"
  "li x7,0x11223344\n li x8,0x80\n li x9,0x80018001\n li x30,0x7F\n"
  "clz x11,x1\n ctz x12,x1\n clz x13,x2\n ctz x14,x3\n cpop x15,x4\n cpop x16,x5\n"
  "orc.b x17,x6\n rev8 x18,x7\n sext.b x19,x8\n sext.b x20,x30\n sext.h x21,x9\n zext.h x22,x9\n", 30,
  {11: 32, 12: 32, 13: 31, 14: 31, 15: 32, 16: 9,
   17: 0x00FFFF00, 18: 0x44332211, 19: 0xFFFFFF80, 20: 0x7F, 21: 0xFFFF8001, 22: 0x00008001})

# ---- Zbb rotates, min/max, logic with negate
check("zbb_binary",
  "li x1,0x80000001\n li x2,1\n li x3,31\n"
  "rol x10,x1,x2\n ror x11,x1,x2\n rol x12,x1,x0\n rol x13,x1,x3\n rori x14,x2,31\n rori x15,x1,1\n"
  "li x4,0x80000000\n max x16,x4,x2\n min x17,x4,x2\n maxu x18,x4,x2\n minu x19,x4,x2\n"
  "li x5,0xF0F0F0F0\n li x6,0xFF00FF00\n andn x20,x5,x6\n orn x21,x5,x6\n xnor x22,x5,x6\n", 28,
  {10: 0x00000003, 11: 0xC0000000, 12: 0x80000001, 13: 0xC0000000, 14: 0x00000002, 15: 0xC0000000,
   16: 0x00000001, 17: 0x80000000, 18: 0x80000000, 19: 0x00000001,
   20: 0x00F000F0, 21: 0xF0FFF0FF, 22: 0xF00FF00F})

# ---- Zicsr on the scratch CSR 0x7C1 (plain RW) and the W1C status 0x7C0
check("csr_scratch",
  "li x1,0xF0F0\n li x2,0x00FF\n"
  "csrrw x10,0x7c1,x1\n csrrs x11,0x7c1,x2\n csrrc x12,0x7c1,x2\n"
  "csrrwi x13,0x7c1,5\n csrrsi x14,0x7c1,8\n csrrci x15,0x7c1,1\n csrr x16,0x7c1\n"
  "csrrs x17,0x7c1,x0\n csrrwi x18,0x7c1,0\n csrr x19,0x7c1\n", 14,
  {10: 0, 11: 0xF0F0, 12: 0xF0FF, 13: 0xF000, 14: 5, 15: 0xD, 16: 0xC, 17: 0xC, 18: 0xC, 19: 0})
check("csr_status_w1c",
  "csrr x20,0x7c0\n li x1,0x100\n csrrw x0,0x7c0,x1\n csrr x21,0x7c0\n"
  "li x2,0xC00\n csrrs x22,0x7c0,x2\n csrr x23,0x7c0\n", 8,
  {20: 0xF02, 21: 0xE02, 22: 0xE02, 23: 0x002})

# ---- counters: minstret is exact, cycle alias reads one later
check("counters",
  "csrr x1,0xB02\n nop\n nop\n nop\n nop\n nop\n csrr x2,0xB02\n sub x3,x2,x1\n"
  "csrr x4,0xB00\n csrr x5,0xC00\n sub x6,x5,x4\n csrr x7,0xC02\n", 14,
  {1: 0, 2: 6, 3: 6, 6: 1, 7: 11})   # csrr x7 is the 12th instruction: 11 executed before it

# ---- custom-0 stub mode
check("custom_log",
  "li x1,0x10000\n li x2,16\n"
  ".insn r 0x0B,0,0,x0,x1,x2\n .insn r 0x0B,1,0,x0,x1,x2\n"
  ".insn r 0x0B,2,0,x0,x2,x0\n .insn r 0x0B,2,1,x0,x2,x0\n .insn r 0x0B,4,0,x0,x1,x2\n"
  "li x3,0x35\n .insn r 0x0B,3,0,x10,x3,x0\n", 10,
  {10: 5},
  [(0, 0x10000, 16, 0), (1, 0x10000, 16, 0), (2, 0, 16, 0), (2, 0, 16, 1), (3, 0x10000, 16, 0)])

# ---- fence.i is a no-op for the ISS
check("fencei_nop", "addi x1,x0,1\n fence.i\n addi x2,x1,1\n", 3, {1: 1, 2: 2})

# ---- spec memory map: DTCM, SIM_PUTC, SIM_CTRL
s = run("lui x5,0x10\n li x6,0xA5\n sw x6,0(x5)\n lw x7,0(x5)\n lui x8,0x20\n li x9,0x41\n"
        "sb x9,4(x8)\n li x10,1\n sw x10,0(x8)\n", "refiss_spec_map", 9)
ok = (s.x[7] == 0xA5 and s.mem[0] == 0xA5 and s.putc == [0x41] and s.sim_ctrl == [1])
results["refiss_spec_map"] = ok
print(f"[{'PASS' if ok else 'FAIL'}] refiss_spec_map")

# ---- RVVI trace fields (hand-computed): store lane alignment, load record, x0 destination
s = run("lui x5,0x10\n li x6,0x1234ABCD\n sb x6,1(x5)\n sh x6,2(x5)\n sw x6,4(x5)\n lw x7,4(x5)\n addi x0,x0,5\n jal x8,L\nL: nop\n",
        "refiss_trace", 11)
# 0x1234ABCD = lui 0x1234B000 + addi -0x433; (order, pc, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask)
want = [(0, 0x00, 5, 0x00010000, 0, 0, 0),                          # lui x5
        (1, 0x04, 6, 0x1234B000, 0, 0, 0),                          # lui x6
        (2, 0x08, 6, 0x1234ABCD, 0, 0, 0),                          # addi x6
        (3, 0x0C, 0, 0, 0x10001, 0xCDCDCDCD, 0b0010),               # sb at lane 1: byte replicated
        (4, 0x10, 0, 0, 0x10002, 0xABCDABCD, 0b1100),               # sh at the upper half
        (5, 0x14, 0, 0, 0x10004, 0x1234ABCD, 0b1111),               # sw
        (6, 0x18, 7, 0x1234ABCD, 0x10004, 0, 0),                    # lw: address recorded, no write data
        (7, 0x1C, 0, 0, 0, 0, 0),                                   # addi x0: nothing written
        (8, 0x20, 8, 0x00000024, 0, 0, 0),                          # jal links pc+4
        (9, 0x24, 0, 0, 0, 0, 0)]                                   # nop
got = [(t[0], t[1], t[3], t[4], t[5], t[6], t[7]) for t in s.trace[:10]]
ok = (got == want) and all(t[8] == 0 for t in s.trace)
results["refiss_trace"] = ok
print(f"[{'PASS' if ok else 'FAIL'}] refiss_trace")
if not ok:
    for g, w in zip(got, want):
        if g != w: print("        got", [hex(v) for v in g], "want", [hex(v) for v in w])

print("\nSUMMARY:", sum(results.values()), "/", len(results), "pass")
json.dump(results, open("build/results_refiss.json", "w"), indent=1)
