# Mini-NPU Phase 1 (Tuần 1–4): Implementation Plan (bản tiếng Việt)

> **Bản dịch để đọc cho dễ.** Bản chuẩn là bản tiếng Anh `docs/superpowers/plans/2026-10-04-mini-npu-phase1.md`. Khi hai bản khác nhau, bản tiếng Anh thắng. Dịch ngày 2026-10-29 (commit ngay sau `a2b3a97`). Tên task, tên test, tên file, lệnh, câu commit và thuật ngữ kỹ thuật giữ nguyên tiếng Anh.

> **Cho agent:** BẮT BUỘC dùng sub-skill superpowers:subagent-driven-development (khuyến nghị) hoặc superpowers:executing-plans để làm plan này theo từng task. Các step dùng cú pháp checkbox (`- [ ]`) để theo dõi.
>
> **Luật của dự án (ghi đè dòng trên đối với phần được chấm điểm):** sinh viên tự viết toàn bộ RTL, logic golden model, UVM và firmware. Claude review dựa trên các test được nêu ở đây. Các task gắn **[support]** là tooling không chấm điểm, Claude có thể viết khi được yêu cầu.

**Mục tiêu:** Tới cuối tuần 4:
- cổng tool tuần 1 đã đóng;
- core là một pipeline RV32IM + Zicsr + Zifencei + Zbb sạch sẽ, có ITCM/DTCM, port trace RVVI và decode/push custom-0 (test với engine stub);
- MAC engine (D0) pass các directed test so với model tham chiếu C.

**Kiến trúc:** Hai track dùng chung các interface đã freeze ở Task 2. Track A phát triển `rtl/core` tại chỗ và kiểm từng bước bằng `tools/rv32i_check` (ISS Python, mở rộng theo từng extension). Track B làm `model/c/npu_ref.c` trước, rồi tới `rtl/npu/mac_engine.sv`, kiểm bằng một directed testbench SV gọi `npu_ref` qua DPI-C. UVM bắt đầu từ Phase 2.

