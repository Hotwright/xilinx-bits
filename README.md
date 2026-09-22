# 0-xilinx-bits

Series-7 bitstream work built on top of [Project X-Ray][prjxray] and
[RapidWright][rapidwright]: characterising a part prjxray-db does not ship,
porting the fuzzers that produce that data to RapidWright, and building the
back half of the toolchain for WebAssembly so the whole flow can run in a
browser.

Three strands, each with its own documentation:

| | What it produced | Read |
| --- | --- | --- |
| **xc7s25 characterisation** | The database for the Arty S7-25, which prjxray-db has no entry for | [`rw-fuzzers/docs/XC7S25.md`](rw-fuzzers/docs/XC7S25.md) |
| **RapidWright fuzzers** | prjxray's Tcl fuzzers with the permutation and property-dump stages moved to Java | [`rw-fuzzers/README.md`](rw-fuzzers/README.md) |
| **WASI toolchain** | `nextpnr-himbaechel` and `xc7frames2bit` as `wasm32-wasip1` commands | [`wasm-build/`](wasm-build/) script headers |

## This is not a fork

Nothing here vendors prjxray or RapidWright. Both, and the reference
`prjxray-db`, are **separate checkouts that must sit beside this one**:

```
some-parent/
├── 0-xilinx-bits/     <- this repository
├── prjxray/           <- our own branch
├── prjxray-db/        <- read-only reference
└── RapidWright/
```

`.gitignore` excludes all three deliberately. They are cloned, not tracked,
because each is separately versioned and `prjxray-db` is a reference we
validate against rather than something we edit.

**A fresh clone therefore has 553 dangling symlinks until `prjxray-db` is
checked out next to it.** `xray-db-local/` is a writable overlay — every entry
is a relative symlink back into `prjxray-db` except the parts that had to be
real, so reading it is identical to reading the reference and nothing written
through it can reach the reference. That design is why most of the tree is
links; see the "Writable database overlay" section of
[`XC7S25.md`](rw-fuzzers/docs/XC7S25.md) for why it has to work that way.

Anything that copies the overlay has to dereference, not preserve, those links
— `tar -h`, `cp -L`, `rsync -L`.

[`rw-fuzzers/docs/SETUP.md`](rw-fuzzers/docs/SETUP.md) covers what else a fresh
clone does not give you: the prjxray C++ tools, the Python environment, and
Vivado.

## What is actually in here

### `xray-db-local/` — the database overlay

163 real files among 553 symlinks. The real ones are the work:

* **`spartan7/xc7s25/`** — `tilegrid.json`, `tileconn.json`, `node_wires.json`
* **`spartan7/xc7s25csga324-1/`** — `part.yaml`, `part.json`, `package_pins.csv`
* **`spartan7/mapping/`** — a real copy rather than a link, because xc7s25 has
  to be registered in both `parts.yaml` and `devices.yaml` for
  `create_environment.py` to resolve it
* **`zynq7/xc7z007sclg400-1/`** — the same treatment for the Blackboard's part

Those six xc7s25 artefacts are exactly the list `XC7S25.md` opens by saying is
missing upstream. Segbits are not among them and did not need to be: they are
family-level and shared across the Series-7 tile types, which
`010-clb-lutinit` demonstrated by reproducing identical `LUT.INIT` bits on all
seven devices.

### `rw-fuzzers/` — the RapidWright port

What moves to RapidWright is the per-variant Tcl: permuting a placed design N
ways and recording what each permutation set. `write_bitstream` cannot move —
RapidWright has no bitstream generator — so Vivado shrinks to
`open_checkpoint; write_bitstream`. Everything downstream of the bitstream is
stock prjxray, left alone on purpose: that pipeline *is* the X-Ray database, so
this plugs into it rather than reimplementing it.

A second class of fuzzer (`072-ordered_wires`, `074-dump_all`, `071-ppips`, the
PIP fuzzers) never writes a bitstream at all — it only queries Vivado for
tiles, wires, nodes and PIPs — and can move to RapidWright entirely, since the
device model holds the same information offline. See
[`docs/PORTING.md`](rw-fuzzers/docs/PORTING.md).

Ten Series-7 configurations are defined (one of which, `kintex7_160t`, cannot
run — the fuzzer README says why), selected by prjxray settings-file name. `env/xray_env.sh` restates no part definition: it lifts the `XRAY_*`
exports straight out of `prjxray/settings/<config>.sh`, so parts and paths
cannot drift from upstream's.

```bash
source env/xray_env.sh spartan7_s25
fuzzers/010-clb-lutinit/run.sh all spartan7_s25   # one device
./run_all.sh 010-clb-lutinit all                  # every device, with a table
```

### `wasm-build/` — the browser toolchain

Two WASI builds, plus the toolchain files and the `__cxa_*` stubs both need.

The constraint that shapes both: **jco refuses to transpile a module using the
WebAssembly exception-handling proposal**, and jco is the route to the browser.
wasi-sdk 34 offers an `eh/` multilib whose sysroot defines the C++ exception
runtime, but building against it emits exactly the proposal jco rejects. So
both build without exception handling and link `wasi_throw_stubs.cc` to satisfy
the linker.

* `build_nextpnr_xilinx_wasm.sh` — nextpnr-himbaechel with the xilinx uarch,
  following YoWASP's recipe but from our own nextpnr commit, because Himbaechel
  checks the chipdb against the binary and YoWASP's pin has neither the
  Spartan-7 part-name parsing nor xc7s25 in its device list.
* `build_xc7frames2bit_wasm.sh` — prjxray's `xc7frames2bit`. Needs no
  Boost/Eigen stage since prjxray vendors its dependencies, but does need three
  flags the script's header explains at length: `-Wno-deprecated-builtins` (a
  vendored abseil header breaks 14 objects under clang 23, and plain
  `-Wno-error` loses to prjxray's own `add_compile_options(-Wall -Werror)`),
  `-D_WASI_EMULATED_MMAN` (`memory_mapped_file.cc`), and `-DGLOB_TILDE=0`
  (`database.cc` globs `segbits_*.db`; wasi-libc has `glob()` but not the GNU
  tilde flag).

### `bitstreams/` — designs built without Vivado place-and-route

Sources and constraints for parts taken end to end through
`yosys → nextpnr-himbaechel → fasm2frames → xc7frames2bit`, with Vivado not
involved in producing the bitstream at all. [`bitstreams/README.md`](bitstreams/README.md)
has the per-part detail, including which parts needed a new nextpnr die alias
and a hand-made `part.yaml` and which did not.

**Nothing in here has been verified on hardware.** The bitstreams are
structurally valid and carry the correct IDCODE, and they parse cleanly back
through `bitread`, but "it configures and blinks" is unproven.

## Status

The xc7s25 database is produced and is what the browser flow reads. Both WASI
builds work; `xc7frames2bit`'s configuration payload has been checked against
the native tool's on the same FASM and is byte-identical. The hardware claim
above is the one thing outstanding.

[prjxray]: https://github.com/f4pga/prjxray
[rapidwright]: https://github.com/Xilinx/RapidWright
