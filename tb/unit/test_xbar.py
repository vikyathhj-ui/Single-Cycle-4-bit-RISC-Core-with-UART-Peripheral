"""cocotb unit test for lp_rv32_xbar + apb_bridge through tb/unit/xbar_tb.sv (BRIEF A5 "crossbar and
APB bridge"; SPEC §4, MICROARCH §5, MEMORY_MAP regions).

The test plays the core: every cycle it presents a fetch address on the I-port and, when allowed
(one outstanding request; a new one may be issued in the same cycle as a response), a D-port
request. A Python model of the memory map predicts every response:
  * I-port: BOOTROM / IMEM data one cycle later, anything else -> ibus_err;
  * D-port: ROM (read only), IMEM, DMEM, APB slots 0-7 (32-bit only, random wait states and
    PSLVERR), absent slots 8-15, unmapped addresses and addresses past the end of a region -> error;
  * fetch / store coherence: a fetch of an IMEM word returns data written through the D-port.
xbar_tb.sv flags APB protocol violations (apb_violation), which must stay 0.
"""
from __future__ import annotations

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from cocotb_coverage.coverage import CoverCross, CoverPoint

from apb_util import export_coverage

ROM, IMEM, DMEM, APB = 0x0000_0000, 0x1000_0000, 0x2000_0000, 0x4000_0000
SIZE = 256                       # AW = 6 in xbar_tb.sv, and the 64-word ROM
PRESENT = 0x00FF
CYCLES = 20000
SEED = 20261102


@CoverPoint("xbar.d.region", xf=lambda reg, op, out: reg,
            bins=["ROM", "IMEM", "DMEM", "APB", "APB_ABSENT", "APB_NARROW", "PAST_END", "UNMAPPED"])
@CoverPoint("xbar.d.op", xf=lambda reg, op, out: op, bins=["read", "write"])
@CoverPoint("xbar.d.outcome", xf=lambda reg, op, out: out, bins=["ok", "err"])
@CoverCross("xbar.d.region_x_op", items=["xbar.d.region", "xbar.d.op"])
def cov_d(reg, op, out):
    pass


@CoverPoint("xbar.i.region", xf=lambda r: r, bins=["ROM", "IMEM", "OTHER"])
def cov_i(r):
    pass


@CoverPoint("xbar.apb.wait", xf=lambda w: "0" if w == 0 else "1" if w == 1 else "2-5" if w <= 5 else "6-15",
            bins=["0", "1", "2-5", "6-15"])
def cov_wait(w):
    pass


@CoverPoint("xbar.event", xf=lambda e: e,
            bins=["B2B_SRAM", "B2B_APB", "APB_SLVERR", "FETCH_AFTER_STORE"])
def cov_event(e):
    pass