**Tech stack:** Verilog/SystemVerilog (tập con synthesize được cho RTL), Siemens QuestaSim (licence đầy đủ; UVM, DPI-C, coverage), Vivado 2024.1 xsim (dự phòng), Verilator, Icarus Verilog (chỉ để kiểm nhanh), RISC-V GNU binutils/gcc (`-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32`), C (gcc) cho golden model, Python 3.

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` (duyệt 2026-10-04). Các số mục (§) bên dưới là của spec này.

**Working tree:** `SeniorProject2/` (bố cục trong `README.md`). Đường dẫn tính từ thư mục này.

**Người phụ trách (nhóm quyết định 2026-10-15):** Track A (scalar core, `core_env`) — **Nguyễn Hoàng Công Tấn**. Track B (Matrix/MAC engine, `mac_env`) — **Nguyễn Thế Bảo**. Chung: Task 0 và 2, sau này `soc_env`. Tiêu đề task bên dưới ghi tên track; bảng này là chỗ duy nhất ánh xạ track sang người.

**Lịch (spec D22):** tuần 1 = Thứ Hai 2026-10-12 tới Chủ nhật 2026-10-18, tuần *N* bắt đầu sau đó 7(*N*−1) ngày. Phase 1 (tuần 1–4) kết thúc Chủ nhật 2026-11-08; Phase 2 bắt đầu Thứ Hai 2026-11-09.

| Task | Người phụ trách | Trạng thái |
|---|---|---|
| 0 · Tool gate | Tấn: S1 UVM, S3 coverage, S5 toolchain, S6 xsim · Bảo: S2 DPI-C, S4 Verilator ICG, S7 VCD theo scope | đóng 2026-10-18: S1–S3, S5–S7 pass (`docs/smoke/results.md`); phần Verilator của S4 bị bỏ qua ngày 2026-10-18 theo quyết định nhóm, rồi chạy ngày 2026-10-27 dưới WSL (có warning lint của testbench, xem `docs/smoke/results.md`) |
| 1 · Core cleanup | Track A | xong (`69cd798`) |
| 2 · Week-2 freeze | cả hai (Tấn: `docs/core_isa.md`, W2-1; Bảo: `npu_pkg.sv`, retrain notebook; cả hai ký §6/§7.1) | mở. `rtl/top/npu_pkg.sv` viết ngày 2026-10-23 (Verilator lint sạch; QuestaSim 10.7c `vlog -sv` sạch ngày 2026-10-24, 0 error 0 warning); export đã retrain commit ngày 2026-10-23 (D14, spec O1/O2 đóng); §6/§7.1 **frozen 2026-10-29** (Bảo 2026-10-26, Tấn 2026-10-29); còn mở: W2-1 (Tấn, `docs/core_isa.md` §4) |
| 2b · `golden_int8.py` | Bảo | xong 2026-10-23 (`model/py/golden_int8.py`, 13 test, có đối chiếu tile với `npu_ref`; notebook import nó, các byte export không đổi) |
| 3 · Complete RV32I | Track A (Tấn tiếp quản, xem bước bàn giao bên dưới) | xong (`c413abd`) |
| 4 · Extend reference ISS | Claude **[support]** | xong (`0d7b38c`, 2026-10-20) |
| 5, 6, 7, 9, 12 · M, Zicsr, Zifencei/Zbb, custom-0 push, `rv_iss.c` | Tấn | Claude cài đặt theo yêu cầu của Tấn, 2026-10-20: 5 `040e81c`, 6 `ef773fc`, 7 `3d4fede`, 9 `95e5091`, 12 `fbc3fd5`. **Tấn vẫn phải review và bảo vệ được chúng** (báo cáo: `docs/reports/2026-10-20-track-a-phase1.md`). |
| 8 · ITCM/DTCM/MMIO/RVVI | Tấn: LSU của core, ITCM, SIM MMIO, RVVI · Bảo: `dtcm_dp` (port B là interface của engine) | phần của Tấn xong (`6280c97`, 2026-10-20) trên một DTCM tạm chỉ có port A; `dtcm_dp` viết ngày 2026-10-23 (`rtl/mem/dtcm_dp.sv`, test `tb/directed/dtcm_dp_tb.sv` gồm `dtcm_last_word` và `dtcm_port_b_quad`, `make -C sim/verilator test_dtcm_dp`); **xong 2026-10-29**: `dtcm_dp` thay DTCM tạm trong `core_tb_top` (xoá `core_tb_dtcm.sv`), `run_all.py` 1291/1291, một mutant ở đường đọc port A của `dtcm_dp` làm fail 6 test memory |
| 10, 11 · `npu_ref.c`, `mac_engine` D0 | Bảo | 10 xong 2026-10-17; 11 đang mở, bắt đầu dựa trên freeze đề xuất (D20), thứ tự build ở mục Task 11; hạn cuối tuần 4, Chủ nhật 2026-11-08 (D22) |

**Bàn giao (Tấn, trước Task 5):** RTL của Task 3 do Claude viết, còn lịch sử core là của Bảo. Tấn đọc `docs/core_isa.md` và `docs/core_stall.md`, chạy `python tools/rv32i_check/run_all.py` (kỳ vọng: ISA 45/45 (44 cộng `jalr_funct3_is_nop`, thêm ở Task 12), hazard 25/25, random 300/300; toàn bộ `run_all.py` gồm 8 suite, 1291 kết quả ngày 2026-10-27), rồi giải thích từng thay đổi của Task 3 cho Bảo. Xong khi Tấn lần theo được một lệnh `jalr` và một load-use stall đi qua pipeline mà không cần xem ghi chú.

**Việc tiếp theo (Bảo đặt ngày 2026-10-26).** Mỗi sinh viên làm theo danh sách này; "xong khi" nêu test hoặc file chứng minh mục đó. Không mục nào chờ chữ ký (spec D20).

*Tấn (Track A), theo thứ tự:*

1. **Review bàn giao** (đoạn trên), giờ bao gồm cả Task 5, 6, 7, 9 và 12. Đọc `docs/reports/2026-10-20-track-a-phase1.md`, rồi sẵn sàng giải thích các test Review Focus: `div_in_branch_shadow`, `mul_x0` (`tests_m.py`), `csrrw_x0_still_writes_csr`, `csr_raw_back_to_back` (`tests_csr.py`), `push_in_branch_shadow`, `read_result_x0_still_drains` (`tests_custom.py`). Xong khi: với mỗi test, Tấn nói được nguồn stall hay flush nào thắng, và vì sao lệnh trẻ hơn không write back hay push, mà không cần ghi chú.
2. **Ghi W2-1** (lệnh illegal và không hỗ trợ, truy cập ngoài vùng). Các phương án nằm ở `docs/core_isa.md` §4; Tấn viết nháp (dòng Task 2) và cả hai ký. Xong khi: phương án được chọn và ngày quyết định được ghi ở `docs/core_isa.md` §4, ở spec §4.1 và trong nhật ký quyết định của spec, và `rvvi_trap`, `rv_iss` cùng `RefISS` làm theo nó. Trước lúc đó, `fence`, `ecall`, `ebreak` và các encoding không biết vẫn là NOP.
3. **Xong 2026-10-29 (§6/§7.1 frozen).** **Review §6/§7.1 so với core** và tick ô của mình ở header spec, hoặc viết thay đổi mong muốn thành một mục spec có ngày. Tấn kiểm bốn điều: D16 (core đẩy op ILLEGAL với bất kỳ giá trị nào trong `rs1`/`rs2`; test `illegal_funct3`), D17 (giá trị CSR write và luật `csr_we` khớp `CSR_Unit.v`; test `csr_ops_all6`, `csrrw_x0_still_writes_csr`), D18 (bộ đồng bộ reset nằm ở `npu_top`, Phase 2 Task 14) và D21 (`csr_rdata` là tổ hợp theo `csr_addr`, điều mà `CSR_Unit.v` đã giả định; nó giải quyết ruling 2 trong `docs/core_isa.md` §7). Đây không phải cổng chặn Task 11 (D20).
4. **Xong 2026-10-29.** **Thay `dtcm_dp` vào `core_tb_top.sv`** ở chỗ DTCM tạm chỉ có port A `core_tb_dtcm.sv` (dòng Task 8; Tấn chọn làm bây giờ hay ở Task 14). Việc này đổi instance và `peek` trong `core_tb_top.sv`, đổi `mem[k]` thành `peek(k)` trong `tb_dump.v`, và đổi file list trong `run.py` ([support]: Claude làm được hai việc sau khi được yêu cầu). Xong khi: `python tools/rv32i_check/run_all.py` kết thúc bằng `RESULT: PASS`.
5. **Bắt đầu Phase 2 Task 13** (firmware nền). Nó chạy trên `core_tb_top` với engine stub và không dùng RTL của engine, nên có thể bắt đầu ngay khi xong mục 1–3.

*Bảo (Track B), theo thứ tự:*

1. **Task 11**, theo thứ tự build ghi trong task đó. Nó dùng `dtcm_model.sv` dạng behavioural và `npu_ref`, nên không cần core của Tấn.
2. **Phase 2 Task 16** (khung `mac_env`) khi Task 11 Step 4 đã xanh, và **Task 14** (`npu_top`, phía engine) cùng với Tấn.

*Chung:* không có gì bị chặn. Exit checklist của Phase 1 ở cuối plan này vẫn là định nghĩa "Phase 1 xong"; dòng "Spec frozen" của nó cần cả hai tick.

## Ràng buộc chung

- Opcode custom `custom-0 = 0001011`. funct3: `000` LOAD_WEIGHT, `001` LOAD_INPUT, `010` COMPUTE (`funct7[0]` = clr), `011` READ_RESULT, `100–111` reserved → op ILLEGAL (§6.1).
- Encoding op của engine trên `cmd_op[1:0]`: `0` LDW, `1` LDI, `2` MAC, `3` ILLEGAL (§7.1).
- Số học: signed int8 × signed int8 → int32, wrap mod 2³² (§3.1 D5).
- Kích thước engine N×M×K = 4×4×4 (PE dot4, 64 MAC/cycle). `KMAX = 1024` phần tử int8; K phải là bội của 4; WBUF/IBUF = 256 entry × 128 bit. `FIFO_DEPTH = 8`, `DTCM_BASE = 0x0001_0000`, `DTCM_BYTES = 65536`, DTCM = 4 bank × 32 bit, port B 128 bit (§3.1 D10, §4.2).
- Memory map: ITCM `0x0000_0000` 16 KB; DTCM `0x0001_0000` 64 KB; `SIM_CTRL` `0x0002_0000` (`0x1` PASS, `0x2` FAIL, `0x10` BATCH_DONE, `0x20` MEAS_START, `0x21` MEAS_STOP); `SIM_PUTC` `0x0002_0004` (§4.1).
- CSR: `mcycle/mcycleh` 0xB00/0xB80, `minstret/minstreth` 0xB02/0xB82, alias chỉ đọc 0xC00/0xC02/0xC80/0xC82, `npu_status` 0x7C0, `npu_busy_cyc` 0x7C1 (§5, §6.4).
- Bit của `npu_status`: 0 busy, 1 fifo_empty, 2 fifo_full, 8 err_k, 9 err_addr, 10 err_illegal, 11 err_align (bit 8–11 sticky, W1C) (§6.4).
- Thứ tự lane: lane *t* = bit `[8t+7:8t]`; một quad (16 B) chứa word *i* = 4 phần tử liên tiếp của row/ảnh *i*; address LOAD align 16 byte; chỉ số READ_RESULT `idx = 4*i + j` (§6.2).
- Custom instruction được đẩy vào FIFO ở **MEM**; READ_RESULT stall ở MEM cho tới khi `fifo_empty && fsm==IDLE` và write back như một lệnh load (§6.3).
- Số liệu power là "switching-activity estimate", không bao giờ là "measured power" (§1).
- Không chép RTL hay code testbench của CoralNPU (§16).

## Review Focus

1. **Các nguồn stall/flush chồng nhau:** stall của bộ chia, load-use stall, stall do FIFO đầy hoặc READ_RESULT, và flush do branch được lấy có thể cùng xảy ra trong một cycle. Kỳ vọng: lệnh cũ nhất thắng; lệnh trẻ hơn không bao giờ write back hay push. Test: Task 5 `div_in_branch_shadow`, Task 9 `push_in_branch_shadow`.
2. **x0 làm đích của các lệnh mới:** `mul x0,…`, `csrrw x0,…` và `READ_RESULT x0,…` không được ghi x0. CSR write và việc drain của READ_RESULT vẫn phải xảy ra. Test: Task 5 `mul_x0`, Task 6 `csrrw_x0_still_writes_csr`, Task 9 `read_result_x0_still_drains`.
3. **Đọc CSR ngay sau khi ghi:** `csrw` theo ngay sau là `csrr` cùng CSR, và một lệnh ALU dùng kết quả CSR ở slot kế tiếp. Kỳ vọng: giá trị mới, qua forwarding. Test: Task 6 `csr_raw_back_to_back`.
4. **Tràn khoảng address của LOAD:** `a + 4K` có thể wrap qua 2³² (ví dụ `a = 0xFFFF_FFF0`, `K = 8`). Kỳ vọng: `err_addr`, lệnh bị bỏ. Phép check không được dùng số học 32 bit có wrap. Test: Task 10 `load_addr_wraps_32bit`, Task 11 `load_addr_wraps_32bit`.
5. **`COMPUTE` với K = 0 và clr = 1:** K = 0 là no-op với LDW, LDI và MAC (§6.3, D16), nên accumulator **không** bị xoá. Test: Task 10 `compute_k0_clr_keeps_acc`, Task 11 cũng vậy.

---

## Lộ trình các phase (Phase 2–4 đã lên kế hoạch chi tiết ngày 2026-10-15)

| Phase | Tuần | File plan | Điều kiện kết thúc |
|---|---|---|---|
| **1 (plan này)** | 1–4 | `2026-10-04-mini-npu-phase1.md` | Task 0–11 và 2b xong |
| 2 | 5–9 | `2026-10-15-mini-npu-phase2-uvm-integration.md` | `npu_top` đã tích hợp; các env UVM mac/core/soc; coverage đã đóng (SC1, SC2) |
| 3 | 10–12 | `2026-10-15-mini-npu-phase3-gating-power.md` | D1 giống D0 từng cycle (SC3); dữ liệu switching E2 (SC4) |
| 4 | 13–16 | `2026-10-15-mini-npu-phase4-mnist-report.md` | MNIST bit-exact (SC5); E4; gói tái lập (SC6); báo cáo |

**Rủi ro lịch (đã cảnh báo):** trong tuần 3–4, Track A gánh Task 5, 6, 7, 8, 9 và 12, cộng với việc Tấn nhận bàn giao một core mà Tấn không viết. Đây là đoạn dày nhất của dự án. `dtcm_dp` được chuyển sang Track B để giảm tải. Nếu Task 12 (`rv_iss.c`) trễ, nó có thể dời sang tuần 5, vì `core_env` của Phase 2 chỉ cần nó từ tuần 5. Track B bắt đầu muộn: Task 10 có hạn ở tuần 2, nên Bảo bắt đầu nó ngay và Task 11 không còn dư thời gian. Task 2b (thêm ngày 2026-10-21) cộng thêm khoảng nửa ngày (ước lượng) cho Track B trong cùng mấy tuần đó. Nó là việc đầu tiên được hoãn nếu Task 11 trễ, vì chỉ Phase 4 dùng `golden_int8.py` (Phase 2 và 3 không nhắc tới nó); hạn cứng của nó là đầu tuần 13 (Task 25). Không việc gì khác được trễ quá tuần 4 mà không lên kế hoạch lại.

---

### Task 0: Cổng tool tuần 1 (S1–S7) — cả hai sinh viên, tuần 1

**File:**
- Tạo: `sim/questa/smoke/uvm_hello.sv`, `sim/questa/smoke/dpi_add.c`, `sim/questa/smoke/dpi_tb.sv`, `sim/questa/smoke/cov_tb.sv`, `sim/questa/smoke/vcd_scope.do`, `sim/questa/smoke/run.do`, `sim/verilator/smoke/icg_tb.sv`, `sim/verilator/smoke/count_toggles.py`, `sw/smoke/t.S`
- Tạo: `docs/smoke/results.md` (mỗi check một dòng: lệnh, output quan sát được, ✅/❌, đường dẫn log)

**Interface:**
- Tạo ra: xác nhận licence QuestaSim của nhóm chạy được UVM có `randomize`/`covergroup` (spec O3), loại licence ghi trong `docs/smoke/results.md`, và các lệnh tool chính xác mà các phase sau dùng lại.

- [ ] **Step 1 (S1, QuestaSim UVM):** một `hello_test extends uvm_test` có `run_phase` randomize một class nhỏ (`rand bit [7:0] x; constraint c { x < 10; }`) rồi in ra bằng `` `uvm_info("HELLO", ...) ``.
  Chạy (flow thường gặp): `vlib work`, `vlog -sv uvm_hello.sv` (Questa có sẵn UVM đã compile; nếu không thấy `uvm_pkg`, thêm `+incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv`), `vsim -c tb_top +UVM_TESTNAME=hello_test -do "run -all; quit"`.
  Kỳ vọng: một dòng `[HELLO]` với giá trị < 10 và `UVM_ERROR :    0`. Lỗi checkout "verification license" nghĩa là licence là bản FPGA (spec O3). ⚠️ Flag chính xác thay đổi theo phiên bản Questa; ghi lại cái đã chạy được.
