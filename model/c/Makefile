CC      ?= gcc
# C99 (CLAUDE.md section 5). -fno-sanitize-recover makes a sanitizer finding fail the run instead of only printing it.
# MinGW has no ASan/UBSan runtime (ld: cannot find -lasan): there use
#   make CFLAGS="-std=c99 -Wall -Wextra -Werror -O1 -g -fsanitize=undefined -fsanitize-undefined-trap-on-error"
CFLAGS  ?= -std=c99 -Wall -Wextra -Werror -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all
BUILD   := build

.PHONY: test xcheck clean
# test   : unit tests of both golden models (self-contained vectors).
# xcheck : run every program of the Python suites through rv_iss and compare registers and the whole
#          RVVI trace with RefISS. Needs `python tools/rv32i_check/run_all.py` to have been run, and fails
#          (not skips) if the programs are missing.
test: $(BUILD)/test_npu_ref $(BUILD)/test_rv_iss
	./$(BUILD)/test_npu_ref
	./$(BUILD)/test_rv_iss

xcheck: $(BUILD)/test_rv_iss
	./$(BUILD)/test_rv_iss xcheck ../../tools/rv32i_check/build 100

$(BUILD)/test_npu_ref: tests/test_npu_ref.c npu_ref.c npu_ref.h | $(BUILD)
	$(CC) $(CFLAGS) -I. tests/test_npu_ref.c npu_ref.c -o $@

$(BUILD)/test_rv_iss: tests/test_rv_iss.c rv_iss.c rv_iss.h npu_ref.c npu_ref.h | $(BUILD)
	$(CC) $(CFLAGS) -I. tests/test_rv_iss.c rv_iss.c npu_ref.c -o $@

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
