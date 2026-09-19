# RapidWright-based fuzzers for Project X-Ray

Porting prjxray's Tcl fuzzers to RapidWright, and feeding the results back into
the X-Ray database format.

## What actually moves to RapidWright

A prjxray fuzzer does five things:

| Stage | Upstream | Here |
| --- | --- | --- |
| build a design | Vivado Tcl (`synth_design`) | Vivado, once |
| place and route | Vivado Tcl | Vivado, once |
| permute the design N ways | Vivado Tcl | **RapidWright** |
| write a bitstream per permutation | Vivado `write_bitstream` | Vivado (unavoidable) |
| record what was set, per permutation | Vivado Tcl `get_property` | **RapidWright** |
| bitstream -> bits -> segbits | `bitread`, segmaker, `segmatch` | unchanged |

**`write_bitstream` cannot move.** RapidWright has no bitstream generator; its
own `VivadoTools.writeBitstream()` shells out to Vivado. What it does remove is
the per-variant Tcl: the permutation logic and the property dumps become Java
against RapidWright's device and netlist model, and Vivado shrinks to
`open_checkpoint; write_bitstream`.

The stages downstream of the bitstream are stock prjxray and are deliberately
left alone — that pipeline *is* the X-Ray database, so we plug into it rather
than reimplement it.

A second, larger class of fuzzers (`072-ordered_wires`, `074-dump_all`,
`071-ppips`, the PIP fuzzers) never writes a bitstream at all: they only query
Vivado for tiles, wires, nodes and PIPs. Those can move to RapidWright
*entirely*, since its device model has the same information offline. See
`docs/PORTING.md`.

## Devices

All Series-7 families are supported. A device is selected by the name of a
prjxray settings file:

| config | part | family | notes |
| --- | --- | --- | --- |
| `artix7` | xc7a100tfgg676-1 | artix7 | default |
| `artix7_50t` | xc7a50tfgg484-1 | artix7 | |
| `artix7_200t` | xc7a200tffg1156-1 | artix7 | no ROI - whole device |
| `kintex7` | xc7k70tfbg676-2 | kintex7 | |
| `spartan7` | xc7s50fgga484-1 | spartan7 | |
| `spartan7_s25` | xc7s25csga324-1 | spartan7 | not in prjxray-db; see `docs/XC7S25.md` |
| `zynq7_z007s` | xc7z007sclg400-1 | zynq7 | shares the xc7z010 die; see `docs/PARTS.md` |
| `zynq7` | xc7z020clg484-1 | zynq7 | |
| `zynq7010` | xc7z010clg400-1 | zynq7 | |
| `kintex7_160t` | xc7k160tffg676-2 | kintex7 | **cannot run** - see below |

```bash
source env/xray_env.sh zynq7010
fuzzers/010-clb-lutinit/run.sh all zynq7010   # one device
./run_all.sh 010-clb-lutinit all              # every device, with a results table
```

`env/xray_env.sh` does not restate any part definition: it lifts the
`export XRAY_*` lines straight out of `prjxray/settings/<config>.sh`, so parts,
ROIs and frame ranges stay in sync with upstream.

**`kintex7_160t` is excluded.** Upstream ships `settings/kintex7_160t.sh`, but
`prjxray-db` has neither `xc7k160t/tilegrid.json` nor a `part.yaml` for
`xc7k160tffg676-2`. segmaker cannot map sites to frames without the first, and
`bitread` needs the second. Both Vivado and RapidWright support the part; what is
missing is the device characterisation. Supporting it means running fuzzer
`005-tilegrid` for it first, which is a separate job.

## Results: `010-clb-lutinit`

Vivado 2024.2, one specimen per device, six variants each.

| config | part | round trip | `LUT.INIT` vs prjxray-db |
| --- | --- | --- | --- |
| `artix7` | xc7a100tfgg676-1 | bit identical | 512/512 clbll, 512/512 clblm |
| `artix7_50t` | xc7a50tfgg484-1 | bit identical | 512/512, 512/512 |
| `artix7_200t` | xc7a200tffg1156-1 | bit identical | 512/512, 512/512 |
| `kintex7` | xc7k70tfbg676-2 | bit identical | 512/512, 512/512 |
| `spartan7` | xc7s50fgga484-1 | bit identical | 512/512, 512/512 |
| `zynq7` | xc7z020clg484-1 | bit identical | 512/512, 512/512 |
| `zynq7010` | xc7z010clg400-1 | bit identical | 512/512, 512/512 |

"round trip" is the Step B check: RapidWright reads the Vivado checkpoint,
writes it back unmodified, and the bitstream Vivado then produces is compared
byte for byte with the one it produced itself. "vs prjxray-db" is a direct line
diff of `database/<family>/segbits_*.db` against the published database, after
mergedb has put the tags in upstream spelling - no normalisation.

Read the last column as a *flow* validation, not a discovery: the `LUT.INIT`
segbits are byte-identical across all four families in prjxray-db already,
because the CLB tile is common to Series-7. What these runs establish is that
the RapidWright pipeline reproduces the known-good answer on every device.
Logs are kept per step under `work/`: the round-trip evidence for all seven
devices is in `work/010-clb-lutinit__<config>__B.log`, and the database
comparison in the matching `__pushdb.log`.

