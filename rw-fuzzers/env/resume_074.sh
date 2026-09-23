#!/bin/bash
# Resume fuzzer 074-dump_all's post-dump pipeline WITHOUT re-running it.
#
# *** Never re-run generate_after_dump.sh to recover from a failure. ***
# Its third line is
#     rm -rf ${BUILD_DIR}/output
# so it starts by destroying everything the previous run produced - on xc7s25
# that is ~6 hours: nodes.db (285 MB), nodes.pickle (154 MB), node_tree.json
# (313 MB), 111 tile_type_*.json and 39 site_type_*.json. It is also `set -e`,
# so a failure in the middle leaves all of that intact and only the failing
# step needs redoing. This script redoes exactly the remaining steps, with the
# same arguments the wrapper uses.
#
# The steps, in order, and what each needs from the one before:
#   reduce_tile_types.py  -> tile_type_*.json, nodes.db          [done]
#   create_node_tree.py   -> node_tree.json, nodes.pickle        [done]
#   reduce_site_types.py  -> site_type_*.json                    [done]
#   generate_grid.py      -> tileconn.json      <- restarts here by default
#   node_names.py         -> node_wires.json
#   check_nodes.py        -> validation only, writes nothing
#
# generate_grid.py rebuilds the tilegrid from 074's own dumps and asserts it
# against 005-tilegrid's. On xc7s25 that caught a real defect in ours - see
# env/fix_ramb36_site_type.py - so a failure there is a finding, not noise.
#
# usage: env/resume_074_s25.sh [first-step]     (default: generate_grid)
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FROM="${1:-generate_grid}"

source "${RWF_DIR}/env/xray_env.sh" spartan7_s25 > /dev/null
cd "${XRAY_FUZZERS_DIR}/074-dump_all"

BUILD_DIR="build_${XRAY_PART}"
OUT="${BUILD_DIR}/output"
[ -d "$OUT" ] || { echo "resume_074_s25.sh: no ${OUT} - nothing to resume" >&2; exit 1; }
# If these are missing the earlier steps did not finish and resuming is wrong.
for f in node_tree.json nodes.pickle; do
    [ -f "${OUT}/${f}" ] || {
        echo "resume_074_s25.sh: ${OUT}/${f} missing - earlier steps did not complete" >&2
        exit 1; }
done
echo "== resuming from ${FROM}"
echo "   ${OUT}: $(ls "${OUT}"/tile_type_*.json 2>/dev/null | grep -vc site_type) tile types," \
     "$(ls "${OUT}"/site_type_*.json 2>/dev/null | wc -l) site types"

# There is no ignored_wires file for this part (upstream ships one only for
# xc7s50fgga484-1). Both consumers guard with os.path.exists, so the effect is
# an empty ignore set - nothing is suppressed, which is what a new die wants.
IGNORED="ignored_wires/${XRAY_DATABASE}/${XRAY_PART}_ignored_wires.txt"
CPU="${MAX_GRID_CPU:-6}"

want() {
    case "$FROM" in
        generate_grid) return 0 ;;
        node_names)    [ "$1" != generate_grid ] ;;
        check_nodes)   [ "$1" = check_nodes ] ;;
        *) echo "resume_074_s25.sh: unknown step '$FROM'" >&2; exit 1 ;;
    esac
}

if want generate_grid; then
    echo "== generate_grid.py"
    python3 generate_grid.py \
        --root_dir "${BUILD_DIR}/specimen_001/" \
        --output_dir "$OUT" \
        --ignored_wires "$IGNORED" \
        --max_cpu="$CPU"
fi

if want node_names; then
    echo "== node_names.py"
    python3 node_names.py \
        --root_dir "${BUILD_DIR}/specimen_001/" \
        --output_dir "${OUT}/" \
        --max_cpu="$CPU"
fi

if want check_nodes; then
    echo "== check_nodes.py"
    python3 check_nodes.py \
        --root_dir "${BUILD_DIR}/specimen_001/" \
        --output_dir "${OUT}/" \
        --ignored_wires "$IGNORED" \
        --max_cpu="$CPU"
fi

echo "== resume_074_s25: done"
ls -la "${OUT}/tileconn.json" "${OUT}/node_wires.json" 2>/dev/null || true
