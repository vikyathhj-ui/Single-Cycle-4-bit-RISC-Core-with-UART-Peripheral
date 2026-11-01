# lp-rv32-mcu (repo: vikyathhj-ui/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral)

A power-managed RV32I + Zicsr + Zbb microcontroller (UART, timer, GPIO, PMU), verified with
riscv-formal and RISCOF, and taken through LibreLane on sky130A with OpenRAM SRAM macros.

**The binding spec is `docs/BRIEF.md`.** Part A is the design spec; Part B holds the rules and
phases. Status lives in `PROGRESS.md`. To resume: "Read CLAUDE.md and PROGRESS.md and continue".

## Non-negotiable rules (from docs/BRIEF.md Part B)
1. **Never fabricate or hand-type a result.**
   - Every number comes from a script parsing a tool output.
   - Numbers are stored in `results/summary.json` with the source path and the memory configuration
     (GDS 2×1 KB SRAM, or SIM 32 KB behavioural).
   - If a tool fails, report the failure.
2. **Git:**
   - Branch `rework/lp-rv32`.
   - Conventional Commits after each gate, with what/why/verification in the body and the
     `Co-Authored-By: Claude` trailer.
   - Push after each commit and open a PR per phase to `main`.
   - **Never merge** (the owner merges), never force-push, never rewrite history.
3. **Vendored IP** goes in `vendor/` at a pinned commit, recorded in `vendor/VENDOR.md`.
   - A bug in vendored IP is fixed in the source repo (separate branch + PR, ask first), then
     re-vendored.
4. **Ask first before:**
   - renaming repos;
   - changing visibility;
   - installing system packages;
   - acting outside this repo (including P1/P2 repos).
5. **Cite the RISC-V unprivileged/privileged spec sections** for every ISA or trap behaviour.
   Never invent riscv-formal or RISCOF options: read the docs or examples under `ext/`.
6. **`PROGRESS.md` is the single source of truth** for status. Update it before every commit.
7. **Keep up `docs/DECISIONS.md`, `docs/LEARNING.md` and `docs/INTERVIEW.md`.** INTERVIEW needs 40+
   questions, answered with this project's numbers; the topics are listed in BRIEF Part B rule 7.
8. If Part A of the brief looks wrong or infeasible, stop, explain, propose the closest honest
   alternative and wait for the owner.

## Dependencies on other projects
- **P1 ALU:**
  - Repo `vikyathhj-ui/prefix-adder-alu-sky130` (old name `32bit-RTL-To-GDS`), default branch `main`.
  - Local clone at `~/projects/32bit-RTL-To-GDS`.
  - Merged, so it can be vendored.
- **P2 PMU:**
  - Repo `vikyathhj-ui/multipower` (to be renamed `soc-pmu-sequencer`), default branch `master`.
  - Local clone at `~/projects/multipower`.
  - **Not merged yet**, so Phase 3+ waits for it (D-006).

## Layout
```
rtl/core/   core RTL (pipeline, CSRs, RVFI)    rtl/soc/   crossbar, APB bridge, SoC top
rtl/periph/ UART, timer, GPIO, IRQ ctrl, SYSCTRL vendor/   vendored ALU (P1) and PMU (P2), VENDOR.md
sw/         linker scripts, crt0, HAL, programs tb/       cocotb unit + system tests
formal/     riscv-formal config (checks.cfg)    riscof/   RISCOF config + DUT plugin
upf/        lp_rv32.upf (not tool-verified)     flow/     LibreLane config
scripts/    env_check, generators, parsers      results/  machine-generated outputs only
docs/       BRIEF, AUDIT, SPEC, MICROARCH, ... DECISIONS, LEARNING, INTERVIEW
legacy/     original 4-bit core + UART (kept for history; tb_probe.v added for the audit)
ext/        git-ignored external checkouts: riscv-formal, riscv-arch-test (3.10.0), sail
```
Never commit `ext/`, `.venv*/`, `runs/`, `sim_build/` or `*.vcd`.

## Environment
- **Container:** all EDA tools run in the Docker container `iic-osic` (see `~/vlsi/CLAUDE.md`).
  - `~/projects` is mounted at `/foss/projects`.
  - `bash -lc` is required: without a login shell, PATH and PDK variables are missing.

  ```bash
  docker exec -w /foss/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral iic-osic bash -lc '<cmd>'
  ```
- **Host vs container:** `git push` and `gh` run on the host (`gh` is in `~/.local/bin`). `make` exists
  only in the container.
- **Python environments** (created inside the container; `results/env_check.txt` has the versions):
  - `.venv`: `python3 -m venv --system-site-packages .venv && .venv/bin/pip install cocotb-coverage==2.0`
    (reuses the image's cocotb 2.0.1).
  - `.venv-riscof`: an isolated venv for riscof 1.25.3, recreated as in D-004.
    **Always run it with `PYTHONPATH=` cleared**, e.g. `PYTHONPATH= .venv-riscof/bin/riscof --version`.
- **External tools under `ext/`:**
  - `ext/riscv-formal`: git clone of YosysHQ/riscv-formal.
  - `ext/riscv-arch-test`: git clone, `git checkout 3.10.0` (D-003).
  - `ext/sail`: Sail 0.16, `gh release download 0.16 -R riscv/sail-riscv -p 'sail-riscv-Linux-x86_64.tar.gz'`,
    then untar it. The binary is `ext/sail/sail-riscv-Linux-x86_64/bin/sail_riscv_sim`.

Make targets (run in the container):
```bash
make env            # scripts/env_check.sh -> results/env_check.txt (exit 1 if anything is missing)
make legacy-probe   # scripts/legacy_probe.sh -> results/legacy_probe.txt (docs/AUDIT.md evidence)
```

## Tool notes
- **Solver:** the only SMT solver is **yices**. riscv-formal takes `solver yices` (D-002).
- **GCC:** the RISC-V GCC is `riscv64-unknown-elf-gcc` 16.1.0, used with
  `-march=rv32i_zicsr_zbb -mabi=ilp32`. It has an `rv32i/ilp32` multilib.
- **Arch tests:** riscv-arch-test `main` is ACT4 (no RISCOF), so stay on 3.10.0 (D-003).
- **SRAM:** `sky130_sram_1kbyte_1rw1r_32x256_8` has only a TT 1.8 V 25 °C liberty (D-005).
- **ICG:** the sky130 ICG cells are `sky130_fd_sc_hd__dlclkp_{1,2,4}`.
- **Yosys:** has the slang SV frontend (`read_slang`); LibreLane exposes it as `USE_SLANG` (P1, D-012).
