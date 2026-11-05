# Verilator targets (run under Linux or WSL; Verilator is not installed natively on Windows).
#   make lint             -Wall lint of the engine-side RTL: dtcm_dp, cmd_fifo, and mac_engine (with rtl/prim) in D0 and D1
#   make test_dtcm_dp     build tb/directed/dtcm_dp_tb.sv and run it twice:
#                         once with an empty memory, once with the +DTCM backdoor fixture
#   make test_cmd_fifo    build tb/directed/cmd_fifo_tb.sv (Task 11 stage 1) and run it at DEPTH 8 and 5
#   make test_mac_engine  build tb/directed/mac_engine_tb.sv with the npu_ref DPI model and run all tests
#                         (the g++ step can take more than 10 minutes; QuestaSim: sim/questa/run_mac_directed.sh)
VERILATOR ?= verilator
ROOT      := ../..
PKG       := $(ROOT)/rtl/top/npu_pkg.sv
DTCM      := $(ROOT)/rtl/mem/dtcm_dp.sv
TB        := $(ROOT)/tb/directed/dtcm_dp_tb.sv
FIXTURE   := $(ROOT)/tb/directed/dtcm_init.hex
FIFO      := $(ROOT)/rtl/npu/cmd_fifo.sv
FIFO_TB   := $(ROOT)/tb/directed/cmd_fifo_tb.sv
ENGINE    := $(ROOT)/rtl/prim/npu_clk_gate.sv $(FIFO) $(ROOT)/rtl/npu/pe_array.sv $(ROOT)/rtl/npu/mac_engine.sv
MAC_TB    := $(ROOT)/tb/uvm/common/npu_dpi_pkg.sv $(ROOT)/tb/directed/dtcm_model.sv $(ROOT)/tb/directed/mac_engine_tb.sv
NPU_REF   := $(ROOT)/model/c/npu_ref.c
BUILD     := build

.PHONY: lint test_dtcm_dp test_cmd_fifo test_mac_engine clean

lint:
	$(VERILATOR) --lint-only -Wall --top-module dtcm_dp $(PKG) $(DTCM)
	$(VERILATOR) --lint-only -Wall --top-module cmd_fifo $(PKG) $(FIFO)
	$(VERILATOR) --lint-only -Wall --top-module mac_engine $(PKG) $(ENGINE)
	$(VERILATOR) --lint-only -Wall --top-module mac_engine -GGATING_EN="1'b1" $(PKG) $(ENGINE)

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

test_mac_engine: $(BUILD)/mac_tb/Vmac_engine_tb
	./$(BUILD)/mac_tb/Vmac_engine_tb

# npu_ref.c is C: compiled by Verilator's make it would go through g++, the DPI symbols would get C++
# names and the link fails, so it is built with gcc and handed over as an object file. -O0 on the
# generated C++ shortens the build; the test is short, so speed does not matter.
$(BUILD)/npu_ref_c.o: $(NPU_REF) $(ROOT)/model/c/npu_ref.h
	mkdir -p $(BUILD)
	$(CC) -std=c99 -O1 -c -I$(ROOT)/model/c -o $@ $(NPU_REF)

$(BUILD)/mac_tb/Vmac_engine_tb: $(PKG) $(ENGINE) $(MAC_TB) $(BUILD)/npu_ref_c.o
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing -Wall -j 4 --output-split 3000 \
	    -MAKEFLAGS "OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0" --top-module mac_engine_tb --Mdir $(BUILD)/mac_tb \
	    $(PKG) $(ENGINE) $(MAC_TB) $(abspath $(BUILD)/npu_ref_c.o)

clean:
	rm -rf $(BUILD)
