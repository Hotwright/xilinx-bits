#!/usr/bin/env python3
"""Compare segbits produced here against the published prjxray-db.

The two use different tag spellings. segmaker emits the normalised form
(CLBLL_L -> CLB, SLICEL_X0 -> SLICE_X0); the published database holds the
expanded form because mergedb.sh rewrites the tags on the way in - see the
"s/^CLB\\.SLICE_X0\\./CLBLL_L.SLICEL_X0./" rules in utils/mergedb.sh. Both sides
are reduced to a common form here so segbits can be compared before that merge
step; the bit position - "32_15" and friends - is what actually has to match.

After running mergedb the tags are already in the expanded form, so the output
database can be diffed against prjxray-db directly with no normalisation at
all; run.sh's pushdb step does exactly that.

usage: compare.py <ours.db> <reference.db> [tag-substring-filter]
"""
import re
import sys


def normalise(tag):
    """Reduce a tag to <sitekey>.<element>, with SLICEL/SLICEM folded away."""
    # Drop the leading tile type: CLB.SLICE_X0.ALUT... / CLBLL_L.SLICEL_X0.ALUT...
    parts = tag.split('.')
    if len(parts) > 2:
        parts = parts[1:]
    tag = '.'.join(parts)
    tag = re.sub(r'^SLICE[LM]_X', 'SLICE_X', tag)
    return tag


def load(path, keep=None):
    bits = {}
    with open(path) as f:
        for line in f:
            line = line.split()
            if len(line) < 2:
                continue
            tag, value = line[0], ' '.join(sorted(line[1:]))
            if keep and keep not in tag:
                continue
            bits[normalise(tag)] = value
    return bits


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    ours = load(sys.argv[1], sys.argv[3] if len(sys.argv) > 3 else None)
    ref = load(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)

    common = sorted(set(ours) & set(ref))
    only_ours = sorted(set(ours) - set(ref))
    only_ref = sorted(set(ref) - set(ours))

    agree = [t for t in common if ours[t] == ref[t]]
    differ = [t for t in common if ours[t] != ref[t]]

    print(f"ours:      {len(ours)} tags")
    print(f"reference: {len(ref)} tags")
    print(f"in both:   {len(common)}  agree: {len(agree)}  DIFFER: {len(differ)}")
    print(f"only ours: {len(only_ours)}   only reference: {len(only_ref)}")

    for t in differ[:20]:
        print(f"  DIFFER {t}: ours={ours[t]} ref={ref[t]}")
    for t in only_ours[:10]:
        print(f"  only ours: {t} = {ours[t]}")
    for t in only_ref[:10]:
        print(f"  only ref:  {t} = {ref[t]}")

    # Non-zero exit when a tag present on both sides disagrees.
    return 1 if differ else 0


if __name__ == '__main__':
    sys.exit(main())
