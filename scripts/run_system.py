#!/usr/bin/env python3
"""Run the system tests (BRIEF A5 "System tests"): firmware from sw/ on lp_rv32_soc.

    .venv/bin/python scripts/run_system.py [--test hello ...] [--trace]

1. Builds the firmware (scripts/build_sw.py, SIM memory configuration).
2. Builds tb/system/soc_sys_tb.sv + the SoC once with Verilator (-DRISCV_FORMAL so the retire trace
   is available; the RVFI port is otherwise unused).
3. Runs tb/system/test_<name>.py for each test with +imem=sw/build/sim/<prog>/imem.hex.
   Tests write measured values to $METRICS_FILE (JSON); --trace adds +trace=<file> per test.
Results: results/system/summary.json (per test: PASS/FAIL, metrics, memory configuration, log).
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
sys.path[:0] = [str(REPO / "tb" / "system"), str(REPO / "tb")]   # the runner builds PYTHONPATH from sys.path
os.environ["PYTHONPATH"] = os.pathsep.join([str(REPO / "tb" / "system"), str(REPO / "tb"),
                                            os.environ.get("PYTHONPATH", "")])
from cocotb_tools.runner import get_runner  # noqa: E402


def flist(path: str) -> list[str]:
    return [l.strip() for l in (REPO / path).read_text().splitlines() if l.strip() and not l.strip().startswith("//")]


# test name -> (program, boot_sel note); the test module decides boot_sel itself
TESTS = {
    "hello": "hello",
    "loader": "loader_payload",
    "irq_test": "irq_test",
    "sleep_demo": "sleep_demo",
    "zbb_bench": "zbb_bench",
    "coremark": "coremark",
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--test", action="append", choices=sorted(TESTS))
    ap.add_argument("--trace", action="store_true", help="write a retire trace per test")
    ap.add_argument("--no-build", action="store_true", help="reuse the existing Verilator build")
    a = ap.parse_args()
    names = a.test or [t for t in TESTS if (REPO / "tb" / "system" / f"test_{t}.py").exists()]
    progs = sorted({TESTS[n] for n in names})
    subprocess.run([sys.executable, str(REPO / "scripts" / "build_sw.py"), *progs], check=True)

    build = REPO / "sim_build" / "system"
    runner = get_runner("verilator")
    if True:   # build() must run on this runner object; always=False reuses an up-to-date build
        runner.build(sources=[REPO / f for f in flist("rtl/core/core.f") + flist("rtl/soc/soc.f")]
                     + [REPO / "tb" / "system" / "soc_sys_tb.sv"],
                     hdl_toplevel="soc_sys_tb", build_dir=build, always=not a.no_build,
                     build_args=["-Wno-fatal", "--timing", "--x-initial-edge", "-O2", f"-I{REPO / 'rtl' / 'soc'}",
                                 "-DRISCV_FORMAL"],
                     log_file=build / "build.log", timescale=("1ns", "1ps"))
    out = REPO / "results" / "system" / "summary.json"
    summary = json.loads(out.read_text()) if out.exists() else {}
    ok = True
    for n in names:
        prog = TESTS[n]
        mfile = build / f"metrics_{n}.json"
        if mfile.exists():
            mfile.unlink()
        plus = [f"+imem={REPO / 'sw' / 'build' / 'sim' / prog / 'imem.hex'}"]
        if a.trace:
            plus.append(f"+trace={build / f'trace_{n}.txt'}")
        xml = build / f"results_{n}.xml"
        runner.test(test_module=f"test_{n}", hdl_toplevel="soc_sys_tb", build_dir=build, test_dir=build,
                    results_xml=str(xml), plusargs=plus, log_file=build / f"test_{n}.log",
                    extra_env={"METRICS_FILE": str(mfile), "SW_BUILD": str(REPO / "sw" / "build" / "sim")},
                    timescale=("1ns", "1ps"))
        tests = {tc.get("name"): ("FAIL" if tc.find("failure") is not None or tc.find("error") is not None
                                  else "PASS") for tc in ET.parse(xml).getroot().iter("testcase")}
        status = "PASS" if tests and all(v == "PASS" for v in tests.values()) else "FAIL"
        ok &= status == "PASS"
        summary[n] = {"status": status, "tests": tests, "program": f"sw/{prog}",
                      "memory_config": "SIM (IMEM 32 KB + DMEM 32 KB)",
                      "metrics": json.loads(mfile.read_text()) if mfile.exists() else {},
                      "log": str((build / f"test_{n}.log").relative_to(REPO))}
        print(f"{n:<11} {status}  {summary[n]['metrics']}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
