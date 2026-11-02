"""cocotb unit tests for rtl/periph/timer_clint.sv (BRIEF A5 "timer"; SPEC §9, [P §3.2.1]).

Checks: reset values from the memory map; mtime counts every PRESCALE+1 cycles (measured);
mtip = (mtime >= mtimecmp) as an unsigned 64-bit compare, including the carry from MTIME_LO into
MTIME_HI; writing MTIMECMP clears mtip; the safe 3-write MTIMECMP update never raises a false mtip;
msip follows the MSIP register; PSLVERR on unknown addresses.
"""
from __future__ import annotations

import cocotb
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge
from cocotb_coverage.coverage import CoverPoint

from apb_util import ApbMaster, export_coverage, regs, start

R = regs("TIMER")
A = {n: r["off"] for n, r in R.items()}


@CoverPoint("timer.prescale", xf=lambda p: p, bins=[0, 1, 9])
def cov_presc(p):
    pass


@CoverPoint("timer.event", xf=lambda e: e,
            bins=["MTIP_SET", "MTIP_CLEAR", "LO_HI_CARRY", "SAFE_CMP_UPDATE", "MSIP"])
def cov_event(e):
    pass


async def mtime(apb) -> int:
    lo = (await apb.read(A["MTIME_LO"]))[0]
    hi = (await apb.read(A["MTIME_HI"]))[0]
    return (hi << 32) | lo


@cocotb.test()
async def test_reset_values(dut):
    await start(dut)
    apb = ApbMaster(dut)
    for name, r in R.items():
        if name.startswith("MTIME_"):
            continue                                 # counting since reset
        v, err = await apb.read(r["off"])
        assert not err and v & r["mask"] == r["reset"] & r["mask"], f"{name}: {v:#x}"
    await ReadOnly()
    assert int(dut.mtip.value) == 0 and int(dut.msip.value) == 0


@cocotb.test()
async def test_prescale_rate(dut):
    """mtime advances by N/(PRESCALE+1) over N cycles."""
    await start(dut)
    apb = ApbMaster(dut)
    for presc in (0, 1, 9):
        await apb.write(A["PRESCALE"], presc)
        await apb.write(A["MTIME_HI"], 0)
        await apb.write(A["MTIME_LO"], 0)
        await RisingEdge(dut.clk)
        await ReadOnly()
        t0 = int(dut.mtime.value)
        n = 1000
        await ClockCycles(dut.clk, n)
        await ReadOnly()
        t1 = int(dut.mtime.value)
        assert t1 - t0 in (n // (presc + 1), n // (presc + 1) + 1), f"presc {presc}: {t1 - t0} ticks in {n}"
        cov_presc(presc)
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_compare_and_carry(dut):
    """mtip rises when mtime reaches mtimecmp across the LO->HI carry; a new MTIMECMP clears it."""
    await start(dut)
    apb = ApbMaster(dut)
    await apb.write(A["MTIME_HI"], 0)
    await apb.write(A["MTIME_LO"], 0xFFFF_FFF0)
    await apb.write(A["MTIMECMP_LO"], 0x0000_0008)
    await apb.write(A["MTIMECMP_HI"], 0x0000_0001)     # cmp = 0x1_0000_0008
    assert int(dut.mtip.value) == 0
    for _ in range(64):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.mtip.value):
            break
    t = int(dut.mtime.value)
    assert int(dut.mtip.value) == 1 and t == 0x1_0000_0008, f"mtip at mtime {t:#x}"
    cov_event("LO_HI_CARRY")
    cov_event("MTIP_SET")
    await RisingEdge(dut.clk)
    await apb.write(A["MTIMECMP_HI"], 0xFFFF_FFFF)
    await ReadOnly()
    assert int(dut.mtip.value) == 0
    cov_event("MTIP_CLEAR")


@cocotb.test()
async def test_safe_cmp_update(dut):
    """[P §3.2.1] sequence: HI = all ones, LO = new, HI = new. mtip never rises falsely."""
    await start(dut)
    apb = ApbMaster(dut)
    await apb.write(A["MTIME_LO"], 0x100)
    await apb.write(A["MTIMECMP_LO"], 0xFFFF_FFFF)
    await apb.write(A["MTIMECMP_HI"], 0xFFFF_FFFF)
    seen = []

    async def watch():
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            seen.append(int(dut.mtip.value))

    w = cocotb.start_soon(watch())
    await apb.write(A["MTIMECMP_HI"], 0xFFFF_FFFF)
    await apb.write(A["MTIMECMP_LO"], 0x0000_0000)
    await apb.write(A["MTIMECMP_HI"], 0x0000_0001)
    await ClockCycles(dut.clk, 3)
    w.cancel()
    assert not any(seen), "false mtip during the compare update"
    cov_event("SAFE_CMP_UPDATE")


@cocotb.test()
async def test_msip_and_errors(dut):
    await start(dut)
    apb = ApbMaster(dut)
    await apb.write(A["MSIP"], 1)
    await ReadOnly()
    assert int(dut.msip.value) == 1
    await RisingEdge(dut.clk)
    await apb.write(A["MSIP"], 0)
    await ReadOnly()
    assert int(dut.msip.value) == 0
    cov_event("MSIP")
    await RisingEdge(dut.clk)
    assert (await apb.read(0x004))[1], "0x004 is not a register"
    assert await apb.write(0x01C, 0)


@cocotb.test()
async def test_zz_coverage_export(dut):
    await export_coverage(dut)
