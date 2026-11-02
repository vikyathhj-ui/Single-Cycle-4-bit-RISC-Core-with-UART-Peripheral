"""Shared cocotb helpers for the APB peripheral unit tests (tb/unit/test_*.py).

ApbMaster drives an APB3 completer whose ports are named psel/penable/pwrite/paddr/pwdata/prdata/
pready/pslverr (ARM IHI 0024E §3: SETUP then ACCESS, held until PREADY). It also checks the
completer's side of the protocol it can see: PREADY/PSLVERR are only sampled in the access phase.
"""
from __future__ import annotations

import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import memmap  # noqa: E402  (generated: tb/memmap.py)


async def start(dut, period_ns: int = 10):
    """Start the clock and apply a 5-cycle reset."""
    cocotb.start_soon(Clock(dut.clk, period_ns, unit="ns").start())
    dut.rst_n.value = 0
    for sig in ("psel", "penable", "pwrite", "paddr", "pwdata"):
        getattr(dut, sig).value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


class ApbMaster:
    def __init__(self, dut, max_wait: int = 64):
        self.dut = dut
        self.max_wait = max_wait

    async def _xfer(self, addr: int, write: bool, data: int = 0) -> tuple[int, bool]:
        d = self.dut
        d.psel.value, d.penable.value, d.pwrite.value = 1, 0, int(write)
        d.paddr.value, d.pwdata.value = addr, data
        await RisingEdge(d.clk)                      # SETUP -> ACCESS
        d.penable.value = 1
        for _ in range(self.max_wait):
            await ReadOnly()
            if int(d.pready.value):
                rdata, err = int(d.prdata.value), bool(int(d.pslverr.value))
                await RisingEdge(d.clk)
                d.psel.value, d.penable.value = 0, 0
                return rdata, err
            await RisingEdge(d.clk)
        raise AssertionError(f"APB: no PREADY within {self.max_wait} cycles at {addr:#x}")

    async def read(self, addr: int) -> tuple[int, bool]:
        return await self._xfer(addr, False)

    async def write(self, addr: int, data: int) -> bool:
        return (await self._xfer(addr, True, data))[1]


def regs(periph: str) -> dict:
    """Register table of one peripheral from the generated memory map, offsets relative to its base."""
    p = memmap.PERIPHERALS[periph]
    return {name: dict(r, off=r["addr"] - p["base"]) for name, r in p["regs"].items()}


def field(reg: dict, name: str, value: int) -> int:
    msb, lsb = reg["fields"][name]
    return (value >> lsb) & ((1 << (msb - lsb + 1)) - 1)


async def export_coverage(dut):
    """Write every cocotb-coverage cover point (size, hits, percent, bins hit/missed) to $COV_FILE
    as JSON (set by scripts/run_unit.py)."""
    import json
    import os
    from cocotb_coverage.coverage import CoverCross, CoverPoint, coverage_db
    out = {}
    for name in sorted(coverage_db):
        cp = coverage_db[name]
        if not isinstance(cp, (CoverPoint, CoverCross)):   # parent nodes only aggregate their children
            continue
        det = cp.detailed_coverage
        out[name] = {"size": cp.size, "hits": cp.coverage, "percent": round(cp.cover_percentage, 1),
                     "missed_bins": [str(b) for b, n in det.items() if n == 0]}
    path = os.environ.get("COV_FILE")
    if path:
        with open(path, "w") as f:
            json.dump(out, f, indent=2)
    tot = sum(v["size"] for v in out.values())
    hit = sum(v["hits"] for v in out.values())
    dut._log.info("coverage: %d of %d bins hit", hit, tot)
    assert hit == tot, f"coverage holes: {[(k, v['missed_bins']) for k, v in out.items() if v['missed_bins']]}"
