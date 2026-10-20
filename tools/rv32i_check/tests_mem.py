"""Memory map, SIM MMIO and RVVI trace tests (plan Task 8).

Not run here: dtcm_port_b_quad. It belongs to Track B's dtcm_dp (port B is the engine's
interface); core_tb_top uses a port-A-only stand-in until dtcm_dp exists.
Every compare() in the other suites also checks the whole RVVI trace against RefISS."""
from run import compare, check_rtl, assemble, run_rtl, run_iss, DM_BASE
import os, json
os.makedirs("build", exist_ok=True)
E = "\nend: j end\n"
SIM_CTRL, SIM_PUTC = 0x20000, 0x20004
results = {}

def record(name, diffs):
    results[name] = not diffs
    return diffs

# ---- data memory: first and last DTCM word, byte lanes at the top, unmapped accesses -----------
T = {
 "dtcm_last_word": " li x5,DM+0xFFFC\n li x6,0xA5A5A5A5\n sw x6,0(x5)\n lw x7,0(x5)\n li x8,DM+0xFFF8\n li x9,0x5A5A5A5A\n sw x9,0(x8)\n lw x10,0(x8)\n lw x11,0(x5)\n",
 "dtcm_first_word": " li x5,DM\n li x6,0x0F1E2D3C\n sw x6,0(x5)\n lw x7,0(x5)\n lbu x8,3(x5)\n lh x9,2(x5)\n",
 "dtcm_byte_lanes_at_top": " li x5,DM+0xFFFC\n sb x0,0(x5)\n li x6,0x81\n sb x6,3(x5)\n sh x6,0(x5)\n lw x7,0(x5)\n lb x8,3(x5)\n lbu x9,3(x5)\n lh x10,0(x5)\n",
 # outside the data map: loads read 0 and stores are ignored (W2-1 is still open); ITCM is not data
 "unmapped_data_access": " li x6,0xDEADBEEF\n lui x5,0x30\n sw x6,0(x5)\n lw x7,0(x5)\n sw x6,0(x0)\n lw x8,0(x0)\n lui x9,0x20\n lw x10,0(x9)\n lw x11,4(x9)\n sb x6,0(x5)\n lbu x12,0(x5)\n",
 # one word per address bit, then read all back: an address bit that is dropped or aliased shows as a wrong value
 "dtcm_no_aliasing": ' li x5,DM+0x4\n li x6,0x33333333\n sw x6,0(x5)\n li x5,DM+0x8\n li x6,0x44444444\n sw x6,0(x5)\n li x5,DM+0x10\n li x6,0x55555555\n sw x6,0(x5)\n li x5,DM+0x20\n li x6,0x66666666\n sw x6,0(x5)\n li x5,DM+0x40\n li x6,0x77777777\n sw x6,0(x5)\n li x5,DM+0x80\n li x6,0x88888888\n sw x6,0(x5)\n li x5,DM+0x100\n li x6,0x99999999\n sw x6,0(x5)\n li x5,DM+0x200\n li x6,0xaaaaaaaa\n sw x6,0(x5)\n li x5,DM+0x400\n li x6,0xbbbbbbbb\n sw x6,0(x5)\n li x5,DM+0x800\n li x6,0xcccccccc\n sw x6,0(x5)\n li x5,DM+0x1000\n li x6,0xdddddddd\n sw x6,0(x5)\n li x5,DM+0x2000\n li x6,0xeeeeeeee\n sw x6,0(x5)\n li x5,DM+0x4000\n li x6,0xffffffff\n sw x6,0(x5)\n li x5,DM+0x8000\n li x6,0x11111111\n sw x6,0(x5)\n li x5,DM\n li x6,0x0F0F0F0F\n sw x6,0(x5)\n' + ' li x5,DM+0x4\n lw x8,0(x5)\n li x5,DM+0x8\n lw x9,0(x5)\n li x5,DM+0x10\n lw x10,0(x5)\n li x5,DM+0x20\n lw x11,0(x5)\n li x5,DM+0x40\n lw x12,0(x5)\n li x5,DM+0x80\n lw x13,0(x5)\n li x5,DM+0x100\n lw x14,0(x5)\n li x5,DM+0x200\n lw x15,0(x5)\n li x5,DM+0x400\n lw x16,0(x5)\n li x5,DM+0x800\n lw x17,0(x5)\n li x5,DM+0x1000\n lw x18,0(x5)\n li x5,DM+0x2000\n lw x19,0(x5)\n li x5,DM+0x4000\n lw x20,0(x5)\n li x5,DM+0x8000\n lw x21,0(x5)\n li x5,DM\n lw x7,0(x5)\n',
 # a DTCM read leaves data on the memory output; an unmapped load must still read 0, not that data
 "unmapped_load_after_dtcm_read": " li x5,DM+0x20\n li x6,0xCAFEF00D\n sw x6,0(x5)\n lw x7,0(x5)\n lui x9,0x30\n lw x10,0(x9)\n lh x11,2(x9)\n lbu x12,1(x9)\n lw x13,0(x0)\n lui x14,0x20\n lw x15,0(x14)\n",
 "dtcm_store_then_load_back_to_back": " li x5,DM+0x100\n li x6,11\n sw x6,0(x5)\n lw x7,0(x5)\n addi x6,x6,1\n sw x6,0(x5)\n lw x8,0(x5)\n add x9,x7,x8\n",
}
fails = []
for k, v in T.items():
    if record(k, compare(".text\n" + v + E, k, steps=400, cycles=1500)): fails.append(k)
