"""Zbb and Zifencei tests (plan Task 7): RTL vs RefISS."""
from run import compare
from rndgen import rnd_prog
import os, random, json
os.makedirs("build", exist_ok=True)
E = "\nend: j end\n"
ZBB_R = ["andn", "orn", "xnor", "max", "maxu", "min", "minu", "rol", "ror"]
ZBB_UN = ["clz", "ctz", "cpop", "sext.b", "sext.h", "zext.h", "orc.b", "rev8"]
ZBB_SH = ["rori"]
VALS = [0, 1, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFF, 0x00010200, 0x11223344, 0x80018001, 0x80000F0F, 0x0000FF00]

def unary_body(op):
    """Apply one unary op to every value in VALS (results x10.., inputs x1..)."""
    s = ""
    for i, v in enumerate(VALS):
        s += f" li x{1+i % 9},{v:#x}\n {op} x{10+i},x{1+i % 9}\n"
    return s

T = {
 # plan Task 7 tests
 "clz_ctz_zero": " li x1,0\n clz x2,x1\n ctz x3,x1\n li x4,1\n clz x5,x4\n ctz x6,x4\n li x7,0x80000000\n clz x8,x7\n ctz x9,x7\n",
 "cpop_all_ones": " li x1,0xFFFFFFFF\n cpop x2,x1\n li x3,0\n cpop x4,x3\n li x5,0x80000F0F\n cpop x6,x5\n",
 "orc_b": " li x1,0x00010200\n orc.b x2,x1\n li x3,0\n orc.b x4,x3\n li x5,0x80FF0001\n orc.b x6,x5\n",
 "rev8": " li x1,0x11223344\n rev8 x2,x1\n rev8 x3,x2\n li x4,0x80000001\n rev8 x5,x4\n",
 "sext_zext": " li x1,0x80\n sext.b x2,x1\n li x3,0x7F\n sext.b x4,x3\n li x5,0x80018001\n sext.h x6,x5\n zext.h x7,x5\n"
              " li x8,0x7FFF\n sext.h x9,x8\n zext.h x10,x8\n",
 "rol_ror_0_31": " li x1,0x80000001\n li x2,0\n li x3,31\n li x4,32\n rol x10,x1,x2\n ror x11,x1,x2\n rol x12,x1,x3\n ror x13,x1,x3\n"
                 " rol x14,x1,x4\n ror x15,x1,x4\n li x5,0x12345678\n li x6,36\n rol x16,x5,x6\n ror x17,x5,x6\n",
 "rori_31": " li x1,0x80000001\n rori x2,x1,31\n rori x3,x1,0\n rori x4,x1,1\n li x5,1\n rori x6,x5,31\n",
 "max_min_sign": " li x1,0x80000000\n li x2,1\n max x10,x1,x2\n min x11,x1,x2\n maxu x12,x1,x2\n minu x13,x1,x2\n"
                 " max x14,x2,x1\n min x15,x2,x1\n maxu x16,x1,x1\n li x3,-1\n max x17,x3,x2\n minu x18,x3,x2\n",
 "andn_orn_xnor": " li x1,0xF0F0F0F0\n li x2,0xFF00FF00\n andn x10,x1,x2\n orn x11,x1,x2\n xnor x12,x1,x2\n andn x13,x1,x0\n orn x14,x0,x1\n xnor x15,x1,x1\n",
 "fence_i_flush": " li x1,5\n csrr x10,0xB02\n fence.i\n addi x2,x1,1\n add x3,x2,x1\n csrr x11,0xB02\n sub x12,x11,x10\n",
 # extra directed tests
 "zbb_forwarding": " li x1,0x00F0\n clz x2,x1\n add x3,x2,x2\n ctz x4,x3\n sext.b x5,x4\n andn x6,x5,x2\n max x7,x6,x3\n",
 "zbb_after_load": " li x5,DM+0x40\n li x6,0x00FF0000\n sw x6,0(x5)\n lw x1,0(x5)\n clz x2,x1\n lw x3,0(x5)\n rev8 x4,x3\n rol x7,x3,x2\n",
 "zbb_x0_dest": " li x1,0x1234\n clz x0,x1\n rev8 x0,x1\n add x2,x0,x1\n andn x0,x1,x1\n",
 "zbb_dest_is_source": " li x1,0x00123400\n clz x1,x1\n li x2,0x80\n sext.b x2,x2\n li x3,0xFF\n rori x3,x3,4\n",
 "fence_i_in_loop": " li x1,3\nL: addi x1,x1,-1\n fence.i\n bne x1,x0,L\n addi x2,x1,7\n",
 "fence_i_dependent_chain": " li x1,1\n fence.i\n fence.i\n addi x1,x1,1\n fence.i\n add x1,x1,x1\n",
}
for op in ZBB_UN:
    T["unary_" + op.replace(".", "_")] = unary_body(op)

fails = []
for k, v in T.items():
    if compare(".text\n" + v + E, k, steps=400, cycles=1200): fails.append(k)
print(f"\nZBB / ZIFENCEI DIRECTED: {len(T)-len(fails)}/{len(T)} pass; FAIL={fails}")

N = 300
rf = []
for s in range(N):
    src = rnd_prog(random.Random(5000 + s), 60, extra_r=tuple(ZBB_R), extra_un=tuple(ZBB_UN), extra_sh=tuple(ZBB_SH))
    if compare(src, f"randzbb_{s}", steps=400, cycles=1200, quiet=True): rf.append(s)
print(f"RANDOM RV32I+Zbb, {N} seeds x ~60 instr: {N-len(rf)}/{N} pass; failing seeds={rf[:10]}")
res = {f"zbb_{k}": (k not in fails) for k in T}
res.update({f"randzbb_{i}": (i not in rf) for i in range(N)})
json.dump(res, open("build/results_zbb.json", "w"), indent=1)
