# Vendored IP

Every file under `vendor/` is a copy from another repository, pinned to a commit. Bugs are fixed in the
source repository (separate branch and PR, with the owner's approval) and then re-vendored. Vendored
files are never edited here (docs/BRIEF.md Part B rule 3).

| Path | Source repo | Branch | Commit | Commit date | Licence | Status |
|---|---|---|---|---|---|---|
| `vendor/alu/` (`rtl/**`, `LICENSE`) | `vikyathhj-ui/prefix-adder-alu-sky130` (formerly `32bit-RTL-To-GDS`) | `main` | `d59a42ed33e6b930f38eb6915c63e1f011f7c8a1` | 2026-11-01T11:47:25+05:30 | MIT (`vendor/alu/LICENSE`) | Vendored for Phase 2 (combinational units used by `rtl/core/core_alu.sv`, S-2) |
| `vendor/pmu/regmap.yaml` | `vikyathhj-ui/multipower` (to be renamed `soc-pmu-sequencer`) | `rework/pmu` (**not merged**) | `5fe30e0376d3df103832a87eed13702941246aea` | 2026-11-01T07:50:55Z | see the P2 repo | **Provisional**, for the Phase 1 memory map only (D-006, D-009) |

**Notes**
- `vendor/pmu/regmap.yaml`:
  - sha256 `9ca7c006eb3270156f66f90eef363f0b65f4409b31445f9d81e5d1aa903791b1`.
  - It is taken from the P2 work branch rather than `master`. On `master`
    (`5cca517`) the `pd_state` keys `ON`/`OFF` are unquoted, so YAML 1.1 loads them as booleans. P2
    fixed this in `dc12040`, which is not merged yet.
  - When P2 is merged, the full PMU RTL is vendored from P2's default branch and this file is
    re-pinned to the same commit.
- **ALU (P1)**:
  - Copied with `git archive d59a42e rtl LICENSE`. `.gitkeep` was dropped; every other file is
    byte-identical.
  - `alu_top.sv` is kept for traceability but is not compiled into the core: it has latency 2
    (S-2). The core uses `adder` (ARCH = `ADDER_HC`, P1's signed-off recommendation), `shifter`,
    `clz`/`clz_tree`, `cpop`, `pg_black`/`pg_gray` and `alu_pkg`.
  - sha256 of the vendored files:

```
bcb051e1e82b74216e2408cadeda3e0d9d573bfb3e59b22f01b5b262e729488d  vendor/alu/LICENSE
0f51f85ebaa9c9937b1bf4e0cec9c6903f09e592be8dfcbef0adb496925bbb75  vendor/alu/rtl/adders/adder.sv
124228b98843ba9e6b1226c3bd95be1aaa037fb87d270cd2774ce2611fa96fd7  vendor/alu/rtl/adders/adder_beh.sv
30bad554a5c09e6f635d1a0a5826b66221f6cf007ef4b26c39f38d0594414dd0  vendor/alu/rtl/adders/adder_bk.sv
74e760fb126cfd44cd13b36181ce67bd180eba12bcab12eeea8d980ccfb3d06f  vendor/alu/rtl/adders/adder_cla4.sv
77ecfa040bed99e00787acb85bbcc14f158408a28478dffe4eec68e5770de392  vendor/alu/rtl/adders/adder_csla.sv
8aac2b0ffb42731607755bf0d7022fa724627d1fe8ca337b07bb37d801bcdfa5  vendor/alu/rtl/adders/adder_hc.sv
43787e75553534705ec14bcd99e46c6349fea6e9910acbd8e0837b9e0e9c7f4d  vendor/alu/rtl/adders/adder_ks.sv
56f21c1b6952f68221149b4ef1fe7180d2c5ab674d205587f3203030fe8943f8  vendor/alu/rtl/adders/adder_rca.sv
aed80ec1740eeb6fe7f079829a203857eff649fe0518f4d6ff5952288f27f4e4  vendor/alu/rtl/adders/adder_sk.sv
0c025b714bbe248dc7802d6a6bf3052df5c30dd0d99e8df083608f18a812a2eb  vendor/alu/rtl/adders/cla4_unit.sv
1fb71ce239c9be7d4c023c9457f2a0a0e8c9ca9f0bde1f5c68175667e4dcd1af  vendor/alu/rtl/adders/pg_black.sv
0df2bd8e5aac6726033dd8fd29884eb13860ecc29e51adbe8c0de615e06df003  vendor/alu/rtl/adders/pg_gray.sv
a6a69aadecd90aa21bd0314a5f4276aad8df185cb4ac57be4b81f9d29053501b  vendor/alu/rtl/alu_pkg.sv
08abc9284e3405e20f4d8f8d0d493b02e67d3bc73cce2c2067d74e76c86cef8f  vendor/alu/rtl/alu_top.sv
cf7364e62bd6f41356bdf80895efe4850301a9d65682fb3a7c82ce1ba96ca450  vendor/alu/rtl/clz.sv
16a48a695535d2c1962280732458250be7d46717616dbcc7a03c1c2c42d4b19e  vendor/alu/rtl/clz_tree.sv
9da8f6c44f7f30c67fcc7f62e6282e9eeb036e86b38b296e3493746f2d4174a1  vendor/alu/rtl/cpop.sv
1fb7a0a4b868e5ef13fc6f8cd8be219978f903c438e17e05b3cc24b4b4b277fb  vendor/alu/rtl/shifter.sv
```