- [ ] **Step 2 (S2, QuestaSim DPI-C):** `int c_add(int a, int b)` bằng C, `import "DPI-C" function int c_add(input int a, input int b);` bằng SV, `$display("%0d", c_add(2,3))`.
  Output kỳ vọng: `5`. Ghi lại đường compile đã dùng (đưa file `.c` cho `vlog`, hoặc thư viện dùng chung qua `vsim -sv_lib`).
- [ ] **Step 3 (S3, report coverage):** một covergroup có một coverpoint và 4 bin tường minh. Sample các giá trị trúng đúng 2 bin.
  Chạy với `vsim -coverage`, rồi `coverage save cov.ucdb` và `vcover report cov.ucdb`. Kỳ vọng: covergroup hiện 50.00 %.
- [ ] **Step 4 (S4, Verilator ICG):** một `icg_cell` đồ chơi (latch + AND, §8), `en` thấp ở cycle 10–19.
  Chạy: `verilator --lint-only -Wall icg_tb.sv`, rồi `verilator --binary --trace icg_tb.sv`.
  Kỳ vọng: lint sạch, và `count_toggles.py` báo 0 toggle của `gclk` trong cycle 11–19 và 2 toggle mỗi cycle ở chỗ khác.
- [ ] **Step 5 (S5, toolchain):** `t.S` chứa `max a0, a1, a2` và `.insn r 0x0B, 0, 0, x0, a0, a1`.
  Chạy: `<prefix>gcc -march=rv32im_zicsr_zifencei_zbb -mabi=ilp32 -c t.S && <prefix>objdump -d t.o`.
  Kỳ vọng: `max` disassemble được, và word của `.insn` là `0x00b5000b`. Sau đó `objcopy -O verilog` sinh file hex mà `$readmemh` chấp nhận.
- [ ] **Step 6 (S6, dự phòng xsim):** chạy file của Step 1 trên Vivado xsim 2024.1 (`xvlog -sv -L uvm`, `xelab -L uvm`, `xsim -R -testplusarg UVM_TESTNAME=hello_test`). Ghi pass/fail; đây là phương án dự phòng nếu licence Questa bị giới hạn.
- [ ] **Step 7 (S7, QuestaSim VCD theo scope):** một script `.do` với `vcd file engine.vcd`, `vcd add -r /tb_top/dut/*`, `run 1us`, `vcd flush`.
  Kỳ vọng: VCD chỉ chứa tín hiệu của scope đó.
- [ ] **Step 8:** Điền `docs/smoke/results.md`. Ghi loại licence và đóng O3 ở spec §3.2. Nếu S1–S3 pass, cập nhật Bảng 1, 3, 9, 11 và 12 của proposal (QuestaSim + UVM thay cho Verilator/cocotb; marimo thay cho PyTorch).
- [ ] **Step 9: Commit:** `git init` (chỉ lần đầu), rồi `git add -A && git commit -m "chore: week-1 tool gate results"`.

---

### Task 1: Dọn core (gỡ phần dính với Senior Project 1) — Track A, tuần 1–2

**File:**
- Sửa: `rtl/core/RISC_V_Top.v` (bỏ instance `workload_monitor` và các port `workload_*`)
- Sửa: mọi file `rtl/core/**` có port `cpu_en` (chỉ khi quyết định là "bỏ")
- Xoá: `rtl/core/RISC_V_Impl_Top.v`. Chuyển `rtl/core/RISC_V_Fixed_Impl_Top.v` sang `rtl/fpga/` (cho khoá luận).

**Interface:**
- Tạo ra: `RISC_V_Top(clk, reset, …)` không có port DFS. `cpu_en` hoặc bị bỏ, hoặc buộc `1'b1` ở top. Ghi lại lựa chọn trong `docs/core_isa.md` (Task 2).

- [ ] **Step 1:** Chạy `python tools/rv32i_check/run_all.py`. Kỳ vọng: baseline ISA 30/40, hazard 25/25, random 300/300.
- [ ] **Step 2:** Bỏ instance và các port. Áp dụng quyết định về `cpu_en`.
- [ ] **Step 3:** `grep -ri "workload\|q_agent\|dfs" rtl/core` không ra gì. Xoá `tools/rv32i_check/stub_workload_monitor.v`.
- [ ] **Step 4:** Chạy lại `run_all.py`. Kỳ vọng: các con số giống Step 1. Harness giờ phải build được **mà không cần** stub.
- [ ] **Step 5: Commit** `refactor(core): remove Senior Project 1 DFS coupling`.

---

### Task 2: Freeze tuần 2 — cả hai sinh viên, tuần 2

