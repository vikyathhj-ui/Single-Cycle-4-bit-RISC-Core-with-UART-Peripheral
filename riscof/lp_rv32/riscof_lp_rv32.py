"""RISCOF DUT plugin for lp_rv32 (docs/BRIEF.md A5, D-013).

Based on riscv-arch-test 3.10.0 riscof-plugins/rv32/spike_simple/riscof_spike_simple.py.
Each test is compiled with riscv64-unknown-elf-gcc against riscof/env (shared with the Spike
reference), converted to IMEM / DMEM word images with pyelftools, and run on the Verilator
testbench tb/arch/tb_arch.sv (core + crossbar + 2 x 32 KB SIM memories). The testbench dumps
begin_signature..end_signature when the test stores to tohost.

-mno-relax: arch_test.h aligns with `.option rvc`; with linker relaxation the trimmed padding can
leave a 2-byte c.nop in the instruction stream, which a core without C cannot execute (D-016).
"""
import logging
import os

from elftools.elf.elffile import ELFFile

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

IMEM_BASE, DMEM_BASE, MEM_BYTES = 0x80000000, 0x20000000, 32 * 1024   # riscof/env/link.ld, D-015


def elf_to_images(elf_path, out_dir):
    """Write imem.hex / dmem.hex (one 32-bit word per line from each base); return the symbols."""
    images = {IMEM_BASE: bytearray(MEM_BYTES), DMEM_BASE: bytearray(MEM_BYTES)}
    with open(elf_path, "rb") as f:
        elf = ELFFile(f)
        for seg in elf.iter_segments():
            if seg["p_type"] != "PT_LOAD" or seg["p_filesz"] == 0:
                continue
            addr, data = seg["p_paddr"], seg.data()
            for base, img in images.items():
                if base <= addr and addr + len(data) <= base + MEM_BYTES:
                    img[addr - base:addr - base + len(data)] = data
                    break
            else:
                raise RuntimeError(f"{elf_path}: segment at {addr:#x} ({len(data)} B) outside IMEM/DMEM")
        symtab = elf.get_section_by_name(".symtab")
        syms = {s.name: s["st_value"] for s in symtab.iter_symbols()
                if s.name in ("tohost", "begin_signature", "end_signature", "rvtest_entry_point")}
    for base, name in ((IMEM_BASE, "imem.hex"), (DMEM_BASE, "dmem.hex")):
        img = images[base]
        with open(os.path.join(out_dir, name), "w") as h:
            for i in range(0, MEM_BYTES, 4):
                h.write(f"{int.from_bytes(img[i:i + 4], 'little'):08x}\n")
    return syms


class lp_rv32(pluginTemplate):
    __model__ = "lp_rv32"
    __version__ = "phase3"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            raise SystemExit("lp_rv32 plugin: missing config")
        self.dut_exe = os.path.abspath(os.path.join(config.get("PATH", "sim_build/tb_arch"), "tb_arch"))
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])
        self.envpath = os.path.abspath(os.path.join(self.pluginpath, "..", "env"))
        self.isa_spec = os.path.abspath(config["ispec"])
        self.platform_spec = os.path.abspath(config["pspec"])
        self.target_run = config.get("target_run", "1") != "0"

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = ("riscv64-unknown-elf-gcc -march={0} -mabi=ilp32 -mno-relax -static -mcmodel=medany "
                            "-fvisibility=hidden -nostdlib -nostartfiles -g "
                            f"-T {self.envpath}/link.ld -I {self.envpath} -I {archtest_env} "
                            "{1} -o {2} {3}")

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)["hart0"]
        assert 32 in ispec["supported_xlen"], "lp_rv32 is RV32 only"
        if not os.path.exists(self.dut_exe):
            raise SystemExit(f"{self.dut_exe} missing: run 'make tb-arch' first")

    def runTests(self, testList):
        for testname, entry in testList.items():
            test_dir = entry["work_dir"]
            elf = os.path.join(test_dir, "my.elf")
            sig = os.path.join(test_dir, self.name[:-1] + ".signature")
            macros = " -D" + " -D".join(entry["macros"])
            cmd = self.compile_cmd.format(entry["isa"].lower(), entry["test_path"], elf, macros)
            utils.shellCommand(cmd).run(cwd=test_dir)
            if not self.target_run:
                continue
            syms = elf_to_images(elf, test_dir)
            if syms.get("rvtest_entry_point") != IMEM_BASE:
                raise RuntimeError(f"{testname}: entry {syms.get('rvtest_entry_point')} is not IMEM base")
            run = (f"{self.dut_exe} +imem=imem.hex +dmem=dmem.hex +sig={sig} "
                   f"+tohost={syms['tohost']:x} +sig_begin={syms['begin_signature']:x} "
                   f"+sig_end={syms['end_signature']:x} > dut.log 2>&1")
            utils.shellCommand(run).run(cwd=test_dir)
        if not self.target_run:
            raise SystemExit(0)
