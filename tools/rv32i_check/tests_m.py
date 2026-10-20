"""RV32M tests (plan Task 5): RTL vs RefISS."""
from run import compare
from rndgen import rnd_prog, cycles_for, DIV_OPS
import os, random, json
os.makedirs("build", exist_ok=True)
E = "\nend: j end\n"
MUL_OPS = ["mul", "mulh", "mulhsu", "mulhu"]
DIV4 = list(DIV_OPS)
M_ALL = MUL_OPS + DIV4

def pairs_body(pairs, ops, first_rd=10):
    """For every (a,b) pair run every op in `ops`, results in consecutive registers."""
    s, rd = "", first_rd
    for a, b in pairs:
        s += f" li x1,{a:#x}\n li x2,{b:#x}\n"
        for op in ops:
            s += f" {op} x{rd},x1,x2\n"; rd += 1
    return s

T = {
 # plan Task 5 tests
 "mul_corners": pairs_body([(0x80000000, 0x80000000), (0xFFFFFFFF, 0xFFFFFFFF), (0x7FFFFFFF, 2)], MUL_OPS),
 "div_by_zero": pairs_body([(5, 0), (0xFFFFFFF9, 0), (0, 0), (0x80000000, 0)], DIV4, 8),
 "div_overflow": pairs_body([(0x80000000, 0xFFFFFFFF)], DIV4),
 "div_signs": pairs_body([(0xFFFFFFF9, 2), (7, 0xFFFFFFFE), (0xFFFFFFF9, 0xFFFFFFFE), (7, 2)], DIV4, 8),
 "div_back_to_back_dep": " li x1,100\n li x2,7\n div x3,x1,x2\n add x4,x3,x3\n div x5,x4,x2\n rem x6,x5,x2\n mul x7,x6,x6\n",
 "div_in_branch_shadow": " li x1,100\n li x2,7\n li x3,0x55\n beq x0,x0,L\n div x3,x1,x2\n rem x3,x1,x2\n"
                         "L: addi x4,x3,1\n bne x0,x0,M\n div x5,x1,x2\nM: addi x6,x5,1\n",
 "mul_x0": " li x1,12345\n li x2,-77\n mul x0,x1,x2\n add x3,x0,x1\n div x0,x1,x2\n rem x0,x1,x2\n mulh x0,x1,x2\n add x4,x0,x2\n",
 # extra directed tests: operands of a divide arrive by every forwarding path
 "div_operand_forwarded": " addi x1,x0,100\n addi x2,x0,7\n div x3,x1,x2\n nop\n div x4,x1,x2\n addi x5,x0,9\n nop\n nop\n div x6,x5,x2\n",
 "div_operand_from_load": " li x5,DM+0x40\n li x6,91\n sw x6,0(x5)\n li x2,7\n lw x1,0(x5)\n div x3,x1,x2\n lw x4,0(x5)\n rem x7,x2,x4\n",
 "div_chain_both_operands": " li x1,1000003\n li x2,17\n div x3,x1,x2\n rem x4,x1,x2\n div x5,x3,x4\n rem x6,x3,x4\n divu x7,x5,x6\n",
 "div_result_to_store": " li x5,DM+0x40\n li x1,99\n li x2,4\n div x3,x1,x2\n sw x3,0(x5)\n rem x4,x1,x2\n sw x4,4(x5)\n lw x6,0(x5)\n",
 "div_branch_on_result": " li x1,20\n li x2,5\n li x4,4\n div x3,x1,x2\n beq x3,x4,L\n addi x20,x0,1\nL: addi x21,x0,2\n div x5,x1,x2\n bne x5,x4,K\n addi x22,x0,3\nK: addi x23,x0,4\n",
 "mul_chain_dep": " li x1,3\n mul x2,x1,x1\n mul x3,x2,x2\n mul x4,x3,x3\n mulh x5,x4,x4\n mulhu x6,x4,x4\n mulhsu x7,x4,x4\n",
 "div_by_one_and_self": " li x1,0x80000001\n li x2,1\n div x3,x1,x2\n divu x4,x1,x2\n rem x5,x1,x1\n remu x6,x1,x1\n div x7,x1,x1\n",
 "div_then_jalr": " auipc x5,0\n li x1,12\n li x2,3\n div x3,x1,x2\n jalr x4,24(x5)\n addi x20,x0,1\n addi x21,x0,2\n addi x22,x0,3\n",
}
fails = []
for k, v in T.items():
    if compare(".text\n" + v + E, k, steps=400, cycles=2500): fails.append(k)
print(f"\nRV32M DIRECTED: {len(T)-len(fails)}/{len(T)} pass; FAIL={fails}")

N = 300
rf = []
for s in range(N):
    src = rnd_prog(random.Random(1000 + s), 60, extra_r=tuple(M_ALL))
    if compare(src, f"randm_{s}", steps=400, cycles=cycles_for(src), quiet=True): rf.append(s)
print(f"RANDOM RV32IM, {N} seeds x ~60 instr: {N-len(rf)}/{N} pass; failing seeds={rf[:10]}")
res = {f"m_{k}": (k not in fails) for k in T}
res.update({f"randm_{i}": (i not in rf) for i in range(N)})
json.dump(res, open("build/results_m.json", "w"), indent=1)
