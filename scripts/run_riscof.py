#!/usr/bin/env python3
"""Run riscv-arch-test 3.10.0 on lp_rv32 through RISCOF, with Spike as reference (D-003, D-013).

Steps (run inside the iic-osic container from the repo root; riscof runs in .venv-riscof with
PYTHONPATH cleared, D-004):
  1. `riscof testlist` with riscof/config.ini -> the tests RISCOF selects for the DUT ISA yaml.
  2. Exclusions (owner decisions, D-015):
       * rv32i_m/pmp32/*: not applicable, the core has no PMP (SPEC §1).
       * tests whose code or data does not fit the SIM memory configuration (32 KB IMEM + 32 KB
         DMEM, riscof/env/link.ld): "not run (too big)", with the linker's overflow message.
  3. `riscof run --testfile <filtered list>`: compiles and runs every remaining test on the DUT
     (tb/arch/tb_arch.sv, Verilator) and on Spike.
  4. Per test, compares DUT-lp_rv32.signature with Reference-spike_ref.signature word by word.
Outputs: results/riscof/summary.json (per test: status, suite, reason) and results/riscof/tests.txt.
Exit 1 if any test that was run fails. --compare-only re-reads riscof_work without running again.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
WORK = REPO / "riscof_work"
OUT = REPO / "results" / "riscof"
SUITE = REPO / "ext" / "riscv-arch-test" / "riscv-test-suite"
ENV = SUITE / "env"
RISCOF = REPO / ".venv-riscof" / "bin" / "riscof"
CFG = REPO / "riscof" / "config.ini"
LINK = REPO / "riscof" / "env" / "link.ld"


def riscof(*args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, PYTHONPATH="")
    cmd = [str(RISCOF), *args, f"--config={CFG}", f"--suite={SUITE}", f"--env={ENV}", f"--work-dir={WORK}"]
    return subprocess.run(cmd, cwd=REPO, env=env, capture_output=True, text=True)


def short(path: str) -> str:
    return path.split("riscv-test-suite/")[-1]


def fits(entry: dict, tmp: Path) -> tuple[bool, str]:
    """Link the test with the real 32 KB link script; return (fits, linker message)."""
    cmd = (f"riscv64-unknown-elf-gcc -march={entry['isa'].lower()} -mabi=ilp32 -mno-relax -static -mcmodel=medany "
           f"-fvisibility=hidden -nostdlib -nostartfiles -T {LINK} -I {LINK.parent} -I {ENV} "
           f"{entry['test_path']} -o {tmp} -D" + " -D".join(entry["macros"]))
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode == 0:
        return True, ""
    msg = " ".join(m.group(0) for m in re.finditer(r"region `\w+' overflowed by \d+ bytes", r.stderr))
    if not msg:
        raise RuntimeError(f"compile error (not a size problem) for {entry['test_path']}:\n{r.stderr}")
    return False, msg


def compare(dut: Path, ref: Path) -> tuple[str, str]:
    if not dut.exists():
        return "FAIL", "no DUT signature (see dut.log)"
    if not ref.exists():
        return "FAIL", "no reference signature"
    d, r = dut.read_text().split(), ref.read_text().split()
    if len(d) != len(r):
        return "FAIL", f"length {len(d)} vs reference {len(r)} words"
    bad = [i for i, (a, b) in enumerate(zip(d, r)) if a.lower() != b.lower()]
    if bad:
        return "FAIL", f"{len(bad)} of {len(d)} words differ, first at word {bad[0]}"
    return "PASS", f"{len(d)} words match"


def main() -> int:
    compare_only = "--compare-only" in sys.argv   # reuse riscof_work from the last run
    r = riscof("testlist") if not compare_only else subprocess.CompletedProcess([], 0, "", "")
    if r.returncode:
        print(r.stdout[-3000:], r.stderr[-3000:])
        return 2
    tests = yaml.safe_load((WORK / "test_list.yaml").read_text())
    results: dict[str, dict] = {}
    keep = {}
    tmp = REPO / "sim_build" / "riscof_fitcheck.elf"
    for name, entry in tests.items():
        key = short(name)
        suite = key.split("/src/")[0] if "/src/" in key else key.rsplit("/", 1)[0]
        if "/pmp32/" in name:
            results[key] = {"suite": "rv32i_m/pmp32", "status": "N/A", "reason": "no PMP in this core (SPEC §1)"}
            continue
        ok, msg = fits(entry, tmp)
        if not ok:
            results[key] = {"suite": suite, "status": "NOT RUN", "reason": f"too big for SIM config: {msg}"}
            continue
        keep[name] = entry
    filtered = REPO / "sim_build" / "riscof_test_list_filtered.yaml"   # outside WORK: riscof run cleans WORK
    filtered.parent.mkdir(exist_ok=True)
    filtered.write_text(yaml.safe_dump(keep))
    print(f"selected {len(tests)}, running {len(keep)}")

    OUT.mkdir(parents=True, exist_ok=True)
    if not compare_only:
        r = riscof("run", f"--testfile={filtered}", "--no-browser")
        (OUT / "riscof_run.log").write_text(r.stdout + r.stderr)

    for name, entry in keep.items():
        key = short(name)
        wd = Path(entry["work_dir"])
        refs = sorted((wd / "ref").glob("Reference-*.signature"))
        status, why = compare(wd / "dut" / "DUT-lp_rv32.signature", refs[0] if refs else wd / "ref" / "missing")
        results[key] = {"suite": key.split("/src/")[0], "status": status, "reason": why}

    counts = Counter(v["status"] for v in results.values())
    by_suite: dict[str, Counter] = {}
    for v in results.values():
        by_suite.setdefault(v["suite"] if "pmp32" not in v["suite"] else "rv32i_m/pmp32", Counter())[v["status"]] += 1
    commit = subprocess.run(["git", "-C", str(SUITE.parent), "describe", "--tags", "--always"],
                            capture_output=True, text=True).stdout.strip()
    summary = {
        "tool": "riscof 1.25.3",
        "suite": f"riscv-arch-test {commit}",
        "reference": "spike 1.1.1-dev (D-013)",
        "dut": "lp_rv32_core in tb/arch/tb_arch.sv (Verilator)",
        "memory_config": "SIM (IMEM 32 KB + DMEM 32 KB, riscof/env/link.ld)",
        "counts": dict(counts),
        "by_suite": {k: dict(v) for k, v in sorted(by_suite.items())},
        "tests": dict(sorted(results.items())),
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    lines = [f"{k:<50} {v['status']:<8} {v['reason']}" for k, v in sorted(results.items())]
    (OUT / "tests.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(l for l in lines if " PASS " not in l and " N/A " not in l))
    print(f"counts: {dict(counts)}")
    print(json.dumps(summary["by_suite"], indent=1))
    return 1 if counts.get("FAIL", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
