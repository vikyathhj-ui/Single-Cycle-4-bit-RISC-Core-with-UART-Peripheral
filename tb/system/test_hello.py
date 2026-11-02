"""System test: sw/hello (BRIEF A5). Boot with IMEM preloaded (BOOT.SEL = 1) and check the text."""
import cocotb

from sys_util import boot


@cocotb.test()
async def test_hello(dut):
    mon = await boot(dut)
    cyc = await mon.wait_for("DONE", timeout=200000)
    dut._log.info("UART output (%d cycles):\n%s", cyc, mon.text)
    assert "Hello from LP-RV32!" in mon.text
    assert "misa=40000100 mhartid=0 sysctrl_id=4c503332 reset_cause=1" in mon.text, mon.text
