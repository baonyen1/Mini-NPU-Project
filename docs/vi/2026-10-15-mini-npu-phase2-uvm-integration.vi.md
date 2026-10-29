# Mini-NPU Phase 2 (Tuần 5–9): Implementation Plan — Tích hợp, UVM, Coverage (bản tiếng Việt)

> **Bản dịch để đọc cho dễ.** Bản chuẩn là bản tiếng Anh `docs/superpowers/plans/2026-10-15-mini-npu-phase2-uvm-integration.md`. Khi hai bản khác nhau, bản tiếng Anh thắng. Dịch ngày 2026-10-29 (commit ngay sau `a2b3a97`). Tên task, tên test, tên file, lệnh, câu commit và thuật ngữ kỹ thuật giữ nguyên tiếng Anh.

> **Cho agent:** BẮT BUỘC dùng sub-skill superpowers:subagent-driven-development (khuyến nghị) hoặc superpowers:executing-plans để làm plan này theo từng task. Các step dùng cú pháp checkbox (`- [ ]`) để theo dõi.
>
> **Luật của dự án (ghi đè dòng trên đối với phần được chấm điểm):** sinh viên tự viết toàn bộ RTL, logic golden model, UVM và firmware. Claude review dựa trên các test được nêu ở đây. Các task gắn **[support]** là tooling không chấm điểm, Claude có thể viết khi được yêu cầu.

**Mục tiêu:** Tới cuối tuần 9, `npu_top` (core + ITCM + DTCM + MAC engine) chạy được firmware, và ba môi trường UVM tự xây (`mac_env`, `core_env`, `soc_env`) pass mọi directed test và random test, với coverage đã đóng trên D0 (SC1, SC2).

**Kiến trúc:** Tích hợp trước, bằng một testbench SV thường, để bug interface giữa hai track lộ ra ngay ở tuần 5. Các môi trường UVM được xây song song và đi theo topology công khai của CoralNPU (D13): một RVVI agent passive cộng một co-simulation checker chạy ISS C của nhóm theo lockstep, nạp chương trình bằng backdoor, kết thúc test khi có tín hiệu hoàn tất hoặc timeout. Directed test trước (tuần 5–6), random và coverage sau (tuần 7–9).

