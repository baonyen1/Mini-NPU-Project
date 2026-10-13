from run import compare
import os; os.makedirs("build", exist_ok=True)
PRE = """
  .text
  li x1, 0x80000F0F
  li x2, 5
  li x3, -3
  li x4, 0x12345678
"""
END = "\nend: j end\n"
R = ["add","sub","sll","slt","sltu","xor","srl","sra","or","and"]
I = [("addi",-7),("slti",-1),("sltiu",-1),("xori",-1),("ori",0x0F0),("andi",0x7FF),
     ("slli",4),("srli",4),("srai",4)]
results = {}
for op in R:
    src = PRE + f"  {op} x10, x1, x2\n  {op} x11, x1, x3\n  {op} x12, x3, x1\n  {op} x13, x4, x2\n" + END
    results[op] = not compare(src, op)
for op, imm in I:
    src = PRE + f"  {op} x10, x1, {imm}\n  {op} x11, x3, {imm}\n  {op} x12, x4, {imm}\n" + END
    results[op] = not compare(src, op)
results["lui"] = not compare(PRE + "  lui x10, 0xABCDE\n" + END, "lui")
results["auipc"] = not compare(PRE + "  auipc x10, 0x1\n  auipc x11, 0\n" + END, "auipc")
LDST = PRE + "  li x5, 0x100\n  li x6, 0x8091A2B3\n  sw x6, 0(x5)\n  nop\n  nop\n"
for op in ["lb","lh","lw","lbu","lhu"]:
    offs = [0,1,2,3] if op in ("lb","lbu") else ([0,2] if op in ("lh","lhu") else [0])
    body = "".join(f"  {op} x{10+i}, {o}(x5)\n" for i,o in enumerate(offs))
    results[op] = not compare(LDST + body + END, op)
for op in ["sb","sh","sw"]:
    offs = [0,1,2,3] if op=="sb" else ([0,2] if op=="sh" else [0])
    body = "".join(f"  addi x6, x6, 0x11\n  {op} x6, {0x20+o}(x5)\n" for o in offs)
    results[op] = not compare(LDST + body + END, op)
# branches: taken and not-taken, signed/unsigned corner
for op in ["beq","bne","blt","bge","bltu","bgeu"]:
    body = ""
    pairs = [("x1","x2"),("x2","x1"),("x2","x2"),("x3","x2"),("x2","x3")]
    for n,(a,b) in enumerate(pairs):
        body += f"  {op} {a}, {b}, L{n}\n  addi x20, x20, {1<<n}\nL{n}:\n"
    results[op] = not compare(PRE + body + END, op)
results["jal"] = not compare(PRE + "  jal x10, T\n  addi x20,x20,1\nT: addi x21,x21,1\n  jal x0, T2\n  addi x20,x20,2\nT2:" + END, "jal")
results["jalr"] = not compare(PRE + "  auipc x5, 0\n  jalr x10, 16(x5)\n  addi x20,x20,1\n  addi x20,x20,2\n  addi x21,x21,1\n  addi x6, x5, 33\n  jalr x11, -1(x6)\n  addi x20,x20,4\n  addi x21,x21,2\n" + END, "jalr")
for op, txt in [("fence","fence"),("ecall","ecall"),("ebreak","ebreak")]:
    results[op] = not compare(PRE + f"  {txt}\n  addi x10, x0, 7\n" + END, op)
# Task 3 corner tests: signed vs unsigned behaviour on the same bit patterns
results["slt_vs_sltu_sign"] = not compare(
    "  li x1, 0x80000000\n  li x2, 1\n  slt x10, x1, x2\n  sltu x11, x1, x2\n"
    "  slt x12, x2, x1\n  sltu x13, x2, x1\n" + END, "slt_vs_sltu_sign")
results["sltiu_minus1"] = not compare(
    "  li x1, 0x12345678\n  li x2, -1\n  sltiu x10, x1, -1\n  sltiu x11, x2, -1\n"
    "  sltiu x12, x0, 1\n  slti x13, x2, 0\n" + END, "sltiu_minus1")
results["srai_negative"] = not compare(
    "  li x1, 0x80000F0F\n  srai x10, x1, 4\n  srai x11, x1, 31\n  srai x12, x1, 0\n"
    "  srli x13, x1, 31\n  li x2, 36\n  sra x14, x1, x2\n" + END, "srai_negative")
results["bltu_bgeu_sign"] = not compare(
    "  li x1, 0x80000000\n  li x2, 1\n"
    "  bltu x1, x2, A\n  addi x20, x20, 1\nA:\n"
    "  bgeu x1, x2, B\n  addi x20, x20, 2\nB:\n"
    "  blt  x1, x2, C\n  addi x20, x20, 4\nC:\n"
    "  bgeu x0, x0, D\n  addi x20, x20, 8\nD:\n" + END, "bltu_bgeu_sign")
print("\nSUMMARY:", sum(results.values()), "/", len(results), "pass")
print("FAIL:", [k for k,v in results.items() if not v])
import json
json.dump(results, open("build/results_isa.json","w"), indent=1)
