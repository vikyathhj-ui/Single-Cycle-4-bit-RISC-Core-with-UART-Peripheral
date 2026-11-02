"""System test: EEMBC CoreMark (BRIEF A4/A5), SIM memory configuration, RTL simulation.

Validation: CoreMark compares the list / matrix / state CRCs with EEMBC's known values for the
2K performance run (seeds 0/0/0x66, seedcrc 0xe9f5) and prints "ERROR! ... crc" for any mismatch.
None may appear. CoreMark then counts the "less than 10 s" condition as one more error and prints
"Errors detected" instead of "Correct operation validated" (ext/coremark/core_main.c). The test
requires that exactly that: the 10 s line is the only error. CoreMark/MHz is computed here from the printed numbers:
    CoreMark/MHz = Iterations * 1e6 / Total ticks      (ticks = mcycle cycles, core_portme.c)
This is an RTL-simulation figure: the run is far shorter than the 10 s CoreMark requires for a
valid published score, and CoreMark itself prints that error (recorded, D-025).
"""
import json
import os
import re
from pathlib import Path

import cocotb

from sys_util import boot, read_stats


@cocotb.test()
async def test_coremark(dut):
    mon = await boot(dut)
    await mon.wait_for("DONE", timeout=60_000_000)
    out = mon.text.replace("\r", "")
    dut._log.info("UART:\n%s", out)
    assert "ERROR! list crc" not in out and "ERROR! matrix crc" not in out and "ERROR! state crc" not in out, out
    assert re.search(r"seedcrc\s*:\s*0xe9f5", out), "not the 2K performance run (known_id)"
    ten_s = "Must execute for at least 10 secs" in out
    assert "Correct operation validated" in out or (ten_s and "Errors detected" in out), out
    ticks = int(re.search(r"Total ticks\s*:\s*(\d+)", out)[1])
    iters = int(re.search(r"Iterations\s*:\s*(\d+)", out)[1])
    flags = re.search(r"Compiler flags\s*:\s*(.*)", out)[1].strip()
    comp = re.search(r"Compiler version\s*:\s*(.*)", out)[1].strip()
    crcs = dict(re.findall(r"(seedcrc|\[0\]crclist|\[0\]crcmatrix|\[0\]crcstate|\[0\]crcfinal)\s*:\s*(0x\w+)", out))
    stats = read_stats(dut)
    Path(os.environ["METRICS_FILE"]).write_text(json.dumps({
        "hazard_stats_whole_program": stats,
        "iterations": iters, "total_ticks_cycles": ticks,
        "coremark_per_mhz": round(iters * 1e6 / ticks, 4),
        "compiler_version": comp, "compiler_flags": flags, "data_location": "STACK (DMEM)",
        "crcs": crcs, "crcs_match_eembc_known_values": True,
        "ten_second_rule_error_printed": ten_s,
        "valid_published_score": False,
        "label": "RTL simulation, SIM memory configuration (IMEM 32 KB + DMEM 32 KB)",
    }))
