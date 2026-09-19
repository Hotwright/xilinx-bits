#!/bin/bash
# Build the Arty S7 blinker with no vendor place-and-route, for either die:
#
#     bash build_arty_s7.sh 25      # Arty S7-25, xc7s25csga324-1  (default)
#     bash build_arty_s7.sh 50      # Arty S7-50, xc7s50csga324-1
#
# Digilent's Arty-S7-25 and Arty-S7-50 master XDCs put the clock, the four LEDs
# and BTN0 on the same balls, so one constraints file covers both boards.
#
#   blink.v --yosys(synth_xilinx)--> JSON
#           --nextpnr-himbaechel(xilinx)--> FASM
#           --prjxray fasm2frames--> frames
#           --prjxray xc7frames2bit--> .bit
#
# Same pipeline as arty_a7_35t_blink.bit, but every database file it reads for
# xc7s25 was produced in this tree: part.yaml and tilegrid.json from fuzzers
# 001/005, package_pins.csv from 075, tileconn.json from 074, and the chipdb
# generated from those by nextpnr's own xilinx_gen.py.
#
# CHIPDB may point at a chipdb built elsewhere; by default the one in the
# nextpnr build tree is used.
set -e

HERE="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( dirname "$HERE" )"

DIE="${1:-25}"
case "$DIE" in
    25) PART="xc7s25csga324-1"; DEVICE="xc7s25" ;;
    50) PART="xc7s50csga324-1"; DEVICE="xc7s50" ;;
    *)  echo "usage: $0 [25|50]" >&2; exit 1 ;;
esac
OUT="${OUT:-${HERE}/build_s7_${DIE}}"

YOSYS="${YOSYS:-/mnt/i/Hotwright/eda-tools/yosys/build/yosys}"
NEXTPNR="${NEXTPNR:-/mnt/i/Hotwright/eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
CHIPDB="${CHIPDB:-/mnt/i/Hotwright/eda-tools/nextpnr/build-s25/himbaechel/uarch/xilinx/chipdb-${DEVICE}.bin}"
XRAY="${ROOT}/prjxray"
# fasm2frames imports the "fasm" package, which lives in prjxray's venv, not in
# the system python.
PYTHON3="${PYTHON3:-${XRAY}/env/bin/python3}"
[ -x "$PYTHON3" ] || PYTHON3=python3
# xc7s25 exists only in the overlay; xc7s50 is shipped upstream, and reading
# the overlay for it would work too (every entry symlinks to the reference) but
# says the wrong thing.
if [ "$DIE" = 25 ]; then DB="${ROOT}/xray-db-local"; else DB="${ROOT}/prjxray-db"; fi

mkdir -p "$OUT"

echo "== ${PART} (die ${DEVICE})"
echo "== yosys"
"$YOSYS" -q -p "read_verilog ${HERE}/arty_s7_blink.v; synth_xilinx -family xc7 -top top -json ${OUT}/blink.json"

echo "== nextpnr-himbaechel (xilinx)"
"$NEXTPNR" \
    --device "$PART" \
    --chipdb "$CHIPDB" \
    --json "${OUT}/blink.json" \
    -o xdc="${HERE}/arty_s7.xdc" \
    -o fasm="${OUT}/blink.fasm" \
    --seed 1 \
    --log "${OUT}/nextpnr.log"

echo "== fasm2frames"
PYTHONPATH="${XRAY}" XRAY_DATABASE_DIR="$DB" \
"$PYTHON3" "${XRAY}/utils/fasm2frames.py" \
    --db-root "${DB}/spartan7" --part "$PART" \
    "${OUT}/blink.fasm" "${OUT}/blink.frames"

echo "== xc7frames2bit"
"${XRAY}/build/tools/xc7frames2bit" \
    --part_file "${DB}/spartan7/${PART}/part.yaml" \
    --part_name "$PART" \
    --frm_file "${OUT}/blink.frames" \
    --output_file "${OUT}/arty_s7_${DIE}_blink.bit"

echo "== bitread round trip"
"${XRAY}/build/tools/bitread" \
    --part_file "${DB}/spartan7/${PART}/part.yaml" \
    -o "${OUT}/blink.readback.txt" "${OUT}/arty_s7_${DIE}_blink.bit"

ls -l "${OUT}/arty_s7_${DIE}_blink.bit"
