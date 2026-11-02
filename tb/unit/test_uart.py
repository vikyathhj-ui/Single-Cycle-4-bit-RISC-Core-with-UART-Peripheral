"""cocotb unit tests for rtl/periph/uart_lite.sv (BRIEF A5: baud accuracy, FIFO full/empty, framing
error). Register offsets and reset values come from the generated memory map (tb/memmap.py).

Checks, in order of the BRIEF list:
  * baud accuracy: every bit of a transmitted frame is held for exactly BAUD_DIV+1 clock cycles
    (measured on txd, cycle by cycle), for several divisors; the receiver accepts frames whose bit
    period is off by -3 % .. +3 %;
  * FIFO full / empty: STATUS flags and levels at 0, 1, 15, 16 entries; overflow on both sides;
  * framing error: a 0 stop bit sets FRAME_ERR and drops the byte;
  plus reset values, interrupts, flush, and APB error responses.
Functional coverage (cocotb-coverage) is written to results/coverage/uart.json by the runner.
"""
from __future__ import annotations

import random

import cocotb
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge
from cocotb_coverage.coverage import CoverPoint

from apb_util import ApbMaster, field, regs, start

R = regs("UART")
A = {n: r["off"] for n, r in R.items()}
SEED = 20261102


@CoverPoint("uart.tx.div", xf=lambda d: d, bins=[1, 3, 15, 433])
def cov_tx_div(d):
    pass


@CoverPoint("uart.rx.skew", xf=lambda s: s, bins=[-3, 0, 3])
def cov_rx_skew(s):
    pass


@CoverPoint("uart.byte", xf=lambda b: "0x00" if b == 0 else "0xFF" if b == 0xFF else "other",
            bins=["0x00", "0xFF", "other"])
def cov_byte(b):
    pass


@CoverPoint("uart.fifo_level", xf=lambda side, lvl: (side, lvl),
            bins=[(s, l) for s in ("tx", "rx") for l in (0, 1, 15, 16)])
def cov_level(side, lvl):
    pass


@CoverPoint("uart.event", xf=lambda e: e,
            bins=["TX_OVF", "RX_OVF", "FRAME_ERR", "IRQ_RX", "IRQ_TX", "IRQ_ERR", "TX_FLUSH", "RX_FLUSH",
                  "GLITCH_REJECTED"])
def cov_event(e):
    pass


async def setup(dut):
    dut.rxd.value = 1
    await start(dut)
    return ApbMaster(dut)


async def capture_frame(dut, div: int, timeout: int = 200000) -> tuple[int, list[int]]:
    """Wait for a start bit on txd; return (byte, list of per-bit hold times in cycles)."""
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.txd.value) == 0:
            break
    else:
        raise AssertionError("no start bit on txd")
    levels = [0]
    # sample every cycle for 10 bit periods (start + 8 data + stop)
    for _ in range(10 * (div + 1) - 1):
        await RisingEdge(dut.clk)
        await ReadOnly()
        levels.append(int(dut.txd.value))
    holds, bits = [], []
    for k in range(10):
        seg = levels[k * (div + 1):(k + 1) * (div + 1)]
        assert len(set(seg)) == 1, f"bit {k} not constant for {div + 1} cycles: {seg}"
        holds.append(len(seg))
        bits.append(seg[0])
    assert bits[0] == 0 and bits[9] == 1, f"bad start/stop: {bits}"
    byte = sum(b << i for i, b in enumerate(bits[1:9]))
    return byte, holds


async def drive_frame(dut, byte: int, period: float, stop: int = 1):
    """Drive one 8N1 frame on rxd with a (possibly fractional) bit period in cycles."""
    bits = [0] + [(byte >> i) & 1 for i in range(8)] + [stop]
    t = 0.0
    for b in bits:
        dut.rxd.value = b
        t_next = t + period
        await ClockCycles(dut.clk, int(round(t_next)) - int(round(t)))
        t = t_next
    dut.rxd.value = 1


@cocotb.test()
async def test_reset_values(dut):
    """Every register reads its memory-map reset value; DATA reads 0 when RX is empty."""
    apb = await setup(dut)
    for name, r in R.items():
        v, err = await apb.read(r["off"])
        assert not err, name
        assert v & r["mask"] == r["reset"] & r["mask"], f"{name}: {v:#x} != reset {r['reset']:#x}"


@cocotb.test()
async def test_tx_baud_accuracy(dut):
    """Each transmitted bit is held exactly BAUD_DIV+1 cycles; the byte is decoded correctly."""
    apb = await setup(dut)
    rng = random.Random(SEED)
    await apb.write(A["CTRL"], 0x1)
    for div in (1, 3, 15, 433):
        await apb.write(A["BAUD_DIV"], div)
        for byte in (0x00, 0xFF, 0x55, rng.randrange(256)):
            cocotb.start_soon(apb.write(A["DATA"], byte))
            got, holds = await capture_frame(dut, div)
            assert got == byte, f"div {div}: sent {byte:#04x}, txd carried {got:#04x}"
            assert holds == [div + 1] * 10, f"div {div}: bit hold times {holds}"
            cov_tx_div(div)
            cov_byte(byte)
            await ClockCycles(dut.clk, 2 * (div + 1))
        dut._log.info("div %d: every bit held %d cycles (error 0 cycles)", div, div + 1)


