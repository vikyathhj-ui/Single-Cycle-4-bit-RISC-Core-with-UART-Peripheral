#!/usr/bin/env python3
"""fmax per STA corner of a finished LibreLane run (BRIEF A6 "fmax at every corner"; D-029).

Why a sweep: the critical path starts at the SRAM's falling clock edge (MICROARCH §3, M-1), so a
path's slack is T/2 - delay for half-cycle paths and T - delay for full-cycle paths; 1/(T - slack)
would be wrong. Instead, for each of LibreLane's 9 STA corners ({nom,min,max} RC x {tt,ss,ff}),
one OpenSTA session reads the run's final netlist and that corner's SPEF once, then
binary-searches the clock period: at each trial period it re-applies LibreLane's own base.sdc
(CLOCK_PERIOD and the period-derived I/O delays change; uncertainty, derates, driving cell and
load come from the run's resolved.json) and checks the worst setup slack. Result: the smallest
period with setup slack >= 0, to 0.05 ns. Hold slack is reported at the run's own period.

Libraries: the corner's sky130_fd_sc_hd liberty plus the SRAM liberty, which exists for TT only
and is used at every corner (S-10); results are labelled accordingly.

    python3 scripts/sta_fmax.py flow/runs/<tag>      -> results/sta/fmax_<tag>.json
"""
from __future__ import annotations

import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PDK = Path(os.environ["PDK_ROOT"]) / os.environ["PDK"]
HD = PDK / "libs.ref" / "sky130_fd_sc_hd" / "lib"
SRAM_LIB = PDK / "libs.ref" / "sky130_sram_macros" / "lib" / "sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib"
BASE_SDC = Path("/usr/local/lib/python3.12/dist-packages/librelane/scripts/base.sdc")
PVT = {"tt": "tt_025C_1v80", "ss": "ss_100C_1v60", "ff": "ff_n40C_1v95"}


def spef_for(run: Path, rc: str) -> Path:
    cands = sorted((run / "final" / "spef").glob(f"{rc}/*.spef")) or sorted((run / "final" / "spef").glob(f"*{rc}*.spef"))
    if not cands:
        raise FileNotFoundError(f"no {rc} SPEF under {run}/final/spef")
    return cands[0]


def tcl_for(run: Path, rc: str, pvt: str, res: dict, out: Path) -> str:
    env = {k: res[k] for k in ("CLOCK_PORT", "IO_DELAY_CONSTRAINT", "MAX_FANOUT_CONSTRAINT",
                               "MAX_TRANSITION_CONSTRAINT", "SYNTH_DRIVING_CELL", "OUTPUT_CAP_LOAD",
                               "CLOCK_UNCERTAINTY_CONSTRAINT", "CLOCK_TRANSITION_CONSTRAINT",
                               "TIME_DERATING_CONSTRAINT") if res.get(k) is not None}
    sets = "\n".join(f"set ::env({k}) {{{v}}}" for k, v in env.items())
    nl = next((run / "final" / "nl").glob("*.nl.v"))
    return f"""
{sets}
read_liberty {HD / f'sky130_fd_sc_hd__{PVT[pvt]}.lib'}
read_liberty {SRAM_LIB}
read_verilog {nl}
link_design {res['DESIGN_NAME']}
read_spef {spef_for(run, rc)}
proc try_period {{p}} {{
    set ::env(CLOCK_PERIOD) $p
    # global scope: base.sdc mixes `clock_port` and `::clock_port`
    uplevel #0 [list source {BASE_SDC}]
    return [sta::worst_slack_cmd max]
}}
set run_period {res['CLOCK_PERIOD']}
set run_setup [try_period $run_period]
set run_hold [sta::worst_slack_cmd min]
set lo 1.0
set hi 400.0
if {{[try_period $hi] < 0}} {{ set hi -1 }} else {{
    while {{$hi - $lo > 0.05}} {{
        set mid [expr ($lo + $hi) / 2.0]
        if {{[try_period $mid] >= 0}} {{ set hi $mid }} else {{ set lo $mid }}
    }}
}}
set f [open {out} w]
puts $f "min_period $hi"
puts $f "setup_slack_at_run_period $run_setup"
puts $f "hold_slack_at_run_period $run_hold"
close $f
exit
"""


def one(run: Path, rc: str, pvt: str, res: dict, work: Path) -> dict:
    name = f"{rc}_{PVT[pvt]}"
    out = work / f"{name}.txt"
    tcl = work / f"{name}.tcl"
    tcl.write_text(tcl_for(run, rc, pvt, res, out))
    log = subprocess.run(["sta", "-no_splash", "-exit", str(tcl)], capture_output=True, text=True)
    (work / f"{name}.log").write_text(log.stdout + log.stderr)
    if not out.exists():
        return {"corner": name, "error": (log.stdout + log.stderr)[-800:]}
    if "__VIRTUAL_CLK__" in log.stdout:
        return {"corner": name, "error": "clock not applied (virtual clock), see log"}
    vals = dict(re.findall(r"(\S+) (\S+)", out.read_text()))
    p = float(vals["min_period"])
    return {"corner": name, "min_period_ns": round(p, 3) if p > 0 else None,
            "fmax_mhz": round(1000.0 / p, 3) if p > 0 else None,
            # OpenSTA's sta::worst_slack_cmd returns seconds
            "setup_ws_at_run_period_ns": round(float(vals["setup_slack_at_run_period"]) * 1e9, 4),
            "hold_ws_at_run_period_ns": round(float(vals["hold_slack_at_run_period"]) * 1e9, 4)}


def main() -> int:
    run = Path(sys.argv[1]).resolve()
    res = json.loads((run / "resolved.json").read_text())
    work = REPO / "sim_build" / "sta_fmax" / run.name
    work.mkdir(parents=True, exist_ok=True)
    jobs = [(rc, pvt) for rc in ("nom", "min", "max") for pvt in ("tt", "ss", "ff")]
    with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        results = list(ex.map(lambda j: one(run, j[0], j[1], res, work), jobs))
    out = {"run": str(run.relative_to(REPO)), "run_clock_period_ns": res["CLOCK_PERIOD"],
           "method": "OpenSTA period binary search on the final netlist + SPEF with LibreLane base.sdc (D-029)",
           "sram_liberty": "TT_1p8V_25C at every corner (S-10)", "corners": results}
    dst = REPO / "results" / "sta" / f"fmax_{run.name}.json"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(out, indent=2) + "\n")
    for r in results:
        print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
