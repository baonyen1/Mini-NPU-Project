/* npu_ref.c - untimed golden model of the MAC engine (spec 6, 10.2).
 * Skeleton: state and signatures only. Fill in each TODO, one test at a time. */
#include "npu_ref.h"

/* ---- state (spec 6.2, 6.4) -------------------------------------------- */
static uint32_t dtcm[NPU_DTCM_WORDS];       /* the model's own DTCM image            */
static uint32_t wbuf[NPU_KMAX / 4][4];      /* 256 quads; wbuf[s][i] = word i of quad s */
static uint32_t ibuf[NPU_KMAX / 4][4];
static uint32_t acc[4][4];                  /* uint32_t: wrap mod 2^32 is defined in C */
static uint32_t err_bits;                   /* only bits 8..11 of npu_status         */
static uint32_t busy_cyc;                   /* CSR 0x7C1, a plain stored value       */

void npu_ref_reset(void)
{
    /* TODO: clear every piece of state above, including dtcm and the buffers.
     * (The line below only keeps the skeleton compiling under -Werror; delete
     * it once you use these variables for real.) */
    (void)dtcm; (void)wbuf; (void)ibuf; (void)acc; (void)err_bits; (void)busy_cyc;
}

void npu_ref_mem_write(uint32_t word_idx, uint32_t data)
{
    /* TODO: dtcm[word_idx] = data. Decide what to do when word_idx >= 16384
     * (an out-of-bounds write is a bug in the caller, so failing loudly is fine). */
    (void)word_idx; (void)data;
}

void npu_ref_cmd(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr)
{
    /* TODO: check order (record any change in the spec):
     *   1. op == ILLEGAL            -> err_illegal, return
     *   2. k == 0                   -> return (no error; clr is ignored)
     *   3. k > KMAX || k % 4 != 0   -> err_k, return
     *   4. LDW / LDI only:
     *        (addr & 0xF) != 0      -> err_align, return
     *        range check in 64 bit  -> err_addr, return
     *   5. execute: LDW / LDI copy K/4 quads, MAC runs the dot products.
     * Break 5 into small static helpers. */
    (void)op; (void)addr; (void)k; (void)clr;
}

uint32_t npu_ref_read(uint32_t idx)
{
    /* TODO: acc[row][col] with idx & 0xF split as 4*row + col (spec 6.2). */
    (void)idx;
    return 0;
}

uint32_t npu_ref_status(void)
{
    /* TODO: err_bits plus the constant bits (busy 0, fifo_empty 1, fifo_full 0). */
    
    return 0;
}

void npu_ref_csr_write(uint32_t addr, uint32_t data)
{
    /* TODO: 0x7C0 -> write-1-to-clear the four error bits only (never RO bits);
     *       0x7C1 -> busy_cyc = data; other addresses -> ignore. */
    (void)addr; (void)data;
}
