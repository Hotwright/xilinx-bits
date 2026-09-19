# Porting the rest of the fuzzers

prjxray has 93 fuzzer directories. They are not equally worth porting, and they
do not all port the same way. Three shapes, in descending order of payoff.

## Tier 1 — Vivado disappears entirely

Nine fuzzers never call `write_bitstream`. They start Vivado purely to ask the
device model questions, and RapidWright answers the same questions offline:

| Vivado Tcl | RapidWright |
| --- | --- |
| `get_tiles` | `Device.getAllTiles()`, `Device.getTile()` |
| `get_wires` | `Tile.getWireNames()` |
| `get_nodes` | `Tile.getNode()`, `Node` |
| `get_pips` | `Tile.getPIPs()` |
| `get_sites` | `Tile.getSites()`, `Device.getAllSites()` |
| `get_site_pins` | `SitePin` |
| `get_package_pins` | `Package`, `PackagePin` |
| `get_speed_models` | **no direct equivalent** |

The fuzzers:

* **`074-dump_all`** — the single biggest win. It dumps every tile, node, wire
  and PIP to JSON5 and is the longest-running fuzzer in prjxray; upstream shards
  it across parallel Vivado invocations to make it bearable. RapidWright reads
  the same data from its device file with no Vivado process at all. Caveat: its
  `get_speed_model.tcl` step queries timing models, which has no clean
  RapidWright equivalent — port the tile/node/wire/PIP dump and leave the timing
  query on Vivado.
* **`072-ordered_wires`**, **`073-get_counts`**, **`048-int-piplist`**,
  **`piplist`**, **`049-int-imux-gfan`**, **`075-pins`** — same shape, smaller.
* `000-init-db`, `076-ps7` — bookkeeping and PS7-specific; low value.

These need no base checkpoint, no bitstream, and no validation against a golden
bitstream — just a diff of the emitted database files against `prjxray-db`.
**Start here.** They are also the safest, since the Vivado version question
does not arise at all.

## Tier 2 — same hybrid shape as `010-clb-lutinit`

Vivado builds one placed-and-routed base checkpoint; RapidWright permutes cell
properties and emits tag files; Vivado only writes bitstreams. The scaffold in
`fuzzers/010-clb-lutinit` was written to be reused: `LutInitFuzzer` differs from
its siblings only in which property it permutes and which patterns it uses.

Natural next ports, all CLB property permutation on the same base design:

* `011-clb-ffconfig`, `012-clb-n5ffmux`, `014-clb-ffsrcemux`, `015-clb-nffmux`,
  `016-clb-noutmux`, `017-clb-precyinit`, `019-clb-ndi1mux`
* `018-clb-ram` (SLICEM, LUT RAM — INIT permutation like 010)
* `025-bram-config`, `026-bram-data`, `027-bram36-config`, `028-fifo-config`
* `100-dsp-mskpat`

The generalisation is straightforward: replace the hard-coded `LUT6` / `INIT` /
`PATTERNS` with a cell-type filter, a property name and a pattern source.

## Tier 3 — needs RapidWright design construction

The PIP fuzzers (`037-iob-pips`, `041-clk-hrow-pips`, `05x-pip-*`,
`101-dsp-pips`) work by routing specific PIPs and seeing which bits move.
RapidWright is *better* than Tcl at this — it can build a `Net` and assert an
exact PIP list directly, instead of coaxing Vivado's router into using the PIP
you want. But it requires building designs from nothing rather than mutating a
checkpoint, which brings the open questions this milestone deliberately avoided:
DRC on unrouted nets, and correct `LOCK_PINS`-equivalent pin mapping (see
below). High value, but prove design construction on one small case first.

## Tier 4 — leave on Vivado

* `007-timing` — timing models, no RapidWright equivalent.
* `005-tilegrid` — derives frame addresses, needs bitstreams and its own
  `fuzzaddr` machinery. Partially portable at best.
* GTP/GTX, PCIe, PS7, monitor/XADC — vendor IP with little RapidWright leverage.

## Per-device notes

Every port should run through `run_all.sh`, not just the default artix7 part.
Things that differ across the seven supported devices:

* **ROI.** `artix7_200t` defines no `XRAY_ROI` - it characterises the whole
  device. Any Tcl that creates a pblock must guard on the variable being set,
  as `base.tcl` does; otherwise `resize_pblock` fails with an empty range.
* **Pins.** `XRAY_PIN_00..03` come from `settings/<family>/resources.yaml` and
  differ per part. `LVCMOS33` works on all seven because
  `update_resources.tcl` filters data pins to high-range banks; a port that
  picks its own pins on a part with HP banks (kintex7) must do the same or
  constrain the IOSTANDARD accordingly.
* **Reference coverage.** Only devices with a `tilegrid.json` in `prjxray-db`
  can be validated: xc7a50t, xc7a100t, xc7a200t, xc7k70t, xc7s50, xc7z010,
  xc7z020. `xc7k160t` has neither a tilegrid nor a part.yaml, so segmaker
  cannot run for it at all.
* **What is actually device-specific.** For CLB fuzzers, very little: the
  `LUT.INIT` segbits are byte-identical across all four families, because the
  CLB tile is common to Series-7. Running all seven devices is a *flow*
  check. It matters far more for fuzzers whose results genuinely differ per
  device - tilegrid, clocking, IOB - which is most of Tier 1 and Tier 3.

## The pin-mapping trap

`010-clb-lutinit`'s Tcl sets `LOCK_PINS {I0:A1 ... I5:A6}`. This is not
cosmetic. The tags record the *netlist* INIT while the bitstream holds the
*physical* LUT contents; the two agree only because that constraint forces an
identity mapping from logical LUT inputs to physical BEL pins. The hybrid flow
inherits the constraint from the Vivado base checkpoint, which is why bit
positions came out right.

Any Tier 3 port that places cells from scratch must establish the same identity
mapping itself. Get it wrong and every INIT tag is permuted — `segmatch` will
still produce a clean-looking database, and it will be wrong.
