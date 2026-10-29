# Mini-NPU Phase 4 (Tuần 13–16): Implementation Plan — MNIST, E4, Tái lập, Báo cáo (bản tiếng Việt)

> **Bản dịch để đọc cho dễ.** Bản chuẩn là bản tiếng Anh `docs/superpowers/plans/2026-10-15-mini-npu-phase4-mnist-report.md`. Khi hai bản khác nhau, bản tiếng Anh thắng. Dịch ngày 2026-10-29 (commit ngay sau `a2b3a97`). Tên task, tên test, tên file, lệnh, câu commit và thuật ngữ kỹ thuật giữ nguyên tiếng Anh.

> **Cho agent:** BẮT BUỘC dùng sub-skill superpowers:subagent-driven-development (khuyến nghị) hoặc superpowers:executing-plans để làm plan này theo từng task. Các step dùng cú pháp checkbox (`- [ ]`) để theo dõi.
>
> **Luật của dự án (ghi đè dòng trên đối với phần được chấm điểm):** sinh viên tự viết toàn bộ RTL, logic golden model, UVM và firmware. Claude review dựa trên các test được nêu ở đây. Các task gắn **[support]** là tooling không chấm điểm, Claude có thể viết khi được yêu cầu.

**Mục tiêu:** Tới cuối tuần 16, MLP int8 784-64-32-10 chạy trên `npu_top` khớp bit-exact với `golden_int8.py` trên 1.000 ảnh test MNIST ở cả D0 và D1 (SC5), lần chạy switching activity trên MNIST (E4) đã xong, một lệnh sinh lại được mọi kết quả (SC6), và báo cáo tiếng Anh cùng slide bảo vệ đã nộp (D12).

**Kiến trúc:** `pack_weights.py` biến export đã retrain thành các DTCM image theo layout quad ở §9.2; firmware bare-metal chạy vòng lặp từng layer ở §9.3 với requantization giống từng bit; testbench lái giao thức batch ở §9.4 và so các file LOGITS (D8). E4 dùng lại flow dump/toggle của Phase 3 trên 100 ảnh và được đối chiếu với đường cong E2.

