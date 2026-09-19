#!/usr/bin/env python3
"""Derive a part's ignored_wires.txt from fuzzer 074's error_nodes.json.

074's generate_grid.py and check_nodes.py both end by rebuilding every node
from tileconn and comparing against what Vivado reported. A residue of
disagreements is normal and upstream handles it with a per-part whitelist in
fuzzers/074-dump_all/ignored_wires/<family>/<part>_ignored_wires.txt. There is
no file for xc7s25csga324-1 because nobody has characterised the part before,
so every disagreement is reported: 474 of them on the first run.

They are the standard family. Every whitelist upstream ships is dominated by
the same thing - the clock-capable IO to global-clock path, I2GCLK and CCIO:

    xc7s50fgga484-1    100 of 110      xc7a50tfgg484-1    100 of 110
    xc7z010clg400-1     40 of  44      xc7k160tffg676-2   160 of 176

and on xc7s25 all 48 distinct nodes involved are LIOI_I2GCLK_TOP0 or
RIOI_I2GCLK_TOP0. The 66 wires this produces have the same six families as
upstream's xc7s50 file, in the same proportions, scaled to the smaller die:

    LIOI_I2GCLK_TOP      20  (xc7s50: 30)   CMT_PHASER_UP_DQS_TO_PHASER_D    3  (5)
    LIOI_I2GCLK_BOT      20  (        30)   CMT_PHASER_DOWN_DQS_TO_PHASER_A  3  (5)
    RIOI_I2GCLK_TOP      10  (        20)
    RIOI_I2GCLK_BOT      10  (        20)

What makes them ignorable rather than merely common is the shape, and
prjxray.lib.check_errors is strict about it: for each disagreeing node it takes
the largest reconstruction as correct and asserts every other one is a *single*
stranded wire. Anything bigger - a node genuinely split in two - trips that
assert and no whitelist can silence it. So this only ever emits wires that are
individually stranded, which is the same set check_errors will look for.

    env/gen_ignored_wires.py <error_nodes.json> [output.txt]

With no output path it prints to stdout, which is the way to look before
writing.
"""
import collections
import json
import sys


def stranded_wires(flat_error_nodes):
    """The single wires check_errors() will demand are whitelisted."""
    by_node = collections.defaultdict(set)
    for node, _raw, generated in flat_error_nodes:
        by_node[node].add(tuple(sorted(generated)))

    wires, refused = set(), []
    for node, generated_nodes in by_node.items():
        good = max(generated_nodes, key=len)
        for bad in generated_nodes - {good}:
            if len(bad) == 1:
                wires.add(bad[0])
            else:
                # check_errors asserts this cannot happen; if it does, the node
                # is really split and whitelisting would be hiding a bug.
                refused.append((node, bad))
    return wires, refused


def main(argv):
    if not 2 <= len(argv) <= 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    with open(argv[1]) as f:
        errors = json.load(f)

    wires, refused = stranded_wires(errors)
    if refused:
        print(f"{len(refused)} node(s) are split into multiple wires, not "
              f"stranded singles - NOT ignorable, look at these:", file=sys.stderr)
        for node, bad in refused[:5]:
            print(f"    {node}\n        {bad}", file=sys.stderr)
        return 3

    fams = collections.Counter(w.split("/", 1)[1] for w in wires)
    print(f"# {len(wires)} stranded wires from {len(errors)} error entries",
          file=sys.stderr)
    for name, n in fams.most_common():
        print(f"#     {name:50s} {n}", file=sys.stderr)

    out = "".join(w + "\n" for w in sorted(wires))
    if len(argv) == 3:
        with open(argv[2], "w") as f:
            f.write(out)
        print(f"wrote {argv[2]}", file=sys.stderr)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
