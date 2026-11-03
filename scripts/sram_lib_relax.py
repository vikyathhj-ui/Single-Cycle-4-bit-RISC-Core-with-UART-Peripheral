#!/usr/bin/env python3
"""Derive the SRAM liberty used by the LibreLane flow (D-028).

The PDK file sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib sets `max_transition : 0.04` on the
input buses addr0, wmask0 and addr1, while its default_max_transition is 0.5. No sky130_fd_sc_hd
driver reaches 0.04 ns (resizer: best 0.068 ns), and OpenROAD's post-route design repair stops with
RSZ-0090. This script copies the PDK file and changes ONLY those `max_transition` lines inside the
three buses to the file's own default_max_transition. Everything else (timing arcs, pins, area) is
unchanged. The PDK file is not modified; the diff is written to results/flow/sram_lib_relax.diff.

    python3 scripts/sram_lib_relax.py     -> flow/lib/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.relaxed.lib
"""
import difflib
import os
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
NAME = "sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C"
src = Path(os.environ["PDK_ROOT"]) / os.environ["PDK"] / "libs.ref/sky130_sram_macros/lib" / f"{NAME}.lib"
lines = src.read_text().splitlines(keepends=True)
default = re.search(r"default_max_transition\s*:\s*([\d.]+)", "".join(lines)).group(1)
out, bus, changed = [], None, []
for i, l in enumerate(lines):
    m = re.match(r"\s*bus\((\w+)\)", l)
    if m:
        bus = m.group(1)
    if bus in ("addr0", "wmask0", "addr1") and re.match(r"\s*max_transition\s*:\s*0\.04\s*;", l):
        l = re.sub(r"0\.04", default, l)
        changed.append((i + 1, bus))
    out.append(l)
assert len(changed) == 3, changed
dst = REPO / "flow" / "lib" / f"{NAME}.relaxed.lib"
dst.write_text("".join(out))
diff = "".join(difflib.unified_diff(lines, out, fromfile=str(src), tofile=str(dst.relative_to(REPO))))
d = REPO / "results" / "flow" / "sram_lib_relax.diff"
d.parent.mkdir(parents=True, exist_ok=True)
d.write_text(diff)
print(f"{dst.relative_to(REPO)}: max_transition 0.04 -> {default} at lines {changed}")