**File:**
- Tạo: `docs/core_isa.md`. File này chứa bảng encoding cho mọi lệnh core sẽ hỗ trợ, CSR map, policy W2-1 (lệnh illegal, truy cập ngoài vùng) và quyết định về `cpu_en`.
- Tạo: `rtl/top/npu_pkg.sv`. File này chứa các parameter ở §4.2, `typedef enum logic [1:0] {OP_LDW=2'd0, OP_LDI=2'd1, OP_MAC=2'd2, OP_ILLEGAL=2'd3} npu_op_e;`, và các địa chỉ CSR dưới dạng `localparam`.
- Sửa: spec §3.2 (ghi lựa chọn requant O1, và đóng O2 với `M`, `S` từng layer sau khi retrain cùng accuracy float/int8), spec §4.1 (W2-1), trạng thái spec → "frozen §6, §7.1". Văn bản công thức ở §9.3 giữ nguyên; Task 2b đổi nguồn được ghi của nó sang `golden_int8.py`.

**Interface:**
- Tạo ra: `npu_pkg` (được import bởi mọi file SV trong `rtl/npu`, `rtl/top` và `tb/`); spec §6 và §7.1 đã freeze.

- [ ] **Step 1:** Retrain `notebooks/MiniNPU_MLP.py` với `layer_sizes=[784, 64, 32, 10]` (model của spec). Đặt `Config.export_dir` là `model/py/export` (D14), tính từ chính thư mục của notebook để không phụ thuộc thư mục làm việc của kernel, và chạy pipeline từ giao diện marimo. Export gồm weight, bias, `requant.json`, test vector và `manifest.json`. Kiểm `M`, `S` đã export theo luật ở §9.3 (`S` lớn nhất thoả `bound·M + 2^(S−1) ≤ 2³¹−1`) và ghi `M`, `S` từng layer cùng accuracy float/int8 vào spec §3.2 O2. Commit export cùng lần sửa spec đó; trong cùng commit, xoá các ghi chú "export not committed yet" ở spec §9.2, ở bảng known-issues của spec và ở `CLAUDE.md` §10: `feat(model): retrained 784-64-32-10 export`.
- [ ] **Step 2:** Viết `docs/core_isa.md` và `rtl/top/npu_pkg.sv`. `npu_pkg.sv` phải compile được: chạy `vlog -sv rtl/top/npu_pkg.sv` trên QuestaSim (sạch) và `verilator --lint-only -Wall` trên nó (sạch). Một package đứng riêng không có top module và Verilator 5.020 từ chối nó, nên lint nó cùng với một module nào đó import nó (tạm thời là một wrapper dùng một lần, sau này là `rtl/npu/*.sv` của Task 11).
- [ ] **Step 3:** Cả hai sinh viên đọc §6 và §7.1 rồi ký ở header spec ("Frozen 2026-10-xx by A, B"). Từ lúc này, thay đổi cần cả hai chữ ký.
- [ ] **Step 4: Commit** `docs: freeze ISA and engine interface`.

---

### Task 2b: `golden_int8.py` — Track B, tuần 3–4

Thêm ngày 2026-10-21 (spec D14, D15). SC5 và Phase 4 nhắc tới `golden_int8.py`, nhưng chưa task nào tạo ra nó; trước giờ `IntModel` trong notebook đóng vai tham chiếu số nguyên. Task này chuyển tham chiếu đó vào một file import được và cho nó unit test riêng, điều §10.2 yêu cầu trước khi dùng bất kỳ oracle nào.

**File:**
- Tạo: `model/py/golden_int8.py`, `model/py/tests/test_golden_int8.py`
- Sửa: `notebooks/MiniNPU_MLP.py` (import các hàm đã chuyển đi; `quantize_weight`, `quantize_bias` và code training giữ lại)
- Sửa: spec §9.3 (nguồn được ghi của công thức), spec §10.2 (một câu về `golden_int8.py` và cổng của nó), dòng rủi ro "Requant mismatch with golden", `docs/glossary.md` (danh sách ví dụ "Golden model"), `CLAUDE.md` §10 (bỏ ghi chú về `golden_int8.py`)

**Interface:**
- Dùng: `model/py/export/` đã commit (Task 2 Step 1); `model/c/npu_ref.h` (Task 10).
- Tạo ra (numpy thuần, không torch; chuyển nguyên từ notebook trừ chỗ có ghi chú):
  ```python
  def quantize_input(p: np.ndarray) -> np.ndarray: ...            # int8 in 0..127, spec §4.1: (p*254 + 255) // 510
  def requant(acc: np.ndarray, M: int, S: int) -> np.ndarray: ...  # int8, clamp((acc*M + 2**(S-1)) >> S, 0, 127), arithmetic shift
  def find_ms(real: float, bound: int) -> tuple[int, int]: ...     # largest S with M >= 1 and bound*M + 2**(S-1) <= 2**31 - 1
  def compute_bound(w_q: np.ndarray, b_q: np.ndarray) -> int: ...  # max_j (sum_i |w_q[j][i]|*127 + |b_q[j]|)
  class IntModel:
      def __init__(self, quant: dict): ...                          # quant[i] = {'w_q', 'b_q', 'M', 'S'}; M, S are None on the last layer
      def forward(self, x_int: np.ndarray) -> dict: ...             # act1, act2, logit (int32, padded rows kept), label = argmax(logit[:, :10])
  def load_export(export_dir: str) -> tuple[dict, dict]: ...       # (quant, manifest) read from the .mem files, requant.json, manifest.json
  ```
  Khác biệt so với notebook: `IntModel` không nhận `config` nữa (số layer là `len(quant)`); `load_export` thay cho hai bản sao của hàm đọc file trong các cell round-trip và interactive của notebook.

- [ ] **Step 1: Viết các test fail** trong `test_golden_int8.py`:
  - `requant_hand_vectors`: `(acc, M, S) → y`: `(10,1,1)→5`, `(−5,1,1)→0`, `(1000,1,3)→125`, `(2000,1,3)→127`, `(7,1,2)→2`
  - `requant_matches_python_int` (Phase 4 Review Focus 1): ≥ 10.000 bộ `(acc, M, S)` ngẫu nhiên với `|acc|·M + 2^(S−1) ≤ 2³¹−1`, có cả `acc` âm và các giá trị có `(acc·M) mod 2^S = 2^(S−1)`; `y == min(127, max(0, (acc*M + 2**(S-1)) >> S))` tính bằng int Python
  - `input_quant_all_pixels`: với mọi `p` trong 0..255, `quantize_input(p) == (p*254 + 255)//510`; `0 → 0`, `2 → 1`, `255 → 127`
  - `bound_hand_case`: `w_q = [[127,127,127,−127],[−127,127,−127,127]]`, `b_q = [1000,−1000]` → `65516`
  - `find_ms_is_largest_s`: với 1.000 bộ `(real, bound)` ngẫu nhiên, `real` trong [1e-4, 1e-1] và `bound` trong [10³, 10⁷]: `M ≥ 1`, `bound·M + 2^(S−1) ≤ 2³¹−1`, và với `M' = round(real·2^(S+1))` thì `S` kế tiếp vi phạm bound
  - `forward_matches_python_int`: `quant` 3 layer ngẫu nhiên với shape thật (784-64-32-12, `w_q` trong ±127, `M`, `S` lấy từ `find_ms`); `forward` trên 20 input ngẫu nhiên và trên input toàn 127 bằng với một vòng lặp int Python thuần cho `act1`, `act2`, `logit`
  - `forward_worst_case_no_wrap`: `quant` một layer, `x` = 784 × 127, một row của `w_q` = 784 × 127, `b_q = 0` → `logit == 12,645,136 == compute_bound`, không wrap
  - `argmax_ignores_padding` (Phase 4 Review Focus 3): đặt logit ở row 10–11 cao hơn mọi row 0–9; `label` không đổi và nằm trong 0..9
  - `export_roundtrip`: `load_export('model/py/export')` rồi `forward(testvec_input)` bằng `testvec_expected.npz` trên `act1`, `act2`, `logit[:, :10]`, `label`; SHA-256 của mọi file bằng `manifest.json`
  - `export_requant_matches_rule`: với fc1 và fc2, `find_ms(s_x·s_w/s_y, bound)` từ `manifest.json` bằng `requant.json`, và `bound` bằng `compute_bound` của weight đã export
  - `golden_tile_matches_npu_ref`: build `model/c/npu_ref.c` bằng `gcc -shared` của máy host vào `build/` và nạp bằng `ctypes`; với row 0–3 của W1 và ảnh test 0–3 (K = 784, layout quad ở §6.2, chỉ số `READ_RESULT` `4*i + j`), tile của engine `C[i][j]` bằng `W1[i]·x[j]` (engine không cộng bias)