**Tech stack:** SystemVerilog + UVM 1.2 trên Siemens QuestaSim (licence đầy đủ; xsim dự phòng theo Task 0), DPI-C (gcc), Verilator (lint), RISC-V GCC (`-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32`), Python 3.

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` (bản sửa 2026-10-15, D11–D13). Số § là của spec này. Plan trước: `docs/superpowers/plans/2026-10-04-mini-npu-phase1.md` (Ràng buộc chung của nó vẫn áp dụng nguyên vẹn và không nhắc lại ở đây).

**Người phụ trách:** Track A = Nguyễn Hoàng Công Tấn, Track B = Nguyễn Thế Bảo (bảng phụ trách của Phase 1).

| Task | Người phụ trách | Tuần |
|---|---|---|
| 13 · Firmware base | Tấn | 5 |
| 14 · Tích hợp `npu_top` (không UVM) | cả hai (Tấn: top + firmware; Bảo: phía engine) | 5–6 |
| 15 · Lớp UVM dùng chung + `run.py` | Claude **[support]** cho `run.py`/`manifest.yaml`; Tấn: RVVI agent + cosim checker | 5 |
| 16 · `mac_env` | Bảo | 5–9 |
| 17 · `core_env` | Tấn | 5–9 |
| 18 · `soc_env` | cả hai | 6–9 |
| 19 · Đóng coverage, ký Phase 2, viết nháp chương báo cáo | cả hai | 9–10 |

## Ràng buộc chung (bổ sung cho Phase 2)

- Điều kiện vào: exit checklist của Phase 1 xanh. Nếu `rv_iss.c` (Task 12) bị trễ, Task 17 bắt đầu chỉ với directed test và chuyển sang lockstep ở tuần 6 (rủi ro lịch của Phase 1).
- Topology và tên UVM (D13, §10.1): `npu_rvvi_agent` (passive), `npu_cosim_checker`; package `mac_env_pkg`, `core_env_pkg`, `soc_env_pkg`; file list `mac_dv.f`, `core_dv.f`, `soc_dv.f`; top của soc là `tb/uvm/tb/npu_tb_top.sv`.
- Nạp chương trình/dữ liệu: backdoor `$readmemh` (`+ITCM=<file>`, `+DTCM=<file>`) trước khi nhả reset (D7).
- Kết thúc test (§10.1): ghi `SIM_CTRL` (`0x1` PASS, `0x2` FAIL), hoặc tín hiệu halt/fault của core nếu W2-1 có định nghĩa, hoặc timeout = 10 × số cycle dự kiến (mặc định `+TIMEOUT_CYC=1000000`). Timeout là fail.
- Golden model chỉ thành oracle sau khi pass unit test của chính nó (§10.2). Chỉ được gọi `npu_ref` và `rv_iss` qua `tb/uvm/common/npu_dpi_pkg.sv`.
- Coverage: mọi bin ở §10.5 khai báo trước tuần 7; 100 % số bin đã khai báo trên D0 trước tuần 10 (SC2). Một exclusion cần lý do viết ra trong `docs/coverage_exclusions.md` và có chữ ký của cả hai sinh viên.
- Không chép code CoralNPU (§16). Có thể đọc file của Coral để tham khảo và trích đường dẫn của chúng trong comment.
- Mọi test đều chạy qua `run.py` để sau này SC6 không cần thêm đường ống mới.

## Review Focus

1. **Lockstep bị trôi khi có stall:** một READ_RESULT đang stall, các stall do FIFO đầy và stall của bộ chia trong cùng một khoảng không được làm cosim checker bỏ sót hay đếm trùng một lần retire. Test: Task 17 `core_cosim_stall_storm`.
2. **Golden memory lệch nhau:** một lần ghi của responder hay của backdoor mà không được mô phỏng song song vào `npu_ref` hoặc `rv_iss` sẽ làm các dự đoán sau đó sai, và có thể che mất bug thật. Test: Task 16 `mac_mem_mirror_check` (cuối test so hash memory của responder với `npu_ref`), Task 18 so sánh DTCM với ISS ở cuối mọi test soc.
3. **Treo thay vì fail:** một READ_RESULT không bao giờ trả về phải kết thúc test bằng FAIL do timeout, không được chạy mãi hay báo PASS. Test: Task 17 `core_read_result_hang_times_out` (expected-fail).
4. **Stimulus lỗi của test lại được tính vào coverage:** một COMPUTE đọc các entry buffer chưa từng được ghi kể từ reset (§7.2) là bug của sequence; nó phải báo `UVM_ERROR` và không được tính. Test: Task 16 `mac_unwritten_entry_flagged` (expected-fail).
5. **Toolchain firmware bị lệch:** encoding `.insn` trong `npu.h` phải khớp §6.1 với mọi tổ hợp funct3/funct7, nếu không firmware sẽ âm thầm phát sai lệnh. Test: Task 13 `npu_h_encodings`.

---

### Task 13: Firmware nền — Track A, tuần 5

**File:**
- Tạo: `sw/crt0.S` (đặt `sp` ở đỉnh DTCM `0x0002_0000`, xoá `.bss` về 0, gọi `main`, ghi giá trị trả về: 0 → `SIM_CTRL=0x1`, khác 0 → `0x2`)
- Tạo: `sw/link.ld` (`.text`/`.rodata` trong ITCM `0x0000_0000` 16 KB; `.data`/`.bss`/stack trong DTCM `0x0001_0000` 64 KB; `.data` bắt đầu ở `0x0001_DE00`, sau vùng model ở §9.2; các word `0x0001_DDF4`–`0x0001_DDFF` dành riêng cho kết quả đo do firmware Phase 3/4 ghi)
- Tạo: `sw/npu.h`, `sw/sim.h` (`sim_putc(char)`, `sim_pass()`, `sim_fail()`, `sim_meas_start()`, `sim_meas_stop()`, `sim_batch_done()`)
- Tạo: `sw/Makefile` (`make -C sw TEST=<name>` → `sw/build/<name>/{<name>.elf, itcm.hex, dtcm.hex, <name>.dis}`)
- Tạo: `sw/tests/hello/main.c`, `sw/tests/npu_h_encodings/main.S`, `sw/tools/check_insn.py`

**Interface:**
- Tạo ra (§9.1):
  ```c
  static inline void     npu_load_w(uint32_t addr, uint32_t k);   /* funct3 000, "memory" clobber */
  static inline void     npu_load_i(uint32_t addr, uint32_t k);   /* funct3 001, "memory" clobber */
  static inline void     npu_compute(uint32_t k, uint32_t clr);   /* funct3 010, funct7[0]=clr; clr must be a compile-time constant */
  static inline uint32_t npu_read(uint32_t idx);                  /* funct3 011, no clobber */
  ```
  (Comment: `clr` phải là hằng số lúc compile; `npu_read` không có clobber.)
  Định dạng hex: mỗi dòng một word 32 bit, đánh địa chỉ theo word tính từ base của vùng, đúng như `$readmemh` trong `itcm.sv`/`dtcm_dp.sv` chờ đợi.

- [ ] **Step 1: Viết các test fail:**
  - `hello`: in `"OK\n"` qua `sim_putc`, trả 0. Log kỳ vọng: `OK` rồi `PASS`.
  - `npu_h_encodings`: `main.S` chứa, theo thứ tự, các lệnh mà wrapper sinh ra với register cố định: `npu_load_w(a0,a1)`, `npu_load_i(a0,a1)` (rd = x0), `npu_compute(a0,0)`, `npu_compute(a0,1)` (rs2 = rd = x0), `npu_read(a0)` → a2 (rs2 = x0). `check_insn.py` assert các word, theo thứ tự: `0x00b5000b`, `0x00b5100b`, `0x0005200b`, `0x0205200b`, `0x0005360b`. Nó cũng compile một file C dùng cả bốn wrapper và kiểm cùng các field funct3/funct7 trong bản disassembly.
- [ ] **Step 2:** `make -C sw TEST=hello` rồi chạy trên `core_tb_top` của Phase 1 (`+ITCM=sw/build/hello/itcm.hex +DTCM=sw/build/hello/dtcm.hex`) → FAIL (thiếu file).
- [ ] **Step 3:** Cài đặt các file trên.
- [ ] **Step 4:** `hello` kết thúc bằng `OK` và `PASS`; `python sw/tools/check_insn.py sw/build/npu_h_encodings/npu_h_encodings.dis` thoát với mã 0.
- [ ] **Step 5: Commit** `feat(sw): crt0, linker script, npu.h, sim.h, build`.

---

### Task 14: Tích hợp `npu_top` và smoke test bằng SV thường — cả hai, tuần 5–6

**File:**
- Tạo: `rtl/top/npu_top.sv` (core + `itcm` + `dtcm_dp` + `mac_engine #(GATING_EN)`; port A của core → DTCM cho `0x0001_xxxx`; cửa sổ MMIO của core `0x0002_xxxx` → các port `mmio_*` ở top; các port RVVI đi xuyên qua dưới `` `ifdef RVVI_TRACE ``; halt/fault đi xuyên qua nếu W2-1 định nghĩa chúng)
- Tạo: `tb/directed/npu_top_tb.sv` (cài đặt `SIM_CTRL`/`SIM_PUTC` trên `mmio_*`; `+TIMEOUT_CYC`)
- Tạo: `sw/tests/{t_ldw_ldi_mac,t_read_all,t_errors,t_status_csr,t_war_safe}/main.c`
- Tạo: `sim/questa/run_npu_top.do`, `rtl/rtl.f` (mọi file RTL synthesize được, theo thứ tự compile; mọi `*_dv.f` dùng lại)

