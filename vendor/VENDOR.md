# Vendored IP

Every file under `vendor/` is a copy from another repository, pinned to a commit. Bugs are fixed in the
source repository (separate branch and PR, with the owner's approval) and then re-vendored. Vendored
files are never edited here (docs/BRIEF.md Part B rule 3).

| Path | Source repo | Branch | Commit | Commit date | Licence | Status |
|---|---|---|---|---|---|---|
| `vendor/alu/` (`rtl/**`, `LICENSE`) | `vikyathhj-ui/prefix-adder-alu-sky130` (formerly `32bit-RTL-To-GDS`) | `main` | `d59a42ed33e6b930f38eb6915c63e1f011f7c8a1` | 2026-11-01T11:47:25+05:30 | MIT (`vendor/alu/LICENSE`) | Vendored for Phase 2 (combinational units used by `rtl/core/core_alu.sv`, S-2) |
| `vendor/pmu/` (`rtl/**`, `upf/pmu_soc.upf`, `LICENSE`; `regmap.yaml` = P2 `scripts/regmap.yaml`) | `vikyathhj-ui/soc-pmu-sequencer` (formerly `multipower`) | `master` | `a87ba58fffc41e844f312ff21689d24da2011121` | 2026-11-01T20:13:24+05:30 | MIT (`vendor/pmu/LICENSE`) | Vendored for Phase 3 (D-014) |

**Notes**
- **PMU (P2)**:
  - Copied with `git archive a87ba58 rtl LICENSE upf/pmu_soc.upf`, plus `scripts/regmap.yaml`
    saved as `vendor/pmu/regmap.yaml`. All 14 files are byte-identical to the source.
  - It replaces the provisional regmap copy from `rework/pmu` `5fe30e0` (D-009). The YAML is
    identical in both commits, so the memory map did not change.
  - P2's PR #4 (README and resume bullets) was still open when this was vendored. It does not
    touch `rtl/` or `scripts/regmap.yaml`.
  - sha256 of the vendored files:

```
bcb051e1e82b74216e2408cadeda3e0d9d573bfb3e59b22f01b5b262e729488d  vendor/pmu/LICENSE
9ca7c006eb3270156f66f90eef363f0b65f4409b31445f9d81e5d1aa903791b1  vendor/pmu/regmap.yaml
b8e326d0208b643557b75de0f719d26b8c4aa67016368f24ac295aff6c6d1385  vendor/pmu/rtl/apb_regs.sv
b3e86c0eff0d1bf183f8378059bef2b5f946bd158756ae44049e38e6798b431d  vendor/pmu/rtl/cells/icg_wrap.sv
56dbf0fd25c21f2a2e223d2b15cb8822ab435692a6c74de9d902fe22718222c9  vendor/pmu/rtl/cells/iso_wrap.sv
15c1fb2290a69388b9aaa78dd7586ef826d49ca88f6d2b9086add624d2e83e91  vendor/pmu/rtl/inrush_arb.sv
a2e6dc9abf3089ada2bb5ad2b9d5a5acd6a8026d57f52c5d775699ca8f98b5ae  vendor/pmu/rtl/pd_ctrl.sv
d013a87137bf845da80761e3fc54c581b70a2cebbf34baca4509afaf8edd2173  vendor/pmu/rtl/pmu_regmap_pkg.sv
b82d500a8398d1fcc96fedcb844884dd155292301b5e0df21ff53a664c357585  vendor/pmu/rtl/pmu_top.sv
3532a504a00da411a6de34524393e270bc060903479a5fb50577a4f9c34af8f7  vendor/pmu/rtl/qch_master.sv
ec1fe8a6d70820675118bad52865431a5d11f437108375681837592974722d9b  vendor/pmu/rtl/rst_sync.sv
c37d4add813b6ebcdd1d23e3aafbd484d640f7b0cd203bd22ecb990038c28d81  vendor/pmu/rtl/sync_ff.sv
23d43760b43d201b728c49f37698e19cf96cdd18554708e1a9f1dc62844249f1  vendor/pmu/rtl/wake_ctrl.sv
6dc797f6fb4b2361622f2a9aaeacdf76c113a6ed3810404da485670de60c83fb  vendor/pmu/upf/pmu_soc.upf
```
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

## Third-party code outside `vendor/`
- **`sw/coremark/`** (`core_portme.c`, `core_portme.h`, `ee_printf.c`):
  - **Source:** EEMBC's CoreMark `barebones` porting files from `eembc/coremark` at
    `1f483d5b8316753a742cbf5590caf5bd0a4e4777` (2025-05-01). Apache-2.0 headers are kept.
  - **Changes:** made only where marked "lp_rv32 port", as CoreMark's porting rules allow (D-025).
  - **Not copied:** the CoreMark core files. They are compiled unmodified from the git-ignored
    `ext/coremark` checkout at the same commit (`git clone https://github.com/eembc/coremark
    ext/coremark`). CoreMark® is a trademark of EEMBC.
