# Verilator targets (run under Linux or WSL; Verilator is not installed natively on Windows).
#   make lint           -Wall lint of the engine-side RTL (Task 11 grows it into a mac_engine lint over rtl/npu/*.sv)
#   make test_dtcm_dp   build tb/directed/dtcm_dp_tb.sv and run it twice:
#                       once with an empty memory, once with the +DTCM backdoor fixture
#   make test_cmd_fifo  build tb/directed/cmd_fifo_tb.sv (Task 11 stage 1) and run it at DEPTH 8 and 5
VERILATOR ?= verilator
ROOT      := ../..
PKG       := $(ROOT)/rtl/top/npu_pkg.sv
DTCM      := $(ROOT)/rtl/mem/dtcm_dp.sv
TB        := $(ROOT)/tb/directed/dtcm_dp_tb.sv
FIXTURE   := $(ROOT)/tb/directed/dtcm_init.hex
FIFO      := $(ROOT)/rtl/npu/cmd_fifo.sv
FIFO_TB   := $(ROOT)/tb/directed/cmd_fifo_tb.sv
BUILD     := build

.PHONY: lint test_dtcm_dp test_cmd_fifo clean

lint:
	$(VERILATOR) --lint-only -Wall --top-module dtcm_dp $(PKG) $(DTCM)
	$(VERILATOR) --lint-only -Wall --top-module cmd_fifo $(PKG) $(FIFO)

test_dtcm_dp: $(BUILD)/dtcm_tb/Vdtcm_dp_tb
	./$(BUILD)/dtcm_tb/Vdtcm_dp_tb
	./$(BUILD)/dtcm_tb/Vdtcm_dp_tb +DTCM=$(FIXTURE)

$(BUILD)/dtcm_tb/Vdtcm_dp_tb: $(PKG) $(DTCM) $(TB)
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing -Wall --top-module dtcm_dp_tb --Mdir $(BUILD)/dtcm_tb $(PKG) $(DTCM) $(TB)

test_cmd_fifo: $(BUILD)/fifo_tb/Vcmd_fifo_tb $(BUILD)/fifo_tb5/Vcmd_fifo_tb
	./$(BUILD)/fifo_tb/Vcmd_fifo_tb
	./$(BUILD)/fifo_tb5/Vcmd_fifo_tb

$(BUILD)/fifo_tb/Vcmd_fifo_tb: $(PKG) $(FIFO) $(FIFO_TB)
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing -Wall --top-module cmd_fifo_tb --Mdir $(BUILD)/fifo_tb $(PKG) $(FIFO) $(FIFO_TB)

# the same test at a depth that is not a power of two (see the header of cmd_fifo_tb.sv)
$(BUILD)/fifo_tb5/Vcmd_fifo_tb: $(PKG) $(FIFO) $(FIFO_TB)
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing -Wall -GDEPTH=5 --top-module cmd_fifo_tb --Mdir $(BUILD)/fifo_tb5 $(PKG) $(FIFO) $(FIFO_TB)

clean:
	rm -rf $(BUILD)