**Interface:**
- Dùng: các port của core (Phase 1 Task 8, 9), các port §7.1 của `mac_engine` (Task 11), `dtcm_dp` (Task 8), `npu.h`/`sim.h` (Task 13).
- Tạo ra:
  ```systemverilog
  module npu_top #(parameter bit GATING_EN = 0) (
    input  logic clk, rst_n,
    output logic        mmio_we,  output logic [31:0] mmio_addr, output logic [31:0] mmio_wdata
    `ifdef RVVI_TRACE , /* the Task 8 rvvi_* ports */ `endif
  );
  ```
  Tên hierarchy cố định cho các task sau: `npu_top.u_core`, `npu_top.u_itcm`, `npu_top.u_dtcm`, `npu_top.u_mac_engine` (scope dump ở §11).

- [ ] **Step 1: Viết các test firmware fail.** Mỗi test tính giá trị kỳ vọng bằng C trên core (vòng lặp thường trên cùng các mảng DTCM) và so với `npu_read`, trả khác 0 nếu lệch:
  - `t_ldw_ldi_mac`: dữ liệu `hand_4x4_k4` của Task 10 đặt ở các address DTCM align 16 byte; COMPUTE K=4 clr=1; cả 16 kết quả bằng `r0=[10,1,-1280,-4]`, `r1=[-10,-1,1280,4]`, `r2=[127,127,-16256,254]`, `r3=[-128,0,16384,256]`
  - `t_read_all`: dữ liệu ngẫu nhiên K=64 (seed cố định trong source), clr=1 rồi một COMPUTE thứ hai clr=0; kết quả bằng 2× lần đầu
  - `t_errors`: K=6 → `err_k`; address `0x0001_0004` → `err_align`; `0x0001_FFF0` với K=8 → `err_addr`; funct3 `100` qua `.insn` → `err_illegal`; rồi W1C `0xF00` xoá cả bốn
  - `t_status_csr`: `npu_busy_cyc` (0x7C1) tăng ít nhất 256 qua một COMPUTE K=1024
  - `t_war_safe`: LDW, COMPUTE, READ_RESULT, rồi ghi đè buffer weight và lặp lại; kết quả lần hai dùng dữ liệu mới
