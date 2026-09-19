#!/usr/bin/env python3
"""Normalise a tilegrid.json's site types against fuzzer 074's own view.

Fuzzer 074's generate_grid.py rebuilds the tilegrid from its Vivado dumps and
asserts it equals the one 005-tilegrid produced. On xc7s25 that assertion kept
firing, one site at a time, always the same shape:

    BRAM_L_X6Y45      RAMB36_X0Y9   ours RAMB36E1   074 RAMBFIFO36E1
    CLK_BUFG_BOT_R... BUFGCTRL_X0Y0 ours BUFG       074 BUFGCTRL

A Series-7 site can have several possible SITE_TYPEs, and Vivado reports
whichever is currently selected. 005 picks up whatever selection its design
happened to leave, so its output is internally inconsistent - 8 of 45 RAMB36
sites, 3 of 32 BUFGCTRL sites - which is the tell that ours is the wrong one.
074 dumps the die separately and is uniform, as is every shipped prjxray-db
tilegrid, as is nextpnr's metadata (it ships site_type_RAMBFIFO36E1.json and
site_type_BUFGCTRL.json, and nothing for the alternates).

That last point is why this matters: read_tile_type_json() returns None for a
site type it has no metadata for, silently, so an affected tile comes out with
no site at all.

Rather than fix them one assertion at a time, this regenerates 074's tilegrid -
the same generate_tilegrid() call generate_grid.py makes, about half a minute -
and reports every difference. It rewrites only the 'sites' values, because that
is the field with a known cause and a known right answer; a difference in any
other field is printed and left alone, because it would mean something else is
wrong and should be looked at rather than papered over.

    env/sync_tilegrid_sites.py <074-root_dir> <tilegrid.json> [--check]

e.g. env/sync_tilegrid_sites.py \\
         prjxray/fuzzers/074-dump_all/build_xc7s25csga324-1/specimen_001 \\
         xray-db-local/spartan7/xc7s25/tilegrid.json
"""
import json
import multiprocessing
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "..", "prjxray", "fuzzers", "074-dump_all"))
import generate_grid  # noqa: E402
from prjxray import lib  # noqa: E402


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    check_only = "--check" in argv
    if len(args) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root_dir, grid_path = args

    with open(grid_path) as f:
        ours = json.load(f)

    tiles, _ = lib.read_root_csv(root_dir)
    pool = multiprocessing.Pool(processes=min(multiprocessing.cpu_count(), 6))
    theirs, _ = generate_grid.generate_tilegrid(pool, tiles)

    only_ours = set(ours) - set(theirs)
    only_theirs = set(theirs) - set(ours)
    if only_ours or only_theirs:
        print(f"tile sets differ: {len(only_ours)} only ours, "
              f"{len(only_theirs)} only 074's", file=sys.stderr)
        return 3

    site_fixes, other = [], []
    for tile in sorted(ours):
        for k, want in theirs[tile].items():
            if k == "ignored" or (k == "sites" and theirs[tile].get("ignored")):
                continue
            have = ours[tile].get(k)
            if have == want:
                continue
            if k == "sites":
                for site in sorted(set(have or {}) | set(want or {})):
                    a, b = (have or {}).get(site), (want or {}).get(site)
                    if a != b:
                        site_fixes.append((tile, site, a, b))
            else:
                other.append((tile, k, have, want))

    by_change = {}
    for tile, site, a, b in site_fixes:
        by_change.setdefault((a, b), []).append((tile, site))
    print(f"site type differences: {len(site_fixes)}")
    for (a, b), items in sorted(by_change.items(), key=lambda kv: str(kv[0])):
        print(f"    {a} -> {b}   x{len(items)}")
        for tile, site in items[:4]:
            print(f"        {tile}  {site}")
        if len(items) > 4:
            print(f"        ... and {len(items) - 4} more")

    if other:
        print(f"\nNON-site differences: {len(other)} - NOT changed, look at these")
        for tile, k, have, want in other[:10]:
            print(f"    {tile}  {k}\n        ours: {have}\n        074:  {want}")
        return 4

    if not site_fixes:
        print("nothing to do")
        return 0
    if check_only:
        return 1

    for tile, site, _, b in site_fixes:
        if b is None:
            del ours[tile]["sites"][site]
        else:
            ours[tile].setdefault("sites", {})[site] = b
    # indent=4, sort_keys=False, trailing newline reproduces prjxray's own
    # output byte for byte, so the only diff is the values meant to change.
    with open(grid_path, "w") as f:
        json.dump(ours, f, indent=4)
        f.write("\n")
    print(f"\nrewrote {len(site_fixes)} site types in {grid_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
