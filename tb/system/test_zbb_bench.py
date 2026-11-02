"""System test: sw/zbb_bench (BRIEF A4). Both kernel builds must give the same result; records the
cycle and instruction counts of each (RTL simulation, SIM memory configuration)."""
import json
import os
import re
from pathlib import Path

import cocotb

from sys_util import boot, read_stats


@cocotb.test()
async def test_zbb(dut):
    mon = await boot(dut)
    await mon.wait_for("DONE", timeout=3000000)
    out = mon.text.replace("\r", "")
    dut._log.info("UART:\n%s", out)
    assert "MATCH\n" in out and "MISMATCH" not in out, out
    r = {k: tuple(int(x, 16) if i == 0 else int(x) for i, x in enumerate(m))
         for k, *m in re.findall(r"(BASE|ZBB)  ?result=(\w+) cycles=(\d+) instret=(\d+)", out)}
    base, zbb = r["BASE"], r["ZBB"]
    stats = read_stats(dut)
    Path(os.environ["METRICS_FILE"]).write_text(json.dumps({
        "hazard_stats_whole_program": stats,
        "base_cycles": base[1], "base_instret": base[2], "zbb_cycles": zbb[1], "zbb_instret": zbb[2],
        "result": f"{base[0]:#010x}", "words": 256,
        "march_base": "rv32i_zicsr", "march_zbb": "rv32i_zicsr_zbb"}))