**Tech stack:** Python 3 (numpy), C bare-metal (RISC-V GCC), SystemVerilog/UVM trên QuestaSim, tooling của Phase 2/3 (`run.py`, `compare_runs.py`, `toggle_count.py`).

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` §9 (firmware, layout, requant, giao thức batch), §11 (E4), §12 (tái lập), D11, D12, SC5, SC6. Plan trước: `docs/superpowers/plans/2026-10-15-mini-npu-phase3-gating-power.md` (tag `phase3-d1`).

**Người phụ trách:** Track A = Nguyễn Hoàng Công Tấn, Track B = Nguyễn Thế Bảo.

| Task | Người phụ trách | Tuần |
|---|---|---|
| 25 · `pack_weights.py` + file golden | Bảo | 13 |
| 26 · Firmware MNIST + test requant trên host | Tấn | 13–14 |
| 27 · `soc_mnist`: 1.000 ảnh trên D0 và D1 | cả hai | 14 |
| 28 · E4: switching activity trên MNIST (100 ảnh) | Bảo | 15 |
| 29 · Chạy đủ 10.000 ảnh trên D0 | cả hai | 15 (cắt đầu tiên nếu trễ) |
| 30 · Gói tái lập | Claude **[support]** cho `run.py all`; cả hai kiểm | 15 |
| 31 · Báo cáo tiếng Anh + slide | cả hai | 13 → 16 |

## Ràng buộc chung (bổ sung cho Phase 4)

- Model: 784-64-32-10 lấy từ export đã retrain và commit trong `model/py/export/` (Phase 1 Task 2 và 2b; `manifest.json` của nó liệt kê SHA-256 từng file). SHA-256 của các file export được ghi trong `manifest.yaml`; mọi file hex sinh ra đều ghi hash của export mà nó được tạo từ đó.
- Layout DTCM đúng như §9.2 (base, kích thước, align 16 byte). W3 được đệm từ 10 lên 12 row bằng số 0; nhãn dự đoán là argmax chỉ trên row 0–9.
- Requant (§9.3): `y = clamp((acc * M + 2^(S−1)) >>> S, 0, 127)` với bias đã nằm trong `acc`; layer cuối giữ int32. Firmware chỉ dùng `mul`, `add`, `srai`, `max`, `min`.
- Vùng QP (§9.2, 16 word ở `0x1_CF30`): word 0 = M1, word 1 = S1, word 2 = M2, word 3 = S2, word 4–15 = 0.
- Giao thức batch (§9.4) có một mở rộng, ghi trong `docs/mnist.md`: MAILBOX = 1 nghĩa là "batch tiếp theo đã sẵn sàng", MAILBOX = 2 nghĩa là "hết batch", sau đó firmware ghi `SIM_CTRL = PASS`.
- Số ảnh (D11): 1.000 cho SC5 trên D0 và D1; 100 cho E4; 10.000 một lần trên D0.
- Timeout cho lần chạy dài: `+TIMEOUT_CYC = 10 × 12,000 × batches` (runner tự tính); mặc định 1M cycle của Phase 2 không được áp cho MNIST.
- Với các lần chạy MNIST, có thể tắt ISS lockstep bằng `+COSIM=0`; oracle là phép so file LOGITS (D8). Cosim vẫn bật cho test 1 batch.
- Thứ tự cắt nếu trễ (§15): bỏ Task 29, rồi giảm E4 xuống 20 ảnh. SC3 trên MNIST và báo cáo không bao giờ bị cắt.

## Review Focus

1. **Các trường hợp biên của requant:** accumulator âm, làm tròn đúng nửa, accumulator gần biên int32 mà `find_ms` tìm ra. Kỳ vọng: giống từng bit với `golden_int8.requant`. Test: Task 26 `requant_host_vectors`.
2. **State rò sang batch sau:** nội dung IBUF cũ hay accumulator của batch trước không được ảnh hưởng batch sau. Test: Task 27 `mnist_batch_order_independent`.
3. **Row đệm bị tính như class:** row 10–11 của W3 phải bằng 0 và bị argmax bỏ qua. Test: Task 25 `pack_w3_padding_zero`, bộ so sánh ở Task 27 tính nhãn trên row 0–9.
4. **Export và hex lệch nhau sau khi retrain:** file golden và DTCM image sinh từ hai export khác nhau sẽ cho một phép so sánh vô nghĩa. Test: Task 27 `mnist_export_hash_check` (lần chạy từ chối bắt đầu khi hash không khớp).
5. **Timeout và dung lượng đĩa ở lần chạy dài:** 1.000 ảnh (≈3M cycle) không được chạm timeout mặc định, và VCD của E4 phải nằm gọn trong scope engine và cửa sổ đo. Test: Task 27 chạy với timeout đã tính; Task 28 ghi kích thước VCD và fail nếu bản dump có net nằm ngoài `u_mac_engine`.

---

### Task 25: `pack_weights.py` và file golden — Track B, tuần 13

**File:**
- Tạo: `model/py/pack_weights.py`, `model/py/tests/test_pack.py`
- Tạo (sinh ra, không commit nếu lớn; hash ghi trong `manifest.yaml`): `build/mnist/dtcm_model.hex`, `build/mnist/x_batch_<b>.hex`, `build/mnist/golden_logits_<N>.hex`, `build/mnist/labels_<N>.txt`, `build/mnist/mnist_cfg.h`
- Tạo: `docs/mnist.md` (bảng layout chép từ §9.2 kèm address đã sinh, giao thức batch gồm MAILBOX = 2, các hash)

**Interface:**
- Dùng: export đã retrain trong `model/py/export/`; `golden_int8.load_export` và `golden_int8.IntModel` (Phase 1 Task 2b).
- Tạo ra:
  - `pack_weights.py --export model/py/export --n {100,1000,10000} --out build/mnist`
  - `pack_tile(W_rows: np.ndarray[int8, (4, K)]) -> bytes` (quad s, word i = `W[i][4s..4s+3]`, lane t = byte t); `unpack_tile(b: bytes, K: int) -> np.ndarray`
  - `pack_inputs(X: np.ndarray[int8, (4, K)]) -> bytes` (byte offset `16s + 4j` chứa `X[j][4s..4s+3]`)
  - `mnist_cfg.h`: các macro base của vùng (`W1_BASE` … `MAILBOX_ADDR`) và `N_BATCHES`

- [ ] **Step 1: Viết các test fail** (`test_pack.py`):
  - `pack_roundtrip`: `unpack_tile(pack_tile(W)) == W` với W ngẫu nhiên, K ∈ {784, 64, 32}
  - `pack_layer1_matches_golden`: kết quả int32 của layer 1 tính bằng numpy từ các byte **đã đóng gói** bằng kết quả layer 1 của `golden_int8.py` cho ảnh 0–3
  - `pack_regions_match_spec`: mọi base bằng address ở §9.2 và align 16 byte; tổng dữ liệu = 56.816 B
  - `pack_w3_padding_zero` (Review Focus 3): row 10–11 của W3 và bias của chúng bằng 0
  - `pack_qp_words`: QP word 0–3 bằng M1, S1, M2, S2 lấy từ `requant.json`; word 4–15 bằng 0
- [ ] **Step 2:** `pytest model/py/tests` → FAIL. **Step 3:** Cài đặt. **Step 4:** xanh.
- [ ] **Step 5: Commit** `feat(model): pack_weights and golden files`.

---

### Task 26: Firmware MNIST và test requant trên host — Track A, tuần 13–14

**File:**
- Tạo: `sw/mnist/main.c` (vòng lặp batch, §9.4 + MAILBOX = 2), `sw/mnist/mlp.c`, `sw/mnist/mlp.h`, `sw/mnist/requant.c`, `sw/mnist/requant.h`
- Tạo: `sw/mnist/host/test_requant_host.c` (build bằng gcc của host), `model/py/gen_requant_vectors.py` → `build/mnist/requant_vectors.txt`

**Interface:**
- Dùng: `npu.h`, `sim.h`, `mnist_cfg.h` (Task 25).
- Tạo ra:
  ```c
  int32_t requant(int32_t acc, int32_t m, int32_t s);           /* §9.3; returns 0..127 */
  void layer(uint32_t in_addr, uint32_t w_addr, const int32_t *bias,
             uint32_t out_addr, uint32_t k, uint32_t n_out,
             int32_t m, int32_t s, int keep_int32);                /* §9.3 loop */
  ```

- [ ] **Step 1: Viết các test fail:**
  - `requant_host_vectors` (Review Focus 1): `gen_requant_vectors.py` sinh ≥ 10.000 dòng `(acc, M, S, y)` từ `golden_int8.requant`, gồm `acc` âm, các giá trị `acc` có `(acc·M) mod 2^S = 2^(S−1)` (đúng nửa), và `|acc|` bằng `bound` của từng layer; `test_requant_host` assert mọi `y`
  - `mnist_1batch`: firmware trên `npu_tb_top` có bật cosim (`ISS_FULL`), ảnh 0–3: LOGITS (12 × 4 int32) bằng row 0–9 của `golden_logits` của các ảnh đó
- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt. **Step 4:** cả hai xanh.
- [ ] **Step 5: Commit** `feat(sw): MNIST firmware with bit-exact requant`.

---

### Task 27: `soc_mnist` — 1.000 ảnh trên D0 và D1 — cả hai, tuần 14

**File:**
- Tạo: `tb/uvm/soc_env/soc_mnist_comparator.sv` (khi có `BATCH_DONE`: đọc LOGITS bằng backdoor, so với `golden_logits_<N>.hex`, tính nhãn trên row 0–9, nạp `x_batch_<b>.hex` tiếp theo bằng backdoor, ghi MAILBOX = 1, hoặc 2 sau batch cuối)
- Sửa: `tb/uvm/soc_env/soc_test_pkg.sv` (test `soc_mnist`: `+MNIST_N=<n>`, `+MNIST_DIR=build/mnist`, tuỳ chọn `+BATCH_ORDER=<file>`)
- Sửa **[support]**: `run.py --target mnist_<n> [--config d0|d1]` tính `+TIMEOUT_CYC`; `run.py --target eq_mnist_1000`

**Interface:**
- Dùng: Task 25–26, `compare_runs.py` (Phase 3 Task 21).
- Tạo ra: `out/<date>/<config>/mnist_<n>/{logits.hex, labels.txt, summary.txt}`; `summary.txt` = `images, mismatched_logits, label_matches, wall_s, kcycles_per_s`.

- [ ] **Step 1: Viết các test fail:**
  - `mnist_export_hash_check` (Review Focus 4): với một file hex có hash export đã ghi khác `manifest.yaml`, test dừng trước reset với `UVM_FATAL "EXPORT_HASH"`
  - `mnist_batch_order_independent` (Review Focus 2): 8 ảnh chạy theo thứ tự batch (1, 0) → logit từng ảnh bằng với lần chạy theo thứ tự
  - `mnist_1000`: 250 batch, 0 logit lệch, `label_matches` bằng của golden
- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt.
- [ ] **Step 4:** `run.py --target mnist_1000 --config d0` và `--config d1` đều 0 mismatch (SC5); `run.py --target eq_mnist_1000` giống hệt kể cả `mcycle` (SC3 trên MNIST). Ghi `kcycles_per_s` vào `manifest.yaml` (thay cho ước lượng dựa trên Coral ở §15).
- [ ] **Step 5: Commit** `test: MNIST 1,000 images bit-exact on D0 and D1`.

---

### Task 28: E4 — switching activity trên MNIST, 100 ảnh — Track B, tuần 15

**File:**
- Sửa: `sw/mnist/main.c` (`sim_meas_start()` trước batch 0, `sim_meas_stop()` sau batch cuối; đọc delta của `mcycle`/`npu_busy_cyc` vào `0x0001_DDF4`/`0x0001_DDF8` như Phase 3 Task 22)
- Sửa **[support]**: `run.py --target e4` (`mnist_100`, D0 và D1, `+DUMP_ENGINE`, `toggle_count.py`)
- Tạo: `power/cross_check.py` (CSV E2 + CSV E4 → % thay đổi E2 nội suy tại tỉ lệ idle của MNIST, % thay đổi E4, chênh lệch, và độ phân tán của E2)
- Tạo: `docs/results/e4.md`

**Interface:**
- Dùng: output của Phase 3 Task 23–24 (`e2.csv`), Task 27.
- Tạo ra: `e4.csv` (cùng các cột với `e2.csv`, `workload = mnist_100`), `docs/results/e4.md`.

- [ ] **Step 1: Viết test fail** `cross_check_known`: các điểm E2 giả lập (10 %, 50 %, 90 %) và một dòng E4 ở 30 % → `cross_check.py` báo đúng giá trị nội suy tuyến tính và chênh lệch như test đã tính.
- [ ] **Step 2:** `pytest power/tests` → FAIL. **Step 3:** Cài đặt `cross_check.py`. **Step 4:** xanh.
- [ ] **Step 5:** `run.py --target e4` → 2 dòng; kiểm VCD chỉ chứa net của `u_mac_engine` (Review Focus 5) và ghi kích thước của nó vào `docs/results/e4.md`.
- [ ] **Step 6:** Viết `docs/results/e4.md`: tỉ lệ idle của MNIST, M1/M2 cho D0/D1, % thay đổi, đối chiếu với E2. Mọi giá trị đều gắn nhãn "switching-activity estimate".
- [ ] **Step 7: Commit** `data: E4 MNIST switching activity`.

---

### Task 29: Chạy đủ 10.000 ảnh trên D0 — cả hai, tuần 15 (cắt đầu tiên nếu trễ)

**File:**
- Tạo: `docs/results/mnist_full.md`

**Interface:**
- Dùng: Task 25–27 (`pack_weights.py --n 10000`).
- Tạo ra: accuracy của RTL trên 10.000 ảnh.

- [ ] **Step 1:** `run.py --target mnist_10000 --config d0`.
- [ ] **Step 2:** Kỳ vọng: 0 logit lệch; accuracy của RTL = accuracy int8 của golden cho model đã retrain (ghi ở spec §3.2 bởi Phase 1 Task 2). Ghi thời gian chạy thực, số cycle và accuracy vào `docs/results/mnist_full.md` và `manifest.yaml`.
- [ ] **Step 3: Commit** `data: MNIST full test set on RTL`.

---

### Task 30: Gói tái lập — Claude [support] cho runner, cả hai kiểm, tuần 15

**File:**
- Sửa **[support]**: `run.py all` = `regress_d0`, `regress_d1`, `eq_soc_all`, `eq_synthetic`, `e2`, `mnist_1000` (d0, d1), `eq_mnist_1000`, `e4`; ghi `out/<date>/hashes.txt` (SHA-256 của mọi CSV, hình, file LOGITS và report coverage)
- Sửa: `README.md` (mục "Reproduce": yêu cầu cài đặt kèm phiên bản, lệnh duy nhất, thời gian chạy dự kiến của từng target, nơi kết quả được ghi ra)
- Sửa: `manifest.yaml` (phiên bản tool kèm loại licence QuestaSim, git hash, seed, hash của export)

**Interface:**
- Tạo ra: bằng chứng SC6: một clone sạch cộng `run.py all` sinh lại mọi con số trong `docs/results/` và các report coverage.

- [ ] **Step 1: Test** `repro_clean_clone`: sinh viên **không** viết một flow nào đó clone repository vào một thư mục mới, chỉ làm theo mục "Reproduce" của README, rồi chạy `run.py all`.
- [ ] **Step 2:** Kỳ vọng: thoát mã 0; hash của mọi CSV/LOGITS trong `hashes.txt` mới bằng bản tham chiếu (hình có thể khác nhau ở metadata; so các CSV đầu vào của chúng).
- [ ] **Step 3:** Sửa mọi bước còn thiếu trong README hay runner; lặp lại tới khi Step 2 đúng.
- [ ] **Step 4: Commit** `chore: reproducibility package (SC6)` và gắn tag `phase4-final`.

---

### Task 31: Báo cáo tiếng Anh và slide bảo vệ — cả hai, tuần 13 → 16 (D12)

**File:**
- Tạo/mở rộng: `docs/report/` (bản nháp từng chương bằng Markdown; chuyển sang định dạng cuối cùng mà khoa yêu cầu ở tuần 16): `ch1_intro.md`, `ch2_background.md` (RISC-V, CoralNPU, clock gating, UVM), `ch3_architecture.md`, `ch4_core.md`, `ch5_engine.md`, `ch_verification.md` (viết nháp ở Phase 2 Task 19), `ch7_power.md`, `ch8_mnist.md`, `ch9_coral_relation.md` (lấy từ spec §16), `ch10_conclusion.md`
- Tạo: `docs/report/slides/` (bộ slide bảo vệ)

**Interface:**
- Dùng: `docs/results/{e2,e4,mnist_full}.md`, các report coverage, spec §16, `manifest.yaml`.
- Tạo ra: báo cáo, slide và gói tái lập để nộp.

| Chương | Người viết | Nháp xong trước |
|---|---|---|
| 1, 2, 3, 9 | cả hai | tuần 13 |
| 4 core, 8 MNIST | Tấn | 4: tuần 13; 8: tuần 15 |
| 5 engine, 7 power | Bảo | 5: tuần 13; 7: tuần 14 |
| verification | cả hai (mỗi người env của mình, `soc_env` viết chung) | tuần 10 (Phase 2) |
| 10 kết luận | cả hai | tuần 15 |

- [ ] **Step 1 (tuần 13):** Khung báo cáo với đủ tiêu đề các chương và một đoạn mục đích cho mỗi chương; danh sách hình.
- [ ] **Step 2:** Mỗi chương được viết nháp đúng hạn. Bằng chứng chức năng (chương verification, chương 8) và bằng chứng power (chương 7) nằm ở các chương riêng; mọi con số power đều mang nhãn "switching-activity estimate" và có link tới CSV của nó.
- [ ] **Step 3 (tuần 15):** Review chéo: mỗi sinh viên đọc các chương của người kia và liệt kê mọi khẳng định không trỏ tới một test, CSV hay mục spec nào; sửa hết.
- [ ] **Step 4 (tuần 16):** Slide; một buổi tập dượt trong đó mỗi sinh viên trả lời câu hỏi về track của **người kia** (luật dự án: cả hai đều giải thích được mọi quyết định thiết kế).
- [ ] **Step 5:** Nộp báo cáo, slide và gói tái lập; commit mã nguồn cuối cùng và gắn tag `submitted`.

## Exit checklist của Phase 4

- [ ] SC5: `mnist_1000` 0 mismatch trên D0 và D1; `eq_mnist_1000` giống hệt
- [ ] E4 xong kèm đối chiếu (hoặc giảm xuống 20 ảnh theo luật cắt, có ghi chú)
- [ ] Đã ghi lại lần chạy đủ 10.000 ảnh, hoặc đã cắt một cách tường minh kèm lý do
- [ ] SC6: `repro_clean_clone` đã pass; tag `phase4-final`
- [ ] Báo cáo và slide đã nộp; các test Review Focus 1–5 hoạt động như mô tả