The per-specimen seed is the md5 of the specimen's absolute path, so it is
stable across re-runs of a device and differs between devices - each device
gets its own placement, and re-running one reproduces it exactly.

## Layout

```
env/xray_env.sh    environment: prjxray paths, part selection, tool locations
env/vivado.sh      runs Vivado: native Linux by default, or Windows via cmd.exe
env/mk_db_overlay.sh  writable database overlay for parts prjxray-db lacks
env/find_ioi3_anomaly.py  derives XRAY_IOI3_TILES from measured tilegrid data
env/gen_resources.sh  generates settings/<family>/resources.yaml for all parts
env/run_072_074.sh    runs the two connectivity fuzzers (tileconn.json et al)
env/push_074.sh       collects 074's output into the overlay without writing
                      through its symlinks into the read-only reference
env/check_tileconn_cover.py  can one die's tileconn.json serve another?
env/build_nextpnr_s25.sh  native nextpnr-himbaechel-xilinx + xc7s25 chipdb
java/              RapidWright generators
fuzzers/           one directory per ported fuzzer
run_all.sh         run a fuzzer across every supported device
```

## Environment notes

`env/vivado.sh` drives either of two installs, selected by `XRAY_VIVADO_LINUX`.

**Native Linux Vivado (the default): `/mnt/e/Xilinx/2026.1.1/Vivado`.** Despite
sitting on a Windows drive this is a Linux install — a bash `vivado`,
`settings64.sh`, an `lnx64/` tree and its own `Xilinx_wsl.lic`. The wrapper
sources `settings64.sh` and execs `vivado` directly. No `cmd.exe`, no
`wslpath -w`, no `WSLENV`: paths, environment and working directory are already
in the form the tool expects, so the entire WSL→Windows translation layer drops
out. (`settings64.sh` dereferences unset variables, so the wrapper relaxes
`set -e` around sourcing it.)

**Windows Vivado, via `cmd.exe`.** Still supported — set `XRAY_VIVADO_LINUX=""`
and point `XRAY_VIVADO_BAT` at the `.bat`. This is how every result before
2026-09-18 was produced. Two translations are baked in:

* File arguments are translated with `wslpath -w`.
* The environment is forwarded via `WSLENV`, since Windows processes do not
  inherit the WSL environment and prjxray's Tcl reads `$::env(XRAY_*)`
  throughout. `WSLENV`'s `/p` flag also path-translates the vars that need it.
* Specimen directories must live on a Windows-visible mount (`/mnt/...`).
* A variable that is *set but empty* needs care: Windows cannot hold an empty
  environment variable (`set VAR=` deletes it), so it arrives undefined and
  unguarded Tcl throws rather than seeing an empty string.
  `005-tilegrid`'s `make_project_roi` reads `$::env(XRAY_EXCLUDE_ROI_TILEGRID)`
  with no `info exists` guard and `settings/spartan7.sh` sets exactly that to
  `""`. The wrapper substitutes a single space, which stays defined and still
  iterates zero times in the `foreach` that consumes it.

`env/xray_env.sh` replaces prjxray's `utils/environment.sh` for two reasons:
it drops the hard Vivado-2017.2 gate (which both refuses to run and *silently
corrupts* `XRAY_DIR` on a mismatch), and it points `XRAY_DATABASE_DIR` at a
`prjxray-db` checkout used **read-only** as the comparison reference. Results
are written under `database/` here; nothing ever pushes into `prjxray-db`. It
also puts `XRAY_DIR` on `PYTHONPATH`, because prjxray's `setup.py` declares
`packages=['prjxray']` and so never exposes the sibling `utils` package that
`001-part-yaml` imports.

Parts that upstream `prjxray-db` does not ship cannot use that read-only
reference as their database, since the fuzzers' `pushdb` targets write into it.
`env/mk_db_overlay.sh` builds a writable overlay at `../xray-db-local` for those;
see `docs/XC7S25.md`.

### Vivado version

Upstream prjxray states that only Vivado 2017.2 is supported. This tree now runs
**2026.1.1**; the `010-clb-lutinit` results below were produced with **2024.2**
and have not been re-run. That is a real deviation and the reason every ported
fuzzer is validated against the published database rather than trusted. The
architecture narrows the exposure — with RapidWright doing the permutation,
Vivado's version-sensitive placer and router are out of the loop for everything
after the base checkpoint — but it does not eliminate it.

The two versions agree where they have been compared: both report 3650 SLICE
sites on xc7s25, and both produce the same `part.yaml` for it (see
`docs/XC7S25.md`).

## Prerequisites

* prjxray built (`bitread`, `segmatch`) and its Python package installed
* a `prjxray-db` checkout beside this one, for `tilegrid.json` / `part.yaml`
* RapidWright compiled (`./gradlew compileJava`)
* `settings/<family>/resources.yaml` in the prjxray tree — generated, gitignored,
  and **not** produced by a fresh clone; see `docs/SETUP.md`

## Running

```bash
source env/xray_env.sh              # defaults to artix7
fuzzers/010-clb-lutinit/run.sh all
```

Steps are separable (`run.sh A|B|C|pushdb`) so a failure isolates to one layer.
Specimens live under `fuzzers/<f>/build/<part>/`, so devices never overwrite
each other, and the per-specimen seed differs per part - each device gets a
different placement.
