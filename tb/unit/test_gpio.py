"""cocotb unit tests for rtl/periph/gpio8.sv (BRIEF A5 "GPIO"; SPEC §9, MEMORY_MAP "GPIO").

Checks: reset values; OUT/DIR drive gpio_o/gpio_oe; IN reads the pins through the 2-flop
synchroniser (latency measured); per-pin rising and falling edge interrupts with RISE_EN/FALL_EN;
W1C clearing, including an edge in the same cycle as the clear (set wins); PSLVERR on a write to IN.
"""
from __future__ import annotations

import random

import cocotb
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge
from cocotb_coverage.coverage import CoverCross, CoverPoint

from apb_util import ApbMaster, export_coverage, regs, start

R = regs("GPIO")
A = {n: r["off"] for n, r in R.items()}


@CoverPoint("gpio.edge.pin", xf=lambda pin, kind: pin, bins=list(range(8)))
@CoverPoint("gpio.edge.kind", xf=lambda pin, kind: kind, bins=["rise", "fall"])
@CoverCross("gpio.edge.pin_x_kind", items=["gpio.edge.pin", "gpio.edge.kind"])
def cov_edge(pin, kind):
    pass


async def setup(dut):
    dut.gpio_i.value = 0
    await start(dut)
    return ApbMaster(dut)


@cocotb.test()
async def test_reset_and_outputs(dut):
    apb = await setup(dut)
    for name, r in R.items():
        if name == "IN":
            continue
        v, err = await apb.read(r["off"])
        assert not err and v & r["mask"] == r["reset"] & r["mask"], name
    await apb.write(A["OUT"], 0xA5)
    await apb.write(A["DIR"], 0x0F)
    await ReadOnly()
    assert int(dut.gpio_o.value) == 0xA5 and int(dut.gpio_oe.value) == 0x0F


@cocotb.test()
async def test_input_sync_latency(dut):
    """A pin change is visible in IN after the 2-flop synchroniser (2 or 3 cycles)."""
    apb = await setup(dut)
    await RisingEdge(dut.clk)
    dut.gpio_i.value = 0x3C
    seen = None
    for cyc in range(1, 6):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.s2.value) == 0x3C:
            seen = cyc
            break
    assert seen == 2, f"IN changed after {seen} cycles"
    await RisingEdge(dut.clk)
    v, _ = await apb.read(A["IN"])
    assert v == 0x3C


@cocotb.test()
async def test_edge_interrupts(dut):
    """Every pin, rising and falling: IRQ_STATUS bit set only when that edge is enabled; W1C."""
    apb = await setup(dut)
    rng = random.Random(7)
    for pin in range(8):
        for kind in ("rise", "fall"):
            await apb.write(A["IRQ_STATUS"], 0xFF)
            await apb.write(A["RISE_EN"], (1 << pin) if kind == "rise" else 0)
            await apb.write(A["FALL_EN"], (1 << pin) if kind == "fall" else 0)
            start_level = 0 if kind == "rise" else 1
            dut.gpio_i.value = start_level << pin
            await ClockCycles(dut.clk, 4)
            await apb.write(A["IRQ_STATUS"], 0xFF)
            assert int(dut.irq.value) == 0
            # an edge on another pin must not set this pin's bit
            other = (pin + 1 + rng.randrange(7)) % 8
            dut.gpio_i.value = (start_level << pin) | (1 << other)
            await ClockCycles(dut.clk, 4)
            assert int(dut.irq.value) == 0, f"pin {pin} {kind}: edge on pin {other} raised irq"
            dut.gpio_i.value = ((1 - start_level) << pin) | (1 << other)
            await ClockCycles(dut.clk, 4)
            st, _ = await apb.read(A["IRQ_STATUS"])
            assert st == 1 << pin and int(dut.irq.value) == 1, f"pin {pin} {kind}: IRQ_STATUS {st:#x}"
            cov_edge(pin, kind)
            await apb.write(A["IRQ_STATUS"], 1 << pin)
            await ReadOnly()
            assert int(dut.irq.value) == 0
            await RisingEdge(dut.clk)


@cocotb.test()
async def test_set_wins_over_clear(dut):
    """An edge detected in the same cycle as a W1C of that bit leaves the bit set.

    The delay between the pin edge and the W1C write is swept; a monitor finds the cycles where the
    W1C commits while an enabled edge is detected, and checks the bit is still set afterwards.
    """
    apb = await setup(dut)
    await apb.write(A["RISE_EN"], 0x01)
    coincidences = 0

    async def monitor():
        nonlocal coincidences
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            clr = (int(dut.psel.value) and int(dut.penable.value) and int(dut.pwrite.value)
                   and int(dut.paddr.value) == A["IRQ_STATUS"] and int(dut.pwdata.value) & 1)
            edge = int(dut.s2.value) & 1 and not (int(dut.prev.value) & 1)
            if clr and edge:
                await RisingEdge(dut.clk)
                await ReadOnly()
                assert int(dut.pend.value) & 1, "edge in the W1C cycle was lost"
                coincidences += 1

    mon = cocotb.start_soon(monitor())
    for delay in range(8):
        dut.gpio_i.value = 0
        await ClockCycles(dut.clk, 5)
        await apb.write(A["IRQ_STATUS"], 0x01)
        dut.gpio_i.value = 1
        await ClockCycles(dut.clk, delay)
        await apb.write(A["IRQ_STATUS"], 0x01)
        await ClockCycles(dut.clk, 4)
    mon.cancel()
    assert coincidences >= 1, "the sweep never produced an edge in the W1C cycle"
    dut._log.info("edge/W1C coincidences checked: %d", coincidences)


@cocotb.test()
async def test_apb_errors(dut):
    apb = await setup(dut)
    assert await apb.write(A["IN"], 0xFF), "IN is read-only"
    assert (await apb.read(0x018))[1]


@cocotb.test()
async def test_zz_coverage_export(dut):
    await export_coverage(dut)
