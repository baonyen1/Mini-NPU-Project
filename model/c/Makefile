CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -O1 -g -fsanitize=address,undefined
BUILD   := build

.PHONY: test clean
test: $(BUILD)/test_npu_ref
	./$(BUILD)/test_npu_ref

$(BUILD)/test_npu_ref: tests/test_npu_ref.c npu_ref.c npu_ref.h | $(BUILD)
	$(CC) $(CFLAGS) -I. tests/test_npu_ref.c npu_ref.c -o $@

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
