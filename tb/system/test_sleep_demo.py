"""System test: sw/sleep_demo (BRIEF A5: "check the clock is actually gated during IDLE, the
power-aware corruption works in DEEP_SLEEP, and the wake reason is correct").

Independent hardware monitors (not the firmware's word):
  * clock gating: every window where the PMU holds clk_en[CPU] = 0, the number of rising edges of
    the gated CORE clock (soc_sys_tb.clk_core_edges) inside the window must be 0;
  * power-off: every window where psw_main_ack[CPU] = 0 after boot, iso_en[CPU] must be 1 and, while
    PERI is also off, uart_txd must stay at its clamp value 1 (D-021);
  * corruption model: corrupt_core / corrupt_peri must count exactly one event per DEEP_SLEEP (2).
Firmware results checked: IDLE wake by the timer interrupt with mcycle stopped while mtime ran,
wake sources 0x1 (core irq), 0x2 (UART RX start bit), 0x4 (timer) from SYSCTRL.WAKE_SRC, and the
DMEM .noinit marker kept across both DEEP_SLEEPs.
"""
import json
import os
import re
from pathlib import Path

import cocotb
from cocotb.triggers import Edge, Timer

from sys_util import BIT, PERIOD_NS, boot, cycles_now, uart_send


class PowerMonitor:
    def __init__(self, dut):
        self.dut = dut
        self.gated = []          # (start_cycle, length, core_clock_edges_inside)
        self.off = []            # (start_cycle, length, violations)
        cocotb.start_soon(self._clk_en())
        cocotb.start_soon(self._power())

    async def _clk_en(self):
        d = self.dut.u_soc
        while True:
            await Edge(d.clk_en)
            if int(d.clk_en.value) & 1:
                continue
            t0, e0 = cycles_now(), int(self.dut.clk_core_edges.value)
            while not int(d.clk_en.value) & 1:
                await Edge(d.clk_en)
            self.gated.append((t0, cycles_now() - t0, int(self.dut.clk_core_edges.value) - e0))

    async def _power(self):
        d = self.dut.u_soc
        while True:
            await Edge(d.psw_main_ack)
            if int(d.psw_main_ack.value) & 1 or cycles_now() < 200:
                continue                        # powered, or still the boot sequence
            t0, bad = cycles_now(), 0
            while not int(d.psw_main_ack.value) & 1:
                await Timer(16 * PERIOD_NS, unit="ns")
                if not int(d.iso_en.value) & 1:
                    bad += 1
                if not int(d.psw_main_ack.value) >> 2 & 1 and int(self.dut.uart_txd.value) != 1:
                    bad += 1
            self.off.append((t0, cycles_now() - t0, bad))


@cocotb.test()
async def test_sleep(dut):
    mon = await boot(dut)
    pm = PowerMonitor(dut)

    await mon.wait_for("DEEP1 enter", timeout=500000)
    # wait until the CORE domain is really off, then send one byte: its start bit is the wake event
    for _ in range(1000):
        await Timer(64 * PERIOD_NS, unit="ns")
        if int(dut.corrupt_core.value) == 1:
            break
    assert int(dut.corrupt_core.value) == 1, "CORE never powered off after DEEP1 enter"
    await Timer(2000 * PERIOD_NS, unit="ns")
    t_wake = cycles_now()
    await uart_send(dut, b"\x55", bit=BIT)
    await mon.wait_for("WARM stage=1", timeout=200000)
    await mon.wait_for("DONE", timeout=500000)
    out = mon.text.replace("\r", "")
    dut._log.info("UART:\n%s", out)

    m = re.search(r"IDLE woke timer_irqs=(\d+) mcycle_delta=(\d+) mtime_delta=(\d+) wake_src=(\w+)", out)
    assert m, out
    irqs, mcyc, mtim, wsrc = int(m[1]), int(m[2]), int(m[3]), int(m[4], 16)
    assert irqs == 1 and wsrc & 1, out
    assert mtim >= 3000 and mcyc < mtim, f"mcycle {mcyc} should stop while gated; mtime {mtim}"
    assert "COLD reset_cause=1" in out
    assert "WARM stage=1 wake_src=2 marker=cafef00d" in out, out
    assert "WARM stage=2 wake_src=4 marker=cafef00d" in out, out

    assert int(dut.corrupt_core.value) == 2 and int(dut.corrupt_peri.value) == 2, \
        (int(dut.corrupt_core.value), int(dut.corrupt_peri.value))
    assert pm.gated, "the CORE clock was never gated"
    assert all(edges == 0 for _, _, edges in pm.gated), f"core clock edges while gated: {pm.gated}"
    assert len(pm.off) == 2 and all(bad == 0 for _, _, bad in pm.off), pm.off
    idle = [g for g in pm.gated if g[0] + g[1] < pm.off[0][0] - 64]   # exclude the gating that starts a DEEP_SLEEP
    dut._log.info("gated windows %s; power-off windows %s", pm.gated, pm.off)
    Path(os.environ["METRICS_FILE"]).write_text(json.dumps({
        "idle_gated_windows": [{"start": s, "cycles": n, "core_clock_edges": e} for s, n, e in idle],
        "idle_mcycle_delta": mcyc, "idle_mtime_delta": mtim,
        "deep_sleep_off_windows": [{"start": s, "cycles": n, "violations": b} for s, n, b in pm.off],
        "corrupt_core_events": int(dut.corrupt_core.value),
        "corrupt_peri_events": int(dut.corrupt_peri.value),
        "uart_wake_byte_sent_cycle": t_wake,
    }))