# the last-word results must also be right in absolute terms, not only equal to the model
# absolute check: every address bit must select a distinct word
want = {7: 0x0F0F0F0F}
want.update({8 + k - 2: (0x11111111 * (1 + k % 15)) & 0xFFFFFFFF for k in range(2, 16)})
if record("dtcm_no_aliasing_absolute", check_rtl(".text\n" + T["dtcm_no_aliasing"] + E, "dtcm_no_alias_abs", want, cycles=1500)):
    fails.append("dtcm_no_aliasing_absolute")
if record("unmapped_load_after_dtcm_read_absolute", check_rtl(".text\n" + T["unmapped_load_after_dtcm_read"] + E, "unmapped_abs",
                                                               {7: 0xCAFEF00D, 10: 0, 11: 0, 12: 0, 13: 0, 15: 0}, cycles=900)):
    fails.append("unmapped_load_after_dtcm_read_absolute")
if record("dtcm_last_word_absolute", check_rtl(".text\n" + T["dtcm_last_word"] + E, "dtcm_last_word_abs",
                                               {7: 0xA5A5A5A5, 10: 0x5A5A5A5A, 11: 0xA5A5A5A5}, cycles=900)):
    fails.append("dtcm_last_word_absolute")
print(f"\nMEMORY MAP: {sum(results.values())}/{len(results)} pass; FAIL={fails}")

# ---- SIM MMIO -------------------------------------------------------------------------------
def sim_write(addr, value, width="w"):
    return f" li x30,{addr:#x}\n li x29,{value:#x}\n s{width} x29,0(x30)\n"
def putc(ch): return sim_write(SIM_PUTC, ord(ch), "b")
mmio = []
# a write of 0x1 ends the simulation with PASS: the instruction after the store never completes
mmio.append(("sim_ctrl_pass", sim_write(SIM_CTRL, 0x1) + " addi x10,x0,1\n addi x11,x0,2\n", {10: 0, 11: 0}, ("PASS",)))
mmio.append(("sim_ctrl_fail", sim_write(SIM_CTRL, 0x2) + " addi x10,x0,1\n", {10: 0}, ("FAIL",)))
mmio.append(("sim_putc", putc("O") + putc("K") + putc("\n") + " addi x10,x0,7\n", {10: 7}, ("OK",)))
mmio.append(("sim_markers", sim_write(SIM_CTRL, 0x20) + sim_write(SIM_CTRL, 0x21) + sim_write(SIM_CTRL, 0x10) + " addi x10,x0,3\n",
             {10: 3}, ("MEAS_START", "MEAS_STOP", "BATCH_DONE")))
# stores that are not SIM MMIO writes must not be taken for one
mmio.append(("sim_ctrl_neighbours_do_not_end", " li x5,DM+0xFFFC\n li x6,1\n sw x6,0(x5)\n li x7,0x20008\n sw x6,0(x7)\n addi x10,x0,9\n", {10: 9}, ()))
for name, body, expect, has in mmio:
    d = check_rtl(".text\n" + body + E, name, expect, cycles=600, stdout_has=has)
    if name in ("sim_ctrl_pass", "sim_ctrl_fail", "sim_markers"):
        pass
    if name == "sim_ctrl_neighbours_do_not_end":
        out = run_rtl(assemble(".text\n" + body + E, name + "_o"), 600, (), name + "_o")["_stdout"]
        if "PASS" in out or "FAIL" in out: d.append("a neighbouring store ended the simulation")
    if record(name, d): fails.append(name)

