#!/bin/bash
# Build the Blackboard (Zynq Z-7007S) blinker with no vendor place-and-route.
#
# This part is interesting for one reason: nextpnr has no xc7z007s chipdb and
# does not need one. himbaechel/uarch/xilinx/xilinx.cc aliases the die onto
# xc7z010, whose PL fabric is identical tile for tile - and Vivado's own package
# data agrees, since xc7z007sclg400-1's package_pins.csv came out byte-identical
# to xc7z010clg400-1's.
#
# The one thing that must NOT be taken from xc7z010 is the IDCODE. The alias
# means nextpnr and the chipdb think they are targeting a Z-7010; only the
# part.yaml handed to xc7frames2bit carries 0x3723093, and without it the real
# device rejects the bitstream. Hence PART and CHIPDB below differ deliberately.
set -e

HERE="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( dirname "$HERE" )"
OUT="${OUT:-${HERE}/build_z007s}"

YOSYS="${YOSYS:-/mnt/i/Hotwright/eda-tools/yosys/build/yosys}"
NEXTPNR="${NEXTPNR:-/mnt/i/Hotwright/eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
CHIPDB="${CHIPDB:-/mnt/i/Hotwright/eda-tools/nextpnr/build-xilinx/share/himbaechel/xilinx/chipdb-xc7z010.bin}"
XRAY="${ROOT}/prjxray"
PYTHON3="${PYTHON3:-${XRAY}/env/bin/python3}"
[ -x "$PYTHON3" ] || PYTHON3=python3
DB="${ROOT}/xray-db-local"
PART="xc7z007sclg400-1"

mkdir -p "$OUT"

echo "== yosys"
"$YOSYS" -q -p "read_verilog ${HERE}/blackboard_z007s_blink.v; synth_xilinx -family xc7 -top top -json ${OUT}/blink.json"

echo "== nextpnr-himbaechel (xilinx, via the xc7z007s -> xc7z010 die alias)"
"$NEXTPNR" \
    --device "$PART" \
    --chipdb "$CHIPDB" \
    --json "${OUT}/blink.json" \
    -o xdc="${HERE}/blackboard_z007s.xdc" \
    -o fasm="${OUT}/blink.fasm" \
    --seed 1 \
    --log "${OUT}/nextpnr.log"

echo "== fasm2frames"
PYTHONPATH="${XRAY}" XRAY_DATABASE_DIR="$DB" \
"$PYTHON3" "${XRAY}/utils/fasm2frames.py" \
    --db-root "${DB}/zynq7" --part "$PART" \
    "${OUT}/blink.fasm" "${OUT}/blink.frames"

echo "== xc7frames2bit (with the xc7z007s part.yaml - IDCODE 0x3723093)"
"${XRAY}/build/tools/xc7frames2bit" \
    --part_file "${DB}/zynq7/${PART}/part.yaml" \
    --part_name "$PART" \
    --frm_file "${OUT}/blink.frames" \
    --output_file "${OUT}/blackboard_z007s_blink.bit"

echo "== bitread round trip"
"${XRAY}/build/tools/bitread" \
    --part_file "${DB}/zynq7/${PART}/part.yaml" \
    -o "${OUT}/blink.readback.txt" "${OUT}/blackboard_z007s_blink.bit"

ls -l "${OUT}/blackboard_z007s_blink.bit"
