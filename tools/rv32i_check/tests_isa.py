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
print("\nSUMMARY:", sum(results.values()), "/", len(results), "pass")
print("FAIL:", [k for k,v in results.items() if not v])
