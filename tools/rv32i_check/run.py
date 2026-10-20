#!/usr/bin/env python3
"""Non-graded verification harness: assemble a test, run RTL (iverilog) and a
reference ISS (RefISS), then compare x1..x31, data memory, the engine command
log and the whole RVVI retire trace.

RefISS models RV32IM + Zicsr + Zifencei + Zbb + custom-0 (stub mode) with the
memory map of spec 4.1: ITCM 16 KB at 0 (instruction fetch only), DTCM 64 KB at
0x0001_0000, SIM_CTRL 0x0002_0000, SIM_PUTC 0x0002_0004; any other data address
reads 0 and ignores writes (decision W2-1 is still open). The RTL under test is
rtl/top/core_tb_top.sv (core + ITCM + DTCM + SIM MMIO + engine stub).

Test sources use the assembler symbol DM (0x0001_0000) as the data base.

RVVI record (one per retired instruction), the same fields as spec 5 and the
Phase 2 plan: order pc insn rd rd_wdata mem_addr mem_wdata mem_wmask trap
  rd/rd_wdata : destination index and value written, 0/0 when nothing (or x0) is written
  mem_addr    : effective address of a load or store, else 0
  mem_wdata   : the byte-lane-aligned word driven on the write bus (sb: byte replicated,
                sh: half replicated, sw: the word); 0 for loads and non-memory instructions
  mem_wmask   : the byte enables of the write; 0 for loads and non-memory instructions
  trap        : 0 until decision W2-1 defines traps"""
import subprocess, sys, os, struct, random, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.normpath(os.path.join(HERE, "..", "..", "rtl", "core"))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
os.chdir(HERE)                      # the memories read their hex file from cwd

DM_BASE = 0x10000                   # DTCM base: the assembler symbol DM in test sources
CMP_WORDS = 1024                    # data words (from DM) compared RTL vs ISS
MARCH = "rv32im_zicsr_zifencei_zbb"

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
SIM_CTRL = 0x20000
SIM_PUTC = 0x20004

def build_sim():
    """Compile the DUT with iverilog: the core, core_tb_top (ITCM, DTCM stand-in, SIM MMIO,
    engine stub) and tb_dump.v. RVVI_TRACE enables the retire-trace ports."""
    os.makedirs("build", exist_ok=True)
    srcs = glob.glob(os.path.join(CORE, "**", "*.v"), recursive=True)
    srcs += [os.path.join(ROOT, "rtl", "top", f) for f in ("core_tb_top.sv", "core_tb_dtcm.sv", "npu_stub.sv")]
    srcs += [os.path.join(ROOT, "rtl", "mem", "itcm.sv")]
    cmd = ["iverilog", "-g2012", "-DRVVI_TRACE", f"-DMEM_WORDS={CMP_WORDS}", "-o", "build/sim.vvp", "tb_dump.v"] + srcs
    subprocess.run(cmd, check=True)

_built = False

def sx(v, b):
    v &= (1 << b) - 1
    return v - (1 << b) if v >> (b - 1) else v

def assemble(src, tag, march=MARCH):
    pre = f".equ DM, {DM_BASE:#x}\n"
    with open(f"build/{tag}.S", "w") as f: f.write(pre + src)
    subprocess.run([AS, f"-march={march}", "-mabi=ilp32", "-o", f"build/{tag}.o", f"build/{tag}.S"], check=True)
    subprocess.run([OC, "-O", "binary", "-j", ".text", f"build/{tag}.o", f"build/{tag}.bin"], check=True)
    data = open(f"build/{tag}.bin", "rb").read()
    return [struct.unpack("<I", data[i:i+4])[0] for i in range(0, len(data), 4)]

# ---------------------------------------------------------------- arithmetic
def muldiv(f3, a, b):
    """RV32M. a, b are unsigned 32-bit values; returns the unsigned result."""
    sa, sb = sx(a, 32), sx(b, 32)
    if f3 == 0: return (a * b) & M32                       # mul
    if f3 == 1: return ((sa * sb) >> 32) & M32             # mulh
    if f3 == 2: return ((sa * b) >> 32) & M32              # mulhsu
    if f3 == 3: return ((a * b) >> 32) & M32               # mulhu
    if f3 == 4:                                            # div
        if b == 0: return M32
        if sa == -(1 << 31) and sb == -1: return 0x80000000
        q = abs(sa) // abs(sb)
        return (-q if (sa < 0) != (sb < 0) else q) & M32
    if f3 == 5: return M32 if b == 0 else a // b           # divu
    if f3 == 6:                                            # rem
        if b == 0: return a
        if sa == -(1 << 31) and sb == -1: return 0
        r = abs(sa) % abs(sb)
        return (-r if sa < 0 else r) & M32
    return a if b == 0 else a % b                          # remu

