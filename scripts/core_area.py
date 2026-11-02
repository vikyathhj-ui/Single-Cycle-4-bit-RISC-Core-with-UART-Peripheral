#!/usr/bin/env python3
"""Pre-layout area of lp_rv32_core (BRIEF A2 "area ... data"; MICROARCH §9).

Yosys (slang frontend, which elaborates the core into one flattened module) synthesises
rtl/core/core.f, top lp_rv32_core, maps to sky130_fd_sc_hd (tt_025C_1v80 liberty) with dfflibmap +
abc, and runs `stat -liberty`. Output: results/area/core_yosys.json (cell count, flip-flop count,
area in um^2) and
results/area/core_yosys.log. This is synthesis area, not layout area (Phase 5 reports that).
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = f"{os.environ['PDK_ROOT']}/{os.environ['PDK']}/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
files = [str(REPO / l.strip()) for l in (REPO / "rtl/core/core.f").read_text().splitlines()
         if l.strip() and not l.strip().startswith("//")]
script = (f"plugin -i slang; read_slang --top lp_rv32_core {' '.join(files)}; "
          "hierarchy -top lp_rv32_core; synth -top lp_rv32_core; "
          f"dfflibmap -liberty {LIB}; abc -liberty {LIB}; opt_clean; "
          f"tee -o {REPO}/results/area/core_stat.txt stat -liberty {LIB}")
log = subprocess.run(["yosys", "-q", "-p", script], capture_output=True, text=True)
(REPO / "results/area/core_yosys.log").write_text(log.stdout + log.stderr)
if log.returncode:
    print(log.stderr[-2000:])
    sys.exit(1)
txt = (REPO / "results/area/core_stat.txt").read_text()
mods = {}
for block in re.split(r"\n=== ", "\n" + txt)[1:]:
    name = block.split(" ===")[0].strip()
    cells = re.search(r"^\s+(\d+)\s+[\d.E+-]*\s*cells$", block, re.M) or re.search(r"Number of cells:\s+(\d+)", block)
    area = re.search(r"Chip area for (?:module|top module) .*?:\s*([\d.]+)", block) or re.search(r"^\s+([\d.]+)\s+.*chip area", block, re.M)
    dffs = sum(int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+[\d.E+-]*\s*sky130_fd_sc_hd__(?:df|edf|sdf)\w*", block, re.M))
    mods[name] = {"cells": int(cells.group(1)) if cells else None,
                  "area_um2": float(area.group(1)) if area else None, "flops": dffs}
res = {"tool": subprocess.run(["yosys", "-V"], capture_output=True, text=True).stdout.strip(),
       "liberty": "sky130_fd_sc_hd__tt_025C_1v80.lib", "kind": "synthesis (pre-layout), flattened by the slang frontend",
       "modules": mods}
(REPO / "results/area/core_yosys.json").write_text(json.dumps(res, indent=2) + "\n")
print(json.dumps(mods, indent=1))