class Model:
    def __init__(self):
        self.imem = [0] * (SIZE // 4)
        self.dmem = [0] * (SIZE // 4)
        self.apb = {(s, w): 0x5000_0000 | (s << 8) | w for s in range(16) for w in range(16)}

    @staticmethod
    def region(a: int) -> str:
        if a >> 8 == ROM >> 8:
            return "ROM"
        if a >> 28 == IMEM >> 28:
            return "IMEM" if a - IMEM < SIZE else "PAST_END"
        if a >> 28 == DMEM >> 28:
            return "DMEM" if a - DMEM < SIZE else "PAST_END"
        if a >> 16 == APB >> 16:
            return "APB"
        return "UNMAPPED"

    def fetch(self, a: int):
        r = self.region(a)
        if r == "ROM":
            return 0xC0DE_0000 | ((a >> 2) & 63), False, "ROM"
        if r == "IMEM":
            return self.imem[(a - IMEM) >> 2], False, "IMEM"
        return None, True, "OTHER"

    def access(self, we: bool, a: int, be: int, wd: int, slv_err: bool):
        """Return (expected rdata or None, expected err, coverage region)."""
        r = self.region(a)
        mask = sum(0xFF << (8 * i) for i in range(4) if be >> i & 1)
        if r == "ROM":
            return (None, True, r) if we else (0xC0DE_0000 | ((a >> 2) & 63), False, r)
        if r in ("IMEM", "DMEM"):
            mem, base = (self.imem, IMEM) if r == "IMEM" else (self.dmem, DMEM)
            i = (a - base) >> 2
            if we:
                mem[i] = (mem[i] & ~mask) | (wd & mask)
                return None, False, r
            return mem[i], False, r
        if r == "APB":
            slot, word = (a >> 12) & 15, (a >> 2) & 15
            if be != 0xF:
                return None, True, "APB_NARROW"
            if not PRESENT >> slot & 1:
                return None, True, "APB_ABSENT"
            if slv_err:
                return None, True, r
            if we:
                self.apb[(slot, word)] = wd
                return None, False, r
            return self.apb[(slot, word)], False, r
        return None, True, r


def rand_addr(rng: random.Random) -> int:
    kind = rng.choices(["rom", "imem", "dmem", "apb", "past", "unmapped"], [2, 4, 4, 4, 1, 1])[0]
    if kind == "rom":
        return ROM + rng.randrange(SIZE)
    if kind == "imem":
        return IMEM + rng.randrange(SIZE)
    if kind == "dmem":
        return DMEM + rng.randrange(SIZE)
    if kind == "apb":
        return APB + (rng.randrange(16) << 12) + rng.randrange(64)
    if kind == "past":
        return rng.choice([IMEM, DMEM]) + SIZE + rng.randrange(1 << 20)
    return (rng.choice([0x0000_1000, 0x3000_0000, 0x5000_0000, 0x8000_0000, 0xFFFF_FF00]) + rng.randrange(256)) & 0xFFFF_FFFF


@cocotb.test()
async def test_random_traffic(dut):
    rng = random.Random(SEED)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for s in ("ibus_addr", "dbus_req", "dbus_we", "dbus_addr", "dbus_be", "dbus_wdata", "slv_wait", "slv_err"):
        getattr(dut, s).value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    m = Model()
    prev_fetch = None             # address presented in the previous cycle
    outstanding = None            # (expected rdata, expected err, region, op, is_apb)
    age = 0                       # cycles the outstanding request has waited
    MAX_AGE = 40                  # APB: <= 15 wait states + SETUP + ACCESS + RESP; SRAM: 1
    last_store_imem = set()
    n_d = n_i = 0
    for _ in range(CYCLES):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")  # registered outputs settled; before driving new inputs
        # ---- check the I-port result for the address of the previous cycle
        if prev_fetch is not None:
            exp, err, reg = m.fetch(prev_fetch)
            assert int(dut.ibus_err.value) == int(err), f"fetch {prev_fetch:#x}: err"
            if not err:
                got = int(dut.ibus_rdata.value)
                assert got == exp, f"fetch {prev_fetch:#x}: {got:#x} != {exp:#x}"
                if reg == "IMEM" and (prev_fetch & ~3) in last_store_imem:
                    cov_event("FETCH_AFTER_STORE")
            cov_i(reg)
            n_i += 1
        # ---- check a D-port response
        responded = False
        if outstanding is not None:
            age += 1
            assert age <= MAX_AGE, f"D {outstanding[3]} {outstanding[2]}: no response after {MAX_AGE} cycles"

        if outstanding is not None and int(dut.dbus_rvalid.value):
            exp, err, reg, op, is_apb = outstanding
            got_err = bool(int(dut.dbus_err.value))
            assert got_err == err, f"D {op} {reg}: err {got_err} != {err}"
            if exp is not None:
                got = int(dut.dbus_rdata.value)
                assert got == exp, f"D read {reg}: {got:#x} != {exp:#x}"
            cov_d(reg, op, "err" if err else "ok")
            outstanding, responded = None, True
            n_d += 1
        # ---- drive this cycle
        fa = rand_addr(rng) & ~3
        dut.ibus_addr.value = fa
        prev_fetch = fa
        if outstanding is None and rng.random() < 0.6:
            we = rng.random() < 0.5
            a = rand_addr(rng)
            be = rng.choice([0xF, 0xF, 0x1 << (a & 3), 0x3 << (a & 2)])
            wd = rng.getrandbits(32)
            wait, serr = rng.choice([0, 0, 1, rng.randrange(2, 6), rng.randrange(6, 16)]), rng.random() < 0.15
            dut.slv_wait.value, dut.slv_err.value = wait, int(serr)
            dut.dbus_req.value, dut.dbus_we.value = 1, int(we)
            dut.dbus_addr.value, dut.dbus_be.value, dut.dbus_wdata.value = a & ~3, be, wd
            exp, err, reg = m.access(we, a & ~3, be, wd, serr)
            is_apb = reg == "APB"
            outstanding = (exp, err, reg, "write" if we else "read", is_apb)
            age = 0
            if responded:
                cov_event("B2B_APB" if is_apb else "B2B_SRAM")
            if is_apb:
                cov_wait(wait)
                if serr:
                    cov_event("APB_SLVERR")
            if we and reg == "IMEM" and not err:
                last_store_imem.add(a & ~3)
        else:
            dut.dbus_req.value = 0
        assert int(dut.apb_violation.value) == 0, "APB protocol violation"
    dut.dbus_req.value = 0
    await ClockCycles(dut.clk, 40)
    assert int(dut.apb_violation.value) == 0
    dut._log.info("checked %d fetches and %d D-port transactions", n_i, n_d)


@cocotb.test()
async def test_zz_coverage_export(dut):
    await export_coverage(dut)