def rol32(a, s):
    s &= 31
    return ((a << s) | (a >> (32 - s))) & M32 if s else a

def clz32(a): return 32 - a.bit_length()
def ctz32(a): return 32 if a == 0 else (a & -a).bit_length() - 1

def zbb_unary(sel, a):
    """clz/ctz/cpop/sext.b/sext.h selected by the rs2 field of OP-IMM funct3=001."""
    if sel == 0: return clz32(a)
    if sel == 1: return ctz32(a)
    if sel == 2: return bin(a).count("1")
    if sel == 4: return sx(a, 8) & M32
    if sel == 5: return sx(a, 16) & M32
    return None

def zbb_r(f3, f7, a, b, rs2):
    """Zbb R-type; returns None when (f3, f7) is not a Zbb encoding."""
    sa, sb = sx(a, 32), sx(b, 32)
    k = (f3, f7)
    if k == (7, 0x20): return a & ~b & M32                              # andn
    if k == (6, 0x20): return (a | ~b) & M32                            # orn
    if k == (4, 0x20): return ~(a ^ b) & M32                            # xnor
    if k == (6, 0x05): return (sa if sa > sb else sb) & M32             # max
    if k == (7, 0x05): return max(a, b)                                 # maxu
    if k == (4, 0x05): return (sa if sa < sb else sb) & M32             # min
    if k == (5, 0x05): return min(a, b)                                 # minu
    if k == (1, 0x30): return rol32(a, b)                               # rol
    if k == (5, 0x30): return rol32(a, 32 - (b & 31))                   # ror
    if k == (4, 0x04) and rs2 == 0: return a & 0xFFFF                   # zext.h
    return None

