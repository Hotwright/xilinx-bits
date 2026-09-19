#!/bin/bash
# Run prjxray fuzzers 072-ordered_wires and 074-dump_all for one config.
#
# These two produce the connectivity half of the database: 074 writes
# tileconn.json (per fabric) and tile_type_*.json / site_type_*.json (per
# family), and it cannot run until 072 has dumped ordered wires - 074's
# generate_after_dump.sh reads ../072-ordered_wires/build_${XRAY_PART}/.
# Neither writes a bitstream; they only query Vivado for tiles, wires and nodes.
#
# "make database" only, never "make run" or "make pushdb": 074's pushdb cp's
# tile_type_*.json into ${XRAY_FAMILY_DIR}, and in the xc7s25 overlay those are
# symlinks into the read-only prjxray-db - the copy would write through into the
# reference. Collecting the output into the overlay is push_074.sh's job.
#
# usage: env/run_072_074.sh [config]        (default: spartan7_s25)
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CONFIG="${1:-spartan7_s25}"

source "${RWF_DIR}/env/xray_env.sh" "$CONFIG"

echo "== 072/074 for ${XRAY_PART} (${XRAY_DATABASE}/${XRAY_FABRIC})"
echo "   vivado: $(readlink -f "${XRAY_VIVADO}")"
echo "   db:     ${XRAY_DATABASE_DIR}"

# Vivado instances run in parallel; each is a few GB, and this VM has 31 GB.
export MAX_VIVADO_PROCESS="${MAX_VIVADO_PROCESS:-4}"
export MAX_GRID_CPU="${MAX_GRID_CPU:-6}"

for f in 072-ordered_wires 074-dump_all; do
    echo "== ${f}: make database"
    ( cd "${XRAY_FUZZERS_DIR}/${f}" && make database )
    echo "== ${f}: done"
done

echo "== all done; run env/push_074.sh to collect into the overlay"
