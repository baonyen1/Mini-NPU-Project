# Bảng thuật ngữ Mini-NPU

Các thuật ngữ dùng trong spec, plan, code và buổi bảo vệ. Cột cuối nói thuật ngữ đó xuất hiện ở đâu trong project này. Thuật ngữ giữ tiếng Anh vì code, tài liệu và hội đồng đều dùng như vậy. Bảng này chỉ giải thích; giá trị chính xác (độ rộng bus, địa chỉ, bit CSR) luôn lấy theo spec `docs/superpowers/specs/2026-10-04-mini-npu-design.md`. Khi spec đổi, sửa glossary trong cùng commit.

Mục lục: [1. Kiến trúc tổng thể](#1-kiến-trúc-tổng-thể) · [2. Bộ nhớ](#2-bộ-nhớ) · [3. Tập lệnh RISC-V](#3-tập-lệnh-risc-v) · [4. Pipeline](#4-pipeline) · [5. MAC engine](#5-mac-engine) · [6. Số học và lượng tử hóa](#6-số-học-và-lượng-tử-hóa) · [7. Công suất](#7-công-suất) · [8. Verification](#8-verification) · [9. Công cụ](#9-công-cụ) · [10. Quy trình project](#10-quy-trình-project)

---

## 1. Kiến trúc tổng thể

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **NPU** (Neural Processing Unit) | Bộ xử lý chuyên cho mạng nơ-ron, chủ yếu là nhân ma trận. | Mini-NPU = scalar core + MAC engine. |
| **Accelerator** | Khối phần cứng chuyên làm một loại việc nhanh hơn CPU. | MAC engine là accelerator cho phép nhân ma trận. |
| **CoralNPU** | NPU mã nguồn mở của Google, nền RISC-V, cho thiết bị đeo/edge. | Nguồn cảm hứng kiến trúc. Không dùng lại code. |
| **Scalar core** | CPU xử lý từng số một (không phải vector). Điều khiển chương trình. | Lõi RV32I 5 tầng của nhóm, mở rộng thêm M/Zicsr/Zifencei/Zbb và custom-0. |
| **Matrix engine / MAC engine** | Khối làm phép nhân-cộng dồn trên ma trận. | `rtl/npu/mac_engine.sv`, mảng 4×4×4. |
| **Decoupled** | Hai khối chạy độc lập, liên lạc qua hàng đợi; khối này không phải chờ khối kia từng chu kỳ. | Core đẩy lệnh vào FIFO rồi chạy tiếp; engine tự xử lý. |
| **Command queue / FIFO** | Hàng đợi vào trước ra trước. | Command FIFO 8 entry giữa core và engine (giống Coral). |
| **Backend** | Phần phía sau nhận lệnh từ frontend để thực thi. | Ở Coral: vector/matrix backend. Ở mình: MAC engine. |
| **Superscalar** | CPU phát nhiều lệnh mỗi chu kỳ. | Coral phát tối đa 4 lệnh/chu kỳ; core của mình phát 1. |
| **In-order / Out-of-order** | Thực thi đúng thứ tự chương trình / được đảo thứ tự để nhanh hơn. | Core của mình in-order. Vector backend của Coral out-of-order. |
| **ROB** (Reorder Buffer) | Bộ đệm sắp xếp lại kết quả của CPU out-of-order theo đúng thứ tự. | Chỉ có ở Coral, không có ở Mini-NPU. |
| **RVV / Zve32x** | Extension vector chuẩn của RISC-V. | Coral có; Mini-NPU để dành cho đồ án tốt nghiệp. |
| **Zvt / VME** | Extension matrix thử nghiệm trong CoralNPU. | Chỉ để so sánh; ISA custom của mình khác hoàn toàn. |
| **D0 / D1** | Hai cấu hình so sánh: D0 không clock gating, D1 có gating. | Cùng RTL, chỉ khác tham số `GATING_EN`. |

## 2. Bộ nhớ

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **TCM** (Tightly-Coupled Memory) | SRAM gắn sát lõi, độ trễ cố định, không phải cache. | ITCM 16 KB (lệnh), DTCM 64 KB (dữ liệu). |
| **ITCM / DTCM** | TCM cho lệnh / cho dữ liệu. | ITCM ở `0x0000_0000`, DTCM ở `0x0001_0000`. |
| **Cache** | Bộ nhớ đệm tự động chứa dữ liệu hay dùng; độ trễ thay đổi khi miss. | Không dùng. TCM cho độ trễ biết trước, dễ verify. |
| **Dual-port** | Bộ nhớ có 2 cổng truy cập cùng lúc. | Port A cho core, port B cho engine. |
| **Bank** | Bộ nhớ chia thành nhiều khối nhỏ để đọc song song. | DTCM 4 bank × 32 bit; port B đọc cả 4 bank một lúc = 128 bit. |
| **Port A / Port B** | Hai cổng của DTCM. | A: 32 bit đọc/ghi, của core. B: 128 bit chỉ đọc, của engine. |
| **dtcm_dp** | Module RTL của DTCM hai cổng (dp = dual-port). | `rtl/mem/dtcm_dp.sv`. Đọc có độ trễ 1 chu kỳ; đọc và ghi cùng một word trong cùng chu kỳ thì đọc ra giá trị cũ. |
| **Word / Quad** | Word = 32 bit = 4 byte. Quad = 4 word = 16 byte. | Một lần đọc port B = 1 quad = 1 entry của WBUF/IBUF. |
| **Alignment** (căn chỉnh) | Địa chỉ phải chia hết cho kích thước dữ liệu. | Lệnh LOAD cần địa chỉ chia hết cho 16, nếu không bật `err_align`. |
| **Memory map** | Bảng phân vùng địa chỉ. | Spec §4.1. |
| **MMIO** (Memory-Mapped I/O) | Thiết bị được điều khiển bằng cách ghi/đọc một địa chỉ nhớ. | `SIM_CTRL`, `SIM_PUTC` ở `0x0002_0000`, chỉ dùng trong mô phỏng. |
| **Backdoor / Frontdoor load** | Nạp bộ nhớ trực tiếp từ testbench (`$readmemh`) / nạp qua bus như phần cứng thật. | Đồ án 2 dùng backdoor. |
| **`$readmemh`** | Lệnh Verilog đọc file hex vào mảng nhớ. | Nạp firmware và trọng số. |
| **DMA** | Khối tự chép dữ liệu giữa các vùng nhớ mà CPU không phải làm. | Không làm; cả model vừa trong DTCM. |
| **Ping-pong buffer** | Hai vùng đệm luân phiên: một vùng đang đọc, vùng kia đang ghi. | ACT1/ACT2 cho activation giữa các lớp. |

## 3. Tập lệnh RISC-V

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **ISA** (Instruction Set Architecture) | Bộ lệnh mà phần mềm nhìn thấy. | RV32IM + Zicsr + Zifencei + Zbb + custom-0. |
| **RV32I** | Bộ lệnh số nguyên cơ bản 32 bit, 40 lệnh. | Đã hoàn thành ở Task 3. |
| **M** | Extension nhân/chia: `mul`, `mulh*`, `div*`, `rem*`. | Task 5. Requant dùng `mul`. |
| **Zicsr** | Lệnh đọc/ghi thanh ghi điều khiển (CSR). | Task 6. Đọc `mcycle`, `npu_status`. |
| **Zifencei** | Lệnh `fence.i` đồng bộ bộ nhớ lệnh. | Task 7. Ở core này nó chỉ flush pipeline. |
| **Zbb** | Extension thao tác bit: `clz`, `cpop`, `max`, `min`, `rev8`… | Task 7. `max/min` dùng cho ReLU và clamp. |
| **custom-0** | Opcode `0001011` RISC-V dành sẵn cho lệnh riêng. | 4 lệnh LOAD_WEIGHT, LOAD_INPUT, COMPUTE, READ_RESULT. |
| **opcode / funct3 / funct7** | Các trường trong mã lệnh xác định lệnh nào. | custom-0 dùng funct3 chọn lệnh, funct7[0] = cờ `clr`. |
| **R-type / I-type** | Định dạng lệnh: 2 thanh ghi nguồn / 1 thanh ghi + hằng số. | custom-0 là R-type. |
| **rd / rs1 / rs2** | Thanh ghi đích / nguồn 1 / nguồn 2. | LOAD: rs1 = địa chỉ, rs2 = K. |
| **Immediate** | Hằng số nằm ngay trong mã lệnh. | `addi x1, x0, 5`: 5 là immediate. |
| **Sign-extend / Zero-extend** | Mở rộng số ra nhiều bit hơn bằng cách chép bit dấu / điền 0. | `lb` sign-extend, `lbu` zero-extend; PE sign-extend int8. |
| **Signed / Unsigned** | Có dấu / không dấu: cùng chuỗi bit, hai cách hiểu. | `0x80000000` là −2³¹ (signed) hay 2³¹ (unsigned): lý do `slt` ≠ `sltu`. |
| **CSR** (Control and Status Register) | Thanh ghi đặc biệt cho trạng thái và điều khiển. | `mcycle`, `minstret`, `npu_status` (0x7C0), `npu_busy_cyc` (0x7C1). |
| **`mcycle` / `minstret`** | Bộ đếm số chu kỳ / số lệnh đã hoàn thành. | Dùng so sánh D0/D1 và tính tỉ lệ idle. |
| **Sticky bit** | Bit lỗi đã bật thì giữ nguyên cho tới khi bị xóa có chủ đích. | `err_k`, `err_addr`, `err_illegal`, `err_align`. |
| **W1C** (Write-1-to-Clear) | Ghi 1 vào bit nào thì bit đó bị xóa. | Cách xóa các bit lỗi trong `npu_status`. |
| **Trap / Exception** | Cơ chế nhảy vào trình xử lý khi có lỗi hoặc `ecall`. | Core chưa có; quyết định W2-1 còn mở. |
| **Illegal instruction** | Mã lệnh không hợp lệ. | Hiện chạy như NOP; đề xuất cho halt trong mô phỏng. |
| **`ecall` / `ebreak`** | Lệnh gọi hệ thống / điểm dừng debug. | Hiện là NOP. |
| **NOP** | Lệnh không làm gì (`addi x0, x0, 0`). | Bubble trong pipeline chính là một NOP. |
| **`.insn`** | Cú pháp assembler để viết lệnh theo từng trường khi assembler không biết lệnh đó. | `.insn r 0x0B, 0, 0, x0, a0, a1` = LOAD_WEIGHT. |

## 4. Pipeline

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **Pipeline 5 tầng** | Chia việc chạy lệnh thành 5 bước nối tiếp, mỗi chu kỳ một bước. | IF → ID → EX → MEM → WB. |
| **IF / ID / EX / MEM / WB** | Lấy lệnh / giải mã + đọc thanh ghi / tính toán / truy cập bộ nhớ / ghi thanh ghi. | Lệnh custom được đẩy vào FIFO ở MEM. |
| **Pipeline register** | Thanh ghi giữa hai tầng, giữ thông tin lệnh đang đi qua. | IF/ID, ID/EX, EX/MEM, MEM/WB. |
| **Hazard** | Tình huống lệnh sau không thể chạy đúng ngay. | 3 loại bên dưới. |
| **Data hazard** | Lệnh sau cần kết quả lệnh trước mà chưa có. | Giải quyết bằng forwarding hoặc stall. |
| **Control hazard** | Chưa biết lệnh tiếp theo vì branch chưa quyết. | Branch quyết ở EX, flush 2 lệnh sau. |
| **Structural hazard** | Hai lệnh cần cùng một tài nguyên. | Ví dụ: bộ chia đang bận. |
| **RAW / WAR / WAW** | Đọc-sau-ghi / ghi-sau-đọc / ghi-sau-ghi trên cùng một chỗ. | RAW qua thanh ghi (forwarding); WAR qua DTCM (quy tắc phần mềm + assertion A-SOC-1). |
| **Forwarding / Bypass** | Chuyển kết quả từ tầng sau về EX ngay, không chờ ghi vào thanh ghi. | Từ EX/MEM và MEM/WB về EX. |
| **Load-use hazard** | Lệnh ngay sau `lw` dùng kết quả `lw` (chưa đọc xong). | Stall 1 chu kỳ. `READ_RESULT` cũng được coi như `lw` (Task 9). |
| **Stall** | Giữ lệnh đứng yên một hoặc nhiều chu kỳ. | Bốn nguồn đã có trong RTL: load-use, bộ chia bận, FIFO đầy, `READ_RESULT` chờ engine. Xem `docs/core_stall.md`. |
| **Bubble** | Lệnh rỗng (NOP) chèn vào pipeline khi stall. | Chèn vào thanh ghi ngay sau tầng bị stall. |
| **Flush** | Xóa các lệnh đã vào pipeline nhưng không được chạy. | Khi branch taken: flush IF/ID và ID/EX. |
| **Redirect** | Đổi PC sang địa chỉ đích của branch/jump. | Chỉ được redirect khi EX không bị stall. |
| **Held operand** (operand giữ lại) | Khi tầng EX bị giữ nhiều chu kỳ, lệnh cũ hơn đang forward giá trị cho nó sẽ rời pipeline, nên thanh ghi operand ở ID/EX phải được nạp lại giá trị EX đang thấy. | Task 9, `held_operand_0/1`, test `mem_stall_stale_operand`. |
| **Branch penalty** | Số chu kỳ mất khi đoán sai/nhảy. | 2 chu kỳ. |
| **Retire** | Lệnh hoàn thành ở WB và được tính là đã chạy. | `minstret` đếm số lệnh retire. |
| **Valid bit** | Bit đánh dấu thanh ghi pipeline chứa lệnh thật hay bubble. | Cần để đếm `minstret` và trace đúng. |
| **Scoreboard** (trong CPU) | Bảng theo dõi thanh ghi nào đang chờ kết quả. | Coral dùng. Đừng nhầm với scoreboard trong UVM (mục 8). |
| **Iterative divider** | Bộ chia làm mỗi chu kỳ một bit, khoảng 32 chu kỳ. | Task 5, gây stall ở EX. |
| **`cpu_en`** | Clock-enable của đồ án 1 (giả lập 4 mức tần số cho DFS). | Đã gỡ bỏ ở Task 1. |

## 5. MAC engine

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **MAC** (Multiply-Accumulate) | Phép `acc ← acc + a × b`. | Phép cơ bản của mạng nơ-ron. |
| **PE** (Processing Element) | Một ô tính trong mảng. | 16 PE (4×4), mỗi PE làm 1 dot4/chu kỳ. |
| **Dot product / dot4** | Tích vô hướng: Σ aₜ·bₜ. dot4 = tích vô hướng 4 phần tử. | Mỗi PE: 4 bộ nhân + cây cộng. Giống VDOT của Coral. |
| **Outer product** | Nhân cột với hàng ra cả một ma trận: mỗi phần tử của cột gặp mỗi phần tử của hàng. | Trọng số 4 hàng × input 4 ảnh → 16 kết quả mỗi bước. |
| **N×M×K** | Kích thước engine: N hàng × M cột PE, mỗi PE dot K phần tử. | 4×4×4 = 64 MAC/chu kỳ. Coral điển hình 8×8×4 = 256. |
| **Broadcast** | Một giá trị được đưa tới nhiều PE cùng lúc. | Trọng số của hàng i tới cả hàng PE i; input ảnh j tới cả cột PE j. |
| **Tile / Row-tile** | Một mảnh của ma trận vừa với mảng PE. | 4 hàng output một lần; lớp 1 (64 output) có 16 tile. |
| **K** | Độ dài chiều cộng dồn (số input của một lớp). | Lớp 1: K=784, lớp 2: 64, lớp 3: 32. Phải chia hết cho 4. |
| **Step** | Một chu kỳ tính của engine = xử lý 1 quad. | COMPUTE K phần tử = K/4 step. |
| **Lane** | Một byte trong word 32 bit. | Lane t = bit [8t+7:8t]; lane 0 là byte thấp. |
| **Packing** | Gói nhiều số nhỏ vào một word. | 4 giá trị int8 liên tiếp trong 1 word; `pack_weights.py` làm việc này. |
| **Batch** | Xử lý nhiều input cùng lúc. | 4 ảnh/batch để lấp đủ 4 cột PE. |
| **Accumulator (acc)** | Thanh ghi cộng dồn kết quả. | 4×4 thanh ghi int32 (1 tile). |
| **WBUF / IBUF** | Buffer trọng số / buffer input bên trong engine. | Mỗi cái 256 entry × 128 bit. |
| **LOAD_WEIGHT / LOAD_INPUT** | Engine đọc K phần tử từ DTCM vào WBUF / IBUF. | funct3 000 / 001. |
| **COMPUTE** | Chạy K/4 step; mỗi step, mỗi PE cộng 1 dot4 vào acc của nó. Cờ `clr` xóa acc trước. | funct3 010. |
| **READ_RESULT** | Đọc một phần tử acc về thanh ghi core; chờ engine rảnh. | funct3 011. Đóng vai trò barrier. |
| **Barrier** | Điểm chặn: chờ mọi việc trước đó xong mới đi tiếp. | READ_RESULT chờ FIFO rỗng và FSM về IDLE. |
| **FSM** (Finite-State Machine) | Máy trạng thái điều khiển. | IDLE → CHECK → LOAD hoặc MAC → IDLE. |
| **Operand** | Dữ liệu đầu vào của phép tính. | Trọng số và input. |

## 6. Số học và lượng tử hóa

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **int8 / int32** | Số nguyên có dấu 8 / 32 bit. | int8 × int8 → cộng dồn int32. |
| **Two's complement** | Cách biểu diễn số âm chuẩn trong phần cứng. | −1 = `0xFF` (int8). |
| **Overflow / Wrap** | Tràn: kết quả vượt dải; wrap = quay vòng như phép mod 2³². | Accumulator wrap (quyết định D5). |
| **Saturate** | Khi tràn thì kẹp ở giá trị lớn/nhỏ nhất. | Không dùng cho acc; requant có clamp về [0,127]. |
| **Quantization** (lượng tử hóa) | Chuyển số thực sang số nguyên ít bit. | float32 → int8. |
| **Scale** | Hệ số đổi giữa số thực và số nguyên. | `s_w = max|W| / 127`. |
| **Requantization (requant)** | Đưa kết quả int32 về lại int8 cho lớp sau. | `y = clamp((acc·M + 2^(S−1)) >> S, 0, 127)`. |
| **M, S** | Hệ số nhân và số bit dịch thay cho phép chia thực. | Mỗi lớp một cặp, nằm trong vùng QP của DTCM. |
| **Rounding** | Làm tròn; `+ 2^(S−1)` trước khi dịch để làm tròn thay vì cắt. | Phải giống từng bit với golden. |
| **Clamp** | Kẹp giá trị trong một dải. | `max(0, min(127, x))`, kiêm luôn ReLU. |
| **ReLU** | `max(0, x)`. | Sau lớp 1 và 2. |
| **Bias** | Hằng số cộng vào sau phép nhân ma trận. | Cộng vào acc trước khi requant. |
| **Logit** | Đầu ra thô của lớp cuối, trước argmax. | int32, 10 giá trị (pad lên 12). |
| **Argmax** | Chỉ số của giá trị lớn nhất = nhãn dự đoán. | Testbench và golden cùng tính. |
| **MLP** (Multi-Layer Perceptron) | Mạng nơ-ron gồm các lớp fully-connected. | 784 → 64 → 32 → 10. |
| **MNIST** | Bộ ảnh chữ số viết tay 28×28. | Demo suy luận. |
| **Bit-exact** | Khớp đến từng bit, không chỉ "gần đúng". | Tiêu chí SC5. |

## 7. Công suất

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **Dynamic power** | Công suất tiêu thụ khi tín hiệu đổi trạng thái; tỉ lệ với C·V²·f·hoạt động. | Lý do đo switching activity (P&H 1.7). |
| **Switching activity / Toggle** | Số lần tín hiệu đổi 0↔1. | Thước đo công suất ước tính. Không phải "công suất đo được". |
| **Clock gating** | Tắt clock cho một khối khi nó rảnh để các flip-flop không toggle. | Gate riêng MAC engine. |
| **ICG** (Integrated Clock Gate) | Cell gating chuẩn: latch + cổng AND. | `rtl/npu/icg_cell.sv`. |
| **Latch** | Phần tử nhớ trong suốt theo mức clock (khác flip-flop theo cạnh). | Latch giữ `en` để không tạo xung clock lỗi (glitch). |
| **Glitch** | Xung nhiễu ngắn không mong muốn. | Lý do phải dùng ICG thay vì AND trực tiếp. |
| **Gated clock / free clock** | Clock bị tắt được / clock luôn chạy. | Buffer + PE + acc ở gated; FIFO + FSM + CSR ở free. |
| **Enable (en)** | Tín hiệu cho phép clock chạy. | `en = reset ∨ engine bận ∨ FIFO có lệnh`. |
| **Idle ratio** | Tỉ lệ thời gian engine rảnh. | Đo bằng `npu_busy_cyc / mcycle`; quyết định D1 lợi bao nhiêu. |
| **Cycle-identical** | Hai cấu hình chạy giống nhau từng chu kỳ. | Mục tiêu D0/D1 (SC3). |
| **VCD / FST** | File dạng sóng ghi lại mọi thay đổi tín hiệu. | Nguồn dữ liệu để đếm toggle. |
| **SAIF** | File tổng hợp hoạt động chuyển mạch cho tool ước tính công suất. | Có thể dùng ở đồ án tốt nghiệp. |
| **M1 / M2** | Số toggle trên net `clk_mac` / tổng toggle mọi net của engine. | Hai chỉ số báo cáo (§11). |
| **WFI** | Lệnh "chờ ngắt"; Coral dùng nó để gate cả core. | Mini-NPU không dùng; gating do phần cứng tự quyết. |
| **DFS / DVFS** | Thay đổi tần số (và điện áp) động. | Chủ đề đồ án 1, không thuộc đồ án 2. |

## 8. Verification

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **DUT** (Design Under Test) | Thiết kế đang được kiểm. | `mac_engine`, core, hoặc `npu_top`. |
| **Testbench** | Môi trường mô phỏng bao quanh DUT để kích thích và kiểm tra. | `tools/rv32i_check/tb_dump.v`, các env UVM. |
| **UVM** | Phương pháp luận verification chuẩn (IEEE 1800.2), dựa trên lớp SystemVerilog. | 3 env: `mac_env`, `core_env`, `soc_env`. |
| **Environment (env)** | Nhóm các thành phần UVM cho một DUT. | Mỗi tầng một env. |
| **Agent** | Gói driver + monitor + sequencer cho một interface. | `cmd_agent`, `dtcm_agent`. |
| **Driver** | Chuyển transaction thành tín hiệu chân DUT. | Đẩy lệnh vào cổng push. |
| **Monitor** | Quan sát tín hiệu, tạo lại transaction để kiểm tra. | `rvvi_monitor` đọc trace retire. |
| **Sequencer / Sequence** | Nơi sinh chuỗi transaction / một kịch bản kích thích. | `mac_rand_seq`. |
| **Sequence item / Transaction** | Một đơn vị dữ liệu trừu tượng (một lệnh, một gói). | Một lệnh LDW/LDI/MAC. |
| **Reactive agent / Responder** | Agent trả lời yêu cầu của DUT thay vì chủ động gửi. | `dtcm_agent` giả lập port B. |
| **Scoreboard** (UVM) | Thành phần so sánh kết quả DUT với kết quả mong đợi. | So READ_RESULT với `npu_ref`. |
| **Predictor / Reference model** | Mô hình tính kết quả mong đợi. | `npu_ref.c` qua DPI-C. |
| **Golden model** | Mô hình được tin là đúng, dùng làm chuẩn so sánh. | `npu_ref.c`, `rv_iss.c`, `golden_int8.py`. |
| **Oracle** | Cái quyết định kết quả đúng là gì. | Golden model đóng vai oracle. |
| **ISS** (Instruction Set Simulator) | Chương trình mô phỏng từng lệnh ở mức ISA, không có timing. | `rv_iss.c`; ISS Python trong `run.py`. |
| **Lockstep** | Chạy DUT và ISS song song, so từng lệnh retire. | `core_env` và `soc_env`. |
| **RVVI** | Chuẩn giao diện trace retire của RISC-V cho verification. | Core xuất trace kiểu RVVI. |
| **DPI-C** | Cơ chế SystemVerilog gọi hàm C. | Gọi `npu_ref` và `rv_iss` từ UVM. |
| **Directed test** | Test viết tay cho một tình huống cụ thể. | `hand_4x4_k4`, `div_by_zero`. |
| **Constrained random** | Sinh kích thích ngẫu nhiên trong ràng buộc (`randomize()`). | Cần license QuestaSim đầy đủ. |
| **Seed** | Hạt giống số ngẫu nhiên; cùng seed thì cùng kịch bản. | Ghi lại để tái hiện lỗi. |
| **Functional coverage** | Đo các tình huống mong muốn đã được kiểm chưa. | `covergroup`, spec §10.5. |
| **Covergroup / Coverpoint / Bin** | Nhóm đo coverage / một biến được đo / một giá trị hoặc dải cần gặp. | Ví dụ bin K ∈ {0, 4, KMAX}. |
| **Coverage closure** | Mọi bin đã khai báo đều được gặp ít nhất một lần. | Tiêu chí SC2, trước tuần 10. |
| **Assertion / SVA** | Mệnh đề kiểm tra tự động trong lúc mô phỏng. | A-MAC-1…5, A-GATE-1/2, A-SOC-1. |
| **Regression** | Chạy lại toàn bộ test để chắc không hỏng gì. | `run_all.py`, CI. |
| **Expected failures** | Danh sách test được phép fail tạm thời. | `expected_failures.txt`. |
| **Mutation testing** | Cố tình gây lỗi để xem test có bắt được không. | Làm với `sra`, `bltu`, forwarding. |
| **Smoke test** | Bài kiểm tra nhanh xem công cụ có chạy không. | S1–S7 tuần 1. |
| **CI** (Continuous Integration) | Tự chạy test mỗi lần push. | GitHub Actions `regression.yml`. |
| **Lint** | Kiểm tra code tìm lỗi/cảnh báo mà không mô phỏng. | `verilator --lint-only`. |
| **Cosim** | Đồng mô phỏng RTL với mô hình khác. | Coral cosim với Spike; mình dùng ISS tự viết. |

## 9. Công cụ

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **QuestaSim** | Simulator thương mại của Siemens, hỗ trợ đầy đủ UVM. | Simulator chính (cần license đầy đủ). |
| **Questa–Intel/Altera FPGA Starter** | Bản Questa miễn phí kèm Quartus. | Không chạy được `randomize`/`covergroup`. |
| **xsim** | Simulator trong Vivado. | Phương án dự phòng. |
| **Verilator** | Simulator mã nguồn mở, nhanh, dịch RTL sang C++. | Lint, chạy nhanh full-system. |
| **Icarus Verilog** | Simulator mã nguồn mở đơn giản. | Dùng trong `rv32i_check` và CI. |
| **cocotb / pyuvm** | Viết testbench bằng Python. | Không dùng (proposal cũ có nhắc). |
| **Spike** | ISS RISC-V chính thức. | Coral dùng; mình không dùng. |
| **riscv-arch-test** | Bộ test tuân thủ ISA chính thức. | Nên chạy sau Task 8. |
| **binutils / gcc (riscv)** | Bộ assembler, linker, compiler cho RISC-V. | `riscv-none-elf-` hoặc `riscv64-unknown-elf-`. |
| **marimo** | Notebook Python lưu dạng file `.py`. | `notebooks/MiniNPU_MLP.py`. |

## 10. Quy trình project

| Thuật ngữ | Nghĩa | Trong project |
|---|---|---|
| **Spec** | Tài liệu thiết kế: hệ thống phải làm gì, giao diện ra sao. | `docs/superpowers/specs/2026-10-04-mini-npu-design.md`. |
| **Plan** | Kế hoạch triển khai chia thành task, mỗi task có test định nghĩa "done". | `docs/superpowers/plans/2026-10-04-mini-npu-phase1.md`. |
| **Track A / Track B** | Hai mảng việc: core / MAC engine. | Track A: Tấn. Track B: Bảo (từ 2026-10-15). |
| **Freeze** (đóng băng) | Chốt giao diện; sau đó muốn sửa phải cả hai đồng ý. | §6 và §7.1 đóng băng cuối tuần 2. |
| **D1…D10 / O1…O3** | Mã quyết định đã chốt / câu hỏi còn mở trong spec §3. | Ví dụ D10 = engine 4×4×4. |
| **SC1…SC6** | Tiêu chí thành công (spec §1). | Ví dụ SC5 = MNIST khớp bit-exact. |
| **RQ / H / E** | Câu hỏi nghiên cứu / giả thuyết / thí nghiệm trong proposal. | E2 = so switching activity D0/D1 trên workload tổng hợp. |
| **Review Focus** | Danh sách tình huống dễ sót mà plan bắt buộc phải có test. | 5 mục trong đầu plan. |
| **W2-1** | Câu hỏi: core xử lý lệnh không hợp lệ thế nào. | Còn mở, đề xuất halt. |
| **`finish_task`** | Script: chạy test → commit → rebase → push. | `tools/finish_task.ps1`. |
| **Evidence boundary** | Ranh giới bằng chứng: chức năng (UVM) tách riêng công suất (toggle). | Không bao giờ gọi là "công suất đo được". |
| **Contribution boundary** | Ranh giới đóng góp: cái gì là của nhóm, cái gì tham khảo. | Lấy cảm hứng từ Coral, không dùng lại code. |
