"""RISCOF reference plugin: Spike (D-013, owner decision; BRIEF A5 allows Spike "if Sail is
impractical; say which"). Based on riscv-arch-test 3.10.0 riscof-plugins/rv32/spike_simple.

Uses the same link script as the DUT (riscof/env) and gives Spike exactly the DUT's SIM memory
map for the arch tests: 32 KB at 0x8000_0000 (IMEM) and 32 KB at 0x2000_0000 (DMEM), D-015. The ISA string comes from the DUT ISA yaml.

-mno-relax: arch_test.h aligns with `.option rvc`; with linker relaxation the trimmed padding can
leave a 2-byte c.nop in the instruction stream, which a core without C cannot execute (D-016).
"""
import logging
import os

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


class spike_ref(pluginTemplate):
    __model__ = "spike"
    __version__ = "1.1.1-dev"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            raise SystemExit("spike_ref plugin: missing config")
        self.ref_exe = os.path.join(config.get("PATH", ""), "spike")
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])
        self.envpath = os.path.abspath(os.path.join(self.pluginpath, "..", "env"))

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = ("riscv64-unknown-elf-gcc -march={0} -mabi=ilp32 -mno-relax -static -mcmodel=medany "
                            "-fvisibility=hidden -nostdlib -nostartfiles -g "
                            f"-T {self.envpath}/link.ld -I {self.envpath} -I {archtest_env} "
                            "{1} -o {2} {3}")

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)["hart0"]
        isa = ispec["ISA"].lower()                     # e.g. rv32izicsr_zbb
        base, _, exts = isa.partition("z")
        self.isa = base + ("_z" + exts if exts else "")  # rv32i_zicsr_zbb

    def runTests(self, testList):
        make = utils.makeUtil(makefilePath=os.path.join(self.work_dir, "Makefile." + self.name[:-1]))
        make.makeCommand = "make -k -j" + self.num_jobs
        for testname, entry in testList.items():
            test_dir = entry["work_dir"]
            sig = os.path.join(test_dir, self.name[:-1] + ".signature")
            macros = " -D" + " -D".join(entry["macros"])
            cmd = self.compile_cmd.format(entry["isa"].lower(), entry["test_path"], "ref.elf", macros)
            sim = (f"{self.ref_exe} --isa={self.isa} -m0x80000000:0x8000,0x20000000:0x8000 "
                   f"+signature={sig} +signature-granularity=4 ref.elf")
            make.add_target(f"@cd {test_dir}; {cmd}; {sim};")
        make.execute_all(self.work_dir)
