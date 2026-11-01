#!/usr/bin/env bash
# Environment check for lp-rv32-mcu (docs/BRIEF.md, Phase 0).
# Run inside the iic-osic container from the repo root (login shell so PATH/PDK are set):
#   docker exec -w /foss/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral iic-osic \
#     bash -lc 'scripts/env_check.sh | tee results/env_check.txt'
# Prints a found/missing table with versions and paths; exits 1 if a required item is missing.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
PY="$REPO/.venv/bin/python"
RISCOF="$REPO/.venv-riscof/bin/riscof"
SAIL="$REPO/ext/sail/sail-riscv-Linux-x86_64/bin/sail_riscv_sim"
SRAM=sky130_sram_1kbyte_1rw1r_32x256_8
SRAM_DIR="${PDK_ROOT:-/foss/pdks}/${PDK:-sky130A}/libs.ref/sky130_sram_macros"

missing=0
row() { printf "%-22s %-8s %s\n" "$1" "$2" "$3"; }

check_tool() {   # name | binary | version command
    local name="$1" bin="$2" vcmd="$3" path ver
    path="$(command -v "$bin" 2>/dev/null)"
    if [ -z "$path" ]; then row "$name" "MISSING" "-"; missing=1; return; fi
    ver="$(eval "$vcmd" 2>&1 | grep -v '^\s*$' | head -n1)"
    row "$name" "found" "$ver ($path)"
}

check_py() {     # name | distribution | python
    local name="$1" dist="$2" py="$3" ver
    if ver="$(PYTHONPATH= "$py" -c "import importlib.metadata as m; print(m.version('$dist'))" 2>/dev/null)"; then
        row "$name" "found" "$ver ($py)"
    else
        row "$name" "MISSING" "-"; missing=1
    fi
}

check_git() {    # name | dir
    local name="$1" dir="$2"
    if [ -d "$dir/.git" ]; then
        row "$name" "found" "$(git -C "$dir" log -1 --format='%H %cs') $(git -C "$dir" describe --tags --always 2>/dev/null) ($dir)"
    else
        row "$name" "MISSING" "$dir"; missing=1
    fi
}

echo "# lp-rv32-mcu environment check ($(date -u +%Y-%m-%dT%H:%MZ))"
row "ITEM" "STATUS" "VERSION / PATH"

# --- HDL tools -------------------------------------------------------------------------------
check_tool verilator    verilator    "verilator --version"
check_tool iverilog     iverilog     "iverilog -V"
check_tool yosys        yosys        "yosys -V"
check_tool sby          sby          "echo symbiyosys"
check_tool yosys-smtbmc yosys-smtbmc "echo yosys-smtbmc"

# riscv-formal passes its `solver` option to `smtbmc <solver>` (ext/riscv-formal/checks/genchecks.py);
# at least one SMT solver must exist. Each is reported.
solver=0
for s in yices-smt2 boolector bitwuzla z3; do
    if command -v "$s" >/dev/null 2>&1; then
        row "$s" "found" "$("$s" --version 2>&1 | head -n1)"; solver=1
    else
        row "$s" "absent" "-"
    fi
done
[ "$solver" -eq 1 ] || { row "smt-solver" "MISSING" "need one smtbmc solver"; missing=1; }

# --- RISC-V software ---------------------------------------------------------------------------
if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then CC=riscv32-unknown-elf-gcc; else CC=riscv64-unknown-elf-gcc; fi
check_tool riscv-gcc "$CC" "$CC --version"
tmp="$(mktemp -d)"
printf 'int f(unsigned x){return __builtin_popcount(x);}\nint main(){return f(7);}\n' > "$tmp/t.c"
if "$CC" -march=rv32i_zicsr_zbb -mabi=ilp32 -O2 -nostartfiles -Wl,-e,main "$tmp/t.c" -o "$tmp/t.elf" 2>"$tmp/err"; then
    n="$(riscv64-unknown-elf-objdump -d "$tmp/t.elf" 2>/dev/null | grep -c 'cpop')"
    row "rv32i_zicsr_zbb build" "found" "links with -march=rv32i_zicsr_zbb -mabi=ilp32; cpop instructions emitted: $n"
