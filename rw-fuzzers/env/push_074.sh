#!/bin/bash
# Collect fuzzer 074-dump_all's output into the writable overlay.
#
# This replaces "make pushdb" in 074's Makefile, which cannot be used here: it
# does
#     cp $(BUILD_DIR)/output/tile_type_*.json ${XRAY_FAMILY_DIR}/
# and in the xc7s25 overlay every family-level file is a symlink into the
# READ-ONLY prjxray-db, so that cp writes straight through into the reference.
# Here each family-level file is unlinked first and replaced with a real file,
# which leaves prjxray-db untouched.
#
# Replacing them rather than keeping the symlinks is deliberate. Upstream's
# spartan7 family data was measured on the xc7s50 die, whereas this was measured
# on the die we are characterising, and the summary below says how far the two
# agree - which is itself the cross-check.
#
# That summary only means anything on the FIRST push. Before it, each dst is a
# symlink into the reference, so the comparison is against upstream; after it,
# dst is the file this script already wrote and everything trivially matches.
# On xc7s25 the first push reported 3 new and 151 identical in content.
#
# Note these are NOT read by only one config any more: build_nextpnr_s25.sh
# builds xc7s50 and xc7z010 against this same overlay, so xc7s50's chipdb now
# reads whatever lands here. That is safe because the comparison is semantic
# (json.load, not cmp) and on xc7s25 all 151 shared files came out identical in
# content - only the 3 MONITOR_*_FUJI2 types are new. If that summary ever
# reports a real content difference, xc7s50 must be built against prjxray-db
# instead, the same distinction bitstreams/build_arty_s7.sh already makes.
#
# usage: env/push_074.sh [config]           (default: spartan7_s25)
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ROOT="$( dirname "$RWF_DIR" )"
CONFIG="${1:-spartan7_s25}"

source "${RWF_DIR}/env/xray_env.sh" "$CONFIG" > /dev/null

REF="${ROOT}/prjxray-db"
OUT="${XRAY_FUZZERS_DIR}/074-dump_all/build_${XRAY_PART}/output"
FAM="${XRAY_FAMILY_DIR}"
FABRIC_DIR="${FAM}/${XRAY_FABRIC}"

[ -d "$OUT" ] || { echo "push_074.sh: no 074 output at $OUT" >&2; exit 1; }
case "$FAM" in
    "$REF"/*) echo "push_074.sh: REFUSING - family dir is inside the read-only $REF" >&2; exit 1 ;;
esac

ref_stamp="$(date +%Y-%m-%dT%H:%M:%S)"

# --- per-fabric files --------------------------------------------------------
mkdir -p "$FABRIC_DIR"
for f in tileconn.json node_wires.json; do
    if [ -f "${OUT}/${f}" ]; then
        # Unlink first, exactly as in the family loop below. These two happen
        # to be real files today, but if either were ever a symlink into the
        # read-only prjxray-db this cp would write through it, and the check at
        # the end of this script would only notice after the damage was done.
        rm -f "${FABRIC_DIR}/${f}"
        cp "${OUT}/${f}" "${FABRIC_DIR}/${f}"
        echo "  ${XRAY_FABRIC}/${f}: $(stat -c%s "${FABRIC_DIR}/${f}") bytes"
    else
        echo "  ${XRAY_FABRIC}/${f}: MISSING from 074 output" >&2
    fi
done

# --- family-level files ------------------------------------------------------
new=0; changed=0; same=0
for src in "${OUT}"/tile_type_*.json "${OUT}"/site_type_*.json; do
    [ -e "$src" ] || continue
    name="$(basename "$src")"
    # 074 leaves per-tile intermediates behind; upstream's pushdb deletes them.
    case "$name" in tile_type_*_site_type_*.json) continue ;; esac
    dst="${FAM}/${name}"
    if [ ! -e "$dst" ]; then
        new=$((new + 1))
    # Compare by CONTENT, not bytes. These are JSON written by different runs,
    # so key order and spacing differ freely; a byte compare called all 147
    # shared files "different" when every one of them was in fact identical.
    elif python3 -c 'import json,sys
sys.exit(0 if json.load(open(sys.argv[1]))==json.load(open(sys.argv[2])) else 1)' \
            "$src" "$dst" 2>/dev/null; then
        same=$((same + 1))
        # Still replace the symlink, so the overlay is self-contained.
    else
        changed=$((changed + 1))
        echo "    content differs from reference: ${name}"
    fi
    # Unlink first: without this, cp follows the symlink into prjxray-db.
    rm -f "$dst"
    cp "$src" "$dst"
done
echo "  family files: ${new} new, ${changed} differ from reference, ${same} identical"

# --- the standing rule -------------------------------------------------------
n="$(find "$REF" -newermt "$ref_stamp" -type f 2>/dev/null | wc -l)"
if [ "$n" -ne 0 ]; then
    echo "push_074.sh: ERROR - ${n} file(s) under $REF were modified" >&2
    exit 1
fi
echo "  prjxray-db untouched: ok"