@cocotb.test()
async def test_rx_with_skew(dut):
    """Frames at -3 %, 0 %, +3 % of the nominal bit period are received correctly, no errors."""
    apb = await setup(dut)
    rng = random.Random(SEED + 1)
    div = 15
    await apb.write(A["BAUD_DIV"], div)
    await apb.write(A["CTRL"], 0x2)
    for skew in (-3, 0, 3):
        period = (div + 1) * (1 + skew / 100)
        sent = [0x00, 0xFF] + [rng.randrange(256) for _ in range(6)]
        for b in sent:
            await drive_frame(dut, b, period)
            await ClockCycles(dut.clk, 3)
        got = []
        for _ in sent:
            v, _ = await apb.read(A["DATA"])
            got.append(v & 0xFF)
        assert got == sent, f"skew {skew}%: sent {sent}, got {got}"
        st, _ = await apb.read(A["IRQ_STATUS"])
        assert field(R["IRQ_STATUS"], "FRAME_ERR", st) == 0 and field(R["IRQ_STATUS"], "RX_OVF", st) == 0
        cov_rx_skew(skew)
        for b in sent:
            cov_byte(b)


@cocotb.test()
async def test_rx_glitch_rejected(dut):
    """A low pulse shorter than half a bit is not taken as a start bit."""
    apb = await setup(dut)
    div = 15
    await apb.write(A["BAUD_DIV"], div)
    await apb.write(A["CTRL"], 0x2)
    dut.rxd.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rxd.value = 1
    await ClockCycles(dut.clk, 20 * (div + 1))
    st, _ = await apb.read(A["STATUS"])
    assert field(R["STATUS"], "RX_EMPTY", st) == 1
    cov_event("GLITCH_REJECTED")


@cocotb.test()
async def test_tx_fifo_full_empty_overflow(dut):
    """TX FIFO levels 0/1/15/16, TX_FULL, overflow sets TX_OVF, then 16 bytes go out in order."""
    apb = await setup(dut)
    div = 1
    await apb.write(A["BAUD_DIV"], div)
    data = list(range(0xA0, 0xB0))
    st, _ = await apb.read(A["STATUS"])
    assert field(R["STATUS"], "TX_EMPTY", st) == 1 and field(R["STATUS"], "TX_LEVEL", st) == 0
    cov_level("tx", 0)
    for i, b in enumerate(data):
        await apb.write(A["DATA"], b)
        st, _ = await apb.read(A["STATUS"])
        lvl = field(R["STATUS"], "TX_LEVEL", st)
        assert lvl == i + 1
        assert field(R["STATUS"], "TX_FULL", st) == (1 if i == 15 else 0)
        if lvl in (1, 15, 16):
            cov_level("tx", lvl)
    await apb.write(A["DATA"], 0x99)                   # 17th byte: dropped
    st, _ = await apb.read(A["IRQ_STATUS"])
    assert field(R["IRQ_STATUS"], "TX_OVF", st) == 1
    cov_event("TX_OVF")
    await apb.write(A["IRQ_STATUS"], 1 << R["IRQ_STATUS"]["fields"]["TX_OVF"][1])
    st, _ = await apb.read(A["IRQ_STATUS"])
    assert field(R["IRQ_STATUS"], "TX_OVF", st) == 0
    await apb.write(A["CTRL"], 0x1)
    for b in data:
        got, _ = await capture_frame(dut, div)
        assert got == b
    await ClockCycles(dut.clk, 4 * (div + 1))
    st, _ = await apb.read(A["STATUS"])
    assert field(R["STATUS"], "TX_EMPTY", st) == 1


@cocotb.test()
async def test_rx_fifo_full_overflow(dut):
    """17 frames without reading: RX_FULL, RX_OVF, the first 16 bytes kept in order, then empty."""
    apb = await setup(dut)
    div = 3
    await apb.write(A["BAUD_DIV"], div)
    await apb.write(A["CTRL"], 0x2)
    data = [(0x30 + i) & 0xFF for i in range(17)]
    for i, b in enumerate(data):
        await drive_frame(dut, b, div + 1)
        await ClockCycles(dut.clk, 2)
        st, _ = await apb.read(A["STATUS"])
        lvl = field(R["STATUS"], "RX_LEVEL", st)
        assert lvl == min(i + 1, 16)
        if lvl in (1, 15, 16):
            cov_level("rx", lvl)
    st, _ = await apb.read(A["STATUS"])
    assert field(R["STATUS"], "RX_FULL", st) == 1
    ist, _ = await apb.read(A["IRQ_STATUS"])
    assert field(R["IRQ_STATUS"], "RX_OVF", ist) == 1
    cov_event("RX_OVF")
    got = [(await apb.read(A["DATA"]))[0] & 0xFF for _ in range(16)]
    assert got == data[:16]
    st, _ = await apb.read(A["STATUS"])
    assert field(R["STATUS"], "RX_EMPTY", st) == 1
    cov_level("rx", 0)
    v, _ = await apb.read(A["DATA"])
    assert v == 0, "DATA read with RX empty must return 0"


