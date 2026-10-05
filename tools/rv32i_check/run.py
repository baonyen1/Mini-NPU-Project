#!/usr/bin/env python3
"""Non-graded verification harness: assemble a test, run RTL (iverilog) and a
reference RV32I ISS, then compare x1..x31 and data memory.

Memory model mirrors the DUT: Harvard, 256-word IMEM, 256-word DMEM addressed
by addr[9:0] (aliased)."""
import subprocess, sys, os, struct, random, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.normpath(os.path.join(HERE, "..", "..", "rtl", "core"))
os.chdir(HERE)                      # ProgramMemory reads program.hex from cwd

def _find_prefix():
    if os.environ.get("RV_PREFIX"):
        return os.environ["RV_PREFIX"]
    for p in ("riscv64-unknown-elf-", "riscv-none-elf-", "riscv32-unknown-elf-"):
        if shutil.which(p + "as"):
            return p
    sys.exit("No RISC-V binutils found. Install one (e.g. xPack riscv-none-elf-gcc) "
             "or set RV_PREFIX, e.g. RV_PREFIX=riscv-none-elf-")
PFX = _find_prefix()
AS = PFX + "as"; OC = PFX + "objcopy"
M32 = 0xFFFFFFFF

def build_sim():
    """Compile rtl/core with iverilog."""
    srcs = glob.glob(os.path.join(CORE, "**", "*.v"), recursive=True)
    os.makedirs("build", exist_ok=True)
    subprocess.run(["iverilog", "-g2012", "-o", "build/sim.vvp", "tb_dump.v"] + srcs, check=True)

_built = False

def sx(v, b):
    v &= (1 << b) - 1
    return v - (1 << b) if v >> (b - 1) else v

def assemble(src, tag):
    with open(f"build/{tag}.S", "w") as f: f.write(src)
    subprocess.run([AS, "-march=rv32i", "-mabi=ilp32", "-o", f"build/{tag}.o", f"build/{tag}.S"], check=True)
    subprocess.run([OC, "-O", "binary", "-j", ".text", f"build/{tag}.o", f"build/{tag}.bin"], check=True)
    data = open(f"build/{tag}.bin", "rb").read()
    return [struct.unpack("<I", data[i:i+4])[0] for i in range(0, len(data), 4)]

class ISS:
    def __init__(self, prog):
        self.x = [0]*32; self.pc = 0; self.prog = prog; self.mem = [0]*256
        self.unsupported = set()
    def ld(self, a, n, signed):
        a &= 0x3FF; w = self.mem[a >> 2]
        if n == 1: v = (w >> (8*(a & 3))) & 0xFF
        elif n == 2: v = (w >> (16*((a >> 1) & 1))) & 0xFFFF
        else: v = w
        return sx(v, 8*n) & M32 if signed and n < 4 else v
    def st(self, a, n, v):
        a &= 0x3FF; i = a >> 2
        if n == 4: self.mem[i] = v & M32; return
        sh = 8*(a & 3) if n == 1 else 16*((a >> 1) & 1)
        mask = ((1 << (8*n)) - 1) << sh
        self.mem[i] = (self.mem[i] & ~mask & M32) | ((v << sh) & mask)
    def step(self):
        idx = (self.pc >> 2) & 0xFF
        ins = self.prog[idx] if idx < len(self.prog) else 0x13
        op = ins & 0x7F; rd = (ins >> 7) & 31; f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 31; rs2 = (ins >> 20) & 31; f7 = ins >> 25
        a = self.x[rs1]; b = self.x[rs2]
        iimm = sx(ins >> 20, 12); simm = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
        bimm = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 63) << 5) | (((ins >> 8) & 15) << 1), 13)
        jimm = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 255) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 1023) << 1), 21)
        npc = (self.pc + 4) & M32; w = None
        if op == 0x33:
            k = (f3, f7)
            tbl = {(0,0):a+b,(0,32):a-b,(1,0):a<<(b&31),(2,0):int(sx(a,32)<sx(b,32)),(3,0):int(a<b),
                   (4,0):a^b,(5,0):a>>(b&31),(5,32):(sx(a,32)>>(b&31)),(6,0):a|b,(7,0):a&b}
            w = tbl.get(k)
        elif op == 0x13:
            sh = (ins >> 20) & 31
            if f3 == 0: w = a + iimm
            elif f3 == 2: w = int(sx(a,32) < iimm)
            elif f3 == 3: w = int(a < (iimm & M32))
            elif f3 == 4: w = a ^ (iimm & M32)
            elif f3 == 6: w = a | (iimm & M32)
            elif f3 == 7: w = a & (iimm & M32)
            elif f3 == 1 and f7 == 0: w = a << sh
            elif f3 == 5 and f7 == 0: w = a >> sh
            elif f3 == 5 and f7 == 32: w = sx(a,32) >> sh
        elif op == 0x37: w = ins & 0xFFFFF000
        elif op == 0x17: w = self.pc + (ins & 0xFFFFF000)
        elif op == 0x03:
            ad = (a + iimm) & M32
            m = {0:(1,1),1:(2,1),2:(4,0),4:(1,0),5:(2,0)}
            if f3 in m: w = self.ld(ad, *m[f3])
        elif op == 0x23:
            ad = (a + simm) & M32
            if f3 in (0,1,2): self.st(ad, [1,2,4][f3], b)
        elif op == 0x63:
            c = {0:a==b,1:a!=b,4:sx(a,32)<sx(b,32),5:sx(a,32)>=sx(b,32),6:a<b,7:a>=b}.get(f3)
            if c: npc = (self.pc + bimm) & M32
        elif op == 0x6F: w = self.pc + 4; npc = (self.pc + jimm) & M32
        elif op == 0x67: w = self.pc + 4; npc = (a + iimm) & M32 & ~1
        if w is not None and rd: self.x[rd] = w & M32
        self.pc = npc

def run_iss(prog, steps):
    s = ISS(prog)
    for _ in range(steps):
        s.step()
    return s

def run_rtl(prog, cycles):
    global _built
    if not _built:
        build_sim(); _built = True
    with open("program.hex", "w") as f:
        for wd in prog: f.write(f"{wd:08x}\n")
    subprocess.run(["vvp", "-n", "build/sim.vvp", f"+CYCLES={cycles}"], check=True, capture_output=True)
    st = {}
    for line in open("rtl_state.txt"):
        k, v = line.split(); st[k] = int(v, 16)
    return st

def compare(src, tag, steps=600, cycles=1500, quiet=False):
    """Program must end in 'end: j end'. ISS steps / RTL cycles just need to
    be large enough to reach it."""
    prog = assemble(src, tag)
    ref = run_iss(prog, steps)
    rtl = run_rtl(prog, cycles)
    diffs = []
    for r in range(1, 32):
        if rtl[f"x{r}"] != ref.x[r]:
            diffs.append(f"x{r}: rtl={rtl[f'x{r}']:08x} ref={ref.x[r]:08x}")
    for m in range(256):
        if rtl[f"m{m}"] != ref.mem[m]:
            diffs.append(f"mem[{m*4:#05x}]: rtl={rtl[f'm{m}']:08x} ref={ref.mem[m]:08x}")
    if not quiet:
        print(f"[{'PASS' if not diffs else 'FAIL'}] {tag}")
        for d in diffs[:8]: print("       ", d)
    return diffs

if __name__ == "__main__":
    os.makedirs("build", exist_ok=True)