# --------------------------------------------------------------------- RefISS
class RefISS:
    """Cycle-free reference model. mcycle is modelled as the instruction count
    (ideal 1 CPI), so tests must only use derived booleans of cycle reads.
    minstret is exact: the number of instructions executed before the reader."""
    def __init__(self, prog):
        self.x = [0]*32; self.pc = 0; self.prog = prog
        self.imem_words = 4096       # ITCM 16 KB
        self.mem = [0] * 16384       # DTCM 64 KB
        self.cycle = 0; self.instret = 0
        self.trace = []              # RVVI records, one per executed instruction
        self.cmd_log = []            # (op, addr, k, clr) of every custom-0 push
        self.sim_ctrl = []           # values written to SIM_CTRL (spec map)
        self.putc = []               # characters written to SIM_PUTC (spec map)
        self.npu_err = 0xF           # NPU CSR stub: sticky error bits start set
        self.npu_busy_cyc = 0
        self.unsupported = set()
    # -- data memory
    def _widx(self, a):
        if 0x10000 <= a < 0x20000:
            return (a - 0x10000) >> 2
        return None                  # unmapped (also ITCM as data): loads read 0, stores are ignored (W2-1 open)
    def ld(self, a, n, signed):
        i = self._widx(a)
        if i is None: return 0
        w = self.mem[i]
        if n == 1: v = (w >> (8*(a & 3))) & 0xFF
        elif n == 2: v = (w >> (16*((a >> 1) & 1))) & 0xFFFF
        else: v = w
        return sx(v, 8*n) & M32 if signed and n < 4 else v
    def st(self, a, n, v):
        if a == SIM_CTRL and n == 4: self.sim_ctrl.append(v & M32); return 1    # word writes only
        if a == SIM_PUTC: self.putc.append(v & 0xFF); return 0
        i = self._widx(a)
        if i is None: return 0
        if n == 4: self.mem[i] = v & M32; return 0
        sh = 8*(a & 3) if n == 1 else 16*((a >> 1) & 1)
        mask = ((1 << (8*n)) - 1) << sh
        self.mem[i] = (self.mem[i] & ~mask & M32) | ((v << sh) & mask)
        return 0
    # -- CSRs
    def csr_read(self, c):
        if c in (0xB00, 0xC00): return self.cycle & M32
        if c in (0xB80, 0xC80): return (self.cycle >> 32) & M32
        if c in (0xB02, 0xC02): return self.instret & M32
        if c in (0xB82, 0xC82): return (self.instret >> 32) & M32
        if c == 0x7C0: return (self.npu_err << 8) | 0x2    # stub: fifo_empty=1
        if c == 0x7C1: return self.npu_busy_cyc
        return 0                                           # unknown CSR (W2-1 open)
    def csr_write(self, c, v):
        if c == 0x7C0: self.npu_err &= ~((v >> 8) & 0xF)   # W1C, bits 8..11
        elif c == 0x7C1: self.npu_busy_cyc = v & M32
        # counters and aliases are read-only for software; unknown CSRs ignore writes
    # -- one instruction
    def fetch(self):
        idx = self.pc >> 2
        if idx >= self.imem_words: return 0x13       # outside the ITCM: NOP (W2-1 open)
        return self.prog[idx] if idx < len(self.prog) else 0x13
    def step(self):
        """Execute one instruction; returns 1 when it wrote SIM_CTRL, else 0."""
        ins = self.fetch()
        op = ins & 0x7F; rd = (ins >> 7) & 31; f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 31; rs2 = (ins >> 20) & 31; f7 = ins >> 25
        a = self.x[rs1]; b = self.x[rs2]
        iimm = sx(ins >> 20, 12); simm = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
        bimm = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 63) << 5) | (((ins >> 8) & 15) << 1), 13)
        jimm = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 255) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 1023) << 1), 21)
        npc = (self.pc + 4) & M32; w = None; sim_end = 0
        mem_addr = mem_wdata = mem_wmask = 0
        if op == 0x33:
            if f7 == 1:
                w = muldiv(f3, a, b)
            else:
                k = (f3, f7)
                tbl = {(0,0):a+b,(0,32):a-b,(1,0):a<<(b&31),(2,0):int(sx(a,32)<sx(b,32)),(3,0):int(a<b),
                       (4,0):a^b,(5,0):a>>(b&31),(5,32):(sx(a,32)>>(b&31)),(6,0):a|b,(7,0):a&b}
                w = tbl.get(k)
                if w is None: w = zbb_r(f3, f7, a, b, rs2)
        elif op == 0x13:
            sh = (ins >> 20) & 31; imm12 = (ins >> 20) & 0xFFF
            if f3 == 0: w = a + iimm
            elif f3 == 2: w = int(sx(a,32) < iimm)
            elif f3 == 3: w = int(a < (iimm & M32))
            elif f3 == 4: w = a ^ (iimm & M32)
            elif f3 == 6: w = a | (iimm & M32)
            elif f3 == 7: w = a & (iimm & M32)
            elif f3 == 1 and f7 == 0: w = a << sh
            elif f3 == 1 and f7 == 0x30: w = zbb_unary(sh, a)
            elif f3 == 5 and f7 == 0: w = a >> sh
            elif f3 == 5 and f7 == 32: w = sx(a,32) >> sh
            elif f3 == 5 and f7 == 0x30: w = rol32(a, 32 - sh)       # rori
            elif f3 == 5 and imm12 == 0x287: w = sum(0xFF << (8*i) for i in range(4) if (a >> (8*i)) & 0xFF)  # orc.b
            elif f3 == 5 and imm12 == 0x698: w = int.from_bytes(a.to_bytes(4, "little"), "big")             # rev8
        elif op == 0x37: w = ins & 0xFFFFF000
        elif op == 0x17: w = self.pc + (ins & 0xFFFFF000)
        elif op == 0x03:
            ad = (a + iimm) & M32
            m = {0:(1,1),1:(2,1),2:(4,0),4:(1,0),5:(2,0)}
            if f3 in m: w = self.ld(ad, *m[f3]); mem_addr = ad
        elif op == 0x23:
            ad = (a + simm) & M32
            if f3 in (0,1,2):
                sim_end = self.st(ad, [1,2,4][f3], b)
                mem_addr = ad
                if f3 == 0:   mem_wdata = (b & 0xFF) * 0x01010101;   mem_wmask = 1 << (ad & 3)
                elif f3 == 1: mem_wdata = (b & 0xFFFF) * 0x00010001; mem_wmask = 0b1100 if ad & 2 else 0b0011
                else:         mem_wdata = b;                         mem_wmask = 0xF
        elif op == 0x63:
            c = {0:a==b,1:a!=b,4:sx(a,32)<sx(b,32),5:sx(a,32)>=sx(b,32),6:a<b,7:a>=b}.get(f3)
            if c: npc = (self.pc + bimm) & M32
        elif op == 0x6F: w = self.pc + 4; npc = (self.pc + jimm) & M32
        elif op == 0x67 and f3 == 0: w = self.pc + 4; npc = (a + iimm) & M32 & ~1
        elif op == 0x73 and f3 in (1, 2, 3, 5, 6, 7):                # Zicsr
            csr = (ins >> 20) & 0xFFF
            old = self.csr_read(csr)
            opnd = rs1 if f3 & 4 else a                               # zimm or rs1 value
            if f3 & 3 == 1:   new = opnd; wr = True                   # csrrw / csrrwi
            elif f3 & 3 == 2: new = old | opnd; wr = rs1 != 0        # csrrs / csrrsi
            else:             new = old & ~opnd; wr = rs1 != 0       # csrrc / csrrci
            if wr: self.csr_write(csr, new & M32)
            w = old
        elif op == 0x0B:                                              # custom-0, stub mode
            if f3 == 0:   self.cmd_log.append((0, a, b, 0))
            elif f3 == 1: self.cmd_log.append((1, a, b, 0))
            elif f3 == 2: self.cmd_log.append((2, 0, a, f7 & 1))
            elif f3 == 3: w = a & 0xF                                 # READ_RESULT returns idx
            else:         self.cmd_log.append((3, a, b, 0))           # reserved funct3 -> ILLEGAL
        # op 0x0F (fence, fence.i), ecall/ebreak and unknown encodings execute as NOP
        rec_rd = rec_val = 0
        if w is not None and rd: self.x[rd] = w & M32; rec_rd = rd; rec_val = w & M32
        self.trace.append((self.instret, self.pc, ins, rec_rd, rec_val, mem_addr, mem_wdata, mem_wmask, 0))
        self.pc = npc
        self.cycle += 1; self.instret += 1
        return sim_end

