# Bringing up a new Series-7 part

Three parts have been brought up in this tree, and they sit at three very
different points on the effort curve. The pattern is worth stating, because the
first question for any new part is *which of these is it?*

| part | die | what was missing | work |
| --- | --- | --- | --- |
| `xc7s50csga324-1` | xc7s50 | nothing | build a chipdb |
| `xc7z007sclg400-1` | xc7z010 (shared) | part identity only | one Vivado run |
| `xc7s25csga324-1` | xc7s25 | the entire fabric | the whole fuzzer chain |

All three now build a bitstream with **no vendor place and route** —
yosys → nextpnr-himbaechel(xilinx) → FASM → `fasm2frames` → `xc7frames2bit` —
and all three round trip back through `bitread`:

| part | frames | IDCODE | design |
| --- | --- | --- | --- |
| xc7s25csga324-1 | 3060 | `0x037c4093` | `bitstreams/build_arty_s7.sh 25` |
| xc7s50csga324-1 | 5408 | `0x0362f093` | `bitstreams/build_arty_s7.sh 50` |
| xc7z007sclg400-1 | 5144 | `0x03723093` | `bitstreams/build_blackboard_z007s.sh` |

**None of these has been loaded onto a board.** They are structurally valid and
carry the correct IDCODE; "it configures and blinks" is unproven.

All three also run through the **WebAssembly** nextpnr in
`hotc/web/nextpnr-xilinx-wasm/`, off one 2.3 MB module plus the three chipdbs —
xc7z007s through the `xc7z010` alias. `make check` places and routes each in a
couple of seconds; `make diff` holds each against the native binary on ten
invariants, including an identical post-PnR netlist and a bitstream built from
the WASM FASM. See `docs/XC7S25.md` for why the criterion is the netlist and not
the FASM.

## xc7s50 — nothing was missing

`prjxray-db` ships the complete `spartan7/xc7s50` fabric (`tilegrid.json`,
`tileconn.json`, `node_wires.json`), every part's `part.yaml` and
`package_pins.csv`, and all 112 of its tile types have a family-level
`tile_type_<T>.json`. `xc7s50` was already in nextpnr's
`ALL_HIMBAECHEL_XILINX_DEVICES`. So the entire job was to generate the chipdb
(116 MB `.bba` → 28 MB `.bin`, 5232 unique tile routing shapes) and point the
flow at it. No overlay is involved: the database is read straight from the
read-only reference.

Digilent's Arty-S7-25 and Arty-S7-50 master XDCs put the clock, the four LEDs
and BTN0 on the same balls, which is why `bitstreams/build_arty_s7.sh` takes the
die as an argument and shares one `arty_s7.xdc` between them. That was checked
against both master XDCs, not assumed.

## xc7z007s — the die already existed

The single-core Zynq Z-7007S shares its PL die with the Z-7010. nextpnr already
encodes that as a die alias in `himbaechel/uarch/xilinx/xilinx.cc`, so it loads
`chipdb-xc7z010.bin` and needs no chipdb of its own. What prjxray lacked was the
*part*: no `mapping` entry, no `part.yaml`, no `package_pins.csv`.

Two independent checks confirmed the aliasing is safe to rely on:

* `package_pins.csv` generated for `xc7z007sclg400-1` came out **byte-identical**
  to the shipped `xc7z010clg400-1` one — same die, same package, from Vivado's
  own database.
* `part.json` from `001-part-yaml` differs from xc7z010's in **exactly one
  field**: `idcode`. The frame layout is the same.

That one field is the whole point. **A bitstream built through the alias must be
handed the xc7z007s `part.yaml`** (`0x3723093`), not xc7z010's (`0x3722093`), or
the real device rejects it. nextpnr and the chipdb both believe they are
targeting a Z-7010; only `xc7frames2bit` knows better.

The `part.yaml` produced by this run is byte-identical to one derived in an
earlier session by a different route, which is a useful independent agreement.

Registered in the overlay rather than the reference:
`zynq7/mapping/devices.yaml` maps device `xc7z007s` to **fabric `xc7z010`**, so
it reads that die's tilegrid; `parts.yaml` maps the part to that device.

## xc7s25 — everything was missing

See `XC7S25.md`. That is the long one.

## A trap in the overlay, found the hard way

`env/mk_db_overlay.sh` builds the writable overlay as symlinks back into the
read-only `prjxray-db`, with real directories only where a new part must write.
Promoting a family from *symlinked whole* to *overlaid entry-by-entry* — which
is exactly what adding xc7z007s did to `zynq7` — leaves last run's symlink at
`xray-db-local/zynq7`. `mkdir -p` on a symlink to a directory **succeeds
silently**, and every `ln`/`cp` in the loop then resolves *through* it and
rewrites the reference in place. It replaced 325 files in `prjxray-db/zynq7`
with symlinks before anything noticed.

Everything was recoverable (`git checkout`), and the script now:

* clears a stale symlink before `mkdir`, as the real-part-directory loop already
  did — the hazard was known, the guard was just in the wrong place;
* asserts at the end that no overlay family resolves to the reference;
* asserts that `git status` in `prjxray-db` is clean, and refuses to finish if
  it is not.

The lesson generalises past this script: **the read-only rule is not enforced by
intent, it is enforced by checking.** Every push path in this tree now verifies
the reference afterwards.
