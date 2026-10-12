#!/usr/bin/env python3
"""Cluster censused dies by fabric signature: which need their own chipdb?

Two dies share a fabric when every tile matches in name, type and grid
position - the comparison that established xc7z007s -> xc7z010 and
xc7a35t -> xc7a50t. Where they match, one chipdb serves both and the second
die costs a part.yaml and an alias line instead of a day of fuzzing.

Tile and node counts alone are suggestive, not sufficient: two dies can have
the same totals and a different arrangement. So the cluster key is a hash of
the whole sorted tile list, and the counts are only reported alongside it.

    env/census_report.py [census-dir]
"""
import hashlib
import os
import sys


def main(argv):
    root = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "work", "census")

    rows, errs = [], []
    for die in sorted(os.listdir(root)):
        d = os.path.join(root, die)
        if os.path.exists(os.path.join(d, "ERROR")):
            errs.append((die, open(os.path.join(d, "ERROR")).read().strip()))
            continue
        if not os.path.exists(os.path.join(d, "DONE")):
            continue
        part = dict(l.split(None, 1) for l in
                    open(os.path.join(d, "part.txt")).read().splitlines() if l.strip())
        ext = dict(l.split(None, 1) for l in
                   open(os.path.join(d, "extents.txt")).read().splitlines() if l.strip())
        tiles = open(os.path.join(d, "tiles.txt"), "rb").read()
        rows.append({
            "die": die,
            "family": part.get("family", "?").strip(),
            "idcode": part.get("idcode", "?").strip(),
            "tiles": int(ext.get("tiles", 0)),
            "nodes": int(ext.get("nodes", 0)),
            "sig": hashlib.sha256(tiles).hexdigest()[:12],
        })

    groups = {}
    for r in rows:
        groups.setdefault(r["sig"], []).append(r)

    print(f"{len(rows)} dies censused, {len(groups)} distinct fabrics\n")
    print(f"{'fabric':<14}{'dies':<34}{'family':<11}{'tiles':>8}{'nodes':>10}")
    print("-" * 78)
    for sig, g in sorted(groups.items(), key=lambda kv: kv[1][0]["tiles"]):
        dies = " ".join(r["die"] for r in sorted(g, key=lambda r: r["die"]))
        r = g[0]
        fams = sorted({x["family"] for x in g})
        print(f"{sig:<14}{dies:<34}{('/'.join(fams)):<11}{r['tiles']:>8}{r['nodes']:>10}")
        if len(g) > 1:
            # Family is per DIE, not per fabric: xc7a12t is artix7 and xc7s25 is
            # spartan7 yet they are the same silicon. prjxray files a part under
            # its own family, so a shared fabric can still mean two family dirs.
            for r2 in sorted(g, key=lambda r: r["die"]):
                print(f"{'':14}  {r2['die']:<12} {r2['family']:<10} idcode {r2['idcode']}")

    if errs:
        print(f"\n{len(errs)} unavailable:")
        for die, why in errs:
            print(f"    {die:<12} {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