# Backwards-compatible name for older notes.
ISS = RefISS

def run_iss(prog, steps):
    s = RefISS(prog)
    for _ in range(steps):
        s.step()
    return s

def run_rtl(prog, cycles, plusargs=(), tag="rtl"):
    global _built
    if not _built:
        build_sim(); _built = True
    with open("program.hex", "w") as f:
        for wd in prog: f.write(f"{wd:08x}\n")
    if os.path.exists("rtl_state.txt"): os.remove("rtl_state.txt")     # never read a stale dump
    cp = subprocess.run(["vvp", "-n", "build/sim.vvp", f"+CYCLES={cycles}", "+ITCM=program.hex",
                         f"+RVVI_LOG=build/{tag}.rvvi"] + list(plusargs),
                        check=True, capture_output=True, text=True)
    st = {}
    for line in open("rtl_state.txt"):
        k, v = line.split(); st[k] = int(v, 16)
    st["_stdout"] = cp.stdout
    st["_push"] = [tuple(int(t, 16) for t in l.split()[1:5])
                   for l in cp.stdout.splitlines() if l.startswith("PUSH ")]
    st["_errors"] = [l for l in cp.stdout.splitlines() if l.startswith("STUB_ERROR")]
    st["_rvvi"] = read_rvvi(f"build/{tag}.rvvi")
    return st

def read_rvvi(path):
    """RVVI log written by core_tb_top: one line per retire, hex fields in record order."""
    if not os.path.exists(path): return []
    return [tuple(int(t, 16) for t in line.split()) for line in open(path) if line.strip()]