- [ ] **Step 2:** Chạy `python -m pytest model/py/tests -v` → FAIL (`golden_int8` không import được).
- [ ] **Step 3:** Cài đặt `model/py/golden_int8.py`: chuyển năm định nghĩa từ notebook sang và viết `load_export` (file `.mem` theo thứ tự row-major `[out][in]`, int8 là 2 chữ số hex, int32 là 8; shape lấy từ `manifest['layer_sizes']` và `manifest['fc3_pad']`).
- [ ] **Step 4:** Chạy lại cùng lệnh → tất cả pass; trích dòng tóm tắt.
- [ ] **Step 5:** Trong notebook, đưa `model/py` vào `sys.path` (tính từ thư mục của notebook), import các hàm đã chuyển, xoá định nghĩa của chúng và các test notebook chỉ phủ chúng, và thay cả hai hàm đọc file bằng `load_export`. Chạy lại pipeline từ giao diện marimo. Kỳ vọng: các unit test còn lại, cell round-trip và cell kiểm tái lập đều pass, và `git diff --stat model/py/export` rỗng (refactor không đổi byte export nào).
- [ ] **Step 6: Commit** `feat(model): golden_int8 reference with unit tests`. Trong cùng commit: spec §9.3 ghi `model/py/golden_int8.py` (hàm `requant`, `find_ms`) là nguồn của công thức, dòng rủi ro "Requant mismatch with golden" trỏ tới `golden_int8.requant` thay vì bản trong notebook, spec §10.2 có thêm một câu về file và cổng của nó, và dòng "Golden model" trong glossary liệt kê `golden_int8.py` thay cho "notebook int8".

---

### Task 3: Hoàn thiện RV32I — Track A, tuần 3

**File:**
- Sửa: `rtl/core/StageDecode/Control.v`, `rtl/core/StageExecute/ALU.v`, `rtl/core/StageExecute/Branch_Comparator.v`
- Sửa **[support]**: `tools/rv32i_check/tests_hazard.py` (thêm các lệnh mới vào `SUP_R`, `SUP_I` và danh sách branch)

**Interface:**
- Dùng: `RISC_V_Top` đã dọn ở Task 1.
- Tạo ra: đủ RV32I base. Mã op mới của ALU lấp các giá trị còn trống của `alu_operation` 4 bit. Ghi chúng vào `docs/core_isa.md`.

- [ ] **Step 1:** Các test fail đã có sẵn trong `tools/rv32i_check/tests_isa.py`: `slt sltu sra slti sltiu slli srli srai bltu bgeu`. Chạy `python tools/rv32i_check/tests_isa.py`. Kỳ vọng: `30 / 40`.
- [ ] **Step 2:** Thêm các corner test này vào `tests_isa.py` (mỗi test so RTL với ISS):
  - `slt_vs_sltu_sign`: `x1=0x80000000, x2=1` → `slt`=1, `sltu`=0
  - `sltiu_minus1`: `sltiu x3,x1,-1` → 1 với `x1 ≠ 0xFFFFFFFF`
  - `srai_negative`: `srai` của `0x80000F0F` dịch 4 → `0xF80000F0`
  - `bltu_bgeu_sign`: `bltu 0x80000000, 1` không nhảy; `bgeu` nhảy
- [ ] **Step 3:** Cài đặt decode, các op ALU và phép so sánh không dấu của branch.
- [ ] **Step 4:** Chạy `run_all.py`. Kỳ vọng: ISA **44/44** (40 + 4 corner test; 45 kể từ khi Task 12 thêm `jalr_funct3_is_nop`), hazard 25/25, random 300/300 với bộ sinh đã mở rộng.
- [ ] **Step 5: Commit** `feat(core): complete RV32I base`.

---

### Task 4 [support]: Mở rộng rv32i_check cho M, Zicsr, Zifencei, Zbb và memory map mới — tuần 3

