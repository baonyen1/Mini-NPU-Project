# Verilator targets (run under Linux or WSL; Verilator is not installed natively on Windows).
#   make lint           -Wall lint of the engine-side RTL (Task 11 adds rtl/npu/*.sv here)
#   make test_dtcm_dp   build tb/directed/dtcm_dp_tb.sv and run it twice:
#                       once with an empty memory, once with the +DTCM backdoor fixture
VERILATOR ?= verilator
ROOT      := ../..
PKG       := $(ROOT)/rtl/top/npu_pkg.sv
DTCM      := $(ROOT)/rtl/mem/dtcm_dp.sv
TB        := $(ROOT)/tb/directed/dtcm_dp_tb.sv
FIXTURE   := $(ROOT)/tb/directed/dtcm_init.hex
BUILD     := build

.PHONY: lint test_dtcm_dp clean

lint:
	$(VERILATOR) --lint-only -Wall --top-module dtcm_dp $(PKG) $(DTCM)

test_dtcm_dp: $(BUILD)/dtcm_tb/Vdtcm_dp_tb
	./$(BUILD)/dtcm_tb/Vdtcm_dp_tb
	./$(BUILD)/dtcm_tb/Vdtcm_dp_tb +DTCM=$(FIXTURE)

$(BUILD)/dtcm_tb/Vdtcm_dp_tb: $(PKG) $(DTCM) $(TB)
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing -Wall --top-module dtcm_dp_tb --Mdir $(BUILD)/dtcm_tb $(PKG) $(DTCM) $(TB)

clean:
	rm -rf $(BUILD)
