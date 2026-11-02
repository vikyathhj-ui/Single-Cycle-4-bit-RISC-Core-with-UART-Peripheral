#!/usr/bin/env python3
"""Run the cocotb unit tests (BRIEF A5 "Unit tests") and collect results.

    .venv/bin/python scripts/run_unit.py                 # every unit
    .venv/bin/python scripts/run_unit.py --unit uart     # one unit

Each unit: Verilator build of its top-level through cocotb_tools.runner, cocotb test module
tb/unit/test_<unit>.py, per-test results from cocotb's results.xml, functional coverage from
cocotb-coverage exported to results/coverage/<unit>.json. Summary: results/unit/summary.json.
Exit 1 if any test fails.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tb" / "unit"))
os.environ["PYTHONPATH"] = os.pathsep.join([str(REPO / "tb" / "unit"), str(REPO / "tb"),
                                            os.environ.get("PYTHONPATH", "")])
from cocotb_tools.runner import get_runner  # noqa: E402

def flist(path: str) -> list[str]:
    return [l.strip() for l in (REPO / path).read_text().splitlines() if l.strip() and not l.strip().startswith("//")]


CORE = flist("rtl/core/core.f")
SOC = flist("rtl/soc/soc.f")
UNITS = {
    "uart":  {"top": "uart_lite",   "sources": ["rtl/periph/uart_lite.sv"]},
    "timer": {"top": "timer_clint", "sources": ["rtl/periph/timer_clint.sv"]},
    "gpio":  {"top": "gpio8",       "sources": ["rtl/periph/gpio8.sv"]},
    "xbar":  {"top": "xbar_tb",     "sources": ["rtl/soc/mem_1rw1r_sim.sv", "rtl/soc/lp_rv32_xbar.sv",
                                                "rtl/soc/apb_bridge.sv", "tb/unit/xbar_tb.sv"]},
    "soc":   {"top": "soc_tb",      "sources": CORE + SOC + ["tb/unit/soc_tb.sv"],
              "program": "sw/tests/smoke.S"},
}


def build_program(src: str, out_dir: Path) -> Path:
    """Link a bare-metal test program at IMEM_BASE and write a word-per-line IMEM image."""
    out_dir.mkdir(parents=True, exist_ok=True)
    elf, binf, hexf = out_dir / "prog.elf", out_dir / "prog.bin", out_dir / "imem.hex"
    subprocess.run(["riscv64-unknown-elf-gcc", "-march=rv32i_zicsr_zbb", "-mabi=ilp32", "-nostdlib",
                    "-nostartfiles", "-Wl,-Ttext=0x10000000", "-Wl,--no-relax", "-o", str(elf),
                    str(REPO / src)], check=True)
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", str(elf), str(binf)], check=True)
    data = binf.read_bytes()
    data += b"\0" * (-len(data) % 4)
    hexf.write_text("".join(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n" for i in range(0, len(data), 4)))
    return hexf


def run_unit(name: str) -> dict:
    u = UNITS[name]
    build = REPO / "sim_build" / "unit" / name
    cov = REPO / "results" / "coverage" / f"{name}.json"
    cov.parent.mkdir(parents=True, exist_ok=True)
    if cov.exists():
        cov.unlink()
    runner = get_runner("verilator")
    runner.build(sources=[REPO / s for s in u["sources"]], hdl_toplevel=u["top"], build_dir=build,
                 build_args=["-Wno-fatal", "--timing", f"-I{REPO / 'rtl' / 'soc'}"], always=True,
                 log_file=build / "build.log", timescale=("1ns", "1ps"))
    plusargs = [f"+imem={build_program(u['program'], build)}"] if "program" in u else []
    xml = build / "results.xml"
    runner.test(test_module=f"test_{name}", hdl_toplevel=u["top"], build_dir=build, test_dir=build,
                results_xml=str(xml), extra_env={"COV_FILE": str(cov)}, log_file=build / "test.log",
                plusargs=plusargs,
                timescale=("1ns", "1ps"))
    tests = {}
    for tc in ET.parse(xml).getroot().iter("testcase"):
        failed = tc.find("failure") is not None or tc.find("error") is not None
        tests[tc.get("name")] = "FAIL" if failed else "PASS"
    cov_pct, bins = None, None
    if cov.exists():
        data = json.loads(cov.read_text())
        size = sum(v["size"] for v in data.values())
        hits = sum(v["hits"] for v in data.values())
        cov_pct = round(100.0 * hits / size, 1) if size else None
        bins = {"hit": hits, "total": size}
    return {"top": u["top"], "tests": tests, "coverage_percent": cov_pct, "coverage_bins": bins,
            "coverage_file": str(cov.relative_to(REPO)) if cov.exists() else None,
            "log": str((build / "test.log").relative_to(REPO))}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--unit", action="append", choices=sorted(UNITS))
    a = ap.parse_args()
    names = a.unit or list(UNITS)
    out = REPO / "results" / "unit" / "summary.json"
    summary = json.loads(out.read_text()) if out.exists() and a.unit else {}
    ok = True
    for n in names:
        r = run_unit(n)
        summary[n] = r
        npass = sum(1 for v in r["tests"].values() if v == "PASS")
        print(f"{n:<6} {npass}/{len(r['tests'])} PASS  coverage {r['coverage_percent']}% {r['coverage_bins']}")
        ok &= npass == len(r["tests"]) and len(r["tests"]) > 0
    vers = subprocess.run(["verilator", "--version"], capture_output=True, text=True).stdout.strip()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({**summary, "_simulator": vers}, indent=2, sort_keys=True) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