**File:**
- Sửa: `tools/rv32i_check/run.py`. Đổi tên class `ISS` → `RefISS`. Thêm M, Zicsr (`minstret` mô hình chính xác; đọc `mcycle` thì mask), Zifencei (no-op), Zbb, và custom-0 ở mode stub (READ_RESULT → `idx`; LDW/LDI/MAC → ghi `(op, addr, k, clr)` vào `RefISS.cmd_log`). Thêm công tắc memory map, `MEMMAP = "sp1"` (bản 1 KB/1 KB hiện tại) hoặc `"spec"` (ITCM 16 KB, DTCM 64 KB tại `0x0001_0000`). *(Đã thay thế: công tắc bị bỏ cùng với map SP1 ở 6280c97; harness chỉ chạy map của spec.)*
- Sửa: `tools/rv32i_check/tb_dump.v`. Cho các đường dẫn hierarchy chọn được bằng `` `define`` để theo được Task 8.
- Tạo: `tools/rv32i_check/tests_m.py`, `tests_csr.py`, `tests_zbb.py`, `tests_custom.py` (nội dung test liệt kê ở Task 5–9).

**Interface:**
- Tạo ra: `compare(src, tag, steps, cycles, quiet, march="rv32im_zicsr_zifencei_zbb") -> list[str]`, và `RefISS.cmd_log: list[tuple[int,int,int,int]]`.

- [ ] **Step 1:** Unit-check `RefISS` với giá trị tính tay cho mọi test vector của Task 5–7 trước khi dùng nó làm tham chiếu.
- [ ] **Step 2: Commit** `test(tools): extend reference ISS`.

---

### Task 5: M extension — Track A, tuần 3

**File:**
- Tạo: `rtl/core/StageExecute/Multiplier.v` (1 cycle, `MUL/MULH/MULHSU/MULHU`), `rtl/core/StageExecute/Divider.v` (radix-2 lặp, ~32 cycle, `start/busy/done`)
- Sửa: `Control.v`, `StageExecute_Top.v`, `Hazard_Unit.v` (thêm stall `div_busy`)
- Test: `tools/rv32i_check/tests_m.py`

**Interface:**
- Tạo ra: `Divider(clk, reset, start, is_signed, is_rem, a[31:0], b[31:0], busy, done, result[31:0])`; input `div_busy` của `Hazard_Unit`.

- [ ] **Step 1: Viết các test fail** trong `tests_m.py` (RTL so với `RefISS`):
  - `mul_corners`: `(0x80000000,0x80000000)`, `(-1,-1)`, `(0x7FFFFFFF,2)` cho từng lệnh `mul mulh mulhsu mulhu`
  - `div_by_zero`: `div`/`divu` chia 0 → `0xFFFFFFFF`; `rem`/`remu` chia 0 → số bị chia
  - `div_overflow`: `div -2^31,-1` → `0x80000000`; `rem` → `0`
  - `div_signs`: `div -7,2` → `-3`; `rem -7,2` → `-1`; `div 7,-2` → `-3`; `rem 7,-2` → `1`
  - `div_back_to_back_dep`: `div x3,…` theo ngay sau là `add x4,x3,x3`
  - `div_in_branch_shadow`: `beq` được lấy, theo sau là một `div` không được write back (Review Focus 1)
  - `mul_x0`: `mul x0,x1,x2` giữ x0 = 0 (Review Focus 2)
  - random: 300 seed có trộn lệnh M
- [ ] **Step 2:** Chạy. Kỳ vọng: FAIL (chưa decode M).
- [ ] **Step 3:** Cài đặt. Bộ chia stall IF/ID/EX trong lúc busy. Kết quả vào pipeline ở EX/MEM giống một kết quả ALU.
- [ ] **Step 4:** Chạy `tests_m.py` và `run_all.py`. Kỳ vọng: tất cả pass, và các test base vẫn xanh.
- [ ] **Step 5: Commit** `feat(core): M extension`.

---

### Task 6: Zicsr và các counter — Track A, tuần 3–4

**File:**
- Tạo: `rtl/core/StageExecute/CSR_Unit.v`
- Sửa: `Control.v`, `StageExecute_Top.v`, `Forwarding_Unit.v` (forward dữ liệu đọc CSR như một kết quả ALU)
- Test: `tools/rv32i_check/tests_csr.py`

**Interface:**
- Tạo ra: `CSR_Unit(clk, reset, csr_op[2:0], csr_addr[11:0], wdata[31:0], rdata[31:0], retire, npu_csr_we, npu_csr_addr[11:0], npu_csr_wdata[31:0], npu_csr_rdata[31:0])`. Write tới 0x7C0 và 0x7C1 đi ra port `npu_csr_*`: `npu_csr_we` được gate theo address, còn `npu_csr_addr` đi theo immediate của EX ở mọi cycle (spec D21). Task 9 đưa port này ra khỏi `RISC_V_Top` với tên §7.1 là `csr_we`, `csr_addr`, `csr_wdata`, `csr_rdata`.

- [ ] **Step 1: Viết các test fail:**
  - `csr_ops_all6`: `csrrw csrrs csrrc csrrwi csrrsi csrrci` trên một CSR nháp. Dùng 0x7C0 qua stub; stub cài đặt W1C trên bit 8–11 theo §6.4.
  - `minstret_delta`: `csrr a,minstret; <N=5 instrs>; csrr b,minstret` (N = 5 lệnh) → `b-a == 6`
  - `mcycle_ge_minstret`: delta của `mcycle` ≥ delta của `minstret`, kiểm ngay trong chương trình bằng `sltu` vào một register
  - `cycle_alias_reads`: `rdcycle`/`rdinstret` bằng `mcycle`/`minstret` đọc ở cùng vị trí (so có mask)
  - `csrrw_x0_still_writes_csr` (Review Focus 2)
  - `csr_raw_back_to_back` (Review Focus 3)
- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt. **Step 4:** Chạy `tests_csr.py` và `run_all.py` → PASS.
- [ ] **Step 5: Commit** `feat(core): Zicsr and counters`.

---

### Task 7: Zifencei và Zbb — Track A, tuần 4

**File:**
- Tạo: `rtl/core/StageExecute/BitManip.v` (mọi op Zbb ở §5)
- Sửa: `Control.v`, `StageExecute_Top.v`, đường flush cho `fence.i`
- Test: `tools/rv32i_check/tests_zbb.py`

**Interface:**
- Tạo ra: `BitManip(a[31:0], b[31:0], op[4:0], result[31:0])`. Liệt kê encoding op trong `docs/core_isa.md`.

- [ ] **Step 1: Viết các test fail:**
  - `clz_ctz_zero`: `clz 0` = `ctz 0` = 32
  - `cpop_all_ones`: = 32
  - `orc_b`: `0x00010200` → `0x00FFFF00`
  - `rev8`: `0x11223344` → `0x44332211`
  - `sext_b`: `0x80` → `0xFFFFFF80`; `sext_h`, `zext_h` trên `0x8001_8001` (cài đặt thành test `sext_zext`, cộng với `unary_sext_b` được sinh tự động)
  - `rol_ror_0_31`; `rori_31`
  - `max_min_sign`: `max/min` so với `maxu/minu` trên `(0x80000000, 1)`
  - `andn_orn_xnor`
  - `fence_i_flush`: `fence.i` theo sau bởi các lệnh ALU phụ thuộc cho kết quả đúng, và delta `minstret` đếm `fence.i` đúng một lần
  - random: 300 seed có Zbb
- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt. **Step 4:** Chạy → PASS, mọi suite trước đó vẫn xanh.
- [ ] **Step 5: Commit** `feat(core): Zifencei and Zbb`.

---

### Task 8: ITCM/DTCM, SIM MMIO và RVVI trace — Track A; `dtcm_dp` của Track B, tuần 4

**File:**
- Tạo: `rtl/mem/itcm.sv` (16 KB, đọc tổ hợp, backdoor `$readmemh` từ plusarg `+ITCM=<file>`)
- Tạo: `rtl/mem/dtcm_dp.sv` (64 KB chia 4 bank × 32 bit, bank = word address [1:0]; port A đọc/ghi 32 bit có byte enable, đọc 1 cycle; port B chỉ đọc 128 bit (mỗi bank một word), đọc 1 cycle; backdoor `+DTCM=<file>`)
- Tạo: `rtl/top/core_tb_top.sv` (core + itcm + dtcm + decode SIM MMIO + engine stub của Task 9)
- Sửa: đường LSU trong `rtl/core` (định dạng byte lane vẫn nằm trong core; bỏ `Data_Memory.v`/`ProgramMemory.v` cũ); thêm các port output RVVI dưới `` `ifdef RVVI_TRACE ``
- Sửa **[support]**: `tools/rv32i_check` → `MEMMAP="spec"`, cập nhật đường dẫn hierarchy *(công tắc đã bị bỏ ở 6280c97; harness chỉ chạy map của spec)*

**Interface:**
- Tạo ra, port của core:
  - `imem_addr[31:0]`, `imem_rdata[31:0]`
  - `dmem_re`, `dmem_we[3:0]`, `dmem_addr[31:0]`, `dmem_wdata[31:0]`, `dmem_rdata[31:0]`
  - `rvvi_valid`, `rvvi_order[63:0]`, `rvvi_pc[31:0]`, `rvvi_insn[31:0]`, `rvvi_rd[4:0]`, `rvvi_rd_wdata[31:0]`, `rvvi_mem_addr[31:0]`, `rvvi_mem_wdata[31:0]`, `rvvi_mem_wmask[3:0]`, `rvvi_trap`
- Tạo ra, port của `dtcm_dp`:
  - port A: `a_re`, `a_we[3:0]`, `a_addr[13:0]`, `a_wdata[31:0]`, `a_rdata[31:0]`
  - port B (đúng như §7.1): `b_req`, `b_addr[11:0]` (chỉ số quad), `b_rdata[127:0]` (bank 0 ở bit [31:0])

- [ ] **Step 1: Các test fail:**
  - mọi suite trước đó chạy lại trên map của spec (công tắc `MEMMAP` sau này bị bỏ, 6280c97)
  - `dtcm_last_word`: store và load ở `0x0001_FFFC`
  - `dtcm_port_b_quad`: sau các store qua port A vào `0x0001_0010..0x0001_001C`, một lần đọc port B quad 1 trả về 4 word đó theo thứ tự bank
  - `sim_ctrl_pass`: ghi `0x1` vào `0x0002_0000` kết thúc simulation với "PASS"
  - `sim_putc`: `"OK\n"` xuất hiện trong log
  - `rvvi_order_monotonic`: `order` của trace tăng 1 mỗi lần retire, không có khoảng trống sau stall hay flush (kiểm bằng một script Python nhỏ trên bản dump của trace; cài đặt thành `rvvi_order_monotonic_flushes`, `_divider`, `_engine_waits`, `_csr_in_stall` và `rvvi_order_selftest`)
- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt. **Step 4:** Chạy → PASS.
- [ ] **Step 5: Commit** `feat(mem,core): ITCM/DTCM, SIM MMIO, RVVI trace`.

---

### Task 9: Decode và push custom-0 với engine stub — Track A, tuần 4

**File:**
- Tạo: `rtl/top/npu_stub.sv` (luôn ready, hoặc ready theo mẫu plusarg `+STUB_READY=<bitstring>`; log mỗi lần push dạng `PUSH op addr k clr`; `rd_ready=1`, `rd_data={28'b0,rd_idx}`; đọc CSR trả 0)
- Sửa: `Control.v` (decode §6.1), `StageMemory_Top.v` (push ở MEM; stall khi `!cmd_ready`; READ_RESULT stall khi `!rd_ready`; WB lấy từ `rd_data`), `Hazard_Unit.v`
- Test: `tools/rv32i_check/tests_custom.py`

