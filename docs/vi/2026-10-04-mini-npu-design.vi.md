# Mini-NPU Design Spec (bản tiếng Việt) — RISC-V NPU lấy cảm hứng từ CoralNPU

> **Bản dịch để đọc cho dễ.** Bản chuẩn là bản tiếng Anh `docs/superpowers/specs/2026-10-04-mini-npu-design.md`. Khi hai bản khác nhau, bản tiếng Anh thắng. Dịch ngày 2026-10-29 từ bản có §6/§7.1 frozen (commit ngay sau `a2b3a97`). Tên tín hiệu, file, lệnh, mã quyết định (D1, D2, ...) và thuật ngữ kỹ thuật giữ nguyên tiếng Anh.

- **Dự án:** Senior Project 2 (Đồ án 2), HCMUTE, lớp 23161FIE, GVHD Phạm Văn Khoa
- **Nhóm:** Nguyễn Hoàng Công Tấn (23161064) — Track A, scalar core; Nguyễn Thế Bảo (23144002) — Track B, Matrix/MAC engine (phân công 2026-10-15)
- **Repository:** https://github.com/baonyen1/Mini-NPU-Project
- **Ngày:** 2026-10-04 (sửa 2026-10-14: QuestaSim, công thức requant, xác nhận kích thước model; sửa 2026-10-15: engine N×M×K = 4×4×4 với PE dot4 và DTCM port B 128 bit; người phụ trách; D11–D13 cho Phase 2–4) · **Trạng thái:** đã duyệt; **§6/§7.1 frozen 2026-10-29 bởi Tấn, Bảo** (đề xuất 2026-10-24 sau khi đối chiếu với `npu_pkg.sv`, `npu_ref`, `npu_stub.sv`, đường push/CSR của core, `rv_iss` và `dtcm_dp`; D17–D19, D21). Từ nay mọi thay đổi §6/§7.1 cần chữ ký của cả hai và một mục quyết định có ngày (D20)
- **Tài liệu nguồn:** `Proposal_Senior_Project_2_MiniNPU_VI.docx`; repository CoralNPU `google-coral/coralnpu` tại commit `382b5c1` (2026-10-02)

Spec này biến proposal thành một thiết kế build được. Nó chốt interface và semantics để hai track làm song song. Nó nói mỗi khối phải làm *gì* và *chứng minh bằng cách nào*. Spec không chứa RTL, code UVM hay firmware; sinh viên tự viết những phần đó.

---

## 1. Mục tiêu và tiêu chí thành công

Xây một NPU nhỏ gồm:

1. Core RV32I 5 tầng có sẵn của nhóm, mở rộng lên **RV32IM + Zicsr + Zifencei + Zbb**.
2. Bốn custom instruction: **LOAD_WEIGHT, LOAD_INPUT, COMPUTE, READ_RESULT**. Chúng đi qua một command FIFO tới một **MAC engine outer-product int8, N×M×K = 4×4×4**, chạy tách rời (16 PE, mỗi PE là dot product 4 phần tử: 64 MAC/cycle). Đây là cùng cách tham số hoá mà CoralNPU dùng ở cỡ 8×8×4.
3. Một **DTCM 64 KB** gồm 4 bank × 32 bit, dùng chung bởi core (port A, 32 bit) và engine (port B, 128 bit, chỉ đọc).
4. **Clock gating ở mức module** cho MAC engine. Thiết kế được build hai lần: **D0** không gating và **D1** có gating.

Toàn bộ được verify bằng môi trường **SystemVerilog UVM** tự xây. Hệ thống phải chạy được **MLP int8 784-64-32-10 trên MNIST** với output khớp bit-exact với `golden_int8.py`.

| # | Tiêu chí | Điều kiện chấp nhận |
|---|---|---|
| SC1 | Tính đúng chức năng | Mọi directed test và random test đã định nghĩa đều pass, không có mismatch ở scoreboard và không có assertion fail, trên cả D0 và D1. |
| SC2 | Coverage | Coverage plan ở §10.5 đóng trên D0 trước khi bắt đầu làm gating (tuần 10). |
| SC3 | Tương đương D0/D1 | Cùng một chương trình cho cùng hash của retire trace, cùng `mcycle` và cùng output (giống nhau từng cycle). Phương án dự phòng: giống nhau về kết quả, kèm lý do được ghi lại. |
| SC4 | Switching activity | Báo cáo % thay đổi của D1 so với D0 cho metric M1 và M2 (§11) trên workload synthetic và MNIST. Không đặt trước mục tiêu %. |
| SC5 | MNIST | Logit và nhãn của RTL khớp bit-exact với `golden_int8.py` trên 1.000 ảnh test MNIST đầu tiên, trên D0 và D1 (D11). Một lần chạy đủ 10.000 ảnh trên D0 báo cáo accuracy của RTL, và nó phải bằng accuracy của golden. |
| SC6 | Tái lập được | Mỗi flow có một lệnh sinh lại dữ liệu regression, coverage và switching activity. Phiên bản tool và seed được ghi trong `manifest.yaml`. |

**Ranh giới bằng chứng.** Số liệu power là *ước lượng switching activity* từ RTL simulation, không bao giờ được gọi là "measured power". Bằng chứng chức năng (UVM) và bằng chứng power (toggle) được báo cáo riêng.

## 2. Phạm vi

**Trong phạm vi:**
- phần mở rộng ISA của core
- 4 custom instruction
- MAC engine (FIFO, operand buffer, PE array, accumulator, CSR)
- DTCM dual-port, ITCM và MMIO cho simulation
- clock gating cell và cấu hình D1
- ba môi trường UVM, cộng golden model C và ISS bằng C
- firmware bare-metal và pipeline MNIST
- flow đếm toggle

**Ngoài phạm vi (để dành cho khoá luận tốt nghiệp):**
- RVV/Zve32x và F extension
- DMA, nhiều accumulator tile, PE có pipeline
- FPGA synthesis và bring-up trên board
- compiler toolchain (IREE/TFLM)
- nạp dữ liệu frontdoor (qua bus)
- verification có LLM hỗ trợ

## 3. Nhật ký quyết định

### 3.1 Đã quyết định

