#!/usr/bin/env python3
"""Activity-based power of the finished layout, ACTIVE vs IDLE (BRIEF A6; D-032).

1. Gate-level simulation in Icarus of the run's final netlist (final/nl/lp_rv32_soc.nl.v) with the
   PDK's functional cell models (FUNCTIONAL, UNIT_DELAY = #1 as in P1's scripts/gls_power.py) and
   a behavioural SRAM model with the macro's ports (tb/gls/sram_gls_model.sv), running sw/power_gds/power.S (GDS memory configuration) at the run's clock
   period. tb/gls/gls_tb.sv dumps one phase per simulation: +window=0 (ACTIVE: UART + compute loop)
   or +window=1 (IDLE: MODE_REQ = IDLE + WFI until the timer wakes the core).
2. OpenSTA, tt_025C_1v80: std-cell liberty + the derived SRAM liberty (D-028), the run's netlist,
   nominal SPEF and SDC; read_vcd for that phase; report_power.
3. µW/MHz = total power / clock frequency of the simulation (1000 / period MHz).
Zero-delay functional simulation has no glitches, so glitch power is not included.
Output: results/power/power_<run>.json (+ the OpenSTA power reports next to it).

    python3 scripts/gls_power.py flow/runs/<tag>
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PDK = Path(os.environ["PDK_ROOT"]) / os.environ["PDK"]
HD = PDK / "libs.ref" / "sky130_fd_sc_hd"
SRAM_V = REPO / "tb/gls/sram_gls_model.sv"   # PDK model does not elaborate in Icarus (D-032)
SRAM_LIB = REPO / "flow/lib/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.relaxed.lib"
PHASES = {"active": 0, "idle": 1}


def build_image(work: Path) -> Path:
    elf, binf, hexf = work / "power.elf", work / "power.bin", work / "imem.hex"
    subprocess.run(["riscv64-unknown-elf-gcc", "-march=rv32i_zicsr_zbb", "-mabi=ilp32", "-nostdlib",
                    "-nostartfiles", "-Wl,--no-relax", "-T", str(REPO / "sw/common/link_gds.ld"),
                    str(REPO / "sw/power_gds/power.S"), "-o", str(elf)], check=True)
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", str(elf), str(binf)], check=True)
    d = binf.read_bytes()
    d += b"\0" * (-len(d) % 4)
    hexf.write_text("".join(f"{int.from_bytes(d[i:i + 4], 'little'):08x}\n" for i in range(0, len(d), 4)))
    return hexf


def main() -> int:
    run = Path(sys.argv[1]).resolve()
    res = json.loads((run / "resolved.json").read_text())
    period = float(res["CLOCK_PERIOD"])
    work = REPO / "sim_build" / "gls" / run.name
    work.mkdir(parents=True, exist_ok=True)
    hexf = build_image(work)
    nl = run / "final/nl/lp_rv32_soc.nl.v"
    sim = work / "gls.vvp"
    subprocess.run(["iverilog", "-g2012", "-DFUNCTIONAL", "-DUNIT_DELAY=#1", "-o", str(sim), "-s", "gls_tb",
                    str(HD / "verilog/primitives.v"), str(HD / "verilog/sky130_fd_sc_hd.v"), str(SRAM_V),
                    str(nl), str(REPO / "tb/gls/gls_tb.sv")], check=True)
    out = {"run": str(run.relative_to(REPO)), "clock_period_ns": period,
           "frequency_mhz": round(1000.0 / period, 4), "corner": "tt_025C_1v80, nom SPEF",
           "workload": "sw/power_gds/power.S (GDS memory configuration)",
           "notes": "zero-delay functional GLS: no glitch power", "phases": {}}
    spef = sorted((run / "final/spef").glob("nom/*.spef")) or sorted((run / "final/spef").glob("*nom*.spef"))
    sdc = next((run / "final/sdc").glob("*.sdc"))
    for name, win in PHASES.items():
        vcd = work / f"{name}.vcd"
        log = subprocess.run(["vvp", "-n", str(sim), f"+imem={hexf}", f"+period={period}", f"+vcd={vcd}",
                              f"+window={win}"], capture_output=True, text=True, cwd=work)
        (work / f"sim_{name}.log").write_text(log.stdout + log.stderr)
        s = re.search(r"DUMP start at cycle (\d+)", log.stdout)
        e = re.search(r"DUMP end at cycle (\d+)", log.stdout)
        if not (s and e) or "GLS_END" not in log.stdout:
            print(log.stdout[-2000:])
            return 1
        rpt = REPO / "results" / "power" / f"power_{run.name}_{name}.rpt"
        rpt.parent.mkdir(parents=True, exist_ok=True)
        tcl = work / f"power_{name}.tcl"
        tcl.write_text(f"""
read_liberty {HD / 'lib/sky130_fd_sc_hd__tt_025C_1v80.lib'}
read_liberty {SRAM_LIB}
read_verilog {nl}
link_design lp_rv32_soc
read_spef {spef[0]}
read_sdc {sdc}
read_vcd -scope gls_tb/dut {vcd}
report_power > {rpt}
report_activity_annotation > {work / f'annot_{name}.rpt'}
exit
""")
        sta = subprocess.run(["sta", "-no_splash", "-exit", str(tcl)], capture_output=True, text=True)
        (work / f"sta_{name}.log").write_text(sta.stdout + sta.stderr)
        txt = rpt.read_text()
        tot = re.search(r"^Total\s+([\d.eE+-]+)\s+([\d.eE+-]+)\s+([\d.eE+-]+)\s+([\d.eE+-]+)", txt, re.M)
        internal, switching, leakage, total = (float(x) for x in tot.groups())
        out["phases"][name] = {
            "window_cycles": int(e.group(1)) - int(s.group(1)), "window_start_cycle": int(s.group(1)),
            "internal_w": internal, "switching_w": switching, "leakage_w": leakage, "total_w": total,
            "total_uw": round(total * 1e6, 3), "uw_per_mhz": round(total * 1e6 / (1000.0 / period), 4),
            "report": str(rpt.relative_to(REPO))}
        print(name, out["phases"][name])
    a, i = out["phases"]["active"]["total_w"], out["phases"]["idle"]["total_w"]
    out["idle_vs_active_saving_percent"] = round(100.0 * (a - i) / a, 2)
    dst = REPO / "results" / "power" / f"power_{run.name}.json"
    dst.write_text(json.dumps(out, indent=2) + "\n")
    print("saving", out["idle_vs_active_saving_percent"], "% ->", dst.relative_to(REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