@cocotb.test()
async def test_framing_error(dut):
    """A frame whose stop bit is 0 sets FRAME_ERR (sticky, W1C) and the byte is dropped."""
    apb = await setup(dut)
    div = 7
    await apb.write(A["BAUD_DIV"], div)
    await apb.write(A["CTRL"], 0x2)
    await drive_frame(dut, 0x5A, div + 1, stop=0)
    await ClockCycles(dut.clk, 3 * (div + 1))           # let the line recover
    ist, _ = await apb.read(A["IRQ_STATUS"])
    st, _ = await apb.read(A["STATUS"])
    assert field(R["IRQ_STATUS"], "FRAME_ERR", ist) == 1
    assert field(R["STATUS"], "RX_EMPTY", st) == 1, "byte with a framing error must be dropped"
    cov_event("FRAME_ERR")
    await apb.write(A["IRQ_STATUS"], 1 << R["IRQ_STATUS"]["fields"]["FRAME_ERR"][1])
    ist, _ = await apb.read(A["IRQ_STATUS"])
    assert field(R["IRQ_STATUS"], "FRAME_ERR", ist) == 0
    await drive_frame(dut, 0xC3, div + 1)             # the receiver still works afterwards
    await ClockCycles(dut.clk, 2)
    v, _ = await apb.read(A["DATA"])
    assert v & 0xFF == 0xC3


@cocotb.test()
async def test_interrupts(dut):
    """irq = |(IRQ_STATUS & IRQ_EN): RX threshold, TX empty, error interrupts, and masking."""
    apb = await setup(dut)
    div = 3
    await apb.write(A["BAUD_DIV"], div)
    await apb.write(A["CTRL"], 0x2 | (1 << 8))          # RX_EN, RX_THRESH = 1
    await ReadOnly()
    assert int(dut.irq.value) == 0, "all interrupts disabled after reset"
    await RisingEdge(dut.clk)
    await apb.write(A["IRQ_EN"], 0x1)                  # RX
    # The stop bit is sampled about half a bit after drive_frame returns (2-flop synchroniser +
    # mid-bit sampling), so wait one full bit period before looking at irq.
    await drive_frame(dut, 0x11, div + 1)
    await ClockCycles(dut.clk, div + 1 + 4)
    assert int(dut.irq.value) == 0, "1 byte is not above RX_THRESH = 1"
    await drive_frame(dut, 0x22, div + 1)
    await ClockCycles(dut.clk, div + 1 + 4)
    assert int(dut.irq.value) == 1
    cov_event("IRQ_RX")
    await apb.read(A["DATA"])
    await apb.read(A["DATA"])
    await ClockCycles(dut.clk, 1)
    assert int(dut.irq.value) == 0
    await apb.write(A["IRQ_EN"], 0x2)                  # TX (FIFO empty is a level)
    await ClockCycles(dut.clk, 1)
    assert int(dut.irq.value) == 1
    cov_event("IRQ_TX")
    await apb.write(A["IRQ_EN"], 0x4)                  # FRAME_ERR
    await drive_frame(dut, 0x00, div + 1, stop=0)
    await ClockCycles(dut.clk, 3 * (div + 1))
    assert int(dut.irq.value) == 1
    cov_event("IRQ_ERR")
    await apb.write(A["IRQ_STATUS"], 0x1F)
    await ClockCycles(dut.clk, 1)
    assert int(dut.irq.value) == 0


@cocotb.test()
async def test_flush(dut):
    """CTRL.TX_FLUSH / RX_FLUSH empty the FIFOs and read back 0."""
    apb = await setup(dut)
    div = 3
    await apb.write(A["BAUD_DIV"], div)
    for b in (1, 2, 3):
        await apb.write(A["DATA"], b)
    await apb.write(A["CTRL"], 0x2)
    await drive_frame(dut, 0x44, div + 1)
    await ClockCycles(dut.clk, 2)
    await apb.write(A["CTRL"], 0x2 | 0x4 | 0x8)
    st, _ = await apb.read(A["STATUS"])
    assert field(R["STATUS"], "TX_LEVEL", st) == 0 and field(R["STATUS"], "RX_LEVEL", st) == 0
    ctrl, _ = await apb.read(A["CTRL"])
    assert ctrl & 0xC == 0
    cov_event("TX_FLUSH")
    cov_event("RX_FLUSH")


@cocotb.test()
async def test_apb_errors(dut):
    """PSLVERR on a write to STATUS (read-only) and on an unknown address; PREADY always 1."""
    apb = await setup(dut)
    assert await apb.write(A["STATUS"], 0) is True
    _, err = await apb.read(0x018)
    assert err
    assert await apb.write(0xFFC, 0) is True
    _, err = await apb.read(A["CTRL"])
    assert not err


@cocotb.test()
async def test_zz_coverage_export(dut):
    """Export functional coverage (runs last)."""
    from apb_util import export_coverage
    await export_coverage(dut)