- [ ] **Step 2:** Chạy từng test trên `npu_top_tb` → FAIL (chưa build top).
- [ ] **Step 3:** Cài đặt `npu_top.sv` và `npu_top_tb.sv`. Các chỗ interface lệch tìm thấy ở đây được sửa trong RTL của track sở hữu nó và ghi lại trong commit message.
- [ ] **Step 4:** Cả năm test kết thúc bằng `PASS`; `verilator --lint-only -Wall -f rtl/rtl.f --top-module npu_top` sạch.
- [ ] **Step 5: Commit** `feat(top): npu_top integration and firmware smoke tests`.

---

### Task 15: Lớp UVM dùng chung, RVVI agent, cosim checker, `run.py` — Tấn + Claude [support], tuần 5

**File:**
- Tạo: `tb/uvm/common/npu_dpi_pkg.sv` (mọi `import "DPI-C"` cho `npu_ref_*` và `iss_*`; không chỗ nào khác import DPI)
- Tạo: `tb/uvm/common/npu_rvvi_if.sv`, `tb/uvm/common/npu_rvvi_agent_pkg.sv` (passive: `npu_rvvi_monitor` → `uvm_analysis_port #(npu_rvvi_item)`)
- Tạo: `tb/uvm/common/npu_cosim_checker.sv` (subscriber: với mỗi `npu_rvvi_item`, gọi `iss_step(&rec)` rồi so sánh)
- Tạo: `tb/uvm/common/npu_sim_ctrl_if.sv`, `npu_sim_ctrl_monitor` (kết thúc test khi PASS/FAIL; báo `UVM_FATAL` khi timeout)
- Tạo: `tb/uvm/common/npu_base_test.sv` (nạp backdoor theo plusarg, giữ objection cho tới khi `sim_ctrl` kết thúc hoặc timeout)
- Tạo **[support]**: `run.py`, `sim/tests.yaml` (test → env, firmware, kết quả kỳ vọng `pass|fail`, seed), bộ ghi `manifest.yaml`
- Sửa (Tấn): `model/c/rv_iss.{h,c}`: thêm `uint32_t iss_mem_read(uint32_t addr);` (Task 18 cần cho bước kiểm cuối test)

