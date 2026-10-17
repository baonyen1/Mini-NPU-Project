/* npu_ref.c - untimed golden model of the MAC engine (spec 6, 10.2). */
#include "npu_ref.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NPU_ERR_MASK (NPU_ST_ERR_K | NPU_ST_ERR_ADDR | NPU_ST_ERR_ILLEGAL | NPU_ST_ERR_ALIGN)

/* ---- state (spec 6.2, 6.4) -------------------------------------------- */
static uint32_t dtcm[NPU_DTCM_WORDS];       /* the model's own DTCM image            */
static uint32_t wbuf[NPU_KMAX / 4][4];      /* 256 quads; wbuf[s][i] = word i of quad s */
static uint32_t ibuf[NPU_KMAX / 4][4];
static uint32_t acc[4][4];                  /* uint32_t: wrap mod 2^32 is defined in C */
static uint32_t err_bits;                   /* only bits 8..11 of npu_status         */
static uint32_t busy_cyc;                   /* CSR 0x7C1, a plain stored value       */

/* ---- internal helpers ------------------------------------------------- */

/* Copy K/4 quads from the model's DTCM into a buffer (spec 6.3, LOAD).
 * Caller has already checked K, alignment and range. */
static void load_quads(uint32_t buf[][4], uint32_t addr, uint32_t k)
{
    uint32_t quads     = k / 4u;
    uint32_t base_word = (addr - NPU_DTCM_BASE) / 4u;

    for (uint32_t s = 0; s < quads; s++) {
        for (uint32_t i = 0; i < 4u; i++) {
            buf[s][i] = dtcm[base_word + 4u * s + i];
        }
    }
}

/* Dot product of the 4 int8 lanes of two words. |sum| <= 4 * 128 * 128 = 65536. */
static int32_t dot4(uint32_t w_word, uint32_t i_word)
{
    int32_t sum = 0;
    for (int t = 0; t < 4; t++) {
        int32_t w_lane = (int8_t)(w_word >> (8 * t));   /* sign-extend lane t */
        int32_t i_lane = (int8_t)(i_word >> (8 * t));
        sum += w_lane * i_lane;
    }
    return sum;
}

/* acc[i][j] = (clr ? 0 : acc[i][j]) + sum over quads s of dot4(W[s].word_i, I[s].word_j). */
static void run_mac(uint32_t k, uint32_t clr)
{
    uint32_t quads = k / 4u;

    for (uint32_t i = 0; i < 4u; i++) {
        for (uint32_t j = 0; j < 4u; j++) {
            if (clr != 0u) {
                acc[i][j] = 0u;
            }
            for (uint32_t s = 0; s < quads; s++) {
                acc[i][j] += (uint32_t)dot4(wbuf[s][i], ibuf[s][j]);   /* uint32_t: wraps */
            }
        }
    }
}

/* ---- public API: status -> reset -> mem_write -> read -> cmd -> csr_write ---- */

uint32_t npu_ref_status(void)
{
    /* The model is untimed: busy = 0, fifo_empty = 1, fifo_full = 0 (spec 6.4). */
    return (err_bits & NPU_ERR_MASK) | NPU_ST_FIFO_EMPTY;
}

void npu_ref_reset(void)
{
    memset(dtcm, 0, sizeof dtcm);
    memset(wbuf, 0, sizeof wbuf);
    memset(ibuf, 0, sizeof ibuf);
    memset(acc,  0, sizeof acc);
    err_bits = 0u;
    busy_cyc = 0u;
}

void npu_ref_mem_write(uint32_t word_idx, uint32_t data)
{
    /* Not assert(): it disappears under -DNDEBUG and the write would corrupt memory. */
    if (word_idx >= NPU_DTCM_WORDS) {
        fprintf(stderr, "npu_ref_mem_write: word_idx %u out of range (max %u)\n",
                (unsigned)word_idx, (unsigned)(NPU_DTCM_WORDS - 1u));
        abort();
    }
    dtcm[word_idx] = data;
}

uint32_t npu_ref_read(uint32_t idx)
{
    uint32_t masked = idx & 0xFu;           /* spec 6.3: only idx[3:0] is used */
    return acc[masked >> 2][masked & 0x3u]; /* idx = 4*i + j (spec 6.2)        */
}

void npu_ref_cmd(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr)
{
    /* 1. Illegal op. */
    if (op != NPU_OP_LDW && op != NPU_OP_LDI && op != NPU_OP_MAC) {
        err_bits |= NPU_ST_ERR_ILLEGAL;
        return;
    }

    /* 2. K == 0 is a no-op for every op: no error, and clr is ignored (Review Focus 5). */
    if (k == 0u) {
        return;
    }

    /* 3. K too big or not a multiple of 4. */
    if (k > NPU_KMAX || (k & 0x3u) != 0u) {
        err_bits |= NPU_ST_ERR_K;
        return;
    }

    /* 4. LOAD only: alignment first, then the range in 64 bit (Review Focus 4). */
    if (op == NPU_OP_LDW || op == NPU_OP_LDI) {
        if ((addr & 0xFu) != 0u) {
            err_bits |= NPU_ST_ERR_ALIGN;
            return;
        }
        uint64_t start = (uint64_t)addr;
        uint64_t end   = start + 4ull * (uint64_t)k;
        uint64_t limit = (uint64_t)NPU_DTCM_BASE + (uint64_t)NPU_DTCM_BYTES;
        if (start < (uint64_t)NPU_DTCM_BASE || end > limit) {
            err_bits |= NPU_ST_ERR_ADDR;
            return;
        }
    }

    /* 5. Every check passed: execute. */
    if (op == NPU_OP_LDW) {
        load_quads(wbuf, addr, k);
    } else if (op == NPU_OP_LDI) {
        load_quads(ibuf, addr, k);
    } else {
        run_mac(k, clr);
    }
}

void npu_ref_csr_write(uint32_t addr, uint32_t data)
{
    if (addr == NPU_CSR_STATUS) {
        err_bits &= ~(data & NPU_ERR_MASK);     /* W1C on bits 8..11 only; RO bits untouched */
    } else if (addr == NPU_CSR_BUSY_CYC) {
        busy_cyc = data;                        /* plain stored value (spec 6.4) */
    }
    /* any other CSR address: ignored */
}
