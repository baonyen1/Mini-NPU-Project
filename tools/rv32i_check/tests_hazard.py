from run import compare
import os, random; os.makedirs("build", exist_ok=True)
E = "\nend: j end\n"
T = {
"fwd_exmem_rs1rs2": " addi x1,x0,7\n add x2,x1,x1\n sub x3,x2,x1\n",
"fwd_memwb": " addi x1,x0,7\n nop\n add x2,x1,x0\n addi x3,x0,9\n nop\n add x4,x0,x3\n",
"fwd_priority_exmem_over_memwb": " addi x1,x0,1\n addi x1,x0,2\n add x2,x1,x0\n",
"load_use_rs1": " li x5,0x40\n li x6,123\n sw x6,0(x5)\n lw x7,0(x5)\n addi x8,x7,1\n",
"load_use_rs2": " li x5,0x40\n li x6,123\n sw x6,0(x5)\n lw x7,0(x5)\n add x8,x0,x7\n",
"load_then_1nop_use": " li x5,0x40\n li x6,77\n sw x6,0(x5)\n lw x7,0(x5)\n nop\n add x8,x7,x7\n",
"load_to_store_data": " li x5,0x40\n li x6,0x55\n sw x6,0(x5)\n lw x7,0(x5)\n sw x7,4(x5)\n",
"load_to_store_addr": " li x5,0x40\n li x6,0x80\n sw x6,0(x5)\n lw x7,0(x5)\n sw x5,0(x7)\n",
"alu_to_store_data": " li x5,0x40\n addi x6,x0,99\n sw x6,8(x5)\n addi x6,x6,1\n nop\n sw x6,12(x5)\n",
"load_load_chain": " li x5,0x40\n li x6,0x44\n sw x6,0(x5)\n li x9,5\n sw x9,4(x5)\n lw x7,0(x5)\n lw x8,0(x7)\n add x10,x8,x8\n",
"branch_on_fwd": " addi x1,x0,3\n addi x2,x0,3\n beq x1,x2,L\n addi x20,x0,1\nL: addi x21,x0,2\n",
"branch_on_load": " li x5,0x40\n li x6,4\n sw x6,0(x5)\n lw x7,0(x5)\n bne x7,x0,L\n addi x20,x0,1\nL: addi x21,x0,2\n",
"jalr_on_load": " li x5,0x40\n auipc x6,0\n addi x6,x6,28\n sw x6,0(x5)\n lw x7,0(x5)\n jalr x1,0(x7)\n addi x20,x0,1\n addi x21,x0,2\n",
"jal_link_fwd": " jal x1,L\nL: addi x2,x1,0\n add x3,x1,x1\n",
"jalr_link_fwd_memwb": " auipc x5,0\n jalr x1,12(x5)\n nop\n nop\n add x3,x1,x0\n",
"x0_no_forward": " addi x0,x0,5\n add x1,x0,x0\n lw x0,0(x0)\n add x2,x0,x0\n",
"shadow_store_flushed": " li x5,0x40\n j L\n sw x5,0(x5)\n sw x5,4(x5)\nL: addi x1,x0,1\n",
"shadow_load_use_with_branch": " li x5,0x40\n li x6,9\n sw x6,0(x5)\n beq x0,x0,L\n lw x7,0(x5)\n add x8,x7,x7\nL: addi x9,x0,1\n",
"branch_after_branch": " beq x0,x0,A\n beq x0,x0,B\nA: bne x0,x0,B\n addi x20,x0,1\nB: addi x21,x0,1\n",
"jump_to_jump": " j A\n addi x20,x0,1\nA: j B\n addi x20,x0,2\nB: addi x21,x0,1\n",
"loop_backward": " addi x1,x0,10\n addi x2,x0,0\nL: add x2,x2,x1\n addi x1,x1,-1\n bne x1,x0,L\n",
"nested_loops": " addi x1,x0,4\nO: addi x2,x0,3\nI: addi x3,x3,1\n addi x2,x2,-1\n bne x2,x0,I\n addi x1,x1,-1\n bne x1,x0,O\n",
"memcpy_loop": " li x5,0x80\n li x6,0x100\n addi x7,x0,8\n addi x9,x0,0x11\nF: sw x9,0(x5)\n addi x9,x9,0x22\n addi x5,x5,4\n addi x7,x7,-1\n bne x7,x0,F\n li x5,0x80\n addi x7,x0,8\nC: lw x8,0(x5)\n sw x8,0(x6)\n addi x5,x5,4\n addi x6,x6,4\n addi x7,x7,-1\n bne x7,x0,C\n",
"function_call": " addi x10,x0,5\n jal x1,F\n addi x11,x10,0\n j end\nF: add x10,x10,x10\n jalr x0,0(x1)\n",
"byte_store_then_word_load": " li x5,0x40\n li x6,0x11223344\n sw x6,0(x5)\n li x7,0xAB\n sb x7,1(x5)\n lw x8,0(x5)\n lbu x9,1(x5)\n lb x10,1(x5)\n",
}
fails = []
for k,v in T.items():
    if compare(".text\n"+v+E, k): fails.append(k)