**Interface:**
- Dùng: `rv_iss` (`iss_init`, `iss_step`, `rvvi_rec_t`, `ISS_STUB`/`ISS_FULL`, Phase 1 Task 12); các port RVVI (Task 8).
- Tạo ra:
  - `class npu_rvvi_item extends uvm_sequence_item;` các field giống `rvvi_rec_t` (`order, pc, insn, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask, trap`)
  - `class npu_cosim_checker extends uvm_subscriber #(npu_rvvi_item);` cấu hình: `iss_mode` (`ISS_STUB`|`ISS_FULL`), `mask_csr_reads` = {0xB00, 0xB80, 0xC00, 0xC80, 0x7C1} (§10.2). Báo `COSIM_MISMATCH` kèm field đầu tiên bị lệch.
  - `run.py --simulator {questa,xsim} --target <test|suite> [--config d0|d1] [--seeds N] [--cov]` → thoát mã 0 khi và chỉ khi mọi lần chạy khớp kết quả kỳ vọng của nó; log ở `out/<date>/<config>/<test>/<seed>/`.

- [ ] **Step 1: Viết các test fail:**
  - `cosim_selftest_pass`: một chương trình ALU 20 lệnh trên `core_env` (khung của Task 17) → 0 mismatch
  - `cosim_selftest_detects`: cùng chương trình, với `+COSIM_INJECT=7` khiến checker làm hỏng `rd_wdata` của ISS ở lần retire thứ 7 → test FAIL với `COSIM_MISMATCH` ở order 7 (expected-fail trong `tests.yaml`)
  - `run_py_selftest` **[support]**: `run.py --target selftest` chạy một test giả expected-pass và một test giả expected-fail và thoát mã 0; đảo một trong hai kỳ vọng thì thoát mã 1
- [ ] **Step 2:** Chạy → FAIL.
- [ ] **Step 3:** Cài đặt.
- [ ] **Step 4:** Cả ba hoạt động như mô tả; `manifest.yaml` liệt kê phiên bản Questa và loại licence, phiên bản Verilator, GCC, Python, git hash.
- [ ] **Step 5: Commit** `feat(tb): shared UVM layer, RVVI agent, cosim checker, run.py`.

---

### Task 16: `mac_env` — Track B, tuần 5–9

**File:**
- Tạo: `tb/uvm/mac_env/mac_cmd_if.sv`, `mac_dtcm_if.sv`, `mac_cmd_agent_pkg.sv`, `mac_dtcm_agent_pkg.sv`, `mac_predictor.sv`, `mac_scoreboard.sv`, `mac_coverage.sv`, `mac_env_pkg.sv`, `mac_seq_lib.sv`, `mac_test_pkg.sv`, `mac_tb_top.sv`, `mac_dv.f`
- Tạo: `tb/sva/mac_engine_sva.sv` (A-MAC-1..5, `bind mac_engine`)
- Sửa: `model/c/npu_ref.{h,c}`: thêm `uint32_t npu_ref_mem_read(uint32_t word_idx);` kèm một unit test cho nó

**Interface:**
- Dùng: các port §7.1 của `mac_engine`, `npu_dpi_pkg`, `npu_pkg`.
- Tạo ra:
  - `class mac_cmd_item extends uvm_sequence_item;` `rand npu_op_e op; rand bit [31:0] addr, k; rand bit clr;` cộng `kind` ∈ {PUSH, READ, CSR_RD, CSR_WR}, `idx`, `csr_addr`, `csr_wdata`, response `rdata`
  - `mac_dtcm_agent`: responder phản ứng trên `b_req/b_addr/b_rdata`, giữ `bit [127:0] mem[4096]`; mọi lần ghi đi qua `write_word(idx, data)`, hàm này đồng thời gọi `npu_ref_mem_write`
  - `mac_predictor` → `mac_scoreboard`: so từng kết quả READ và từng lần đọc `npu_status` với `npu_ref`; báo `UVM_ERROR "UNWRITTEN_ENTRY"` khi K/4 của một COMPUTE vượt quá số entry đã được ghi kể từ reset (§7.2)
  - Các covergroup đúng như §10.5: `cg_cmd`, `cg_operand`, `cg_fifo`, `cg_state`, `cg_acc`, `cg_err`, `cg_addr` (`cg_gate` được thêm ở Phase 3)

