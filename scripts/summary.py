#!/usr/bin/env python3
"""Build results/summary.json (BRIEF Part B rule 1): every reported number, copied by this script
from a result file, with that file's path and the memory configuration it came from.

    python3 scripts/summary.py

Missing inputs are skipped (listed under "missing"), never estimated.
"""
from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SIM = "SIM (IMEM 32 KB + DMEM 32 KB)"
entries: dict[str, dict] = {}
missing: list[str] = []


def load(rel: str):
    p = REPO / rel
    if not p.exists():
        missing.append(rel)
        return None
    return json.loads(p.read_text())


def put(name, value, source, config="n/a", unit="", note=""):
    entries[name] = {"value": value, "unit": unit, "source": source, "memory_config": config}
    if note:
        entries[name]["note"] = note


f = load("results/formal/summary.json")
if f:
    put("formal.checks_pass", f["counts"].get("PASS", 0), "results/formal/summary.json")
    put("formal.checks_total", len(f["checks"]), "results/formal/summary.json")
    put("formal.reg_depth", f["checks"]["reg_ch0"]["depth"], "results/formal/summary.json", unit="cycles (SBY depth)")
r = load("results/riscof/summary.json")
if r:
    for k, v in r["counts"].items():
        put(f"riscof.{k.lower().replace(' ', '_').replace('/', '')}", v, "results/riscof/summary.json", SIM)
u = load("results/unit/summary.json")
if u:
    tests = [t for k, v in u.items() if not k.startswith("_") for t in v["tests"].values()]
    put("unit.tests_pass", sum(t == "PASS" for t in tests), "results/unit/summary.json")
    put("unit.tests_total", len(tests), "results/unit/summary.json")
    for k, v in u.items():
        if not k.startswith("_") and v.get("coverage_bins"):
            put(f"unit.{k}.coverage_bins_hit", v["coverage_bins"]["hit"], "results/unit/summary.json")
            put(f"unit.{k}.coverage_bins_total", v["coverage_bins"]["total"], "results/unit/summary.json")
s = load("results/system/summary.json")
if s:
    src = "results/system/summary.json"
    put("system.tests_pass", sum(v["status"] == "PASS" for v in s.values()), src, SIM)
    put("system.tests_total", len(s), src, SIM)
    cm = s.get("coremark", {}).get("metrics", {})
    if cm:
        put("coremark.per_mhz", cm["coremark_per_mhz"], src, SIM, "CoreMark/MHz",
            "RTL simulation; 10 iterations, below CoreMark's 10 s rule, not a valid published score (D-025)")
        put("coremark.iterations", cm["iterations"], src, SIM)
        put("coremark.total_cycles", cm["total_ticks_cycles"], src, SIM, "cycles")
    zb = s.get("zbb_bench", {}).get("metrics", {})
    if zb:
        put("zbb_bench.base_cycles", zb["base_cycles"], src, SIM, "cycles")
        put("zbb_bench.zbb_cycles", zb["zbb_cycles"], src, SIM, "cycles")
    sd = s.get("sleep_demo", {}).get("metrics", {})
    if sd:
        put("sleep.idle_gated_cycles", sd["idle_gated_windows"][0]["cycles"], src, SIM, "cycles")
        put("sleep.idle_core_clock_edges", sd["idle_gated_windows"][0]["core_clock_edges"], src, SIM, "edges")
        put("sleep.idle_mcycle_delta", sd["idle_mcycle_delta"], src, SIM, "cycles")
        put("sleep.idle_mtime_delta", sd["idle_mtime_delta"], src, SIM, "ticks")
        put("sleep.deep_sleep_isolation_violations", sum(w["violations"] for w in sd["deep_sleep_off_windows"]), src, SIM)
    ld = s.get("loader", {}).get("metrics", {})
    if ld:
        put("boot.loader_image_bytes", ld["image_bytes"], src, SIM, "bytes")
c = load("results/cpi/cpi_model.json")
if c and "coremark" in c["workloads"]:
    m = c["workloads"]["coremark"]["model"]
    for k in ("2-stage", "3-stage", "5-stage"):
        put(f"cpi.coremark.{k}_model", m[k]["cpi"], "results/cpi/cpi_model.json", SIM, "CPI", "trace-driven model")
    put("cpi.coremark.3-stage_measured", m["3-stage measured"]["cpi"], "results/cpi/cpi_model.json", SIM, "CPI")
a = load("results/area/core_yosys.json")
if a:
    top = a["modules"]["lp_rv32_core"]
    put("area.core_synth_um2", top["area_um2"], "results/area/core_yosys.json", unit="um^2",
        note="Yosys synthesis, sky130_fd_sc_hd tt, pre-layout")
    put("area.core_synth_flops", top["flops"], "results/area/core_yosys.json")
b = load("results/sw/build_sim.json")
if b:
    put("sw.compiler", b["compiler"], "results/sw/build_sim.json")
out = REPO / "results" / "summary.json"
out.write_text(json.dumps({"entries": entries, "missing": missing}, indent=2, sort_keys=True) + "\n")
print(f"{len(entries)} entries, missing: {missing}")
