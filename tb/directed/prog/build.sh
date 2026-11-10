#!/usr/bin/env bash
# Assembles the npu_top directed programs (plan Phase 2 Task 14) into the word-per-line hex files
# that itcm.sv (+ITCM) and dtcm_dp.sv (+DTCM) read with $readmemh: <name>.itcm.hex (.text, word 0 =
# address 0x0000_0000) and <name>.dtcm.hex (.data, word 0 = DTCM_BASE 0x0001_0000).
# Run on Linux/WSL with binutils/gcc-riscv64-unknown-elf; from Windows:
#   wsl.exe -e bash -c "cd <repo> && bash tb/directed/prog/build.sh"
# The hex files are committed so that sim/questa/run_npu_top.sh needs no RISC-V toolchain on Windows;
# rerun this script after editing a .S file. ELF and disassembly go to tb/directed/prog/out/ (ignored).
set -euo pipefail
cd "$(dirname "$0")"
P=${RV_PREFIX:-riscv64-unknown-elf-}
MARCH="-march=rv32im_zicsr_zifencei_zbb -mabi=ilp32"     # CLAUDE.md section 5 (firmware flags)
mkdir -p out

# objcopy -O verilog writes an "@<address>" line and several words per line; -j <section> is needed
# (docs/smoke/results.md S5). Byte order: with binutils 2.42 (WSL Ubuntu 24.04) --verilog-data-width=4
# alone already gives the little-endian words and --reverse-bytes=4 swaps them (the S5 recipe, run
# with Vitis binutils, needed it), so the word order is checked against a raw binary dump instead of
# trusted. Keep one section starting at the memory's word 0, drop the address line, one word per line.
to_words() {   # <elf> <section> <out.hex>
    "${P}objcopy" -O verilog --verilog-data-width=4 -j "$2" "$1" "$3.tmp"
    local n first want
    n=$(grep -c '^@' "$3.tmp")
    [ "$n" -eq 1 ] || { echo "build.sh: $1 $2: expected one @address line, got $n" >&2; exit 1; }
    grep -v '^@' "$3.tmp" | tr -s ' \r' '\n\n' | sed '/^$/d' > "$3"
    rm -f "$3.tmp"
    # The first 32-bit little-endian word of the section, read from the raw bytes.
    "${P}objcopy" -O binary -j "$2" "$1" "$3.bin"
    want=$(od -An -v -t x1 -N 4 "$3.bin" | awk '{ print toupper($4 $3 $2 $1) }')
    rm -f "$3.bin"
    first=$(head -n 1 "$3" | tr 'a-f' 'A-F')
    [ "$first" = "$want" ] || { echo "build.sh: $3: first word $first, expected $want (byte order)" >&2; exit 1; }
}

for src in t_*.S; do
    name=${src%.S}
    # .text at the ITCM base, .data at DTCM_BASE (spec 4.1); no startup files or libraries.
    "${P}gcc" $MARCH -nostdlib -nostartfiles -Wl,-Ttext=0x0 -Wl,-Tdata=0x10000 -Wl,--no-relax \
        -o "out/$name.elf" "$src"
    "${P}objdump" -d -j .text "out/$name.elf" > "out/$name.dis"
    # Both sections must start at their memory's base, or word 0 of the hex file is misplaced.
    "${P}objdump" -h "out/$name.elf" | awk -v n="$name" '
        $2 == ".text" && $4 != "00000000" { print n ": .text at " $4 > "/dev/stderr"; bad = 1 }
        $2 == ".data" && $4 != "00010000" { print n ": .data at " $4 > "/dev/stderr"; bad = 1 }
        END { exit bad }'
    # Only .text and .data reach the hex files, so any other allocated section (.rodata, .sdata,
    # .bss, ...) would be silently missing from the memories: fail instead. objdump -h prints each
    # section on two lines, "<idx> <name> <size> ..." and then its flags.
    "${P}objdump" -h "out/$name.elf" | awk -v n="$name" '
        $1 ~ /^[0-9]+$/ { sec = $2; next }
        sec != "" && /ALLOC/ && sec != ".text" && sec != ".data" {
            print n ": allocated section " sec " is not written to a hex file" > "/dev/stderr"; bad = 1 }
        { sec = "" }
        END { exit bad }'
    to_words "out/$name.elf" .text "$name.itcm.hex"
    to_words "out/$name.elf" .data "$name.dtcm.hex"
    echo "$name: $(wc -l < "$name.itcm.hex") ITCM words, $(wc -l < "$name.dtcm.hex") DTCM words"
done
