#!/usr/bin/env python3
"""Can one die's tileconn.json be reused for another die of the same family?

tileconn.json carries no tile instance names. Each entry is
(tile_types[2], grid_deltas[2]) -> wire_pairs, and nextpnr's apply_tileconn()
indexes it as ttn[typeA][dx, dy][typeB]. So the file is a property of the
family's tile *types*, not of the die, and it is reusable exactly when every
lookup the new die can perform is one the source die also performed.

The probe set is not every adjacency in the grid - only the (dx, dy) registered
for that typeA. A "miss" is a tile of type A whose neighbour at a registered
delta has a type B with no entry. On the die the file was generated from, every
miss is a genuinely unconnected pair, so that die's own misses are the baseline;
anything the new die misses that the source die does not is unexplained, and is
the answer to the question.

    env/check_tileconn_cover.py <src-fabric-dir> <new-fabric-dir> [family-dir]

e.g. env/check_tileconn_cover.py prjxray-db/spartan7/xc7s50 \
                                 xray-db-local/spartan7/xc7s25 \
                                 prjxray-db/spartan7
"""
import collections
import json
import os
import sys


def load_tileconn(path):
    ttn = collections.defaultdict(lambda: collections.defaultdict(dict))
    for e in json.load(open(path)):
        t0, t1 = e["tile_types"]
        ttn[t0][tuple(e["grid_deltas"])][t1] = len(e["wire_pairs"])
    return ttn


def load_grid(path):
    g = json.load(open(path))
    by_xy, types = {}, collections.Counter()
    for d in g.values():
        by_xy[d["grid_x"], d["grid_y"]] = d["type"]
        types[d["type"]] += 1
    return by_xy, types


def probe(by_xy, ttn):
    hit, miss = collections.Counter(), collections.Counter()
    for (x, y), ta in by_xy.items():
        if ta not in ttn:
            continue
        for (dx, dy), nd in ttn[ta].items():
            tb = by_xy.get((x + dx, y + dy))
            if tb is None:
                continue
            (hit if tb in nd else miss)[(ta, tb, dx, dy)] += 1
    return hit, miss


def main(argv):
    if not 3 <= len(argv) <= 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    src, new = argv[1], argv[2]
    family = argv[3] if len(argv) > 3 else os.path.dirname(os.path.abspath(src))

    ttn = load_tileconn(os.path.join(src, "tileconn.json"))
    src_xy, _ = load_grid(os.path.join(src, "tilegrid.json"))
    new_xy, new_types = load_grid(os.path.join(new, "tilegrid.json"))

    h_src, m_src = probe(src_xy, ttn)
    h_new, m_new = probe(new_xy, ttn)
    print(f"connections applied: {os.path.basename(new)} {sum(h_new.values())}, "
          f"{os.path.basename(src)} {sum(h_src.values())}")

    risk = collections.Counter({k: v for k, v in m_new.items() if k not in m_src})
    print(f"\nunexplained misses: {len(risk)}")
    for k, n in sorted(risk.items()):
        print(f"    {k}  x{n}")

    # A tile type with no tile_type_<T>.json is worse than a missing tileconn
    # entry: nextpnr's read_tile_type_json() returns None for it silently, so
    # the tile ends up with no wires at all and nothing is reported.
    missing = [t for t in sorted(new_types)
               if not os.path.exists(os.path.join(family, f"tile_type_{t}.json"))]
    print(f"\ntile types with no tile_type_<T>.json: {len(missing)}")
    for t in missing:
        print(f"    {t}  x{new_types[t]}")

    return 0 if not risk and not missing else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