- [ ] **Step 1 (tuần 5–6): Viết các directed test fail** (mỗi test một `uvm_test`, phủ mọi dòng mac ở §10.3):
  - `mac_single_k4` (dữ liệu tính tay), `mac_k_kmax`, `mac_k0`, `mac_k_too_big` (1028), `mac_k_mod4` (6), `mac_misaligned` (`a[3:0]=4`), `mac_addr_oob`, `mac_addr_wraps_32bit` (`0xFFFF_FFF0`, K=8), `mac_illegal`
  - `mac_clr_vs_accum`, `mac_forced_wrap` (lặp COMPUTE clr=0 với mọi lane −128 cho tới khi `acc` wrap; giá trị kỳ vọng lấy từ `npu_ref`)
  - `mac_fifo_full` (8 lần push liên tiếp + thêm 1 trong lúc busy; quan sát được `cmd_ready` xuống thấp), `mac_read_while_busy` (`rd_ready` thấp cho tới khi drain xong), `mac_w1c`
  - `mac_mem_mirror_check` (Review Focus 2): `report_phase` của mọi test so một hash của memory responder với `npu_ref_mem_read` trên cả 16.384 word
  - `mac_unwritten_entry_flagged` (Review Focus 4, expected-fail): COMPUTE K=8 sau reset trong khi mới nạp một quad → `UVM_ERROR UNWRITTEN_ENTRY`
- [ ] **Step 2:** `run.py --target mac_directed` → FAIL. **Step 3:** Cài đặt env, agent, predictor, scoreboard, SVA. **Step 4:** Tất cả pass; test expected-fail chỉ fail vì đúng lý do đã nêu.
- [ ] **Step 5: Commit** `feat(tb): mac_env directed`.
- [ ] **Step 6 (tuần 7–9): Viết `mac_rand_seq`** (§10.3): trọng số trộn op LDW 30 / LDI 30 / MAC 30 / ILLEGAL 2 / READ 8; các bin K như `cg_cmd` với 5 % K không hợp lệ; address 90 % trong vùng và align; lane operand thiên 20 % về {−128, −1, 0, 1, 127}; khoảng cách giữa các lệnh 0–20 cycle. Ràng buộc: không COMPUTE vượt quá số entry đã ghi (§7.2). Test `mac_rand` với ≥ 200 seed.
- [ ] **Step 7:** `run.py --target mac_rand --seeds 200 --cov` → 0 mismatch, 0 lần SVA fail; covergroup khai báo đầy đủ trước cuối tuần 7 (đóng coverage là Task 19).
- [ ] **Step 8: Commit** `feat(tb): mac_env random and coverage`.

---

### Task 17: `core_env` — Track A, tuần 5–9

**File:**
- Tạo: `tb/uvm/core_env/core_env_pkg.sv`, `core_instr_item.sv`, `core_seq_lib.sv`, `core_coverage.sv`, `core_test_pkg.sv`, `core_uvm_tb_top.sv` (core + ITCM + DTCM + `npu_stub` của Phase 1 Task 9), `core_dv.f`
- Tạo: `tb/sva/core_sva.sv` (A-CORE-1)

