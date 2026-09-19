#!/bin/bash
# Generate prjxray's settings/<family>/resources.yaml for every Series-7 part
# this tree targets.
#
# The file is gitignored and absent from a fresh clone, and settings/<fam>.sh
# fails without it. Upstream's utils/update_resources.py would regenerate it,
# but it loops over every part in the database (hundreds) and needs a Linux
# Vivado. This does the same query for just the parts we use.
#
# Note prjxray's set_part_resources() opens the file "w+", so a per-part run
# would clobber the family file; parts are therefore collected per family and
# written once.
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
XRAY_DIR="$( dirname "$RWF_DIR" )/prjxray"
WORK="${RWF_DIR}/work/resources"
mkdir -p "$WORK"

# family:part, matching the settings/*.sh files.
PARTS="
artix7:xc7a50tfgg484-1
artix7:xc7a100tfgg676-1
artix7:xc7a200tffg1156-1
kintex7:xc7k70tfbg676-2
kintex7:xc7k160tffg676-2
spartan7:xc7s50fgga484-1
spartan7:xc7s25csga324-1
zynq7:xc7z010clg400-1
zynq7:xc7z007sclg400-1
zynq7:xc7z020clg484-1
"

cd "$WORK"
for entry in $PARTS; do
    fam="${entry%%:*}"
    part="${entry##*:}"
    out="${WORK}/${fam}__${part}.json"
    if [ -s "$out" ]; then
        echo "  $part: cached"
        continue
    fi
    echo "== $fam / $part =="
    # link_design fails fast if the part is not installed in this Vivado.
    if XRAY_PART="$part" TMP_FILE="$out" \
       "${RWF_DIR}/env/vivado.sh" -mode batch \
       -source "${XRAY_DIR}/utils/update_resources.tcl" > "${fam}__${part}.log" 2>&1; then
        [ -s "$out" ] && echo "   ok" || echo "   FAILED: no output (see ${fam}__${part}.log)"
    else
        echo "   FAILED: vivado error (see ${fam}__${part}.log)"
    fi
done

echo "== merging into settings/<family>/resources.yaml =="
"${XRAY_DIR}/env/bin/python" - "$WORK" "$XRAY_DIR" <<'PY'
import glob, json, os, sys
work, xray_dir = sys.argv[1], sys.argv[2]
import yaml

by_family = {}
for path in sorted(glob.glob(os.path.join(work, '*__*.json'))):
    base = os.path.basename(path)[:-len('.json')]
    fam, part = base.split('__', 1)
    try:
        data = json.load(open(path))
    except Exception as e:
        print("  skip %s: %s" % (part, e))
        continue
    clk = data['clk_pins'].split()
    dat = data['data_pins'].split()
    if not clk or not dat:
        print("  skip %s: empty pin list" % part)
        continue
    # Same selection as utils/update_resources.py.
    pins = {0: clk[0], 1: dat[0], 2: dat[int(len(dat) / 2)], 3: dat[-1]}
    by_family.setdefault(fam, {})[part] = {'pins': pins}

for fam, info in by_family.items():
    d = os.path.join(xray_dir, 'settings', fam)
    os.makedirs(d, exist_ok=True)
    out = os.path.join(d, 'resources.yaml')
    # Preserve entries for parts not regenerated here.
    if os.path.exists(out):
        existing = yaml.safe_load(open(out)) or {}
        existing.update(info)
        info = existing
    yaml.dump(info, open(out, 'w'))
    print("  %s: %d parts -> %s" % (fam, len(info), out))
PY
