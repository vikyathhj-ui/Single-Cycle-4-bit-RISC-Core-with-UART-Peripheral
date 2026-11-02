#!/usr/bin/env python3
"""Trace-driven CPI model for 2-, 3- and 5-stage in-order pipelines (docs/MICROARCH.md §9, BRIEF A2
"Justify 3 stages vs 2 or 5 ... with area and CPI data").

Input: the hazard counts that tb/system/soc_sys_tb.sv measures from the RVFI retire stream of a real
program run on the 3-stage RTL (results/system/summary.json, "hazard_stats_whole_program"):
retired instructions N, taken control transfers T (any pc change other than +4: taken branches,
jumps, traps, MRET), loads L, load-use pairs at distance 1 (U1) and distance 2 (U2).

Penalty rules (all pipelines in order, single issue, the same synchronous OpenRAM memories whose
read data arrives one cycle after the address, MICROARCH §3):
  3-stage  IF | ID/EX | MEM/WB  (this RTL): taken transfer 1 cycle (registered redirect, H4),
           load-use at distance 1: 1 cycle (H3).
  2-stage  IF | EX+MEM+WB: a load's data arrives a cycle after EX, so every load holds the single
           back stage one extra cycle: 1 cycle per load; taken transfer 1 cycle.
  5-stage  IF | ID | EX | MEM | WB, full forwarding: branches resolve in EX, 2 instructions behind
           are flushed: 2 cycles per taken transfer; load-use at distance 1: 1 cycle.
CPI_model = 1 + penalties / N. "Other" = measured cycles - 3-stage model cycles: stalls that every
pipeline depth would see (APB wait states, UART polling loops are already counted as instructions;
WFI, start-up). The comparison is a model applied to measured traces, not a measurement of 2- and
5-stage hardware (only the 3-stage pipeline exists). Area is not modelled: only the 3-stage core is
synthesised (results/area/core_yosys.json).
Output: results/cpi/cpi_model.json and a Markdown table on stdout.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def model(s: dict) -> dict:
    n, t, l, u1 = s["retired"], s["ct_taken"], s["loads"], s["load_use_d1"]
    pen = {"2-stage": t + l, "3-stage": t + u1, "5-stage": 2 * t + u1}
    out = {k: {"penalty_cycles": v, "cpi": round(1 + v / n, 4)} for k, v in pen.items()}
    measured_cpi = s["cycles"] / n
    out["3-stage measured"] = {"cycles": s["cycles"], "cpi": round(measured_cpi, 4),
                               "other_stall_cycles": s["cycles"] - (n + pen["3-stage"])}
    return out


def main() -> int:
    summ = json.loads((REPO / "results" / "system" / "summary.json").read_text())
    res = {}
    for test in ("coremark", "zbb_bench"):
        st = summ.get(test, {}).get("metrics", {}).get("hazard_stats_whole_program")
        if not st:
            continue
        res[test] = {"stats": st, "model": model(st)}
    out = REPO / "results" / "cpi" / "cpi_model.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"source": "results/system/summary.json (SIM memory configuration, RTL simulation)",
                               "workloads": res}, indent=2) + "\n")
    print("| Workload | N retired | taken CT | loads | load-use d1 | CPI 2-stage (model) | CPI 3-stage (model) | "
          "CPI 3-stage (measured) | CPI 5-stage (model) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for k, r in res.items():
        s, m = r["stats"], r["model"]
        print(f"| {k} | {s['retired']} | {s['ct_taken']} | {s['loads']} | {s['load_use_d1']} | "
              f"{m['2-stage']['cpi']} | {m['3-stage']['cpi']} | {m['3-stage measured']['cpi']} | {m['5-stage']['cpi']} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
