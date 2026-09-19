#!/usr/bin/env python3
"""Derive XRAY_IOI3_TILES from 005-tilegrid's measured output.

XRAY_IOI3_TILES names the IOI3 tiles whose frame address sits one frame higher
than the rest of their column. generate_full.py:propagate_IOI_Y9 then fills them
in from the previous same-type tile, forcing words=4, offset=18.

What the anomaly actually looks like in the data: those tiles are **absent from
the solved tdb altogether**. The fuzzer toggles a bit and looks for it at the
address the column's regular progression predicts; for these tiles it is a frame
away, so segmatch solves nothing and emits no row. They are missing, not wrong.
That is why propagate_IOI_Y9 has to *synthesise* their entry rather than correct
it, and it is why looking for a deviant baseaddr finds nothing - an earlier
version of this script did exactly that and reported a clean bill of health on
data that was missing two tiles.

So the test is a set difference: every IOI3 tile the basicdb knows about, minus
every IOI3 tile the ioi sub-fuzzer managed to solve.

usage: find_ioi3_anomaly.py <basicdb/<fabric>/tilegrid.json> <ioi/build_*/segbits_tilegrid.tdb>
       find_ioi3_anomaly.py <tilegrid_tdb.json>     (post-add_tdb baseaddr check)
"""
import collections
import json
import re
import sys

IOI3_TYPES = ('LIOI3', 'RIOI3', 'RIOI')


def ykey(name):
    m = re.search(r'Y(\d+)$', name)
    return int(m.group(1)) if m else -1


def unsolved_report(grid_fn, tdb_fn):
    db = json.load(open(grid_fn))
    solved = {l.split('.')[0] for l in open(tdb_fn) if l.strip()}

    suspects = []
    for ttype in IOI3_TYPES:
        tiles = {n: t for n, t in db.items() if t.get('type') == ttype}
        if not tiles:
            continue
        missing = sorted((n for n in tiles if n not in solved), key=ykey)
        print("\n## %s: %d tiles, %d solved, %d unsolved"
              % (ttype, len(tiles), len(tiles) - len(missing), len(missing)))
        for n in missing:
            print("   %-20s grid_x=%-4d grid_y=%-4d"
                  % (n, tiles[n]['grid_x'], tiles[n]['grid_y']))
        suspects += missing

    print("\n" + "=" * 70)
    if not suspects:
        print("Every IOI3 tile solved - no anomaly, and nothing for")
        print("XRAY_IOI3_TILES to name. Check that the ioi sub-fuzzer really ran.")
        return
    # One per column is the expected shape; anything else wants a human.
    by_col = collections.Counter(n.split('Y')[0] for n in suspects)
    if any(c != 1 for c in by_col.values()):
        print("WARNING: expected exactly one unsolved tile per IOI3 column,")
        print("         got %s - inspect before trusting this."
              % dict(by_col))
    print('export XRAY_IOI3_TILES="%s"' % " ".join(suspects))


def baseaddr_report(fn):
    """Post-add_tdb sanity check: within one (type, grid_x, region) group an
    IOI column shares a base address. Region is bits 22:17 of the frame address
    - the top/bottom half bit plus the clock-region row - because one physical
    column spans several regions with different bases."""
    db = json.load(open(fn))
    groups = collections.defaultdict(list)
    for name, tile in db.items():
        if tile.get('type') not in IOI3_TYPES:
            continue
        bits = tile.get('bits', {}).get('CLB_IO_CLK')
        if not bits or 'baseaddr' not in bits:
            continue
        base = int(bits['baseaddr'], 16)
        groups[(tile['type'], tile['grid_x'], (base >> 17) & 0x3F)].append(
            (tile['grid_y'], name, base, bits))

    odd = []
    for (ttype, gx, region), tiles in sorted(groups.items()):
        counts = collections.Counter(b for _, _, b, _ in tiles)
        majority, n = counts.most_common(1)[0]
        print("## %s grid_x=%d region=0x%02x  %d tiles, majority 0x%08x (%d)"
              % (ttype, gx, region, len(tiles), majority, n))
        for gy, name, base, bits in sorted(tiles, key=lambda t: -t[0]):
            if base != majority:
                print("   %-20s base=0x%08x  <== %+d off the column"
                      % (name, base, base - majority))
                odd.append(name)
    print("\n" + "=" * 70)
    print("baseaddr outliers: %s" % (" ".join(odd) if odd else "none"))


def main():
    if len(sys.argv) == 3:
        unsolved_report(sys.argv[1], sys.argv[2])
    elif len(sys.argv) == 2:
        baseaddr_report(sys.argv[1])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
