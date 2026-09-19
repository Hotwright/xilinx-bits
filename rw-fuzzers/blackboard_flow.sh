#!/bin/bash
# End-to-end open-source flow for the Real Digital Blackboard (XC7Z007S).
#
#   verilog -> yosys -> nextpnr-himbaechel -> FASM -> frames -> .bit
#
# Two things make this work, both verified rather than assumed:
#
#  1. The Z-7007S shares its PL die with the Z-7010. Every tile name, tile
#     type, site name and site type matches position for position, so the
#     xc7z010 chipdb and the xc7z010 frame layout are correct for this part.
#     nextpnr needs a patch to know that (branch blackboard-xc7z007s in
#     eda-tools/nextpnr); without it the part name does not even parse.
#
#  2. The IDCODE does NOT match, and the device checks it during
#     configuration. Frames are generated against xc7z010 but the bitstream
#     must be emitted with an xc7z007s part.yaml - identical to xc7z010's
#     except for that one field (0x3723093 vs 0x3722093).
#
# NOT YET RUN ON HARDWARE. Everything below completes cleanly and the
# bitstream carries the right IDCODE, but no one has configured a board with
# it.
#
# usage: blackboard_flow.sh <design.v> <constraints.xdc> [top]
set -e

DESIGN="${1:?usage: blackboard_flow.sh <design.v> <constraints.xdc> [top]}"
XDC="${2:?need an xdc}"
TOP="${3:-top}"

ROOT="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
NEXTPNR="${NEXTPNR:-$( dirname "$ROOT" )/eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
PRJXRAY="${PRJXRAY:-$ROOT/prjxray}"
XRAYDB="${XRAYDB:-$ROOT/prjxray-db}"
PARTYAML="${PARTYAML:-$ROOT/rw-fuzzers/database/zynq7/xc7z007sclg400-1/part.yaml}"

BASE="$(basename "${DESIGN%.*}")"

# fasm2frames.py needs the fasm module, which lives in prjxray's venv rather
# than the system python.
PY3="python3"
[ -x "${PRJXRAY}/env/bin/python" ] && PY3="${PRJXRAY}/env/bin/python"

# nextpnr's XDC reader accepts a narrow subset: "set_property LOC <pin>
# [get_ports <name>]" and the IOSTANDARD equivalent. It does NOT accept
# -dict or braces inside get_ports, and it aborts on an assertion rather
# than reporting a parse error, so the vendor's master .xdc cannot be fed
# to it unmodified.
yosys -p "synth_xilinx -family xc7 -flatten -top ${TOP}; write_json ${BASE}.json" "$DESIGN"

"$NEXTPNR" --device xc7z007sclg400-1 \
    --json "${BASE}.json" \
    -o xdc="$XDC" \
    -o fasm="${BASE}.fasm"

# Frames come from the xc7z010 database: same die, same frame layout.
"$PY3" "${PRJXRAY}/utils/fasm2frames.py" \
    --db-root "${XRAYDB}/zynq7" --part xc7z010clg400-1 \
    "${BASE}.fasm" "${BASE}.frames"

# The bitstream, however, must carry the xc7z007s IDCODE.
"${PRJXRAY}/build/tools/xc7frames2bit" \
    --part_file "$PARTYAML" \
    --part_name xc7z007sclg400-1 \
    --frm_file "${BASE}.frames" \
    --output_file "${BASE}.bit"

echo "wrote ${BASE}.bit"
echo -n "  IDCODE in bitstream: "
xxd -p "${BASE}.bit" | tr -d '\n' | grep -oE '30018001[0-9a-f]{8}' | head -1 | sed 's/^30018001/0x/'
echo "  (xc7z007s must be 0x03723093; 0x03722093 would be the xc7z010 and the board would reject it)"