# ---- RVVI order: one retire per instruction, no gaps after stalls and flushes ---------------
def order_problems(trace):
    """The retire order must be 0, 1, 2, ... with no gap and no repeat."""
    return [f"record {i} has order {rec[0]}, expected {i}" for i, rec in enumerate(trace) if rec[0] != i][:3]

# the checker must not be able to pass vacuously: fabricated traces with a gap, a repeat and an empty log
bad = {"gap": [(0,), (1,), (3,)], "repeat": [(0,), (1,), (1,)], "starts_at_1": [(1,), (2,)]}
selftest = all(order_problems(t) for t in bad.values()) and not order_problems([(0,), (1,), (2,)])
results["rvvi_order_selftest"] = selftest
if not selftest: fails.append("rvvi_order_selftest")
print(f"[{'PASS' if selftest else 'FAIL'}] rvvi_order_selftest (the order checker flags a gap, a repeat and a wrong start)")

# ---- harness self-tests: compare() must not pass an RTL that never finishes the program -----------
# (found by the independent review: only min(len(rtl), len(ref)) records were compared, so a deadlock
# on a trailing READ_RESULT x0 passed). Each case is a program the RTL cannot finish, or one it can.
DEAD_RR = " li x3,5\n li x4,7\n .insn r 0x0B,3,0,x0,x3,x0\n"          # READ_RESULT x0 with rd_ready never high
DEAD_CSR = " li x3,5\n li x5,0x55\n .insn r 0x0B,3,0,x0,x3,x0\n csrw 0x7c1,x5\n"
hs = {
 "harness_detects_deadlock_on_read_result": (DEAD_RR, ("+STUB_RDREADY=0",), True),
 "harness_detects_deadlock_before_csr_write": (DEAD_CSR, ("+STUB_RDREADY=0",), True),
 "harness_no_false_alarm_when_engine_ready": (DEAD_RR, (), False),
}
for name, (body, pa, must_fail) in hs.items():
    d = compare(".text\n" + body + E, name, steps=100, cycles=400, plusargs=pa, quiet=True)
    ok = (any("never reached the end" in x for x in d)) if must_fail else not d
    print(f"[{'PASS' if ok else 'FAIL'}] {name} ({'diffs=' + str(len(d))})")
    if record(name, [] if ok else ["harness verdict wrong: " + str(d[:2])]): fails.append(name)

SLOW = ("+STUB_READY=0000000000000001", "+STUB_RDREADY=0000000000000001")
LDW = ".insn r 0x0B,0,0,x0,x1,x2\n"
RR = ".insn r 0x0B,3,0,x20,x3,x0\n"
STRESS = {
 "flushes": (" li x5,DM+0x40\n li x6,9\n sw x6,0(x5)\n beq x0,x0,L\n lw x7,0(x5)\n add x8,x7,x7\nL: jal x9,M\n addi x10,x0,1\nM: fence.i\n addi x11,x0,2\n", ()),
 "divider": (" li x1,100\n li x2,7\n div x3,x1,x2\n rem x4,x1,x2\n mul x5,x3,x4\n beq x0,x0,L\n div x6,x1,x2\nL: addi x7,x5,1\n", ()),
 "engine_waits": (" li x1,DM+0x40\n li x2,16\n li x3,5\n " + LDW + " " + RR + " add x21,x20,x20\n beq x0,x0,L\n " + LDW + "L: " + RR, SLOW),
 "csr_in_stall": (" li x1,DM+0x40\n li x2,16\n li x3,5\n li x5,0xF\n " + RR + " csrrw x10,0x7c1,x5\n csrr x11,0xB02\n", SLOW),
}
for name, (body, pa) in STRESS.items():
    src = ".text\n" + body + E
    tag = "rvvi_" + name
    tr = run_rtl(assemble(src, tag), 4000, pa, tag)["_rvvi"]
    d = order_problems(tr)
    if len(tr) < 20: d.append("trace too short: the log was not written")
    if record("rvvi_order_monotonic_" + name, d): fails.append("rvvi_order_monotonic_" + name)
    print(f"[{'PASS' if not d else 'FAIL'}] rvvi_order_monotonic_{name} ({len(tr)} records)")
    for x in d: print("       ", x)

print(f"\nMEMORY / SIM MMIO / RVVI: {sum(results.values())}/{len(results)} pass; FAIL={fails}")
json.dump({f"mem_{k}": v for k, v in results.items()}, open("build/results_mem.json", "w"), indent=1)
