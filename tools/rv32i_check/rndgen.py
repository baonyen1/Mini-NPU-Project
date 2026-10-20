"""Constrained-random program generator shared by tests_m.py and tests_zbb.py.

Same shape as the generator in tests_hazard.py (small register pool for dense
dependencies, x31 = data base, loads/stores/branches mixed in), plus
  * a corner-value preload of x1..x7 so that divide-by-zero, -2^31 / -1 and
    sign cases are reached by plain random operand choice;
  * extra op groups (M, Zbb) selected by the caller."""
import random

CORNERS = [0, 1, 2, 3, 7, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF, 0xFFFFFFFE,
           0x0000FFFF, 0xFFFF0000, 0x12345678, 0xDEADBEEF, 0x000000FF, 0x80000F0F]
BASE_R  = ["add", "sub", "xor", "or", "and", "sll", "srl", "sra", "slt", "sltu"]
BASE_I  = ["addi", "xori", "ori", "andi", "slti", "sltiu"]
BASE_SH = ["slli", "srli", "srai"]
DIV_OPS = ("div", "divu", "rem", "remu")
END = "\nend: j end\n"

def rnd_prog(rng, n=60, extra_r=(), extra_un=(), extra_sh=()):
    """extra_r: R-type mnemonics (rd,rs1,rs2); extra_un: unary mnemonics (rd,rs1);
    extra_sh: immediate-shift mnemonics (rd,rs1,shamt)."""
    regs = list(range(1, 8))
    L = [f" li x31,DM+0x200"]
    for r in regs:
        L.append(f" li x{r},{rng.choice(CORNERS):#x}")
    lab = 0
    r_all = BASE_R + list(extra_r) * 3            # extra ops are favoured
    for _ in range(n):
        r = rng.random(); d = rng.choice(regs); a = rng.choice(regs + [0]); b = rng.choice(regs + [0])
        if r < 0.33: L.append(f" {rng.choice(r_all)} x{d},x{a},x{b}")
        elif r < 0.43: L.append(f" {rng.choice(BASE_I)} x{d},x{a},{rng.randint(-2048, 2047)}")
        elif r < 0.50: L.append(f" {rng.choice(BASE_SH + list(extra_sh))} x{d},x{a},{rng.randint(0, 31)}")
        elif r < 0.56 and extra_un: L.append(f" {rng.choice(list(extra_un))} x{d},x{a}")
        elif r < 0.62: L.append(f" lui x{d},{rng.randint(0, 0xFFFFF)}")
        elif r < 0.74:
            op = rng.choice(["lw", "lh", "lhu", "lb", "lbu"]); al = {"lw": 4, "lh": 2, "lhu": 2}.get(op, 1)
            L.append(f" {op} x{d},{rng.randrange(0, 64, al)}(x31)")
        elif r < 0.86:
            op = rng.choice(["sw", "sh", "sb"]); al = {"sw": 4, "sh": 2}.get(op, 1)
            L.append(f" {op} x{b},{rng.randrange(0, 64, al)}(x31)")
        else:
            op = rng.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"]); lab += 1
            L.append(f" {op} x{a},x{b},R{lab}")
            for _ in range(rng.randint(0, 3)):
                L.append(f" {rng.choice(extra_r + tuple(BASE_R[:1]))} x{rng.choice(regs)},x{rng.choice(regs)},x{rng.choice(regs)}"
                         if extra_r and rng.random() < 0.5 else
                         f" addi x{rng.choice(regs)},x{rng.choice(regs)},{rng.randint(-50, 50)}")
            L.append(f"R{lab}:")
    return ".text\n" + "\n".join(L) + END

def cycles_for(src, base=900, per_div=45):
    """RTL cycle budget: each divide/remainder stalls ~34 cycles."""
    return base + per_div * sum(src.count(f" {op} ") for op in DIV_OPS)