| ID | Quyết định | Lý do |
|---|---|---|
| D1 | UVM 1.2 (IEEE 1800.2) bằng SystemVerilog. **Simulator chính: Siemens QuestaSim** (nhóm quyết định 2026-10-14). Dự phòng: Vivado xsim 2024.1. Verilator dùng để lint và chạy nhanh cả hệ thống. | Simulator UVM chuẩn công nghiệp, có sẵn UVM, DPI-C và coverage. **Cần licence QuestaSim đầy đủ:** bản Questa–Intel/Altera FPGA (Starter) miễn phí không hỗ trợ `randomize`/`covergroup` (diễn đàn Altera, xem §17), nên testbench UVM có constrained random và coverage sẽ không chạy được trên đó. S1–S3 xác nhận hoặc bác bỏ điều này. |
| D1a | VCD switching activity cho D0/D1 lấy từ **một** simulator cho cả hai cấu hình: mặc định QuestaSim; chỉ dùng Verilator nếu Questa chạy MNIST quá lâu (quyết định sau lần chạy MNIST đầu tiên). | Muốn so D0/D1 công bằng (§11) thì tool phải giống nhau. |
| D2 | Mở rộng core RV32I pipeline 5 tầng có sẵn. | Nhóm đã build sẵn. |
| D3 | Chia việc theo subsystem. **Track A** (Tấn): core và `core_env`. **Track B** (Bảo): MAC engine, `dtcm_dp` và `mac_env`. Hai track cùng làm tích hợp SoC và `soc_env`. | Làm song song với một interface rõ ràng. |
| D4 | "Coral thu nhỏ": engine tự lấy operand từ DTCM vào operand buffer, rồi cộng dồn vào một tile 4×4. | Giống Coral: `vle8` → vector reg → `vtmms` → tile → `vtmv`. |
| D5 | Signed int8 × signed int8 → cộng dồn int32. **Overflow thì wrap** (two's complement). | Khớp với `int32_t` trong golden C. Output ReLU nằm trong [0,127], nên signed là đủ. |
| D6 | Toàn bộ model nằm trong DTCM 64 KB. Không có DMA. Đóng open item 3. | Layout cần 56.816 B (§9.2). |
| D7 | Dữ liệu được nạp trước bằng backdoor `$readmemh`. Đóng open item 4. | Đường đơn giản nhất mà chạy được. Nạp frontdoor là việc của khoá luận. |
| D8 | Golden ↔ scoreboard: DPI-C ở mức block và mức hệ thống; so sánh file cho MNIST. Đóng open item 5. | Random test cần dự đoán ngay khi chạy. MNIST đã có golden Python. |
| D10 | Kích thước engine **N×M×K = 4×4×4**: mỗi PE tính một dot4 mỗi cycle; entry WBUF/IBUF và DTCM port B rộng 128 bit; K phải là bội của 4. Nhóm quyết định 2026-10-15 (phương án B). | Khớp với outer-product engine N×M×K của CoralNPU (8×8×4, VDOT = "4 phép nhân 8 bit cộng dồn vào accumulator 32 bit"). Số cycle engine ít hơn khoảng 4 lần so với 4×4×1, và các khoảng idle dài hơn giúp kết quả D1 lộ rõ trên MNIST. |
| D11 | Số ảnh MNIST: **1.000** ảnh test cho regression SC5 (D0 và D1); **10.000** ảnh (toàn bộ tập test) chạy một lần trên D0 ở tuần 15; **100** ảnh cho lần chạy switching activity E4. Nhóm quyết định 2026-10-15. | 1.000 ảnh ≈ 3M cycle mỗi cấu hình, đủ ngắn để chạy regression thường xuyên; lần chạy đầy đủ cho ra con số accuracy của RTL; 100 ảnh giữ VCD nhỏ. |
| D12 | Sản phẩm cuối: báo cáo bằng **tiếng Anh**, slide bảo vệ và gói tái lập (SC6). Mỗi chương báo cáo được viết nháp khi phase tương ứng kết thúc. Nhóm quyết định 2026-10-15. | Dùng lại được cho khoá luận; tránh dồn hết việc viết vào tuần 16. |
| D13 | Đi theo cấu trúc công khai của CoralNPU ở chỗ nào có (datasheet, developer guide, `google-coral/coralnpu`): topology UVM (RVVI agent passive + co-simulation checker so với một ISS), nạp chương trình bằng backdoor, kết thúc test khi có tín hiệu hoàn tất hoặc timeout, một regression runner Python có `--simulator`/`--target`. Tự viết toàn bộ code; ghi mọi chỗ cố ý khác Coral vào §16. Nhóm quyết định 2026-10-15. | Giữ cho thiết kế "lấy cảm hứng từ CoralNPU" một cách kiểm chứng được và cho báo cáo một ranh giới đóng góp rõ ràng. |
| D9 | Clock gating chỉ áp dụng cho MAC engine, theo trạng thái idle do phần cứng phát hiện. | Coral gate cả core khi WFI/CSR (`CoreAxi.scala`). Độ chi tiết mịn hơn là đóng góp của nhóm. |
| D14 | Export của model đã retrain nằm trong `model/py/export/` và được commit: `fc{1,2,3}_weight.mem`, `fc{1,2,3}_bias.mem`, `requant.json`, `testvec_input.mem`, `testvec_expected.npz`, `manifest.json` (SHA-256 từng file). Notebook ghi vào đó. Track B quyết định 2026-10-21 (Bảo). | Một model cố định duy nhất cho `pack_weights.py`, các file golden và bước kiểm hash của export (Phase 4 Task 25 và 27); khớp với cây thư mục `model/py/`. |
| D15 | Golden số nguyên cho MLP là `model/py/golden_int8.py` (numpy thuần: `quantize_input`, `requant`, `find_ms`, `compute_bound`, `IntModel`, `load_export`). Nó có unit test riêng và được đối chiếu chéo với `npu_ref`; notebook import nó thay vì giữ một bản sao. Do Phase 1 Task 2b tạo ra. Track B quyết định 2026-10-21 (Bảo). | SC5 nhắc tới `golden_int8.py` nhưng chưa task nào tạo ra nó. Không thể import notebook nếu thiếu marimo và torch, và §10.2 chỉ cho dùng một oracle sau khi nó pass unit test của chính nó. |
| D16 | Lệnh có op `ILLEGAL` được xử lý chỉ dựa vào `op`: engine set `err_illegal` và không làm gì khác, kể cả khi K = 0, K > KMAX, K không chia hết cho 4 hay address sai. Thứ tự check trong `CHECK`: ILLEGAL, K = 0, khoảng K và bội của 4, rồi (với LOAD) alignment, rồi tới khoảng address. Track B quyết định 2026-10-23 (Bảo, phương án A); Tấn xác nhận khi ký freeze §6. | Core đẩy ILLEGAL với bất kỳ giá trị nào đang có trong `rs1`/`rs2`, nên K và address của lệnh ILLEGAL là tuỳ ý. Nếu K = 0 thắng, một `funct3` reserved có `rs2 = 0` sẽ bị nuốt im lặng và lỗi phần mềm bị che mất. Test: `npu_ref` `test_illegal_op`, `test_illegal_wins_over_other_checks`; test `t_illegal` của Task 11 phải bao gồm K = 0, K = 6, K = 1028 và address sai. |
| D17 | CSR write tới 0x7C0/0x7C1 mang **giá trị mới mà core đã tính** (`csrrw`: rs1; `csrrs`: old \| rs1; `csrrc`: old & ~rs1; các dạng `i` dùng uimm), và `csr_we` = 1 chỉ khi lệnh thực sự ghi (`csrrw`/`csrrwi` luôn ghi; `csrrs`/`csrrc`/`csrrsi`/`csrrci` chỉ ghi khi rs1/uimm khác 0). W1C trên `npu_status` áp lên giá trị đó. Firmware xoá error bit bằng `csrw`/`csrrwi`. Ghi `npu_busy_cyc` trong cycle đang busy thì giá trị ghi thắng phép tăng. | Khớp với core (`CSR_Unit.v`), `npu_stub.sv`, `rv_iss.c` và RefISS như đã build; đây là read-modify-write chuẩn của Zicsr. Hệ quả: `csrrs npu_status, t0` với t0 ≠ 0 xoá mọi error bit đang set, và `csrrc` xoá mọi error bit đang set nằm ngoài mask của nó. |
| D18 | Reset của engine: `rst_n` active low, **assert bất đồng bộ và nhả đồng bộ** theo `clk` (bộ đồng bộ nằm ở `npu_top`, lấy từ `reset` active-high của core). Reset làm rỗng FIFO, đưa FSM về IDLE, và xoá error bit, `npu_busy_cyc` cùng 16 accumulator về 0. WBUF và IBUF không bị reset (§7.2). | Luật RTL của dự án (async assert, sync deassert; nhóm quyết định 2026-10-24). Term `!rst_n_sync` ở §8 giữ cho `clk_mac` chạy trong lúc nhả reset; `npu_ref_reset` và test của Task 10 đã giả định acc = 0 sau reset. |
| D19 | Quy ước RTL của engine: port giữ tên như §7.1 (core và `npu_stub` đã dùng); tín hiệu nội bộ theo style lowRISC (`_q`/`_d`, parameter CamelCase). Clock-gating cell duy nhất là `rtl/prim/npu_clk_gate.sv` (latch + AND trong simulation, sau này dùng `BUFGCE` sau `` `ifdef FPGA_XILINX ``); `mac_engine #(GATING_EN)` truyền `GATING_EN` xuống cell này, và khi bằng 0 thì enable bị buộc lên 1. | Nhóm quyết định 2026-10-24. Đổi tên port sẽ đụng tới Task 9 và stub ngay trước lúc freeze; một primitive gating duy nhất giữ lựa chọn sim/FPGA ở một file. |
| D20 | Task 11 (`mac_engine` D0) bắt đầu dựa trên freeze §6/§7.1 đang đề xuất, không chờ Tấn ký. Tấn review §6/§7.1 so với core song song, theo danh sách "Next actions" trong plan Phase 1, và tick ô của mình khi xong; ô đó để trống cho tới khi Tấn tick. Một thay đổi §6/§7.1 trước khi có đủ hai tick được ghi ở đây thành một mục có ngày; sau khi đủ hai tick thì cần chữ ký của cả hai. Track B quyết định 2026-10-26 (Bảo). | Interface đã được đối chiếu ngày 2026-10-24 với `npu_pkg.sv`, `npu_ref`, `npu_stub.sv`, đường push/CSR của core, `rv_iss` và `dtcm_dp` (header), và Task 11 chặn Task 14 và 16 của Phase 2. Cái giá của rủi ro: nếu review của Tấn đổi §6/§7.1 thì Task 11 phải hấp thụ thay đổi; các mục Tấn review là D16 (thứ tự ưu tiên của ILLEGAL), D17 (giá trị CSR write) và D18 (reset). |
| D21 | Hợp đồng đọc CSR (§7.1). `csr_rdata` là hàm tổ hợp chỉ của `csr_addr` và state đã register của engine (state tại cạnh `clk` gần nhất), hợp lệ ngay trong cycle đó; không có đường tổ hợp từ bất kỳ input nào khác của engine, kể cả `csr_we` và `csr_wdata`, nên đọc trong cycle có write sẽ thấy giá trị cũ. Đọc không có side effect: port không có read strobe, và core lái `csr_addr` từ immediate của tầng EX ở mọi cycle (`CSR_Unit.v` dòng 93, `StageExecute_Top.v` dòng 257), nên engine cũng thấy các address tuỳ ý, kể cả 0x7C0/0x7C1, trong những cycle không có lệnh CSR; chỉ `csr_we` được gate theo 0x7C0/0x7C1 (`CSR_Unit.v` dòng 92). Mọi address khác đọc ra 0 và write vào bị bỏ qua. `npu_status` không phải barrier (§6.3 luật 4). Track B quyết định 2026-10-28 (Bảo), ghi trước khi đủ hai tick như D20 yêu cầu; nó thêm D21 vào các mục Tấn review ở D20, và Tấn xác nhận bằng tick §7.1. | Core đọc `npu_csr_rdata` theo kiểu tổ hợp ở EX, forward nó như một kết quả ALU và tạo giá trị write của D17 từ nó (`CSR_Unit.v`, comment ở dòng 24–25, đọc ở dòng 74; ruling 2 trong `docs/core_isa.md` §7). Nếu đọc qua register thì mỗi lần truy cập CSR của engine tốn thêm một cycle stall, và một đường từ `csr_wdata` ngược về `csr_rdata` sẽ tạo vòng tổ hợp qua read-modify-write đó. `npu_stub.sv` hoạt động như vậy; `npu_ref_csr_read` và `rv_iss` (đọc trước ghi, address khác ra 0) cũng nhất quán. Test: Task 11 `t_csr_write_semantics`. |
| D22 | Lịch: tuần 1 là Thứ Hai 2026-10-12 tới Chủ nhật 2026-10-18, tuần *N* bắt đầu sau đó 7(*N*−1) ngày. Phase 1 (tuần 1–4) kết thúc Chủ nhật 2026-11-08, Phase 2 (5–9) Chủ nhật 2026-12-13, Phase 3 (10–12) Chủ nhật 2027-01-03, Phase 4 (13–16) Chủ nhật 2027-01-31. Bảo ghi ngày 2026-10-28; Tấn xác nhận. | Các plan đếm theo tuần nhưng chưa tài liệu nào ghi ngày cho tuần 1. Với lịch này, freeze tuần 2 và W2-1 có hạn Chủ nhật 2026-10-25, còn Task 11 (tuần 3–4) có hạn Chủ nhật 2026-11-08. |

### 3.2 Còn mở (nhóm quyết định; nếu tới cuối tuần 2 chưa ghi quyết định thì dùng mặc định)

| ID | Câu hỏi | Lựa chọn | Mặc định |
|---|---|---|---|
| O1 | Requantization giữa các layer (open item 2) | **A**: nhân + shift + clamp (`mul`, `srai`, `max`/`min`). **B**: chỉ shift. | A, **xác nhận 2026-10-23** (notebook cài đặt cách này và export đã commit dùng nó) |
| O2 | Công thức requant chính xác | Công thức ghi ở §9.3, lấy từ notebook. Giá trị `M`, `S` từng layer lấy từ model 784-64-32-10 đã retrain (`requant.json`). | **Đóng 2026-10-23.** Công thức chốt ở §9.3. Export 784-64-32-10 đã retrain (seed 0, 15 epoch, calibration 10.000 ảnh ở percentile 99,99): FC1 `M` = 768, `S` = 20 (bound 1.608.339); FC2 `M` = 7891, `S` = 21 (bound 249.259); FC3 không requant (bound 171.847). Accuracy trên 10.000 ảnh test MNIST: float 97,48 %, int8 97,43 % (chênh 0,05 điểm phần trăm); nhãn float và int8 trùng nhau 99,81 %; 100 test vector đã export đạt 99,00 %. `M`, `S` được tính lại từ `manifest.json` bằng `golden_int8.find_ms` (test `export_requant_matches_rule`). Export được tạo trên Linux với torch 2.14.1 (CPU) và numpy 2.5.4; hai lần chạy trên máy đó cho cùng SHA-256, nhưng nền tảng khác có thể lệch ở các bit cuối, nên các file đã commit là bản tham chiếu, không phải bản sinh lại. |
| O3 | Nhóm có licence QuestaSim (licence của lab hoặc trường, không phải bản FPGA Starter) | S1–S3 trên licence thật. Nếu `randomize`/`covergroup` fail thì chuyển sang xsim. | QuestaSim. **Đóng 2026-10-17**: S1–S3 pass trên QuestaSim 10.7c (`docs/smoke/results.md`); phương án xsim dự phòng đã kiểm (S6). |

## 4. Kiến trúc hệ thống

```
                 ┌──────────────────────── npu_top ─────────────────────────┐
                 │                                                          │
  ITCM 16KB ◄────┤  core (5-stage RV32IM+Zicsr+Zifencei+Zbb + custom-0)     │
  0x0000_0000    │     │ IF │ ID │ EX │ MEM │ WB │                           │
                 │                    │   ▲                                 │
                 │       cmd push ────┘   │ READ_RESULT data                │
                 │       (MEM stage)      │ + CSR 0x7C0/0x7C1               │
                 │                ┌───────┴──────────────────────────┐      │
                 │                │ mac_engine                       │      │
                 │                │  free clk : cmd FIFO(8), FSM,    │      │
                 │                │             CSRs, port-B ctrl    │      │
                 │                │  clk_mac  : WBUF, IBUF 256×128,  │      │
                 │                │             PE 4×4 dot4, acc 4×4 │      │
                 │                │  npu_clk_gate(en) → clk_mac      │      │
                 │                └───────┬──────────────────────────┘      │
                 │   LSU (port A, 32b R/W) │ port B (128b, read-only)       │
                 │          ▼             ▼                                 │
                 │     DTCM 64 KB, 4 banks × 32b, 0x0001_0000             │
                 │   SIM MMIO 0x0002_0000 (SIM_CTRL, SIM_PUTC) — tb only   │
                 └──────────────────────────────────────────────────────────┘
```

### 4.1 Memory map

| Base | Kích thước | Vùng | Truy cập |
|---|---|---|---|
| `0x0000_0000` | 16 KB | ITCM (firmware) | core đọc ở IF; nạp backdoor |
| `0x0001_0000` | 64 KB | DTCM, 4 bank × 32 bit (bank = word address [1:0]) | port A: LSU của core, đọc/ghi 32 bit có byte enable; port B: engine, 128 bit (mỗi bank một word), chỉ đọc |
| `0x0002_0000` | 4 B | `SIM_CTRL` (chỉ ghi) | `0x1` PASS, `0x2` FAIL, `0x10` BATCH_DONE, `0x20` MEAS_START, `0x21` MEAS_STOP |
| `0x0002_0004` | 4 B | `SIM_PUTC` (chỉ ghi) | byte thấp được in ra log simulation |

Mọi address khác là access fault. Hành vi do policy hiện có của core quyết định, và Track A ghi lại policy đó ở tuần 2 (W2-1).

### 4.2 Parameter (`npu_pkg.sv`)

| Tên | Mặc định | Ghi chú |
|---|---|---|
| `PE_ROWS` (N), `PE_COLS` (M) | 4, 4 | chỉ lên 8×8 nếu còn thời gian sau SC1–SC3 |
| `K_DOT` (K) | 4 | số lane int8 mỗi PE mỗi cycle (dot4); cố định, không phải parameter được verify |
| `KMAX` | 1024 | K lớn nhất tính theo phần tử int8; độ sâu WBUF/IBUF = KMAX/4 = 256 entry × 128 bit |
| `FIFO_DEPTH` | 8 | cùng độ sâu với command queue của Coral |
| `GATING_EN` | 0 (D0) / 1 (D1) | khác biệt RTL duy nhất giữa D0 và D1 |
| `DTCM_BASE`, `DTCM_BYTES` | `0x0001_0000`, 65536 | |

## 5. Phần mở rộng của scalar core (Track A)

- **M.** `MUL`, `MULH`, `MULHSU`, `MULHU` chạy ở EX trong 1 cycle (chỉ cho simulation). `DIV`, `DIVU`, `REM`, `REMU` dùng bộ chia radix-2 lặp khoảng 32 cycle, stall pipeline. Các corner case bắt buộc theo spec: chia cho 0 (thương = toàn bit 1, dư = số bị chia) và `-2^31 / -1` (thương = `-2^31`, dư = 0).
- **Zicsr.** Cả sáu lệnh CSR. Các CSR:
  - `mcycle`/`mcycleh` (0xB00/0xB80)
  - `minstret`/`minstreth` (0xB02/0xB82), tăng ở WB khi retire
  - alias chỉ đọc cho user `cycle`/`instret` (0xC00/0xC02/0xC80/0xC82)
  - `npu_status` (0x7C0) và `npu_busy_cyc` (0x7C1), chuyển tiếp sang engine (§6.4)
  - kết quả CSR đi qua đường forwarding bình thường.
- **Zifencei.** `fence.i` flush pipeline rồi fetch lại. Không có I-cache. `fence` chạy như NOP.
- **Zbb.** Đủ bộ:
  - `andn orn xnor`
  - `clz ctz cpop`
  - `max maxu min minu`
  - `sext.b sext.h zext.h`
  - `rol ror rori`
  - `orc.b rev8`
- **Retire trace.** Một port retire-trace kiểu RVVI để verification. Về bản chất không phải logic để synthesize, nhưng được giữ trong RTL dưới `` `ifdef RVVI_TRACE ``. Các field: `valid, order, pc, insn, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask, trap`.

## 6. Custom ISA (chuẩn)

### 6.1 Encoding

Cả bốn lệnh dùng opcode **custom-0 = `0001011`** dạng R-type.

| funct3 | Mnemonic | Operand | funct7 |
|---|---|---|---|
| `000` | `LOAD_WEIGHT` | `rs1` = byte address trong DTCM, `rs2` = K | `0000000` |
| `001` | `LOAD_INPUT` | `rs1` = byte address trong DTCM, `rs2` = K | `0000000` |
| `010` | `COMPUTE` | `rs1` = K; `funct7[0]` = clr | `000000c` |
| `011` | `READ_RESULT` | `rd` ← acc[`rs1[3:0]`] | `0000000` |
| `100`–`111` | (reserved) | — | — |

`rd` phải là `x0` với funct3 000–010; phần cứng bỏ qua field này. Các bit khác 0 của `funct7`, trừ bit 0 của `COMPUTE`, bị bỏ qua. Dạng assembler: `.insn r 0x0B, <funct3>, <funct7>, rd, rs1, rs2`.

### 6.2 Định dạng dữ liệu

- Một word DTCM gồm 4 lane int8. Lane *t* là bit `[8t+7:8t]` (lane 0 = LSB, little-endian).
- Một **quad** là 4 word liên tiếp (16 byte, align 16 byte) = một entry 128 bit của WBUF/IBUF = một lần đọc port B.
- K đếm số phần tử int8 theo trục reduction; một lệnh có K phần tử dùng S = K/4 quad (step).
- `WBUF[s]` word *i* (bit `[32i+31:32i]`) = W[r₀+i][4s .. 4s+3]: bốn weight liên tiếp của output row r₀+i.
- `IBUF[s]` word *j* = x_j[4s .. 4s+3]: bốn input liên tiếp của ảnh j (4 ảnh mỗi batch).
- Trong DTCM, quad *s* của một LOAD tại address *a* nằm ở `a + 16s`, và word *i* (hay *j*) của quad đó ở `a + 16s + 4i`.
- Sau COMPUTE, `acc[i][j]` chứa dot product của output row r₀+i với ảnh j. Chỉ số READ_RESULT `idx = 4*i + j`.

### 6.3 Semantics

| Lệnh | Tác dụng |
|---|---|
| `LOAD_WEIGHT a, K` | với s trong 0..K/4-1: `WBUF[s] ← DTCM[a + 16s .. a + 16s + 15]` (mỗi s một lần đọc port B 128 bit) |
| `LOAD_INPUT a, K` | với s trong 0..K/4-1: `IBUF[s] ← DTCM[a + 16s .. a + 16s + 15]` |
| `COMPUTE K, clr` | `acc[i][j] ← (clr ? 0 : acc[i][j]) + Σ_{s<K/4} Σ_{t<4} sext(WBUF[s].word_i.lane_t) · sext(IBUF[s].word_j.lane_t)`, số học mod 2³² |
| `READ_RESULT rd, idx` | `rd ← acc[idx/4][idx%4]` |

**Luật thứ tự:**
1. LOAD_WEIGHT, LOAD_INPUT và COMPUTE được đẩy vào command FIFO theo thứ tự chương trình và chạy theo thứ tự, mỗi lần một lệnh.
2. Lệnh được đẩy khi nó ở tầng **MEM**. Vì vậy mọi store cũ hơn đã ghi xong vào DTCM, nên phụ thuộc RAW qua DTCM an toàn mà không cần thêm logic.
3. FIFO đầy thì pipeline stall ở MEM.
4. **READ_RESULT** stall ở MEM cho tới khi `fifo_empty && fsm == IDLE`. Sau đó nó trả data ở WB giống một lệnh load và dùng lại logic load-use hazard. Đây là barrier duy nhất.
5. **Luật phần mềm (WAR):** firmware không được store vào một word DTCM mà một LOAD đang chờ hoặc đang chạy sẽ đọc. Thoả luật này bằng cách gọi READ_RESULT (lệnh này drain engine) trước khi ghi đè buffer. Luật được kiểm bằng assertion A-SOC-1 (§10.6).
6. Address của LOAD phải align 16 byte (align theo quad); xem bảng lỗi.

**Xử lý lỗi.** Lệnh vi phạm luật bị bỏ và set một sticky bit trong `npu_status`. Chương trình chạy tiếp.

| Điều kiện | Tác dụng |
|---|---|
| K = 0 (LDW, LDI hoặc MAC; không áp cho ILLEGAL, xem D16) | không làm gì, không lỗi |
| K > KMAX, hoặc K không chia hết cho 4 | bỏ lệnh, `err_k` ← 1 |
| LOAD có `a[3:0] ≠ 0` | bỏ lệnh, `err_align` ← 1 |
| LOAD có `a < DTCM_BASE` hoặc `a + 4K > DTCM_BASE + DTCM_BYTES` (tính không wrap 32 bit) | bỏ lệnh, `err_addr` ← 1 |
| funct3 ∈ {100..111} | core đẩy op `ILLEGAL`; engine set `err_illegal` ← 1 và không làm gì khác, bất kể K, `cmd_addr` và clr mà lệnh mang theo (D16) |
| READ_RESULT có `rs1[31:4] ≠ 0` | bỏ qua bit cao, không lỗi |

### 6.4 CSR

Các CSR được cài đặt trong engine, và CSR unit của core truy cập chúng qua CSR port (§7.1).

`npu_status` (0x7C0):

| Bit | Tên | Truy cập | Ý nghĩa |
|---|---|---|---|
| 0 | `busy` | RO | `fsm != IDLE` |
| 1 | `fifo_empty` | RO | |
| 2 | `fifo_full` | RO | |
| 8 | `err_k` | W1C, sticky | |
| 9 | `err_addr` | W1C, sticky | |
| 10 | `err_illegal` | W1C, sticky | |
| 11 | `err_align` | W1C, sticky | |
| các bit khác | — | RO 0 | |

`npu_busy_cyc` (0x7C1): bộ đếm 32 bit đếm số cycle có `fsm != IDLE`. Nó chạy trên free clock. Một CSR write set giá trị của nó; write trong cycle đang busy thì thắng phép tăng (D17).

CSR write dùng giá trị mà core đã tính cho lệnh CSR (D17). Xoá error bit bằng `csrw npu_status, <bits>` hoặc `csrrwi`. `csrrs`/`csrrc` với mask khác 0 cũng ghi và, do W1C, sẽ xoá nhiều hơn những gì mask gợi ý. `csrr` không ghi.

## 7. Vi kiến trúc MAC engine (Track B)

### 7.1 Interface (trạng thái freeze: xem dòng trạng thái ở header)

```
// command push (core MEM stage → engine), free clock domain
input  cmd_valid; output cmd_ready;          // ready = !fifo_full
input  [1:0] cmd_op;                          // 0 LDW, 1 LDI, 2 MAC, 3 ILLEGAL
input  [31:0] cmd_addr; input [31:0] cmd_k; input cmd_clr;
// result read (core MEM stage)
input  rd_req; input [3:0] rd_idx;
output rd_ready;                              // fifo_empty && fsm==IDLE
output [31:0] rd_data;                        // valid when rd_req && rd_ready
// CSR port
input  csr_we; input [11:0] csr_addr; input [31:0] csr_wdata; output [31:0] csr_rdata;
                                              // csr_wdata = new value computed by the core; csr_we only when the instruction writes (D17)
                                              // csr_rdata = f(csr_addr, registered state) only, same cycle; no path from csr_we/csr_wdata; reads have no side effects (D21)
                                              // csr_addr may hold any value in cycles without a CSR instruction; other addresses read 0 and ignore writes (D21)
// DTCM port B (read-only, 1-cycle latency)
output b_req; output [11:0] b_addr;           // quad index within DTCM (4096 quads)
input  [127:0] b_rdata;                       // 4 words (bank 0 = bits [31:0]), valid the cycle after b_req
// clocks
input clk, rst_n;                             // free clock; rst_n active low, async assert / sync deassert (D18)
```

(Comment trong khối code giữ nguyên tiếng Anh vì đây là nội dung chuẩn của interface. Nghĩa: `csr_wdata` là giá trị mới core đã tính, `csr_we` chỉ bật khi lệnh thực sự ghi; `csr_rdata` chỉ phụ thuộc `csr_addr` và state đã register, có ngay trong cycle, không có đường từ `csr_we`/`csr_wdata`, đọc không có side effect; `csr_addr` có thể mang giá trị bất kỳ khi không có lệnh CSR, address khác đọc ra 0 và bỏ qua write; port B có latency 1 cycle, `b_addr` là chỉ số quad; `rst_n` active low, assert bất đồng bộ, nhả đồng bộ.)

### 7.2 Hành vi

- **Các state của FSM:** `IDLE`, `CHECK`, `LOAD`, `MAC`. Ở `CHECK`, lệnh ở đầu FIFO được pop ra và kiểm tra (bảng lỗi §6.3). LOAD hợp lệ chuyển sang `LOAD`: nó phát K/4 lần đọc quad trên port B và ghi vào WBUF hoặc IBUF. MAC hợp lệ chuyển sang `MAC`: nó đọc `WBUF[s]` và `IBUF[s]` và cập nhật cả 16 accumulator mỗi cycle (64 MAC).
- **Latency:** mỗi lệnh phải xong trong vòng K/4 + 3 cycle kể từ lúc pop. Số cycle chính xác do Track B ghi trong `docs/mac_engine.md`. Scoreboard UVM kiểm giá trị chứ không kiểm latency. Latency chỉ bị giới hạn bởi assertion timeout A-MAC-5.
- **PE (dot4):** mỗi step một cycle (Senior Project 2 không pipeline): `acc_ij <= acc_ij + Σ_{t<4} sext8(a_i[t]) * sext8(b_j[t])`, tức mỗi PE có 4 bộ nhân và một cây cộng 3 bộ cộng, tổng cộng 64 bộ nhân. Khi clr được set, step đầu tiên nạp thẳng dot product thay vì cộng vào.
- **Buffer:** mảng RAM single-port đồng bộ, được ghi ở `LOAD` và đọc ở `MAC`. Hai việc này không bao giờ xảy ra cùng lúc vì mỗi lần chỉ chạy một lệnh.
  - Buffer **không bị reset** và giữ nội dung giữa các lệnh.
  - COMPUTE đọc entry 0..K/4-1 bất kể K của lần LOAD gần nhất là bao nhiêu.
  - Đọc một entry chưa từng được ghi kể từ reset là lỗi của test, không phải lỗi của DUT. Random sequence bị ràng buộc để K/4 của COMPUTE không bao giờ vượt quá số entry nhỏ nhất đã được ghi kể từ reset trong WBUF hoặc IBUF. Predictor báo `UVM_ERROR` nếu một sequence vi phạm luật này.

### 7.3 Clock domain

| Free clock `clk` | Gated clock `clk_mac` |
|---|---|
| cmd FIFO, FSM, CSR, `npu_busy_cyc`, request và bộ đếm address của port B | WBUF, IBUF, các register datapath của PE, 16 accumulator |

READ_RESULT đọc accumulator theo kiểu tổ hợp. Accumulator giữ giá trị trong lúc bị gate.

## 8. Clock gating (D0/D1)

- `npu_clk_gate` (`rtl/prim/npu_clk_gate.sv`, clock-gating cell duy nhất trong thiết kế, D19): một latch trong suốt khi `clk` ở mức thấp, theo sau là một cổng AND.
  ```
  always_latch if (!clk) en_l = en | test_en;
  assign gclk = clk & en_l;
  ```
  Nhóm tự viết cell này. Nó theo cùng mẫu với nhánh mặc định của CoralNPU `hdl/verilog/ClockGate.sv`. Thêm pragma `/* verilator clock_enable */` ở output của latch. Cho FPGA ở khoá luận, một biến thể `BUFGCE` đặt sau `` `ifdef FPGA_XILINX ``.
- **Enable:** `en = !rst_n_sync || (fsm != IDLE) || !fifo_empty`.
  - Term `!rst_n_sync` giữ clock chạy trong lúc reset, để reset đồng bộ trong gated domain vẫn có tác dụng.
  - Các term còn lại lấy thẳng từ register, nên `en` không glitch ở latch. Một lần push ở cycle *t* làm `fifo_empty` xuống thấp ở *t+1*. Latch mở trong nửa chu kỳ thấp của *t+1*, và cạnh gated đầu tiên tới ở *t+2*, đúng lúc FSM lần đầu cần tới datapath. **Vì vậy gating không thêm cycle nào, nên D0/D1 giống nhau từng cycle là làm được (SC3).**
- **D0:** `GATING_EN = 0`, nên `en` bị buộc lên 1 bên trong `npu_clk_gate` (D19) và instance vẫn giữ nguyên. D0 và D1 có cùng hierarchy và cùng netlist, chỉ khác chỗ buộc đó.
- **Bất biến an toàn (assertion A-GATE-1):** `(fsm != IDLE || !fifo_empty) |-> en`.

## 9. Firmware và pipeline MNIST

### 9.1 Build

- C bare-metal với `crt0.S` và `link.ld` (ITCM cho `.text`; DTCM cho `.data`, `.bss` và stack).
- Flag: `-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32 -O2`.
- Toolchain ứng viên: xPack `riscv-none-elf-gcc` (hỗ trợ Zbb cần xác nhận ở S5).
- `npu.h` cung cấp `npu_load_w(addr,k)`, `npu_load_i(addr,k)`, `npu_compute(k,clr)` và `npu_read(idx)` dưới dạng wrapper inline-assembly `.insn`. Tất cả, trừ `npu_read`, có clobber `"memory"`.
- ELF → `itcm.hex` / `dtcm.hex` cho `$readmemh`.

### 9.2 Layout DTCM (batch 4 ảnh)

| Symbol | Nội dung | Word | Byte | Khoảng address |
|---|---|---|---|---|
| W1 | 16 tile × 784 (đóng gói theo §6.2) | 12.544 | 50.176 | `0x1_0000–0x1_C3FF` |
| W2 | 8 tile × 64 | 512 | 2.048 | `0x1_C400–0x1_CBFF` |
| W3 | 3 tile × 32 (10 row đệm lên 12 bằng số 0) | 96 | 384 | `0x1_CC00–0x1_CD7F` |
| B1, B2, B3 | bias int32, 64 + 32 + 12 | 108 | 432 | `0x1_CD80–0x1_CF2F` |
| QP | tham số requant | 16 | 64 | `0x1_CF30–0x1_CF6F` |
| X | input layer 1, 784 word × 4 ảnh | 784 | 3.136 | `0x1_CF70–0x1_DBAF` |
| ACT1 | output layer 1, 64 word | 64 | 256 | `0x1_DBB0–0x1_DCAF` |
| ACT2 | output layer 2, 32 word | 32 | 128 | `0x1_DCB0–0x1_DD2F` |
| LOGITS | int32, 12 row × 4 ảnh | 48 | 192 | `0x1_DD30–0x1_DDEF` |
| MAILBOX | cờ TB→FW "batch tiếp theo đã sẵn sàng" | 1 | 4 | `0x1_DDF0–0x1_DDF3` |
| trống / stack | | | 8.716 | `0x1_DDF4–0x1_FFFF` |

Vùng dữ liệu tổng cộng 56.816 B. Base của mọi vùng đều align 16 byte, như quad LOAD yêu cầu. Weight tile được lưu theo từng quad: word ở byte offset `16s + 4i` (trong tile) chứa W[4t+i][4s..4s+3]; X và các buffer activation chứa, tại byte offset `16s + 4j`, bốn giá trị 4s..4s+3 của ảnh j. Model là **784-64-32-10** (quyết định 2026-10-14); export đã retrain được commit ở `model/py/export/` (2026-10-23, D14), và `pack_weights.py` không được sinh image này từ bất kỳ export nào khác. `pack_weights.py` sinh image này và các linker symbol của nó. Address chính xác của symbol lấy từ linker map, không hard-code.

### 9.3 Vòng lặp từng layer (thuật toán tham chiếu)

```
npu_load_i(IN, K)                              // once per layer; IBUF reused across tiles
for t in 0 .. N_out/4 - 1:
    npu_load_w(W + t*4K, K)                    // a tile is 4 rows × K bytes = 4K bytes
    npu_compute(K, clr=1)
    for i in 0..3, j in 0..3:
        v = npu_read(4*i + j) + B[4t + i]
        out[i][j] = requant(v)                 // final layer keeps int32
    for j in 0..3: OUT[16t + 4j] = pack(out[0][j], out[1][j], out[2][j], out[3][j])
                                               // neurons 4t..4t+3 of image j = next layer's quad t, word j
```

(Nghĩa các comment: `npu_load_i` gọi một lần mỗi layer, IBUF được dùng lại cho mọi tile; một tile là 4 row × K byte = 4K byte; layer cuối giữ int32; neuron 4t..4t+3 của ảnh j trở thành quad t, word j của layer kế tiếp.)

`requant()` phải **giống từng bit** với golden model. Công thức (từ `model/py/golden_int8.py`, các hàm `requant` và `find_ms`):

```
acc = Σ x·w + b_q                       // bias added before requant (int32)
y   = clamp((acc * M + 2^(S-1)) >>> S, 0, 127)   // arithmetic shift; clamp 0 also acts as ReLU
```

(Bias được cộng trước khi requant, dạng int32; `>>>` là shift số học; clamp tại 0 đồng thời đóng vai trò ReLU.)

`find_ms` chọn `S` lớn nhất sao cho `M ≥ 1` và `bound·M + 2^(S−1) ≤ 2³¹−1`, với `bound = max_j (Σ|w_q[j]|·127 + |b_q[j]|)`. Nhờ vậy tích không bao giờ tràn int32, nên firmware chỉ cần `mul` (32 bit thấp), `add`, `srai`, `max`, `min`; không cần `mulh`. Weight được quantize về ±127 (không bao giờ có −128). `M`, `S` từng layer nằm trong vùng QP của DTCM. Layer cuối ghi logit int32 vào LOGITS. Cả testbench lẫn golden đều tính argmax.

### 9.4 Giao thức batch

1. Firmware chạy một batch.
2. Nó ghi `SIM_CTRL = BATCH_DONE`.
3. Testbench đọc LOGITS bằng backdoor, so với file golden, nạp X tiếp theo bằng backdoor và set MAILBOX = 1.
4. Firmware poll MAILBOX, xoá nó và chạy tiếp.

READ_RESULT cuối cùng đã drain engine trước bước 2, nên việc ghi X bằng backdoor không thể vi phạm luật WAR.

## 10. Kiến trúc verification

### 10.1 Các môi trường

| Env | DUT | Người phụ trách | Agent và thành phần |
|---|---|---|---|
| `mac_env` | `mac_engine` | B | `cmd_agent` (active: push, read, CSR); `dtcm_agent` (responder phản ứng, giữ một memory model 16K word); predictor gọi `npu_ref` (DPI-C); scoreboard; coverage; SVA bind vào DUT |
| `core_env` | core + ITCM + DTCM, engine thay bằng stub (luôn ready, log các lệnh, trả `rd_data = idx`, đọc CSR trả 0) | A | `npu_rvvi_agent` (passive); `npu_cosim_checker` chạy `rv_iss` lockstep (DPI-C), tương ứng với `coralnpu_rvvi_agent` + `coralnpu_cosim_checker` của Coral (D13); các sequence luồng lệnh nạp ITCM bằng backdoor; covergroup cho từng extension |
| `soc_env` | `npu_top` | A+B | `npu_rvvi_agent` + `npu_cosim_checker` với `rv_iss` lockstep (custom instruction của nó gọi `npu_ref`, nên cả hệ thống được dự đoán); `fifo_monitor`; `sim_ctrl_monitor`; bộ so file MNIST; harness tương đương D0/D1 |

**Cấu trúc chung (D13):** mỗi env nằm trong một package (`mac_env_pkg`, `core_env_pkg`, `soc_env_pkg`); `tb/uvm/tb/npu_tb_top.sv` khởi tạo DUT cho `soc_env`; mỗi env có một file list compile (`*_dv.f`). Chương trình và dữ liệu được nạp bằng backdoor trước khi nhả reset. **Kết thúc test:** một lần ghi PASS/FAIL vào `SIM_CTRL`, hoặc tín hiệu halt/fault của core nếu policy W2-1 có định nghĩa, hoặc timeout (mặc định 10× số cycle dự kiến). Timeout là fail.

### 10.2 Golden model (C, compile cho DPI-C và thành file chạy unit test độc lập)

**`npu_ref.c`:**
- `npu_ref_reset()`
- `npu_ref_mem_write(word_idx, data)`
- `npu_ref_cmd(op, addr, k, clr)`
- `npu_ref_read(idx)`
- `npu_ref_status()`
- `npu_ref_csr_write(addr, data)`
- `npu_ref_csr_read(addr)`: trả `npu_status` cho 0x7C0, giá trị đã lưu cho 0x7C1, 0 cho mọi address khác (`ISS_FULL` cần hàm này để phục vụ các lần đọc CSR)

Model tham chiếu giữ một DTCM image riêng. Mọi sequence ghi vào memory của responder cũng gọi `npu_ref_mem_write`.

**`golden_int8.py`** (`model/py/`, numpy thuần, quyết định D15): `quantize_input`, `requant`, `find_ms`, `compute_bound`, `IntModel` và `load_export`. Đây là oracle số nguyên cho SC5 và `pack_weights.py`. **Gate:** `python -m pytest model/py/tests -v` phải pass, kể cả bước đối chiếu một tile K = 784 với `npu_ref`, trước khi được dùng.

**`rv_iss.c`:** instruction-set simulator cho RV32IM + Zicsr + Zifencei + Zbb + custom-0.
- API: `iss_init(itcm, dtcm)` và `iss_step(&rec)`, trả về retire record dự kiến.
- Không mô hình hoá: giá trị `mcycle` (phép so sánh mask các lần đọc CSR 0xB00/0xB80/0xC00/0xC80 và `npu_busy_cyc`).
- Mode: `ISS_STUB` (cho `core_env`; custom instruction mô phỏng stub, nên READ_RESULT trả `idx` và đọc 0x7C0/0x7C1 trả 0) và `ISS_FULL` (cho `soc_env`; custom instruction gọi `npu_ref`).

**Gate trước khi dùng:** mỗi golden model phải pass unit test của chính nó trước khi được dùng làm oracle. Với `npu_ref`, các test gồm các trường hợp 4×4 tính tay, wrap khi tràn và mọi trường hợp lỗi. Với `rv_iss`, gồm các corner case của lệnh và signature của riscv-arch-test nếu có.

### 10.3 Danh sách test (tối thiểu)

| Env | Directed | Random |
|---|---|---|
| mac | một LDW/LDI/MAC với K=4; K=KMAX; K=0; K=KMAX+4; K=6 (không chia hết cho 4); address không align (`a[3:0]=4`); address ngoài vùng; op illegal; clr so với cộng dồn; ép wrap (cộng dồn lặp lại với operand ±128·±128); đẩy FIFO tới đầy bằng các push liên tiếp; READ trong lúc busy; W1C xoá error bit | `mac_rand_seq`: trộn op ngẫu nhiên, K theo các bin có trọng số, operand ngẫu nhiên thiên về giá trị biên, khoảng cách ngẫu nhiên giữa các lệnh (0–20 cycle), ≥ 200 seed |
| core | từng lệnh: mọi lệnh M/Zbb/Zicsr/Zifencei kể cả corner của div; khoảng cách hazard 1/2/3 cho từng đường forwarding; load-use; decode custom instruction và timing push (với stub); stall khi FIFO đầy (stub với `ready = 0`) | `core_rand_seq`: luồng ALU/M/Zbb ngẫu nhiên với khoảng cách phụ thuộc có kiểm soát, rồi tới luồng có branch; ≥ 200 seed |
| soc | mỗi custom instruction một test firmware; test âm vi phạm WAR (chờ A-SOC-1 bắn); matmul 4×4×K so với `npu_ref`; matmul cỡ một layer (784×64); MNIST 1.000 ảnh (D11) | `soc_rand_matmul`: Python sinh ma trận int8 M×K×N ngẫu nhiên cùng dữ liệu firmware từ một seed |

### 10.4 Harness tương đương D0/D1

Chạy cùng một test với cùng binary và seed trên `GATING_EN=0` và `GATING_EN=1`. So sánh:
- SHA-256 của log RVVI retire
- `mcycle` và `minstret` cuối cùng
- bản dump LOGITS

Mọi test soc và mọi lần chạy MNIST đều chạy ở cả hai cấu hình. Bất kỳ khác biệt nào cũng là fail (SC3).

### 10.5 Coverage plan (khai báo đủ bin trước tuần 7; phải đóng trước tuần 10)

| Group | Bin |
|---|---|
| `cg_cmd` | op {LDW, LDI, MAC, ILLEGAL} × K {0, 4, 8–60, 64–KMAX-4, KMAX, >KMAX} × K mod 4 {0, 1, 2, 3}; MAC × clr {0, 1} × acc khác 0 trước đó {0, 1} |
| `cg_operand` | từng lane (16 lane mỗi quad), giá trị ∈ {-128, -1, 0, 1, 127, khác} cho WBUF và IBUF |
| `cg_fifo` | độ đầy lúc push {0, 1, 2–6, 7, 8=đầy}; quan sát được push khi đầy (stall) |
| `cg_state` | chuyển IDLE→CHECK, CHECK→LOAD, CHECK→MAC, CHECK→IDLE (bị bỏ), LOAD→IDLE, MAC→IDLE; READ tới trong lúc busy |
| `cg_acc` | kết quả cộng dồn wrap từ dương sang âm và từ âm sang dương |
| `cg_err` | từng error bit được set; set khi đã set sẵn; xoá bằng W1C |
| `cg_addr` | LOAD chạm quad đầu tiên của DTCM, quad cuối cùng, một quad quá cuối; `a[3:0]` ∈ {0, 4, 8, 12, khác} |
| `cg_gate` (chỉ D1) | en lên, en xuống, en thấp 1 cycle, en thấp ≥ 100 cycle |
| core `Cvgrp_*` | từng extension: mọi opcode; rd = x0 và rd ≠ x0; rs1 = rs2; nguồn forwarding {EX/MEM, MEM/WB, không có}; DIV {÷0, overflow, bình thường}; CSR {rw, rs, rc, các biến thể imm} × {0xB00, 0xB02, 0x7C0, 0x7C1} |

### 10.6 Assertion (SVA)

| ID | Thuộc tính |
|---|---|
| A-MAC-1 | không push khi FIFO đầy; không pop khi rỗng |
| A-MAC-2 | `rd_ready |-> (fifo_empty && fsm==IDLE)` |
| A-MAC-3 | `b_req` chỉ có ở `LOAD`; `b_addr` luôn nằm trong DTCM |
| A-MAC-4 | buffer không bao giờ bị ghi ngoài `LOAD` |
| A-MAC-5 | mọi lệnh đã pop đều về IDLE trong vòng K/4 + 3 cycle |
| A-GATE-1 | `(fsm != IDLE || !fifo_empty) |-> en` (không bao giờ gate khi còn việc) |
| A-GATE-2 | khi `GATING_EN = 1` và `en_l = 0`, `clk_mac` giữ mức thấp |
| A-SOC-1 | một store qua port A vào word *w* trong lúc một LOAD đang chờ hoặc đang chạy phủ lên *w* là vi phạm WAR (lỗi) |
| A-CORE-1 | trong lúc READ_RESULT stall ở MEM, không lệnh trẻ hơn nào được write back |

## 11. Phương pháp đo switching activity

**Workload:**
- Firmware **synthetic** xen kẽ các đợt NPU (LDW + LDI + MAC với K=256) với vòng lặp bận của scalar. Tỉ lệ idle là 10, 25, 50, 75 và 90 % (đo bằng `npu_busy_cyc / mcycle`).
- **MNIST**, 100 ảnh = 25 batch (E4, D11). Đối chiếu chéo: đặt tỉ lệ idle của MNIST (`npu_busy_cyc / mcycle`) lên đường cong synthetic E2 thì phải dự đoán được kết quả E4 trong phạm vi độ phân tán của các điểm E2.

**Cửa sổ đo:** firmware ghi `SIM_CTRL = MEAS_START` và `MEAS_STOP`. Chỉ dump VCD/FST trong cửa sổ đó và chỉ cho scope `npu_top.u_mac_engine`.

**Metric:**
- **M1:** số toggle trên net `clk_mac`.
- **M2:** tổng số toggle của mọi net trong `u_mac_engine`, tách thành M2-free và M2-gated.
- Cả hai được báo cáo theo mỗi 1.000 cycle. Lưu ý M1 gần như tỉ lệ với phần thời gian busy, còn M2 phản ánh hoạt động dữ liệu thật.

**Công bằng:** D0 và D1 dùng cùng binary, cùng phiên bản simulator và cùng tuỳ chọn dump. Mỗi cấu hình chỉ chạy một lần; chỉ chạy lại sau một lỗi bên ngoài đã được ghi log.

**Tooling:** `power/toggle_count.py` đọc VCD, ghi CSV, và `power/plots.py` vẽ hình. Mọi hình đều ghi rõ cấu hình, workload, seed và đơn vị, và được gắn nhãn "switching-activity estimate". Nếu có lần chạy nào dùng Verilator (D1a), một lần chạy VCD QuestaSim cùng workload sẽ đối chiếu lại số đếm.

## 12. Tool, repository và khả năng tái lập

```
mini-npu/
  rtl/{core,npu,mem,top,prim}/   rtl/prim/npu_clk_gate.sv   rtl/top/npu_pkg.sv
  tb/uvm/{common,mac_env,core_env,soc_env,tb}/   tb/sva/
  model/c/{npu_ref.c,rv_iss.c,tests/}   model/py/{golden_int8.py,pack_weights.py,gen_matmul.py}
  sw/{crt0.S,link.ld,npu.h,tests/,mnist/,synthetic/}
  sim/questa/   sim/verilator/   power/   notebooks/   docs/
  manifest.yaml   Makefile (or run.py)
```

- `manifest.yaml` ghi phiên bản QuestaSim (và loại licence), Vivado, Verilator, GCC và Python, git hash, seed và danh sách test.
- Điểm vào của regression `run.py --simulator {questa,xsim} --target <test|suite> [--config d0|d1] [--seeds N]` (cùng kiểu interface với `utils/run_uvm_regression.py` của Coral, D13) in pass/fail cho từng test × seed và gộp coverage. `run.py all` sinh lại mọi artefact SC1–SC5 và dữ liệu E2/E4 (SC6).
- Log thô và VCD lưu ở `out/<date>/<config>/`. File lớn không commit; chỉ ghi lại hash của chúng.

## 13. Cổng smoke test tuần 1

Mỗi mục trả lời "chạy được / không chạy được, kèm bằng chứng (log)". Proposal (Bảng 1, 3, 9, 11 và 12) được cập nhật sau cổng này.

| ID | Kiểm tra |
|---|---|
| S1 | QuestaSim compile và chạy một `uvm_test` tối thiểu có class gọi `randomize()`, và `` `uvm_info `` in được ra (đây là bước sẽ fail trên bản FPGA Starter) |
| S2 | QuestaSim gọi một hàm C qua DPI-C (`import "DPI-C"`), truyền int và `bit [31:0]` |
| S3 | Functional coverage của QuestaSim (một covergroup) sinh được report (`vcover report`) |
| S4 | Verilator lint một thiết kế nhỏ; mô phỏng một `icg_cell` có latch và dump VCD trong đó `gclk` dừng khi `en = 0` |
| S5 | Toolchain GCC assemble được một lệnh Zbb (`max`) và một `.insn r 0x0B, ...`; objcopy sinh được file hex cho `$readmemh` |
| S6 | Vivado xsim chạy cùng test S1 (kiểm phương án dự phòng, 15 phút) |
| S7 | QuestaSim dump VCD cho một scope được chọn trong một cửa sổ thời gian được chọn (`vcd file`, `vcd add`) |

## 14. Phân công và lịch tổng quát

Lịch (D22): tuần 1 là Thứ Hai 2026-10-12 tới Chủ nhật 2026-10-18; tuần *N* bắt đầu sau đó 7(*N*−1) ngày. Các phase kết thúc vào Chủ nhật 2026-11-08 (1), Chủ nhật 2026-12-13 (2), Chủ nhật 2027-01-03 (3) và Chủ nhật 2027-01-31 (4).

| Tuần | Track A (core) — Tấn | Track B (MAC engine) — Bảo | Chung |
|---|---|---|---|
| 1 | S1–S7 (chia nhau) | S1–S7 (chia nhau) | review cổng |
| 2 | tài liệu ISA và encoding, CSR map, policy trap/fault | freeze interface engine (§7.1), `npu_ref` + unit test | ký §6 và §7.1 |
| 3–4 | M, Zicsr, Zifencei, Zbb, decode/push custom; `rv_iss` + unit test | RTL `mac_engine` (D0); `dtcm_dp`; khung `mac_env` | |
| 5–6 | `core_env` + directed test | directed test cho `mac_env` | tích hợp `npu_top`, test soc đầu tiên |
| 7–9 | random + coverage cho core | random + coverage cho mac | test soc, đóng coverage (SC2) |
| 10–11 | — | `npu_clk_gate`, D1 | harness tương đương, regression D1 (SC3) |
| 12 | firmware synthetic | `toggle_count.py` | dữ liệu E2 |
| 13–14 | firmware MNIST | `pack_weights.py`, file golden | MNIST 1.000 ảnh bit-exact trên D0/D1 (SC5); khung báo cáo |
| 15 | | toggle MNIST E4 (100 ảnh) | chạy đủ 10.000 ảnh (D0); `run.py all` trên một clone sạch (SC6) |
| 16 | | | báo cáo tiếng Anh, slide, gói tái lập (D12) |

Các chương báo cáo được viết nháp khi kết thúc phase: verification (tuần 10), power (tuần 13), MNIST và kết luận (tuần 15).

Plan chi tiết theo task (kèm test "done" cho từng task) được viết tiếp trong `docs/superpowers/plans/`.

## 15. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Không có licence QuestaSim đầy đủ, hoặc thiếu tính năng (UVM/DPI/coverage) | Phát hiện ở tuần 1 (S1–S3). Dự phòng: xsim (S6). Cách cuối cùng: Verilator UVM hoặc pyuvm. |
| Questa chạy các batch MNIST quá lâu | Đo ở tuần 14. Chỉ để hình dung độ lớn: Coral báo model RTL Verilator của họ chạy khoảng 15 kcycle/s (một thiết kế khác và lớn hơn), như vậy 1.000 ảnh (≈3M cycle) mất vài phút. Nếu quá chậm: chạy dài trên Verilator kèm đối chiếu Questa (D1a). Thứ tự cắt nếu trễ: bỏ lần chạy 10.000 ảnh, rồi giảm E4 xuống 20 ảnh; SC3 trên MNIST và báo cáo không bao giờ bị cắt. |
| `rv_iss` trễ, chặn `core_env` | Giữ ISS tối thiểu và test nó trước. Tạm thời: dùng signature tự kiểm của riscv-arch-test làm directed test. |
| Interface giữa hai track thay đổi liên tục | Freeze §6 và §7.1 vào cuối tuần 2. Thay đổi sau đó cần cả hai sinh viên ký và cập nhật spec. |
| Firmware có bug WAR trên DTCM | Luật phần mềm cộng A-SOC-1, và một test âm chứng minh assertion có bắn. |
| Requant lệch với golden | Công thức chốt ở §9.3; unit test hàm `requant()` của firmware trên máy host so với `golden_int8.requant` với `M`, `S` đã retrain. |
| Áp lực lịch | Giữ thứ tự D0 đúng → D1 tương đương → switching activity → MNIST. 8×8 và pipeline bị bỏ trước tiên. |

## 16. Quan hệ với CoralNPU (ranh giới đóng góp)

| Khía cạnh | CoralNPU (`VmeCoreMini`, commit `382b5c1`) | Mini-NPU |
|---|---|---|
| Scalar core | superscalar 4 lane, in-order, Chisel | pipeline 5 tầng của nhóm, Verilog/SV |
| ISA | RV32IMF_Zba_Zbb_Zicsr_Zifencei + RVV 1.0 + Zvt (thử nghiệm) | RV32IM_Zicsr_Zifencei_Zbb + 4 lệnh custom-0 |
| Đường lệnh | scalar dispatch → command queue 8 entry → backend tách rời | push ở tầng MEM → FIFO 8 entry → engine tách rời |
| Nạp operand | `vle8` từ DTCM vào vector register file 32×128 bit | LOAD của engine từ DTCM vào WBUF/IBUF |
| Tính toán ma trận | outer-product engine N×M×K (tài liệu: thường là 8×8×4 = 256 MAC/cycle, VDOT dot4 mỗi PE); VME trong repo: 16 tile `mt0..mt15`, INT8/FP32/BF16 | N×M×K = 4×4×4 = 64 MAC/cycle, PE dot4 int8, 1 tile |
| Đường kết quả | `vtmv.v.t` rồi `vse32` | READ_RESULT vào một scalar register |
| Memory | datasheet: ITCM 8 KB, DTCM 32 KB, SRAM một cycle; repo: DTCM chia bank (4 × 32 b) + crossbar, DBus 128 bit | ITCM 16 KB; DTCM 4 bank × 32 b, 64 KB (model cần 56,8 KB, D6); port A 32 b (core), port B 128 b (engine) |
| Clock gating | gate cả core khi WFI/CSR (`CoreAxi.scala`) | gate MAC engine khi phần cứng phát hiện idle |
| Verification | các suite cocotb; UVM trên VCS/Verilator với `coralnpu_rvvi_agent` (passive) và `coralnpu_cosim_checker` so với MPACT simulator (`tests/uvm/env/coralnpu_env_pkg.sv`, nhánh main, đọc ngày 2026-10-15); nạp ELF bằng backdoor; kết thúc khi `halted`/`fault` hoặc timeout | chỉ UVM SV tự xây; `npu_rvvi_agent` + `npu_cosim_checker` so với `rv_iss` của nhóm; model NPU C của nhóm; backdoor `$readmemh`; kết thúc bằng `SIM_CTRL`, halt/fault hoặc timeout |
| Bằng chứng power | mục tiêu power trong guide ("10 mW power envelope"); flow tách VCS của cocotb được giữ "cho gate-level power analysis" | chỉ ước lượng switching activity ở RTL (Senior Project 2 không synthesize) |
| Workload | MobileNet qua LiteRT; ví dụ matmul RVV (`tests/cocotb/rvv/ml_ops/`) | MLP int8 784-64-32-10 trên MNIST, C bare-metal |

**Trạng thái của matrix engine.** Phần giới thiệu trong developer guide vẫn nói matrix execution unit được lên kế hoạch cho một bản phát hành sau, trong khi repository ở `382b5c1` đã có một bản cài đặt VME (Zvt) thử nghiệm. Mini-NPU đi theo semantics đã được tài liệu hoá (outer product, N×M×K, dot4 vào int32) và không phụ thuộc vào RTL thử nghiệm đó.

Không dùng lại RTL hay code testbench nào của CoralNPU. CoralNPU được trích dẫn là nguồn cảm hứng kiến trúc, và các file nguồn của nó được trích dẫn ở những chỗ đã tham khảo một mẫu thiết kế (`ClockGate.sv`, cấu trúc `tests/uvm`, `vme_matmul_test_program.cc`).

## 17. Tài liệu tham khảo

- Áp dụng các tài liệu tham khảo [1]–[12] của proposal.
- Google, `google-coral/coralnpu`, commit `382b5c1`: `doc/overview.md`, `doc/microarch/*.md`, `hdl/verilog/ClockGate.sv`, `hdl/chisel/src/coralnpu/CoreAxi.scala`, `hdl/verilog/rvv/design/Zvt/`, `tests/uvm/README.md`, `tests/cocotb/vme_test/vme_matmul_test_program.cc`.
- Google, Coral NPU developer guides (developers.google.com/coral/guides): Introduction to Coral NPU (`intro-coralNPU`); Datasheet (`hardware/datasheet`); ML inferencing (`hardware/arch_ml`); Decode and dispatch (`hardware/decode-dispatch`); IP evaluation guide (`hardware/evaluation`); Performance and power (`power`); Bare-metal programming (`software/bare-metal-prog`); Matrix multiplication examples (`software/examples-matmuls`). Đọc ngày 2026-10-15.
- Google, `google-coral/coralnpu` nhánh main (đọc ngày 2026-10-15): `tests/uvm/README.md`, `tests/uvm/env/coralnpu_env_pkg.sv`, `tests/cocotb/README.md`.
- [PH] D. A. Patterson, J. L. Hennessy, *Computer Organization and Design: The Hardware/Software Interface, RISC-V Edition*, 2nd ed., Morgan Kaufmann, 2021.
- [ST] W. Stallings, *Computer Organization and Architecture: Designing for Performance*, 11th ed., Pearson, 2019.
- Hướng dẫn đọc theo chương cho từng task: `docs/references/README.md`.
- Altera, *Questa–Intel FPGA Edition Simulation User Guide*, mục "Simulator versions and licensing" (bản Starter: miễn phí, hiệu năng giảm). Altera Community, "Questa Starter Edition 25.1 – svverification license checkout fails" (câu trả lời của nhân viên: bản FPGA không hỗ trợ `randomize`/`covergroup`; cần QuestaSim đầy đủ).
