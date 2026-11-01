#!/usr/bin/env python3
"""Run riscv-formal on lp_rv32_core and collect the results (docs/MICROARCH.md §10, BRIEF A5).

Steps:
  1. Copy formal/checks.cfg (with @core_files@ replaced from rtl/core/core.f) and formal/wrapper.sv into
     ext/riscv-formal/cores/lp_rv32/ (genchecks.py must run two levels below the framework root).
  2. Run the framework's own generator: python3 ../../checks/genchecks.py
  3. Run every generated SBY job with make -C checks -j N (or the subset given by --only).
  4. Read each job's status file and write results/formal/summary.json and
     results/formal/checks.txt. Counterexample traces of failing checks are copied to
     results/formal_cex/<check>.vcd.

    python3 scripts/run_formal.py                 # full depths from formal/checks.cfg
    python3 scripts/run_formal.py --quick         # every depth capped (CI)
    python3 scripts/run_formal.py --only 'insn_add|reg'   # regex over check names

Run inside the iic-osic container from the repo root.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RF = REPO / "ext" / "riscv-formal"
OUT = REPO / "results" / "formal"
CEX = REPO / "results" / "formal_cex"


def cap_depths(cfg: str, cap: int) -> str:
    """Cap every number in the [depth] section at `cap` (quick mode)."""
    out, in_depth = [], False
    for line in cfg.splitlines():
        if line.startswith("["):
            in_depth = line.strip() == "[depth]"
        elif in_depth and line.strip() and not line.startswith("#"):
            name, *nums = line.split()
            nums = [str(min(int(n), cap)) for n in nums]
            line = "  ".join([f"{name:<15}"] + nums)
        out.append(line)
    return "\n".join(out) + "\n"


def set_depth(cfg: str, name: str, depth: str) -> str:
    """Replace the depth numbers of one [depth] entry, e.g. reg=5,16 (used to probe depths)."""
    out, in_depth, found = [], False, False
    for line in cfg.splitlines():
        if line.startswith("["):
            in_depth = line.strip() == "[depth]"
        elif in_depth and line.split() and line.split()[0] == name:
            line = f"{name:<15} " + "  ".join(depth.split(","))
            found = True
        out.append(line)
    assert found, f"no [depth] entry named {name}"
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--quick", action="store_true", help="cap all depths (default cap 10)")
    ap.add_argument("--cap", type=int, default=10)
    ap.add_argument("--only", default="", help="regex: run only matching checks")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--set", action="append", default=[], metavar="NAME=D[,D..]",
                    help="override one [depth] entry, e.g. reg=5,16 (results go to a probe file)")
    ap.add_argument("--work", default="lp_rv32", help="work dir name under ext/riscv-formal/cores/")
    args = ap.parse_args()
    WORK = RF / "cores" / args.work

    if not (RF / "checks" / "genchecks.py").exists():
        print("ext/riscv-formal missing (see CLAUDE.md)", file=sys.stderr)
        return 2

    files = [l.strip() for l in (REPO / "rtl" / "core" / "core.f").read_text().splitlines()
             if l.strip() and not l.strip().startswith("//")]
    cfg = (REPO / "formal" / "checks.cfg").read_text().replace(
        "@core_files@", " ".join(str(REPO / f) for f in files))
    if args.quick:
        cfg = cap_depths(cfg, args.cap)
    for item in args.set:
        name, depth = item.split("=", 1)
        cfg = set_depth(cfg, name, depth)
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    (WORK / "checks.cfg").write_text(cfg)
    shutil.copy(REPO / "formal" / "wrapper.sv", WORK / "wrapper.sv")

    subprocess.run([sys.executable, "../../checks/genchecks.py"], cwd=WORK, check=True)
    names = sorted(p.stem for p in (WORK / "checks").glob("*.sby"))
    if args.only:
        names = [n for n in names if re.search(args.only, n)]
    targets = [f"{n}/status" for n in names]
    print(f"running {len(targets)} checks with -j{args.jobs}")
    t0 = time.time()
    subprocess.run(["make", "-k", "-C", "checks", f"-j{args.jobs}", *targets], cwd=WORK)
    wall = time.time() - t0

    depths = {}
    for n in names:
        sby = (WORK / "checks" / f"{n}.sby").read_text()
        m = re.search(r"^depth\s+(\d+)", sby, re.M)
        depths[n] = int(m.group(1)) if m else None

    results = {}
    OUT.mkdir(parents=True, exist_ok=True)
    CEX.mkdir(parents=True, exist_ok=True)
    for n in names:
        status_file = WORK / "checks" / n / "status"
        status = status_file.read_text().split()[0] if status_file.exists() else "ERROR"
        results[n] = {"status": status, "depth": depths[n]}
        if status not in ("PASS",):
            for vcd in sorted((WORK / "checks" / n).glob("engine_*/trace*.vcd")):
                dst = CEX / f"{args.work}_{n}.vcd"
                shutil.copy(vcd, dst)
                results[n]["cex"] = str(dst.relative_to(REPO))
                break

    counts = {}
    for r in results.values():
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    tool = subprocess.run(["git", "-C", str(RF), "log", "-1", "--format=%H"], capture_output=True, text=True)
    summary = {
        "tool": "riscv-formal",
        "riscv_formal_commit": tool.stdout.strip(),
        "config": "formal/checks.cfg" + (f" (quick, depth cap {args.cap})" if args.quick else ""),
        "solver": "yices",
        "subset": args.only or None,
        "depth_overrides": args.set or None,
        "wall_seconds": round(wall, 1),
        "counts": counts,
        "checks": results,
    }
    name = "summary_quick.json" if args.quick else "summary.json"
    if args.set or args.only:
        name = f"probe_{args.work}.json"
    (OUT / name).write_text(json.dumps(summary, indent=2) + "\n")
    lines = [f"{n:<40} {r['status']:<6} depth {r['depth']}" for n, r in results.items()]
    if not name.startswith("probe_"):
        (OUT / name.replace(".json", ".txt").replace("summary", "checks")).write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"counts: {counts}  wall: {wall:.0f} s  -> results/formal/{name}")
    return 0 if counts.get("PASS", 0) == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
