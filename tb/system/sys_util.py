"""Shared helpers for the system tests (tb/system/test_*.py).

UartMonitor decodes 8N1 frames from uart_txd (sampling each bit at its middle) into text.
UartDriver sends bytes into uart_rxd. Both use BIT = UART_DIV + 1 cycles per bit (sw/common/hal.h).
"""
from __future__ import annotations

import os

import cocotb
from cocotb.triggers import Edge, FallingEdge, Timer
from cocotb.utils import get_sim_time

UART_DIV = int(os.environ.get("UART_DIV", "7"))
BIT = UART_DIV + 1


PERIOD_NS = 10                   # matches the clock generated in soc_sys_tb.sv


def cycles_now() -> int:
    """Clock cycles since time 0, from simulation time (no per-cycle Python coroutine)."""
    return int(get_sim_time("ns")) // PERIOD_NS


class UartMonitor:
    """Event-driven: sleeps until uart_txd falls, then samples the frame at bit centres."""

    def __init__(self, dut, bit: int = BIT):
        self.dut = dut
        self.bit = bit               # cycles per bit; tests may change it (boot loader at reset divisor)
        self.text = ""
        self.cycle_of = []           # cycle at which each character was complete
        self.error = None            # a frame error ends the monitor; wait_* re-raise it
        self.edges = []              # (cycle, level) of every uart_txd change, when record_edges
        self.record_edges = False
        self.switch = None           # (after_n_chars, new_bit): change baud exactly after a character
        cocotb.start_soon(self._run())
        cocotb.start_soon(self._edges())

    async def _edges(self):
        while True:
            await Edge(self.dut.uart_txd)
            if self.record_edges:
                self.edges.append((cycles_now(), int(self.dut.uart_txd.value)))

    async def _run(self):
        d = self.dut
        while True:
            await FallingEdge(d.uart_txd)
            b = self.bit
            await Timer(PERIOD_NS * b // 2, unit="ns")
            if int(d.uart_txd.value) != 0:
                continue                         # glitch
            v = 0
            for i in range(8):
                await Timer(PERIOD_NS * b, unit="ns")
                v |= int(d.uart_txd.value) << i
            await Timer(PERIOD_NS * b, unit="ns")
            if int(d.uart_txd.value) != 1:
                self.error = f"uart_txd: stop bit not high after {self.text!r} + {v:#04x} at cycle {cycles_now()}"
                return
            self.text += chr(v)
            self.cycle_of.append(cycles_now())
            if self.switch and len(self.text) >= self.switch[0]:
                self.bit, self.switch = self.switch[1], None

    async def wait_for_len(self, n: int, timeout: int) -> int:
        """Wait until at least n characters have been received."""
        start = cycles_now()
        while len(self.text) < n:
            await Timer(PERIOD_NS * 1024, unit="ns")
            assert self.error is None, self.error
            if cycles_now() - start > timeout:
                raise AssertionError(f"timeout waiting for {n} characters; got {self.text!r}")
        return cycles_now()

    async def wait_for(self, s: str, timeout: int) -> int:
        """Wait until the text contains s; return the cycle count at that moment."""
        start = cycles_now()
        while s not in self.text:
            await Timer(PERIOD_NS * 4096, unit="ns")
            assert self.error is None, self.error
            if cycles_now() - start > timeout:
                raise AssertionError(f"timeout waiting for {s!r}; UART so far:\n{self.text}")
        return cycles_now()


async def uart_send(dut, data: bytes, bit: int = BIT, gap: int = 2):
    for b in data:
        bits = [0] + [(b >> i) & 1 for i in range(8)] + [1]
        for x in bits:
            dut.uart_rxd.value = x
            await Timer(PERIOD_NS * bit, unit="ns")
        await Timer(PERIOD_NS * gap, unit="ns")


async def boot(dut, boot_sel: int = 1, bit: int = BIT) -> UartMonitor:
    dut.rst_n.value = 0
    dut.boot_sel.value = boot_sel
    dut.uart_rxd.value = 1
    dut.gpio_i.value = 0
    await Timer(5 * PERIOD_NS, unit="ns")
    mon = UartMonitor(dut, bit)
    dut.rst_n.value = 1
    return mon


def read_stats(dut) -> dict:
    """Hazard statistics counted by soc_sys_tb.sv from the RVFI retire stream (CPI study)."""
    g = lambda n: int(getattr(dut, n).value)
    return {"retired": g("st_ret"), "cycles": g("st_last") - g("st_first"), "ct_taken": g("st_ct"),
            "loads": g("st_load"), "load_use_d1": g("st_lu1"), "load_use_d2": g("st_lu2")}