**Interface:**
- Dùng: `npu_pkg::npu_op_e` (Task 2); các port của core ở Task 8.
- Tạo ra, port engine của core (đúng như §7.1): `cmd_valid`, `cmd_ready`, `cmd_op[1:0]`, `cmd_addr[31:0]`, `cmd_k[31:0]`, `cmd_clr`, `rd_req`, `rd_idx[3:0]`, `rd_ready`, `rd_data[31:0]`, `csr_we`, `csr_addr[11:0]`, `csr_wdata[31:0]`, `csr_rdata[31:0]`

- [ ] **Step 1: Các test fail:** mỗi test so log `PUSH` của stub với `RefISS.cmd_log`, và so register với `RefISS`:
  - `push_each_op`: một LDW, một LDI, một MAC clr=0, một MAC clr=1
  - `illegal_funct3`: funct3 `100` đẩy op 3
  - `read_result_returns_idx`: idx 0..15
  - `fifo_full_stall`: `+STUB_READY=0001` (ready 1 cycle trong 4), 6 lần push liên tiếp → log và register giống như khi luôn ready
  - `store_then_load_order`: `sw` data vào `addr`, rồi LDW `addr`; lúc push, testbench đọc `dtcm[addr]` bằng backdoor và nó bằng giá trị vừa store
  - `push_in_branch_shadow`: một LDW sau một branch được lấy không bao giờ được push (Review Focus 1)
  - `read_result_x0_still_drains` (Review Focus 2)
- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt. **Step 4:** Chạy → PASS, mọi suite trước đó xanh.
- [ ] **Step 5: Commit** `feat(core): custom-0 decode, MEM-stage push, READ_RESULT`.

---

### Task 10: Golden model `npu_ref.c` và unit test của nó — Track B, tuần 2

**File:**
- Tạo: `model/c/npu_ref.h`, `model/c/npu_ref.c`
- Tạo: `model/c/tests/test_npu_ref.c` (assert C thuần, build bằng target `test` của `model/c/Makefile`)

**Interface:**
- Tạo ra (spec §10.2):
  ```c
  void     npu_ref_reset(void);
  void     npu_ref_mem_write(uint32_t word_idx, uint32_t data);   /* word_idx 0..16383 */
  void     npu_ref_cmd(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr);
  uint32_t npu_ref_read(uint32_t idx);                           /* uses idx & 0xF */
  uint32_t npu_ref_status(void);
  void     npu_ref_csr_write(uint32_t addr, uint32_t data);       /* 0x7C0 W1C, 0x7C1 set */
  uint32_t npu_ref_csr_read(uint32_t addr);                       /* 0x7C0 status, 0x7C1 stored value, else 0 */
  ```
  `npu_ref_status()` trả layout §6.4 với busy = 0, fifo_empty = 1, fifo_full = 0 (model không có timing).

- [ ] **Step 1: Viết các test fail** trong `test_npu_ref.c`:
  - `hand_4x4_k4` (K=4, một quad): row r0=[1,2,3,4], r1=[−1,−2,−3,−4], r2=[127,0,0,0], r3=[0,0,0,−128]; ảnh x0=[1,1,1,1], x1=[1,0,0,0], x2=[−128,−128,−128,−128], x3=[2,−2,2,−2] → các row acc (j=0..3): r0 = [10, 1, −1280, −4]; r1 = [−10, −1, 1280, 4]; r2 = [127, 127, −16256, 254]; r3 = [−128, 0, 16384, 256]
  - `hand_k8_accumulate`: COMPUTE K=4 (clr=1) trên quad 0 rồi K=4 (clr=0) trên quad 1 bằng một COMPUTE K=8 trên cả hai quad
  - `extremes`: mọi lane −128 × −128, K=1024 → mỗi acc = 16.777.216
  - `wrap`: 129 × COMPUTE(K=1024, clr=0) với −128 × −128 → mỗi acc = `(uint32_t)(129 * 16777216)`
  - `k0_noop`: K=0 với mỗi op giữ nguyên state và status
  - `compute_k0_clr_keeps_acc` (Review Focus 5)
  - `k_too_big`: K=1028 → set `err_k`; buffer và acc không đổi
  - `k_not_multiple_of_4`: K=6 với mỗi op → `err_k`, lệnh bị bỏ
  - `addr_out_of_range`: `addr = 0x0000_FFF0` với K=4, và `addr = 0x0001_FFF0` với K=8 → `err_addr`
  - `load_addr_wraps_32bit`: `addr=0xFFFF_FFF0, K=8` → `err_addr` (Review Focus 4)
  - `last_quad_ok`: `addr=0x0001_FFF0, K=4` → không lỗi
  - `illegal_op`: op 3 → `err_illegal`
  - `w1c`: ghi `0xF00` vào 0x7C0 xoá cả bốn error bit; ghi `0x100` chỉ xoá `err_k`
  - `addr_misaligned`: `addr=0x0001_0004` (và `0x0001_0001`) với K=4 → `err_align`, lệnh bị bỏ
- [ ] **Step 2:** Chạy `make -C model/c test` → FAIL (chưa cài đặt).
- [ ] **Step 3:** Cài đặt. Thứ tự check trong `npu_ref_cmd` (từ D16, 2026-10-23, ILLEGAL được check trước tất cả những điều này): K==0 → no-op; K>KMAX hoặc K%4 → `err_k`; với load, `a[3:0]≠0` → `err_align`, rồi tới kiểm khoảng bằng số học 64 bit `(uint64_t)a + 4ull*k > DTCM_BASE + DTCM_BYTES` → `err_addr`. Ghi thứ tự này vào spec nếu nhóm thay đổi nó.
- [ ] **Step 4:** Chạy `make -C model/c test` → mọi assert pass.
- [ ] **Step 5: Commit** `feat(model): npu_ref golden model with unit tests`.

---

### Task 11: RTL `mac_engine` (D0) với directed testbench dùng DPI — Track B, tuần 3–4

**File:**
- Tạo: `rtl/npu/mac_engine.sv`, `rtl/npu/cmd_fifo.sv`, `rtl/npu/pe_array.sv` (16 PE dot4), `rtl/prim/npu_clk_gate.sv` (với `GATING_EN=0` nó buộc `en` lên 1, §8, D19)
- Tạo: `tb/directed/mac_engine_tb.sv`, `tb/directed/dtcm_model.sv` (memory port B 128 bit dạng behavioural, chứa cùng nội dung đã ghi qua `npu_ref_mem_write`)
- Tạo: `sim/questa/run_mac_directed.do` (kèm wrapper `.bat`/`.sh`); mở rộng target `lint` có sẵn trong `sim/verilator/Makefile` (hiện là `npu_pkg` + `dtcm_dp`) với `verilator --lint-only -Wall --top-module mac_engine rtl/top/npu_pkg.sv rtl/prim/*.sv rtl/npu/*.sv` (package phải đứng đầu: nếu nó nằm sau một file import nó, Verilator 5.020 dừng với PKGNODECL, đã kiểm ngày 2026-10-28)
- Tạo: `docs/mac_engine.md` (sơ đồ FSM, latency chính xác của từng op cho A-MAC-5)

**Interface:**
- Dùng: `npu_pkg` (Task 2); `npu_ref` (Task 10) qua `import "DPI-C"` với cùng signature.
- Tạo ra: `module mac_engine #(parameter GATING_EN = 0)` với đúng các port ở §7.1. `mac_env` và `npu_top` của Phase 2 bind vào các tên này.

