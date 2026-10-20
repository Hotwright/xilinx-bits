#!/bin/bash
# Characterise one Series-7 die end to end, one stage at a time, with markers
# so an interrupted run resumes where it left off.
#
# The die is identified by its settings file (config), exactly like
# env/xray_env.sh uses them. Everything runs against the writable overlay
# (xray-db-local), never prjxray-db.
#
# Stages, each marked done by a file in work/campaign/<config>/:
#   001   - 001-part-yaml -> part.yaml/part.json in the overlay part dir
#   005   - 005-tilegrid -> <fabric>/tilegrid.json
#   072   - 072-ordered_wires (prerequisite of 074)
#   074   - 074-dump_all -> tileconn.json, node_wires.json, tile/site-type JSONs
#   finish - finish_074.sh (push/cover/chipdb; bitstream only where a board
#            flow exists, i.e. xc7s25/xc7s50)
#
# The campaign needs a working Vivado. Linux 2026.1.1 on this machine currently
# has a dead license (WSL MAC rotated away from the node-locked eval license),
# so the default here is the Windows install via XRAY_VIVADO_LINUX="".
#
# usage: env/campaign_die.sh <config> [stage ...]   (default: all stages)
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CONFIG="${1:?usage: env/campaign_die.sh <config> [stage ...]}"; shift
WANT="${*:-001 005 072 074 finish}"
XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-}"
export XRAY_VIVADO_LINUX

source "${RWF_DIR}/env/xray_env.sh" "$CONFIG"
PART="${XRAY_PART}"; DIE="${XRAY_FABRIC}"; FAM="${XRAY_DATABASE}"
echo "== campaign $CONFIG: $DIE ($PART) via $XRAY_VIVADO_LINUX"
echo "   db: $(readlink -f "${XRAY_DATABASE_DIR}")"

CAMP="${RWF_DIR}/work/campaign/${CONFIG}"
mkdir -p "$CAMP"

stage_done() { [ -f "${CAMP}/$1.done" ]; }
mark_done() { : > "${CAMP}/$1.done"; }

if [[ " $WANT " == *" 001 "* ]] && ! stage_done 001; then
    echo "== 001-part-yaml"
    ( cd "${XRAY_FUZZERS_DIR}/001-part-yaml" && make database && make pushdb )
    mark_done 001
fi

if [[ " $WANT " == *" 005 "* ]] && ! stage_done 005; then
    echo "== 005-tilegrid"
    # cfg cannot run on Vivado newer than 2017.2 (BSCAN JTAG_CHAIN DRC); see
    # rw-fuzzers/docs/XC7S25.md. Without this every die stops at cfg.
    ( cd "${XRAY_FUZZERS_DIR}/005-tilegrid" && SKIP_CFG=1 make database )
    mark_done 005
fi

# Vivado instances run in parallel in 072/074; same limits as run_072_074.sh.
export MAX_VIVADO_PROCESS="${MAX_VIVADO_PROCESS:-4}"
export MAX_GRID_CPU="${MAX_GRID_CPU:-6}"

if [[ " $WANT " == *" 072 "* ]] && ! stage_done 072; then
    echo "== 072-ordered_wires"
    ( cd "${XRAY_FUZZERS_DIR}/072-ordered_wires" && make database )
    mark_done 072
fi

if [[ " $WANT " == *" 074 "* ]] && ! stage_done 074; then
    echo "== 074-dump_all"
    ( cd "${XRAY_FUZZERS_DIR}/074-dump_all" && make database )
    mark_done 074
fi

if [[ " $WANT " == *" finish "* ]] && ! stage_done finish; then
    echo "== finish_074 (push cover chipdb)"
    "${RWF_DIR}/env/finish_074.sh" "$CONFIG" push cover chipdb
    mark_done finish
fi

echo "== campaign $CONFIG: complete"
