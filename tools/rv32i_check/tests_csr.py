"""Zicsr and counter tests (plan Task 6): RTL vs RefISS.

mcycle is cycle-accurate in the RTL but ideal (1 CPI) in RefISS, so tests only
keep derived booleans of cycle reads and zero the raw registers before the
end-of-test compare. minstret is exact in both models and may stay raw.
The scratch CSR is 0x7C1 (plain RW in the engine stub); 0x7C0 is the W1C status."""
from run import compare
import os, json
os.makedirs("build", exist_ok=True)
E = "\nend: j end\n"
T = {
 # plan Task 6 tests
 "csr_ops_all6": " li x1,0xF0F0\n li x2,0x00FF\n csrrw x10,0x7c1,x1\n csrrs x11,0x7c1,x2\n csrrc x12,0x7c1,x2\n"
                 " csrrwi x13,0x7c1,5\n csrrsi x14,0x7c1,8\n csrrci x15,0x7c1,1\n csrr x16,0x7c1\n csrrs x17,0x7c1,x0\n"
                 " csrrwi x18,0x7c1,0\n csrr x19,0x7c1\n",
 "minstret_delta": " csrr x1,0xB02\n addi x5,x0,1\n addi x5,x5,1\n addi x5,x5,1\n addi x5,x5,1\n addi x5,x5,1\n csrr x2,0xB02\n sub x3,x2,x1\n",
 "mcycle_ge_minstret": " li x5,DM+0x40\n csrr x1,0xB00\n csrr x2,0xB02\n sw x5,0(x5)\n lw x6,0(x5)\n add x7,x6,x6\n beq x0,x0,L\n addi x8,x0,1\n addi x8,x0,2\n"
                       "L: csrr x3,0xB00\n csrr x4,0xB02\n sub x9,x3,x1\n sub x10,x4,x2\n sltu x11,x9,x10\n li x1,0\n li x3,0\n li x9,0\n",
 "cycle_alias_reads": " csrr x1,0xB00\n csrr x2,0xC00\n sub x3,x2,x1\n addi x3,x3,-1\n seqz x4,x3\n"
                      " csrr x5,0xB02\n csrr x6,0xC02\n sub x7,x6,x5\n csrr x8,0xB80\n csrr x9,0xC80\n csrr x10,0xB82\n csrr x11,0xC82\n"
                      " li x1,0\n li x2,0\n li x3,0\n",
 "csrrw_x0_still_writes_csr": " li x1,0x1357\n csrrw x0,0x7c1,x1\n csrr x2,0x7c1\n li x3,0x100\n csrrw x0,0x7c0,x3\n csrr x4,0x7c0\n",
 "csr_raw_back_to_back": " li x1,0x2468\n csrrw x0,0x7c1,x1\n csrr x2,0x7c1\n csrrw x3,0x7c1,x2\n csrr x4,0x7c1\n"
                         " csrr x5,0x7c1\n add x6,x5,x5\n csrr x7,0x7c1\n xor x8,x7,x6\n csrr x9,0x7c1\n sub x10,x0,x9\n",
 # extra directed tests
 "csr_minstret_with_stalls_and_flushes": " li x5,DM+0x40\n csrr x1,0xB02\n sw x5,0(x5)\n lw x6,0(x5)\n add x7,x6,x6\n beq x0,x0,L\n addi x8,x0,1\n addi x8,x0,2\n"
                                          "L: li x2,3\n bne x2,x0,K\n addi x9,x0,1\nK: jal x10,J\n addi x11,x0,1\nJ: csrr x3,0xB02\n sub x4,x3,x1\n",
 # closes the blind spot found in Task 5: a divide must retire exactly once, so minstret counts it once
 "minstret_across_divide": " csrr x1,0xB02\n li x2,100\n li x3,7\n div x4,x2,x3\n csrr x5,0xB02\n rem x6,x2,x3\n mul x7,x4,x6\n csrr x8,0xB02\n sub x9,x5,x1\n sub x10,x8,x5\n",
 "csr_status_w1c": " csrr x20,0x7c0\n li x1,0x100\n csrrw x0,0x7c0,x1\n csrr x21,0x7c0\n li x2,0xC00\n csrrs x22,0x7c0,x2\n csrr x23,0x7c0\n",
 "csr_rs_rc_x0_no_write": " csrrs x1,0x7c0,x0\n csrrc x2,0x7c0,x0\n csrrsi x3,0x7c0,0\n csrrci x4,0x7c0,0\n csrr x5,0x7c0\n",
 "csr_unknown_reads_zero": " li x2,0x55\n nop\n nop\n csrr x6,0xB02\n csrr x1,0x7ff\n csrrw x0,0x7ff,x2\n csrr x3,0x7ff\n csrr x4,0xC01\n csrr x5,0x7c2\n",
 "csr_counters_read_only": " li x1,0x70000000\n csrrw x0,0xB00,x1\n csrr x2,0xB00\n srli x3,x2,28\n li x2,0\n"
                           " csrrw x0,0xC02,x1\n csrrw x0,0xB02,x1\n csrr x4,0xB02\n csrr x5,0xC82\n",
 "csr_result_forwarded": " li x4,DM+0x40\n csrrw x0,0x7c1,x4\n csrr x5,0x7c1\n sw x4,0(x5)\n lw x6,0(x5)\n csrr x7,0x7c1\n beq x7,x4,L\n addi x20,x0,1\nL: addi x21,x0,2\n",
 "csr_rs1_after_load": " li x5,DM+0x40\n li x6,0x77\n sw x6,0(x5)\n lw x1,0(x5)\n csrrw x2,0x7c1,x1\n csrr x3,0x7c1\n lw x4,0(x5)\n csrrs x8,0x7c1,x4\n csrr x9,0x7c1\n",
 "csr_imm_not_a_register_use": " lw x1,0(x0)\n csrrwi x2,0x7c1,1\n csrrsi x3,0x7c1,2\n csrr x4,0x7c1\n",
}
fails = []
CYCLE_DEPENDENT = {"mcycle_ge_minstret"}      # computes on raw mcycle values: RVVI rd_wdata not compared after them
for k, v in T.items():
    if compare(".text\n" + v + E, k, steps=300, cycles=900, cycle_dependent=(k in CYCLE_DEPENDENT)): fails.append(k)
print(f"\nZICSR: {len(T)-len(fails)}/{len(T)} pass; FAIL={fails}")
json.dump({k: (k not in fails) for k in T}, open("build/results_csr.json", "w"), indent=1)
