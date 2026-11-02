#!/usr/bin/env python3
"""Build the firmware in sw/ (BRIEF A4) for one memory configuration.

    python3 scripts/build_sw.py [--cfg sim|gds] [prog ...]     (default: all programs, sim)

Per program sw/<prog>/*.c|*.S + sw/common: riscv64-unknown-elf-gcc -march=rv32i_zicsr_zbb
-mabi=ilp32 (-march per program can be overridden, see PROGRAMS), linker script
sw/common/link_<cfg>.ld. Outputs in sw/build/<cfg>/<prog>/: prog.elf, prog.dis, prog.bin (the IMEM
image: code + rodata + .data load image, also what the UART loader receives), imem.hex (one word
per line, for the testbench preload), size.txt. results/sw/build_<cfg>.json records the compiler
version, flags and section sizes.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CC = "riscv64-unknown-elf-gcc"
ITERATIONS = 10        # CoreMark iterations (RTL simulation; far below the 10 s rule, see D-025)
BASE_FLAGS = ["-march=rv32i_zicsr_zbb", "-mabi=ilp32", "-O2", "-ffreestanding", "-fno-builtin-printf",
              "-nostdlib", "-nostartfiles", "-Wall", "-Wextra", "-g"]
# program -> extra flags / extra source dirs
PROGRAMS: dict[str, dict] = {
    "hello": {},
    "irq_test": {},
    "sleep_demo": {},
    "zbb_bench": {"per_file": {"kernel.c": [("_base", ["-march=rv32i_zicsr", "-DSUFFIX=_base"]),
                                            ("_zbb", ["-march=rv32i_zicsr_zbb", "-DSUFFIX=_zbb"])]}},
    # EEMBC CoreMark: core files unmodified from ext/coremark (pinned, D-025), port in sw/coremark.
    "coremark": {"extra_sources": ["ext/coremark/core_list_join.c", "ext/coremark/core_main.c",
                                   "ext/coremark/core_matrix.c", "ext/coremark/core_state.c",
                                   "ext/coremark/core_util.c"],
                 "flags": ["-Iext/coremark", "-DPERFORMANCE_RUN=1", "-DITERATIONS=ITERS"],
                 "coremark": True},
    "loader_payload": {},
}


def build(prog: str, cfg: str) -> dict:
    src_dir = REPO / "sw" / prog
    out = REPO / "sw" / "build" / cfg / prog
    out.mkdir(parents=True, exist_ok=True)
    spec = PROGRAMS[prog]
    sources = sorted(src_dir.glob("*.c")) + sorted(src_dir.glob("*.S")) + [
        REPO / "sw" / "common" / "crt0.S", REPO / "sw" / "common" / "hal.c"] + [
        REPO / f for f in spec.get("extra_sources", [])]
    extra = [f.replace("-Iext/", f"-I{REPO}/ext/").replace("ITERS", str(ITERATIONS)) for f in spec.get("flags", [])]
    if spec.get("coremark"):
        # CoreMark reporting rules: the flags are printed in the result (COMPILER_FLAGS).
        shown = " ".join(f for f in BASE_FLAGS if not f.startswith("-W") and f != "-g")
        extra.append(f'-DCOMPILER_FLAGS="{shown}"')
    flags = BASE_FLAGS + extra + [
        f"-DLP_RV32_CFG_{cfg.upper()}", f"-I{REPO / 'sw' / 'include'}", f"-I{REPO / 'sw' / 'common'}",
        f"-I{src_dir}", f"-T{REPO / 'sw' / 'common' / f'link_{cfg}.ld'}", "-Wl,--gc-sections"]
    objs = []
    for s in sources:                     # per-file flags (zbb_bench compiles one file twice)
        for variant, extra in spec.get("per_file", {}).get(s.name, [("", [])]):
            o = out / f"{s.stem}{variant}.o"
            subprocess.run([CC, *flags, *extra, "-ffunction-sections", "-fdata-sections", "-c", str(s),
                            "-o", str(o)], check=True)
            objs.append(o)
    elf = out / "prog.elf"
    subprocess.run([CC, *flags, *[str(o) for o in objs], "-lgcc", "-o", str(elf)], check=True)
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", "--remove-section=.bss", str(elf),
                    str(out / "prog.bin")], check=True)
    (out / "prog.dis").write_text(subprocess.run(["riscv64-unknown-elf-objdump", "-d", str(elf)],
                                                 capture_output=True, text=True, check=True).stdout)
    data = (out / "prog.bin").read_bytes()
    data += b"\0" * (-len(data) % 4)
    (out / "imem.hex").write_text("".join(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n"
                                          for i in range(0, len(data), 4)))
    size = subprocess.run(["riscv64-unknown-elf-size", "-A", str(elf)], capture_output=True, text=True).stdout
    (out / "size.txt").write_text(size)
    secs = {l.split()[0]: int(l.split()[1]) for l in size.splitlines() if l.startswith(".") and l.split()[1].isdigit()}
    return {"elf": str(elf.relative_to(REPO)), "image_bytes": len(data), "sections": secs,
            "flags": [f.replace(str(REPO) + "/", "") for f in flags]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cfg", choices=["sim", "gds"], default="sim")
    ap.add_argument("progs", nargs="*")
    a = ap.parse_args()
    progs = a.progs or [p for p in PROGRAMS if (REPO / "sw" / p).is_dir()]
    ver = subprocess.run([CC, "--version"], capture_output=True, text=True).stdout.splitlines()[0]
    res_file = REPO / "results" / "sw" / f"build_{a.cfg}.json"
    res = json.loads(res_file.read_text()) if res_file.exists() else {}
    res["compiler"] = ver
    for p in progs:
        r = build(p, a.cfg)
        res.setdefault("programs", {})[p] = r
        print(f"{a.cfg}/{p}: {r['image_bytes']} B IMEM image")
    res_file.parent.mkdir(parents=True, exist_ok=True)
    res_file.write_text(json.dumps(res, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
