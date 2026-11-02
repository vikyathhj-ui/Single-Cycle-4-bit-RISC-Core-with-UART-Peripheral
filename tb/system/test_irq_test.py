"""System test: sw/irq_test (BRIEF A5). Checks every result line; drives gpio_i[0] when asked.

Expected values (SPEC §3, §5; [P §3.1.9]):
  CSR read-back after writing all ones: mstatus 0x1888 (MPP=11, MPIE, MIE), mie 0x888,
  mtvec 0xfffffffc, mepc 0xfffffffc, mcause 0x8000000f; misa stays 0x40000100 after writing 0.
  ECALL: mcause 0xb, mtval 0. Illegal (word 0): mcause 0x2, mtval 0 (the instruction bits).
  Timer x3, software x1, priority MSI (3) before MTI (7), one GPIO interrupt.
"""
import json
import os
from pathlib import Path

import cocotb
from cocotb.triggers import Timer

from sys_util import PERIOD_NS, boot


@cocotb.test()
async def test_irq(dut):
    mon = await boot(dut)
    await mon.wait_for("WAIT GPIO", timeout=400000)
    await Timer(200 * PERIOD_NS, unit="ns")
    dut.gpio_i.value = 1
    await mon.wait_for("DONE", timeout=200000)
    out = mon.text.replace("\r", "")
    dut._log.info("UART:\n%s", out)
    expect = [
        "CSR mstatus=00001888 mie=00000888 mtvec=fffffffc mepc=fffffffc mcause=8000000f misa=40000100",
        "EXC ecall mcause=b mtval=0",
        "EXC illegal mcause=2 mtval=0",
        "TIMER count=3",
        "SOFT count=1",
        "ORDER 3 7",
        "GPIO count=1",
    ]
    for line in expect:
        assert line in out, f"missing {line!r}"
    Path(os.environ["METRICS_FILE"]).write_text(json.dumps({"checked_lines": len(expect)}))
