#!/bin/bash
# Build the Basys 3 (XC7A35T-1CPG236C) blinker with no vendor place-and-route.
#
# The xc7a35t has no chipdb of its own: himbaechel/uarch/xilinx/xilinx.cc
# aliases the die onto xc7a50t, of which the 35T is a bonded-out subset, and
# prjxray-db already carries xc7a35tcpg236-1 under the xc7a50t fabric. As with
# the Blackboard, the IDCODE is the one thing NOT taken from the alias: only
# the part.yaml handed to xc7frames2bit carries 0x362d093.
#
# This is also the native reference the browser chain is checked against:
# hotc's web/fasm2frames-pyodide tests compare against build_a35t/.
set -e

HERE="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( dirname "$HERE" )"
OUT="${OUT:-${HERE}/build_a35t}"

YOSYS="${YOSYS:-/mnt/i/Hotwright/eda-tools/yosys/build/yosys}"
NEXTPNR="${NEXTPNR:-/mnt/i/Hotwright/eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
CHIPDB="${CHIPDB:-/mnt/i/Hotwright/eda-tools/nextpnr/build-xilinx/share/himbaechel/xilinx/chipdb-xc7a50t.bin}"
XRAY="${ROOT}/prjxray"
PYTHON3="${PYTHON3:-${XRAY}/env/bin/python3}"
[ -x "$PYTHON3" ] || PYTHON3=python3
DB="${ROOT}/xray-db-local"
PART="xc7a35tcpg236-1"

mkdir -p "$OUT"

echo "== yosys"
"$YOSYS" -q -p "read_verilog ${HERE}/basys3_blink.v; synth_xilinx -family xc7 -top top -json ${OUT}/blink.json"

echo "== nextpnr-himbaechel (xilinx, via the xc7a35t -> xc7a50t die alias)"
"$NEXTPNR" \
    --device "$PART" \
    --chipdb "$CHIPDB" \
    --json "${OUT}/blink.json" \
    -o xdc="${HERE}/basys3.xdc" \
    -o fasm="${OUT}/blink.fasm" \
    --seed 1 \
    --log "${OUT}/nextpnr.log"

echo "== fasm2frames"
PYTHONPATH="${XRAY}" XRAY_DATABASE_DIR="$DB" \
"$PYTHON3" "${XRAY}/utils/fasm2frames.py" \
    --db-root "${DB}/artix7" --part "$PART" \
    "${OUT}/blink.fasm" "${OUT}/blink.frames"

echo "== xc7frames2bit (with the xc7a35t part.yaml - IDCODE 0x362d093)"
"${XRAY}/build/tools/xc7frames2bit" \
    --part_file "${DB}/artix7/${PART}/part.yaml" \
    --part_name "$PART" \
    --frm_file "${OUT}/blink.frames" \
    --output_file "${OUT}/basys3_blink.bit"

echo "== bitread round trip"
"${XRAY}/build/tools/bitread" \
    --part_file "${DB}/artix7/${PART}/part.yaml" \
    -o "${OUT}/blink.readback.txt" "${OUT}/basys3_blink.bit"

ls -l "${OUT}/basys3_blink.bit"