def rvvi_diffs(rtl_trace, ref_trace, cycle_dependent=False):
    """Compare the retire traces over the instructions both sides executed. The RTL must not
    retire fewer instructions than the program needs (the state compare covers that).
    cycle_dependent=True is for the rare test that does arithmetic on raw cycle counts: from the
    first cycle-counter read on, rd_wdata is not compared (all other fields still are)."""
    n = min(len(rtl_trace), len(ref_trace))
    names = ("order", "pc", "insn", "rd", "rd_wdata", "mem_addr", "mem_wdata", "mem_wmask", "trap")
    tainted = False
    for i in range(n):
        a, b = list(rtl_trace[i]), list(ref_trace[i])
        if reads_cycle_counter(b[2]):       # mcycle/cycle are cycle-accurate in the RTL, ideal in RefISS:
            tainted = tainted or cycle_dependent
            a[4] = b[4] = 0                 # their value is masked, every other field is still compared
        if tainted:
            a[4] = b[4] = 0
        if a != b:
            f = [f"{nm}: rtl={x:#x} ref={y:#x}" for nm, x, y in zip(names, a, b) if x != y]
            return [f"rvvi[{i}] pc={ref_trace[i][1]:#x}: " + ", ".join(f)]
    return []

def reads_cycle_counter(insn):
    """True for a Zicsr instruction addressing mcycle/mcycleh/cycle/cycleh."""
    return (insn & 0x7F) == 0x73 and ((insn >> 12) & 7) not in (0, 4) and (insn >> 20) in (0xB00, 0xB80, 0xC00, 0xC80)

def compare(src, tag, steps=600, cycles=1500, quiet=False, march=MARCH, plusargs=(), cycle_dependent=False):
    """Program must end in 'end: j end'. ISS steps / RTL cycles just need to
    be large enough to reach it. Returns the list of differences (empty = pass)."""
    prog = assemble(src, tag, march)
    ref = run_iss(prog, steps)
    rtl = run_rtl(prog, cycles, plusargs, tag)
    diffs = []
    for r in range(1, 32):
        if rtl[f"x{r}"] != ref.x[r]:
            diffs.append(f"x{r}: rtl={rtl[f'x{r}']:08x} ref={ref.x[r]:08x}")
    for m in range(CMP_WORDS):
        if rtl[f"m{m}"] != ref.mem[m]:
            diffs.append(f"mem[{m*4:#05x}]: rtl={rtl[f'm{m}']:08x} ref={ref.mem[m]:08x}")
    if rtl["_push"] != ref.cmd_log:
        diffs.append(f"cmd_log: rtl={rtl['_push']} ref={ref.cmd_log}")
    diffs += rtl["_errors"]                      # engine-stub protocol violations
    diffs += rvvi_diffs(rtl["_rvvi"], ref.trace, cycle_dependent)  # every retired instruction, in order
    with open(f"build/{tag}.ref.txt", "w") as f:      # consumed by model/c rv_iss tests
        for r in range(1, 32): f.write(f"x{r} {ref.x[r]:08x}\n")
        f.write(f"steps {steps}\nmemmap spec\n")
    with open(f"build/{tag}.ref_trace.txt", "w") as f:  # RefISS RVVI records, same hex format as the RTL log
        for t in ref.trace: f.write("%016x %08x %08x %02x %08x %08x %08x %x %x\n" % t)
    if not quiet:
        print(f"[{'PASS' if not diffs else 'FAIL'}] {tag}")
        for d in diffs[:8]: print("       ", d)
    return diffs

def check_rtl(src, tag, expect, cycles=1500, quiet=False, march=MARCH, plusargs=(), stdout_has=()):
    """RTL-only check for timing properties RefISS cannot model (it is cycle-free).
    `expect` maps register numbers to the values they must hold at the end;
    `stdout_has` lists lines (prefix match) the simulation must have printed.
    Returns the list of differences (empty = pass)."""
    prog = assemble(src, tag, march)
    rtl = run_rtl(prog, cycles, plusargs, tag)
    diffs = [f"x{r}: rtl={rtl[f'x{r}']:08x} want={v:08x}" for r, v in expect.items() if rtl[f"x{r}"] != v]
    diffs += rtl["_errors"]
    for want in stdout_has:
        if not any(l.startswith(want) for l in rtl["_stdout"].splitlines()):
            diffs.append(f"stdout lacks line starting with {want!r}")
    if not quiet:
        print(f"[{'PASS' if not diffs else 'FAIL'}] {tag}")
        for d in diffs[:8]: print("       ", d)
    return diffs

if __name__ == "__main__":
    os.makedirs("build", exist_ok=True)
