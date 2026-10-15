/* npu_ref.h - untimed golden model of the Mini-NPU MAC engine (spec 6, 10.2).
 * Interface from Phase 1 plan, Task 10. Implementation: npu_ref.c (Bao). */
#ifndef NPU_REF_H
#define NPU_REF_H

#include <stdint.h>

/* Parameters, mirror rtl/top/npu_pkg.sv (spec 4.2). */
#define NPU_KMAX        1024u
#define NPU_DTCM_BASE   0x00010000u
#define NPU_DTCM_BYTES  65536u
#define NPU_DTCM_WORDS  (NPU_DTCM_BYTES / 4u)   /* 16384 */

/* Engine ops, mirror npu_pkg::npu_op_e (spec 7.1). */
enum { NPU_OP_LDW = 0, NPU_OP_LDI = 1, NPU_OP_MAC = 2, NPU_OP_ILLEGAL = 3 };

/* npu_status layout (spec 6.4). */
#define NPU_ST_BUSY        (1u << 0)
#define NPU_ST_FIFO_EMPTY  (1u << 1)
#define NPU_ST_FIFO_FULL   (1u << 2)
#define NPU_ST_ERR_K       (1u << 8)
#define NPU_ST_ERR_ADDR    (1u << 9)
#define NPU_ST_ERR_ILLEGAL (1u << 10)
#define NPU_ST_ERR_ALIGN   (1u << 11)

#define NPU_CSR_STATUS     0x7C0u
#define NPU_CSR_BUSY_CYC   0x7C1u

void     npu_ref_reset(void);
void     npu_ref_mem_write(uint32_t word_idx, uint32_t data);  /* word_idx 0..16383 */
void     npu_ref_cmd(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr);
uint32_t npu_ref_read(uint32_t idx);                           /* uses idx & 0xF */
uint32_t npu_ref_status(void);
void     npu_ref_csr_write(uint32_t addr, uint32_t data);      /* 0x7C0 W1C, 0x7C1 set */

#endif