**Interface:**
- Dùng: `npu_rvvi_agent`, `npu_cosim_checker` ở mode `ISS_STUB` (Task 15); plusarg của `npu_stub` `+STUB_READY=<bits>` và plusarg mới `+STUB_RDREADY=<bits>` (thêm vào `npu_stub.sv`, cùng mẫu).
- Tạo ra:
  - `class core_instr_item extends uvm_sequence_item;` lớp opcode ngẫu nhiên ∈ {ALU, ALUI, M, ZBB, LOAD, STORE, BRANCH, CSR, CUSTOM}, `rd, rs1, rs2, imm`; `function bit [31:0] encode();` (encoding theo `docs/core_isa.md`)
  - `core_rand_seq`: phát N item với khoảng cách phụ thuộc có kiểm soát (`dep_dist` ∈ {1, 2, 3, ≥4}), ghi chúng vào ITCM bằng backdoor, thêm lệnh store PASS vào `SIM_CTRL` ở cuối
  - Các covergroup `Cvgrp_rv32i`, `Cvgrp_m`, `Cvgrp_zbb`, `Cvgrp_csr`, `Cvgrp_fwd` với các bin ở §10.5 (dòng core)

- [ ] **Step 1 (tuần 5–6): Directed test.** Dùng lại các chương trình của Phase 1 (`tools/rv32i_check` build → `.hex`) thành các `uvm_test` chạy qua `core_env` có cosim: `core_isa_<suite>` cho mỗi suite rv32i/m/zbb/csr/custom; cộng thêm
  - `core_fifo_full_stall` (`+STUB_READY=0001`)
  - `core_cosim_stall_storm` (Review Focus 1): chuỗi DIV + 6 lần push với `+STUB_READY=0001` + READ_RESULT với `+STUB_RDREADY=00000001`, tất cả trong vòng 40 lệnh → 0 mismatch, `order` không có khoảng trống
  - `core_read_result_hang_times_out` (Review Focus 3, expected-fail): `+STUB_RDREADY=0` → test FAIL do timeout, không bao giờ PASS
- [ ] **Step 2:** `run.py --target core_directed` → FAIL. **Step 3:** Cài đặt. **Step 4:** Tất cả pass như mô tả.
- [ ] **Step 5: Commit** `feat(tb): core_env directed with cosim`.
- [ ] **Step 6 (tuần 7–9):** `core_rand_alu` (luồng ALU/M/Zbb, `dep_dist` phân bố đều trên các bin của nó) và `core_rand_branch` (thêm branch/jump có target nằm trong chương trình), mỗi cái ≥ 200 seed; bind A-CORE-1.
- [ ] **Step 7:** `run.py --target core_rand --seeds 200 --cov` → 0 mismatch.
- [ ] **Step 8: Commit** `feat(tb): core_env random and coverage`.

---

### Task 18: `soc_env` — cả hai, tuần 6–9

**File:**
- Tạo: `tb/uvm/tb/npu_tb_top.sv` (`npu_top #(GATING_EN) u_dut` + `npu_rvvi_if` + `npu_sim_ctrl_if`; `GATING_EN` lấy từ `+define+GATING_EN=0|1`; tên instance `u_dut` cố định, Phase 3 dump `u_dut.u_mac_engine`)
- Tạo: `tb/uvm/soc_env/soc_env_pkg.sv` (`npu_rvvi_agent`, `npu_cosim_checker` ở mode `ISS_FULL`, `soc_fifo_monitor`, `npu_sim_ctrl_monitor`, `soc_end_checker`), `soc_test_pkg.sv`, `soc_dv.f`
- Tạo: `tb/sva/soc_sva.sv` (A-SOC-1)
- Tạo: `model/py/gen_matmul.py` (seed → ma trận int8 ngẫu nhiên A[M×K], B[K×N], DTCM image đã đóng gói theo alignment của §6.2/§9.2, và C int32 kỳ vọng)
- Tạo: `sw/tests/{t_matmul_4x4xk,t_layer_784x64,t_war_violation}/main.c`, `sw/tests/soc_rand_matmul/main.c` (đọc kích thước và address từ một header do `gen_matmul.py` sinh ra)

