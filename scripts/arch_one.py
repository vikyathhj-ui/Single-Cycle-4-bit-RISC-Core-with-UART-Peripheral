#!/usr/bin/env python3
"""Run one riscv-arch-test source on the DUT testbench, for debugging (not used by make riscof).

    PYTHONPATH= .venv-riscof/bin/python scripts/arch_one.py rv32i_m/I/src/add-01.S [--trace] [--march rv32i]

Compiles with riscof/env (same as the RISCOF plugin), converts with the plugin's elf_to_images, and
runs sim_build/tb_arch_trace/tb_arch (RVFI build, `make tb-arch-trace`) with +trace if asked.
Work files go to sim_build/arch_one/<test>/.
"""
import argparse
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "riscof" / "lp_rv32"))
import riscof_lp_rv32 as plugin  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("test", help="path below riscv-test-suite/, e.g. rv32i_m/I/src/add-01.S")
ap.add_argument("--march", default="rv32i_zicsr_zbb")
ap.add_argument("--trace", action="store_true")
ap.add_argument("--timeout", type=int, default=200000)
ap.add_argument("--macro", action="append", default=["XLEN=32", "TEST_CASE_1=True"])
a = ap.parse_args()

suite = REPO / "ext" / "riscv-arch-test" / "riscv-test-suite"
wd = REPO / "sim_build" / "arch_one" / Path(a.test).name
wd.mkdir(parents=True, exist_ok=True)
env = REPO / "riscof" / "env"
cmd = (f"riscv64-unknown-elf-gcc -march={a.march} -mabi=ilp32 -mno-relax -static -mcmodel=medany -nostdlib "
       f"-nostartfiles -g -T {env}/link.ld -I {env} -I {suite}/env {suite / a.test} -o my.elf "
       + " ".join(f"-D{m}" for m in a.macro))
subprocess.run(cmd, shell=True, cwd=wd, check=True)
s = plugin.elf_to_images(str(wd / "my.elf"), str(wd))
args = [str(REPO / "sim_build" / "tb_arch_trace" / "tb_arch"), "+imem=imem.hex", "+dmem=dmem.hex",
        "+sig=dut.sig", f"+tohost={s['tohost']:x}", f"+sig_begin={s['begin_signature']:x}",
        f"+sig_end={s['end_signature']:x}", f"+timeout={a.timeout}"] + (["+trace"] if a.trace else [])
sys.exit(subprocess.run(args, cwd=wd).returncode)
