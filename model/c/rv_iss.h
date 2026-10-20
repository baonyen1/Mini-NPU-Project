/* rv_iss.h - untimed instruction-set simulator of the Mini-NPU core (spec 10.2, plan Task 12).
 *
 * Models RV32IM + Zicsr + Zifencei + Zbb + the custom-0 instructions with the memory map of
 * spec 4.1: ITCM 16 KB at 0 (fetch only), DTCM 64 KB at 0x0001_0000, SIM_CTRL 0x0002_0000
 * (word writes), SIM_PUTC 0x0002_0004. A data address outside the map reads 0 and ignores
 * writes, and a fetch outside the ITCM executes a NOP (decision W2-1 is still open).
 *
 * The retire record has the meaning documented in docs/core_isa.md section 9.2; it is what
 * the RVVI port of the RTL produces and what the cosim checker compares.
 *
 * Modes
 *   ISS_STUB  custom-0 follows the core-only testbench stub: a command is only logged, READ_RESULT
 *             returns its index, CSR 0x7C0 reads {err[3:0], 8'b0000_0010} with the four sticky bits
 *             set at reset (write-1-to-clear on bits 11..8), CSR 0x7C1 is a plain register.
 *   ISS_FULL  the engine is npu_ref: commands execute, READ_RESULT returns the accumulator and the
 *             engine CSRs 0x7C0/0x7C1 come from npu_ref. Core stores to the DTCM are mirrored into
 *             npu_ref's DTCM image.
 * Zicsr: csrrs/csrrc write only when rs1/zimm is not zero; the engine CSR port gets the
 * read-modify-write result; counters and aliases are read-only; an unknown CSR reads 0.
 * mcycle counts one per instruction (ideal 1 CPI); minstret is the number of instructions
 * executed before the reader. */
#ifndef RV_ISS_H
#define RV_ISS_H

#include <stdint.h>

typedef struct {
    uint32_t valid, pc, insn, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask, trap;
    uint64_t order;
} rvvi_rec_t;

enum { ISS_STUB = 0, ISS_FULL = 1 };

#define ISS_ITCM_WORDS  4096u        /* 16 KB */
#define ISS_DTCM_WORDS  16384u       /* 64 KB */
#define ISS_DTCM_BASE   0x00010000u
#define ISS_SIM_CTRL    0x00020000u
#define ISS_SIM_PUTC    0x00020004u

/* Load the images (a NULL pointer or a zero length leaves the memory at NOP / 0), clear the
 * registers, set pc = 0 and reset the engine model. Longer images are truncated. */
void iss_init(const uint32_t *itcm, uint32_t itcm_words,
              const uint32_t *dtcm, uint32_t dtcm_words, int mode);

/* Execute one instruction and fill *rec (rec may be NULL). Returns 1 when that instruction was
 * a word write to SIM_CTRL, else 0. */
int iss_step(rvvi_rec_t *rec);

/* ---- inspection ------------------------------------------------------------------------- */
uint32_t iss_reg(uint32_t index);               /* x0..x31 */
uint32_t iss_pc(void);
uint64_t iss_instret(void);
uint32_t iss_mem_read(uint32_t byte_addr);      /* DTCM word containing byte_addr, 0 outside the DTCM */
uint32_t iss_sim_ctrl_value(void);              /* last value written to SIM_CTRL */
uint32_t iss_putc_count(void);                  /* bytes written to SIM_PUTC */
uint32_t iss_putc_get(uint32_t i);              /* i-th byte written to SIM_PUTC */

/* Commands pushed by LOAD_WEIGHT / LOAD_INPUT / COMPUTE / reserved funct3 (op 3 = ILLEGAL):
 * {op, addr, k, clr} with addr = 0 for COMPUTE, as in the RTL push. */
uint32_t iss_cmd_count(void);
void     iss_cmd_get(uint32_t i, uint32_t *op, uint32_t *addr, uint32_t *k, uint32_t *clr);

#endif