- [ ] **Step 1: Viết các directed test fail** trong `mac_engine_tb.sv`. Mỗi test lái lệnh qua port push của §7.1, mô phỏng song song chúng trên `npu_ref`, rồi so cả 16 giá trị READ_RESULT và `npu_status` (`$fatal` khi lệch):
  - `t_single_k4` (`hand_4x4_k4` của Task 10)
  - `t_k_kmax` (K=1024)
  - `t_k0`
  - `t_k_too_big` (1028), `t_k_mod4` (K=6)
  - `t_addr_oob`, `t_addr_misaligned`
  - `load_addr_wraps_32bit`
  - `compute_k0_clr_keeps_acc`
  - `t_illegal` (D16: kèm cả K = 0, K = 6, K = 1028 và address sai; chỉ được set `err_illegal`)
  - `t_clr_vs_acc`
  - `t_wrap` (cộng dồn lặp lại như Task 10)
  - `t_fifo_full`: 9 lần push liên tiếp; `cmd_ready` xuống khi có 8 entry và không lệnh nào bị mất
  - `t_read_while_busy`: `rd_ready` giữ 0 cho tới khi idle, rồi data khớp
  - `t_w1c`
  - `t_csr_write_semantics` (D17): ghi `0x100` vào `npu_status` chỉ xoá `err_k`; ghi 0 không đổi gì; ghi `npu_busy_cyc` trong cycle busy thì thắng phép tăng (đọc lại ở cycle sau); (D21) trong cycle của mỗi lần ghi, `csr_rdata` vẫn hiện giá trị cũ, và các address 0x000, 0x7C2, 0x7C3, 0x3C0, 0xFC0 và 0xB00 đọc ra 0 và bỏ qua write trong lúc error bit đang set và `npu_busy_cyc` ≠ 0 (để một decode address không đầy đủ sẽ lộ ra dưới dạng alias)
  - `t_reset_state` (D18): với error bit đang set, một accumulator khác 0 và `npu_busy_cyc` khác 0, assert `rst_n`; sau đó FIFO rỗng, error bit của `npu_status` bằng 0, `npu_busy_cyc` bằng 0 và cả 16 giá trị `READ_RESULT` bằng 0 (nội dung buffer sau reset không được test, §7.2)
- [ ] **Step 2:** Chạy `sim/questa/run_mac_directed` → FAIL (chưa có engine).
- [ ] **Step 3:** Cài đặt theo §7.2–§7.3: FSM `IDLE/CHECK/LOAD/MAC`; hai domain free clock và `clk_mac`; `en = !rst_n_sync || (fsm != IDLE) || !fifo_empty`.
  Thứ tự build. Với mỗi bước, directed test tương ứng đã có sẵn và fail trước khi làm bước đó (Step 1), và các bước trước nó vẫn xanh:
  1. `cmd_fifo.sv`: độ sâu `npu_pkg::FIFO_DEPTH`; push khi `cmd_valid && cmd_ready`; `cmd_ready = !full` (A-MAC-1: không push khi đầy, không pop khi rỗng). Đạt tới `t_fifo_full`.
  2. CHECK theo thứ tự D16: ILLEGAL; K = 0; K > KMAX hoặc K mod 4 ≠ 0 (`err_k`); với LOAD `addr[3:0] ≠ 0` (`err_align`), rồi kiểm khoảng bằng số học 64 bit (`err_addr`). Đạt tới `t_illegal`, `t_k0`, `t_k_too_big`, `t_k_mod4`, `t_addr_misaligned`, `t_addr_oob`, `load_addr_wraps_32bit`, `compute_k0_clr_keeps_acc`.
  3. LOAD: K/4 lần đọc port B; `b_addr` là chỉ số quad, `(addr - DTCM_BASE) >> 4` (12 bit, suy ra từ §6.2 và §7.1); `b_rdata` hợp lệ ở cycle sau `b_req`; ghi WBUF hoặc IBUF (256 × 128 bit). Đạt tới nửa load của `t_single_k4`.
  4. `pe_array.sv` (16 PE dot4; với clr, step đầu tiên nạp thẳng dot product thay vì cộng vào), state MAC và 4×4 accumulator. Đạt tới `t_single_k4`, `t_k_kmax`, `t_clr_vs_acc`, `t_wrap`.
  5. Khối CSR (§6.4, D17, D21): các bit `npu_status` và W1C trên giá trị được ghi, `npu_busy_cyc`; `csr_rdata` tổ hợp theo `csr_addr`, không có đường từ `csr_we`/`csr_wdata`; `rd_ready = fifo_empty && fsm == IDLE`; READ_RESULT đọc accumulator theo kiểu tổ hợp. Đạt tới `t_w1c`, `t_read_while_busy`, `t_csr_write_semantics`.
  6. Reset (D18): `rst_n` active low; assert nó xoá FIFO, FSM, error bit, `npu_busy_cyc` và accumulator, và WBUF/IBUF không bị reset. Đạt tới `t_reset_state`. D18 chốt kiểu reset: assert bất đồng bộ, nhả đồng bộ; bộ đồng bộ nằm ở `npu_top`, nên `rst_n` đi vào engine đã là `rst_n_sync` của §8.
  7. Instance `npu_clk_gate`, `GATING_EN` truyền xuống từ `mac_engine`; ở D0 enable của nó bị buộc lên 1, nên cả suite không đổi.
- [ ] **Step 4:** Chạy directed suite → tất cả PASS. Chạy `make -C sim/verilator lint` → sạch (Verilator 5.020 chạy dưới WSL trên máy của Bảo từ 2026-10-27: chạy `make -C sim/verilator lint` ở đó). Ghi latency đo được vào `docs/mac_engine.md`. Mỗi latency phải ≤ K/4 + 3.
- [ ] **Step 5: Commit** `feat(npu): mac_engine D0 with directed DPI testbench`.

---

### Task 12: ISS tham chiếu `rv_iss.c` — Track A, tuần 4 (có thể trễ sang tuần 5, xem Rủi ro lịch)

**File:**
- Tạo: `model/c/rv_iss.h`, `model/c/rv_iss.c`, `model/c/tests/test_rv_iss.c`

**Interface:**
- Dùng: `npu_ref` (Task 10) cho mode `ISS_FULL`.
- Tạo ra (spec §10.2):
  ```c
  typedef struct { uint32_t valid, pc, insn, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask, trap; uint64_t order; } rvvi_rec_t;
  enum { ISS_STUB = 0, ISS_FULL = 1 };
  void iss_init(const uint32_t *itcm, uint32_t itcm_words, const uint32_t *dtcm, uint32_t dtcm_words, int mode);
  int  iss_step(rvvi_rec_t *rec);   /* returns 0 normally, 1 after a SIM_CTRL write */
  ```

- [ ] **Step 1: Các test fail:** `test_rv_iss.c` chạy cùng các chương trình với các suite Python (Task 3, 5, 6, 7, 9), nạp từ các file `.bin` do `tools/rv32i_check/build/` sinh ra. Nó assert register cuối cùng bằng bản dump của `RefISS` (`build/<tag>.ref.txt`, do `run.py` **[support]** ghi).
- [ ] **Step 2:** Chạy `make -C model/c test` → FAIL. **Step 3:** Cài đặt. **Step 4:** Chạy → PASS với mọi chương trình.
- [ ] **Step 5: Commit** `feat(model): rv_iss reference ISS`.

---

## Exit checklist của Phase 1

- [ ] Task 0: `docs/smoke/results.md` đầy đủ; đã ghi loại licence, đóng O3; đã cập nhật proposal nếu S1–S3 pass
- [ ] Task 1–9: `python tools/rv32i_check/run_all.py` chạy xanh mọi suite, kể cả các test Review Focus 1–3 (xanh ngày 2026-10-27: 1291/1291 trong WSL; CI chạy nó ở mỗi lần push và mọi lần chạy đã kiểm từ 00a9207 tới 2b1ed05 đều xanh; harness chỉ chạy map của spec từ 6280c97; ô này để nhóm tự tick)
- [x] Task 10: `make -C model/c test` xanh, kể cả Review Focus 4–5 (22/22 ngày 2026-10-17; 23/23 từ 8f7ed32, 2026-10-21, thêm `test_k_checked_before_align_and_addr`)
- [ ] Task 11: directed suite của engine xanh trên QuestaSim; Verilator lint sạch
- [x] Task 12: `make -C model/c test` và `make -C model/c xcheck` xanh (2026-10-20)
- [x] Spec đã freeze (§6, §7.1) và đã ghi O1/O2 (frozen 2026-10-29 bởi Tấn, Bảo; O1/O2 đóng 2026-10-23)