**Interface:**
- Dùng: `npu_top` (Task 14), lớp dùng chung (Task 15), `iss_mem_read` (Task 15).
- Tạo ra: `soc_end_checker` — ở cuối mọi test soc, so cả 16.384 word DTCM (backdoor `npu_top.u_dtcm`) với `iss_mem_read`, và dump LOGITS nếu test có định nghĩa chúng. `gen_matmul.py --seed S --m M --k K --n N --out <dir>` ghi `dtcm.hex`, `matmul_cfg.h`, `expected.hex`.

- [ ] **Step 1: Viết các test fail** (dòng soc ở §10.3):
  - `soc_t_ldw_ldi_mac`, `soc_t_read_all`, `soc_t_errors`, `soc_t_status_csr` (firmware của Task 14, giờ có cosim)
  - `soc_matmul_4x4xk` với K ∈ {4, 64, 1024}
  - `soc_layer_784x64` (một matmul cỡ layer 1 đầy đủ, 16 tile)
  - `soc_war_violation` (expected-fail): firmware store vào một buffer trong lúc LOAD của nó đang chờ → A-SOC-1 bắn
  - `soc_rand_matmul`: `gen_matmul.py` với kích thước M, N ∈ {4, 8, 12, 16}, K là bội của 4 tới 256, ≥ 50 seed
  - mọi test: phép so sánh DTCM của `soc_end_checker` pass (Review Focus 2)
- [ ] **Step 2:** `run.py --target soc_all` → FAIL. **Step 3:** Cài đặt. **Step 4:** Tất cả pass; `soc_war_violation` chỉ fail vì A-SOC-1.
- [ ] **Step 5: Commit** `feat(tb): soc_env with full-system cosim`.

---

### Task 19: Đóng coverage, ký Phase 2, viết chương báo cáo — cả hai, tuần 9–10

**File:**
- Tạo: `docs/coverage_exclusions.md` (bảng rỗng nếu không có: bin, lý do, chữ ký A/B)
- Tạo: `docs/report/ch_verification.md` (bản nháp tiếng Anh, D12): các môi trường, golden model, danh sách test kèm số lần pass, bảng coverage, assertion, dòng so sánh với CoralNPU lấy từ §16
- Sửa **[support]**: các suite trong `sim/tests.yaml`: `mac_regress` = `mac_directed + mac_rand`; `core_regress` = `core_directed + core_rand`; `regress_d0` = `mac_regress + core_regress + soc_all` với `--config d0`, gộp UCDB vào `out/<date>/d0/cov/merged.ucdb`; `regress_d1` = cùng các suite đó với `--config d1` (dùng từ Phase 3)

**Interface:**
- Tạo ra: baseline D0 mà Phase 3 sẽ so sánh: log `out/<date>/d0/`, coverage đã gộp, và log RVVI của mọi test soc.

- [ ] **Step 1:** `run.py --target regress_d0 --cov` → liệt kê các bin chưa được phủ (`vcover report -details`).
- [ ] **Step 2:** Với mỗi lỗ hổng: thêm một directed test hoặc chỉnh constraint trong env sở hữu nó; một bin chỉ được exclude khi có lý do viết ra.
- [ ] **Step 3:** Chạy lại → 0 failure (SC1), 100 % số bin đã khai báo (SC2).
- [ ] **Step 4:** Viết nháp `ch_verification.md`; mỗi sinh viên viết phần env của mình, `soc_env` viết chung.
- [ ] **Step 5: Commit** `test: Phase 2 D0 regression and coverage closed` và gắn tag `phase2-d0`.

## Exit checklist của Phase 2

- [ ] Task 13–18 xanh trong `run.py`, kể cả các test Review Focus 1–5 hoạt động như mô tả
- [ ] SC1 trên D0: 0 mismatch ở scoreboard, 0 assertion fail, mọi test expected-fail chỉ fail vì đúng lý do đã nêu
- [ ] SC2: 100 % số bin ở §10.5 (trừ các exclusion đã ký) trên D0, report nằm ở `out/<date>/d0/cov/`
- [ ] `manifest.yaml` cập nhật; tag `phase2-d0` đã push
- [ ] Đã viết nháp `docs/report/ch_verification.md`