print(f"\nDIRECTED HAZARD/CONTROL: {len(T)-len(fails)}/{len(T)} pass; FAIL={fails}")

# ---- constrained-random over the SUPPORTED subset only ----
SUP_R = ["add","sub","xor","or","and","sll","srl","sra","slt","sltu"]
SUP_I = ["addi","xori","ori","andi","slti","sltiu"]
SUP_SH = ["slli","srli","srai"]
def rnd_prog(rng, n=60):
    regs = list(range(1,8))            # small reg pool -> dense dependencies
    L = [" li x31,0x200"]              # x31 = data base, never written below
    lab = 0
    for i in range(n):
        r = rng.random(); d = rng.choice(regs); a = rng.choice(regs+[0]); b = rng.choice(regs+[0])
        if r < 0.35: L.append(f" {rng.choice(SUP_R)} x{d},x{a},x{b}")
        elif r < 0.48: L.append(f" {rng.choice(SUP_I)} x{d},x{a},{rng.randint(-2048,2047)}")
        elif r < 0.55: L.append(f" {rng.choice(SUP_SH)} x{d},x{a},{rng.randint(0,31)}")
        elif r < 0.62: L.append(f" lui x{d},{rng.randint(0,0xFFFFF)}")
        elif r < 0.75:
            op = rng.choice(["lw","lh","lhu","lb","lbu"]); al = {"lw":4,"lh":2,"lhu":2}.get(op,1)
            L.append(f" {op} x{d},{rng.randrange(0,64,al)}(x31)")
        elif r < 0.87:
            op = rng.choice(["sw","sh","sb"]); al = {"sw":4,"sh":2}.get(op,1)
            L.append(f" {op} x{b},{rng.randrange(0,64,al)}(x31)")
        else:
            op = rng.choice(["beq","bne","blt","bge","bltu","bgeu"]); lab += 1
            skip = rng.randint(0,3)
            L.append(f" {op} x{a},x{b},R{lab}")
            for _ in range(skip): L.append(f" addi x{rng.choice(regs)},x{rng.choice(regs)},{rng.randint(-50,50)}")
            L.append(f"R{lab}:")
    return ".text\n" + "\n".join(L) + E
rf = []
N = 300
for s in range(N):
    rng = random.Random(s)
    if compare(rnd_prog(rng), f"rand_{s}", steps=400, cycles=800, quiet=True): rf.append(s)
print(f"RANDOM (full RV32I ALU/branch/load/store, {N} seeds x ~60 instr): {N-len(rf)}/{N} pass; failing seeds={rf[:10]}")
import json
res = {k: (k not in fails) for k in T}
res.update({f"rand_{i}": (i not in rf) for i in range(N)})
json.dump(res, open("build/results_hazard.json","w"), indent=1)
