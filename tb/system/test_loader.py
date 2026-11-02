"""System test: boot ROM UART loader (docs/SPEC.md §7). BOOT.SEL = 0, IMEM starts empty.

The test waits for the loader's '>' prompt, then sends a 4-byte little-endian length and the IMEM image of sw/loader_payload at the
reset divisor (BAUD_DIV = 433 -> 434 cycles per bit), checks the 4-byte checksum the loader echoes
(the 32-bit sum of the bytes), then checks that the loaded program runs and prints its marker.
"""
import os
from pathlib import Path

import cocotb

from sys_util import BIT, boot, cycles_now, uart_send

LOADER_BIT = 434


@cocotb.test()
async def test_uart_loader(dut):
    image = (Path(os.environ["SW_BUILD"]) / "loader_payload" / "prog.bin").read_bytes()
    mon = await boot(dut, boot_sel=0, bit=LOADER_BIT)
    t0 = cycles_now()
    await mon.wait_for(">", timeout=50000)            # loader prompt (D-023)
    t_prompt = mon.cycle_of[mon.text.index(">")] - t0  # cycle the prompt's stop bit was sampled
    mon.text = ""
    mon.switch = (4, BIT)                             # after the 4 checksum bytes the payload uses UART_DIV
    await uart_send(dut, len(image).to_bytes(4, "little") + image, bit=LOADER_BIT)
    await mon.wait_for_len(4, timeout=200000)
    echoed = int.from_bytes(mon.text[:4].encode("latin-1"), "little")
    expected = sum(image) & 0xFFFFFFFF
    assert echoed == expected, f"checksum {echoed:#x} != {expected:#x}"
    await mon.wait_for("LOADED OK", timeout=200000)
    await mon.wait_for("\n", timeout=50000)
    t1 = mon.cycle_of[mon.text.index("\n")]          # cycle the payload's line was complete
    dut._log.info("loaded %d bytes, checksum %#x, total %d cycles; output: %s", len(image), echoed,
                  t1 - t0, mon.text.strip())
    assert "boot_sel=0 reset_cause=1" in mon.text, mon.text
    import json
    Path(os.environ["METRICS_FILE"]).write_text(json.dumps(
        {"image_bytes": len(image), "checksum": f"{echoed:#010x}", "load_and_run_cycles": t1 - t0,
         "prompt_after_reset_cycles": t_prompt,
         "loader_baud_div": LOADER_BIT - 1}))
