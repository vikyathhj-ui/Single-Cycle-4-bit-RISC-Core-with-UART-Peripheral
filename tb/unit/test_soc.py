"""SoC integration smoke test for rtl/soc/lp_rv32_soc.sv (Phase 3; the full system tests are Phase 4).

Program: sw/tests/smoke.S (compiled by scripts/run_unit.py into IMEM, BOOT.SEL = 1). Checks that
after the reset pin is released the whole chain works:
  PMU boot (MODE_REQ resets to RUN: CORE and PERI powered up, clocks enabled, isolation released,
  Q-Channel exit) -> core fetches the boot ROM at 0x0 -> jumps to IMEM -> APB writes through the
  bridge to the UART -> "OK" appears on uart_txd as two 8N1 frames at 4 cycles per bit.
"""
from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge

BIT = 4                      # BAUD_DIV = 3 in smoke.S
TIMEOUT = 20000


async def uart_rx_byte(dut, timeout: int) -> tuple[int, int]:
    """Return (byte, cycles waited for the start bit). Samples each bit at its middle."""
    for waited in range(timeout):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.uart_txd.value) == 0:
            break
    else:
        raise AssertionError(f"no start bit on uart_txd within {timeout} cycles")
    await ClockCycles(dut.clk, BIT // 2)
    await ReadOnly()
    assert int(dut.uart_txd.value) == 0, "start bit not low at its middle"
    val = 0
    for i in range(8):
        await ClockCycles(dut.clk, BIT)
        await ReadOnly()
        val |= int(dut.uart_txd.value) << i
    await ClockCycles(dut.clk, BIT)
    await ReadOnly()
    assert int(dut.uart_txd.value) == 1, "stop bit not high"
    return val, waited


@cocotb.test()
async def test_boot_and_uart_ok(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.boot_sel.value = 1
    dut.uart_rxd.value = 1
    dut.gpio_i.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    b1, t1 = await uart_rx_byte(dut, TIMEOUT)
    b2, _ = await uart_rx_byte(dut, 100)
    got = bytes([b1, b2])
    dut._log.info("uart_txd: %r, first start bit %d cycles after reset release", got, t1)
    assert got == b"OK", f"expected b'OK', got {got!r}"
