#!/usr/bin/env python3
"""Print a riscv-formal counterexample VCD as a per-cycle table of selected signals.

    python3 scripts/cex_dump.py results/formal_cex/reg_ch0.vcd [regex ...]

Default signals: the RVFI retire fields and the core's main pipeline state. A signal is
matched by the regex against its full hierarchical name; the first match wins per regex.
Values are printed in hex at each rising clock edge's preceding stable value (sampled when
`clock` goes high).
"""

from __future__ import annotations

import re
import sys

DEFAULT = [
    r"\.rvfi_valid$", r"\.rvfi_order$", r"\.rvfi_insn$", r"\.rvfi_trap$", r"\.rvfi_intr$",
    r"\.rvfi_pc_rdata$", r"\.rvfi_pc_wdata$", r"\.rvfi_rs1_addr$", r"\.rvfi_rs1_rdata$",
    r"\.rvfi_rs2_addr$", r"\.rvfi_rs2_rdata$", r"\.rvfi_rd_addr$", r"\.rvfi_rd_wdata$",
    r"uut\.id_valid$", r"uut\.id_pc$", r"uut\.rd_q$", r"uut\.mw_valid$", r"uut\.mw_rd$",
    r"uut\.ibus_rdata$", r"uut\.dbus_req$", r"uut\.dbus_rvalid$", r"\.reset$",
]


def parse(path: str):
    ids, names, values, times = {}, {}, {}, []
    scope = []
    cur_t = 0
    changes: list[tuple[int, str, str]] = []
    with open(path) as f:
        header = True
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if header:
                if tok[0] == "$scope":
                    scope.append(tok[2])
                elif tok[0] == "$upscope":
                    scope.pop()
                elif tok[0] == "$var":
                    code, name = tok[3], tok[4]
                    full = ".".join(scope + [name])
                    ids.setdefault(code, []).append(full)
                elif tok[0] == "$enddefinitions":
                    header = False
                continue
            if tok[0].startswith("#"):
                cur_t = int(tok[0][1:])
                times.append(cur_t)
            elif tok[0][0] in "bB":
                changes.append((cur_t, tok[1], tok[0][1:]))
            elif tok[0][0] in "01xXzZ":
                changes.append((cur_t, tok[0][1:], tok[0][0]))
    for code, full in ids.items():
        for n in full:
            names[n] = code
    return names, changes


def main() -> int:
    path = sys.argv[1]
    pats = sys.argv[2:] or DEFAULT
    names, changes = parse(path)
    clk = next((c for n, c in names.items() if re.search(r"(^|\.)clock$", n)), None)
    picked = []
    for p in pats:
        m = sorted((n for n in names if re.search(p, n)), key=len)
        if m:
            picked.append((m[0], names[m[0]]))
    state: dict[str, str] = {}
    rows = []
    prev_clk = "0"
    for t, code, val in changes + [(10**18, "", "")]:
        if clk and code == clk:
            if prev_clk == "0" and val == "1":
                rows.append({n: state.get(c, "?") for n, c in picked})
            prev_clk = val
        state[code] = val
    def fmt(v: str) -> str:
        if v in ("?",) or set(v) - set("01"):
            return v
        return hex(int(v, 2))[2:]
    short = [n.split(".")[-1] for n, _ in picked]
    print("cyc " + " ".join(f"{s:>12}" for s in short))
    for i, r in enumerate(rows):
        print(f"{i:>3} " + " ".join(f"{fmt(r[n]):>12}" for n, _ in picked))
    return 0


if __name__ == "__main__":
    sys.exit(main())