else
    row "rv32i_zicsr_zbb build" "MISSING" "$(head -n1 "$tmp/err")"; missing=1
fi
rm -rf "$tmp"
check_tool spike spike "spike --help 2>&1 | head -n1"
if [ -x "$SAIL" ]; then
    row "sail_riscv_sim" "found" "$("$SAIL" --version 2>&1 | head -n1) ($SAIL)"
else
    row "sail_riscv_sim" "MISSING" "$SAIL"; missing=1
fi
if [ -x "$RISCOF" ]; then
    row "riscof" "found" "$(PYTHONPATH= "$RISCOF" --version 2>&1 | tail -n1) ($RISCOF)"
else
    row "riscof" "MISSING" "$RISCOF"; missing=1
fi
check_git riscv-formal    "$REPO/ext/riscv-formal"
check_git riscv-arch-test "$REPO/ext/riscv-arch-test"

# --- Python / cocotb -------------------------------------------------------------------------
check_tool python3 python3 "python3 --version"
check_py   cocotb          cocotb          "$PY"
check_py   cocotb-coverage cocotb-coverage "$PY"

# --- Physical design -------------------------------------------------------------------------
if command -v librelane >/dev/null 2>&1; then
    row "librelane" "found" "$(python3 -c "import librelane; print(librelane.__version__)" 2>/dev/null) ($(command -v librelane))"
else
    row "librelane" "MISSING" "-"; missing=1
fi
check_tool openroad openroad "openroad -version | tail -n1"
check_tool sta      sta      "sta -version"
check_tool magic    magic    "magic --version"
check_tool netgen   netgen   "echo quit | netgen -batch | grep -m1 -i netgen"
check_tool klayout  klayout  "klayout -v"

if [ -d "${PDK_ROOT:-}/sky130A/libs.ref/sky130_fd_sc_hd" ]; then
    row "sky130A PDK" "found" "$PDK_ROOT/sky130A (PDK=${PDK:-unset}, SCL=${STD_CELL_LIBRARY:-unset})"
else
    row "sky130A PDK" "MISSING" "PDK_ROOT=${PDK_ROOT:-unset}"; missing=1
fi
icg="$(ls "$PDK_ROOT"/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib >/dev/null 2>&1 && \
       grep -o 'cell ("sky130_fd_sc_hd__dlclkp_[0-9]*")' "$PDK_ROOT"/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib | \
       sed 's/cell ("sky130_fd_sc_hd__//;s/")//' | tr '\n' ' ')"
if [ -n "$icg" ]; then row "ICG cells (hd, tt)" "found" "$icg"; else row "ICG cells (hd, tt)" "MISSING" "-"; missing=1; fi

# --- SRAM macro (A3 GDS configuration) -----------------------------------------------------
for view in gds:gds lef:lef verilog:v spice:spice maglef:mag; do
    d="${view%%:*}"; e="${view##*:}"
    f="$SRAM_DIR/$d/$SRAM.$e"
    if [ -f "$f" ]; then row "sram $d" "found" "$f"; else row "sram $d" "MISSING" "$f"; missing=1; fi
done
libs="$(ls "$SRAM_DIR"/lib/"$SRAM"_*.lib 2>/dev/null)"
if [ -n "$libs" ]; then
    for f in $libs; do row "sram lib" "found" "$f"; done
    row "sram lib corners" "note" "$(echo "$libs" | wc -l) liberty corner(s) for $SRAM; see docs/AUDIT.md"
else
    row "sram lib" "MISSING" "$SRAM_DIR/lib/${SRAM}_*.lib"; missing=1
fi

echo
if [ "$missing" -eq 0 ]; then echo "RESULT: all required tools found"; else echo "RESULT: missing items above"; fi
exit "$missing"
