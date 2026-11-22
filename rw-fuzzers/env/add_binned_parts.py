#!/usr/bin/env python3
"""Add the parts of a binned die -- one that shares another die's fabric --
to a prjxray database, so nextpnr and fasm2frames can build for them.

A binned die (xc7a15t on xc7a50t, xc7a75t on xc7a100t) needs no chipdb or
tilegrid of its own: env/census.sh showed its tile names, types and grid
positions are the sibling's. What it does need is a part directory per
package and speed grade:

  part.yaml / part.json  the sibling part's, with this die's IDCODE. The frame
                         layout is the fabric's, so it is identical; only the
                         IDCODE differs, as xc7a35t's differs from xc7a50t's.
  package_pins.csv       dumped by Vivado for THIS die (work/binned/dump.tcl,
                         075-pins' format). Never copied: a smaller die can
                         bond out fewer pins in the same package.

The script also checks the method: Vivado's dump of the sibling's package must
reproduce the sibling's package_pins.csv already in the database, or the
dump is not trusted for the new die either.

usage: add_binned_parts.py --die xc7a15t --sibling xc7a50t --family artix7 \\
           --db DIR --dump work/binned --idcode 0x0362e093
"""
import argparse
import json
import os
import re
import sys


def read_rows(path):
    with open(path) as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]
    return lines[0], sorted(lines[1:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--die", required=True)
    ap.add_argument("--sibling", required=True)
    ap.add_argument("--family", required=True)
    ap.add_argument("--db", required=True, help="database root holding <family>/")
    ap.add_argument("--dump", required=True, help="dump.tcl's output directory")
    ap.add_argument("--idcode", required=True)
    args = ap.parse_args()

    fam = os.path.join(args.db, args.family)
    idcode = int(args.idcode, 16)

    # parts.txt: "<part> <package> <speed> <device>", one line per Vivado part.
    parts = []
    with open(os.path.join(args.dump, "parts.txt")) as f:
        for line in f:
            part, pkg, speed, dev = line.split()
            if dev == args.die:
                parts.append((part, pkg, speed.lstrip("-")))
    if not parts:
        sys.exit(f"no {args.die} parts in {args.dump}/parts.txt")

    checked, added, skipped = set(), [], []
    for part, pkg, speed in parts:
        sib = os.path.join(fam, f"{args.sibling}{pkg}-{speed}")
        if not os.path.isdir(sib):
            skipped.append(f"{part}: no sibling part {os.path.basename(sib)} in the database")
            continue

        # Method check, once per package: the dump must match the database.
        if pkg not in checked:
            hdr_db, rows_db = read_rows(os.path.join(sib, "package_pins.csv"))
            hdr_v, rows_v = read_rows(os.path.join(args.dump, f"{args.sibling}{pkg}_package_pins.csv"))
            if (hdr_db, rows_db) != (hdr_v, rows_v):
                sys.exit(f"{args.sibling}{pkg}: Vivado's dump differs from the database's "
                         f"package_pins.csv; not trusting the dump for {args.die}")
            checked.add(pkg)

        dst = os.path.join(fam, part)
        os.makedirs(dst, exist_ok=True)
        with open(os.path.join(sib, "part.yaml")) as f:
            y = f.read()
        y, n = re.subn(r"(?m)^idcode: 0x[0-9a-f]+$", f"idcode: {hex(idcode)}", y)
        if n != 1:
            sys.exit(f"{sib}/part.yaml: expected one idcode line, found {n}")
        with open(os.path.join(dst, "part.yaml"), "w") as f:
            f.write(y)
        # Edited as text, not re-serialised, so the file differs from the
        # sibling's in the one field and nowhere else.
        with open(os.path.join(sib, "part.json")) as f:
            t = f.read()
        t, n = re.subn(r'"idcode": \d+', f'"idcode": {idcode}', t)
        if n != 1 or json.loads(t)["idcode"] != idcode:
            sys.exit(f"{sib}/part.json: expected one idcode field, found {n}")
        with open(os.path.join(dst, "part.json"), "w") as f:
            f.write(t)
        with open(os.path.join(args.dump, f"{args.die}{pkg}_package_pins.csv")) as src, \
             open(os.path.join(dst, "package_pins.csv"), "w") as out:
            out.write(src.read())
        added.append((part, pkg, speed))

    # mapping/parts.yaml and devices.yaml: append what is missing.
    pyaml = os.path.join(fam, "mapping", "parts.yaml")
    with open(pyaml) as f:
        have = f.read()
    with open(pyaml, "a") as f:
        for part, pkg, speed in added:
            if not re.search(rf"(?m)^\"?{part}\"?:", have):
                f.write(f"{part}:\n  device: {args.die}\n  package: {pkg}\n  speedgrade: '{speed}'\n")
    dyaml = os.path.join(fam, "mapping", "devices.yaml")
    with open(dyaml) as f:
        have = f.read()
    if not re.search(rf"(?m)^\"?{args.die}\"?:", have):
        with open(dyaml, "a") as f:
            f.write(f"# {args.die} shares {args.sibling}'s fabric: env/census.sh found the same\n"
                    f"# tile names, types and grid positions (only the IDCODE differs).\n"
                    f"\"{args.die}\":\n  fabric: \"{args.sibling}\"\n")

    print(f"{args.die}: {len(added)} parts added under {fam}")
    for s in skipped:
        print("  skipped", s)


if __name__ == "__main__":
    main()
