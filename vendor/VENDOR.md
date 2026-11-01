# Vendored IP

Every file under `vendor/` is a copy from another repository, pinned to a commit. Bugs are fixed in the
source repository (separate branch and PR, with the owner's approval) and then re-vendored. Vendored
files are never edited here (docs/BRIEF.md Part B rule 3).

| Path | Source repo | Branch | Commit | Commit date | Licence | Status |
|---|---|---|---|---|---|---|
| `vendor/pmu/regmap.yaml` | `vikyathhj-ui/multipower` (to be renamed `soc-pmu-sequencer`) | `rework/pmu` (**not merged**) | `5fe30e0376d3df103832a87eed13702941246aea` | 2026-11-01T07:50:55Z | see the P2 repo | **Provisional**, for the Phase 1 memory map only (D-006, D-009) |

**Notes**
- `vendor/pmu/regmap.yaml`:
  - sha256 `9ca7c006eb3270156f66f90eef363f0b65f4409b31445f9d81e5d1aa903791b1`.
  - It is taken from the P2 work branch rather than `master`. On `master`
    (`5cca517`) the `pd_state` keys `ON`/`OFF` are unquoted, so YAML 1.1 loads them as booleans. P2
    fixed this in `dc12040`, which is not merged yet.
  - When P2 is merged, the full PMU RTL is vendored from P2's default branch and this file is
    re-pinned to the same commit.
- **ALU (P1):** vendored in Phase 2 from `vikyathhj-ui/prefix-adder-alu-sky130` `main` (SPEC §10).
