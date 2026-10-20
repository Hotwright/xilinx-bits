#!/bin/bash
# Build a generic blinker bitstream for any Series-7 part, with no vendor
# place-and-route. Pins are taken from the part's own package_pins.csv, so this
# works for any part the database knows: the first CCIO pin is the clock, the
# next four IO pins blink.
#
# usage: build_part.sh <part> [outdir]
#   e.g. bitstreams/build_part.sh xc7a100tfgg676-1
set -e

HERE="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( dirname "$HERE" )"
PART="${1:?usage: build_part.sh <part> [outdir]}"
OUT="${2:-${HERE}/build_$(echo "$PART" | sed -E 's/[^a-zA-Z0-9]/_/g')}"

YOSYS="${YOSYS:-/mnt/i/Hotwright/eda-tools/yosys/build/yosys}"
NEXTPNR="${NEXTPNR:-/mnt/i/Hotwright/eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
XRAY="${ROOT}/prjxray"
PYTHON3="${PYTHON3:-${XRAY}/env/bin/python3}"
[ -x "$PYTHON3" ] || PYTHON3=python3
DB="${ROOT}/xray-db-local"

# Which family subdir holds this part (artix7/kintex7/spartan7/virtex7/zynq7).
case "$PART" in
    xc7a*) FAM=artix7 ;;
    xc7k*) FAM=kintex7 ;;
    xc7s*) FAM=spartan7 ;;
    xc7v*) FAM=virtex7 ;;
    xc7z*) FAM=zynq7 ;;
    *) echo "unknown family for $PART" >&2; exit 1 ;;
esac
PINS="${DB}/${FAM}/${PART}/package_pins.csv"
[ -f "$PINS" ] || { echo "no package_pins.csv: $PINS" >&2; exit 1; }

mkdir -p "$OUT"

# Clock: first clock-capable (SRCC/MRCC) pin in an HR IOB33 tile (HP IOB18
# banks reject LVCMOS33 on Kintex/Virtex). LEDs: first four plain IOB33 pins,
# skipping clock and PS/transceiver pins.
CLK_PIN="$( awk -F, 'NR>1 && $4 ~ /IOB33/ && $5 ~ /SRCC|MRCC/ {print $1; exit}' "$PINS" )"
LED_PINS="$( awk -F, 'NR>1 && $4 ~ /IOB33/ && $5 !~ /SRCC|MRCC/ {print $1}' "$PINS" | head -4 | tr '\n' ' ' )"
[ -n "$CLK_PIN" ] && [ -n "$LED_PINS" ] || { echo "could not pick pins from $PINS" >&2; exit 1; }

echo "== part $PART (family $FAM), clock $CLK_PIN, leds [$LED_PINS]"

cat > "${OUT}/blink.v" <<END
module top(input CLK, output reg [3:0] LED);
    reg [25:0] counter;
    always @(posedge CLK) counter <= counter + 1;
    always @(*) LED = counter[25:22];
endmodule
END

: > "${OUT}/blink.xdc"
echo "set_property PACKAGE_PIN $CLK_PIN [get_ports CLK]" >> "${OUT}/blink.xdc"
echo "set_property IOSTANDARD LVCMOS33 [get_ports CLK]" >> "${OUT}/blink.xdc"
i=0
for p in $LED_PINS; do
    echo "set_property PACKAGE_PIN $p [get_ports LED[$i]]" >> "${OUT}/blink.xdc"
    echo "set_property IOSTANDARD LVCMOS33 [get_ports LED[$i]]" >> "${OUT}/blink.xdc"
    i=$((i+1))
done

echo "== yosys"
"$YOSYS" -q -p "read_verilog ${OUT}/blink.v; synth_xilinx -family xc7 -top top -json ${OUT}/blink.json"

echo "== nextpnr-himbaechel (xilinx)"
"$NEXTPNR" \
    --device "$PART" \
    --json "${OUT}/blink.json" \
    -o xdc="${OUT}/blink.xdc" \
    -o fasm="${OUT}/blink.fasm" \
    --seed 1 \
    --log "${OUT}/nextpnr.log"

echo "== fasm2frames"
PYTHONPATH="${XRAY}" XRAY_DATABASE_DIR="$DB" \
"$PYTHON3" "${XRAY}/utils/fasm2frames.py" \
    --db-root "${DB}/${FAM}" --part "$PART" \
    "${OUT}/blink.fasm" "${OUT}/blink.frames"

echo "== xc7frames2bit"
"${XRAY}/build/tools/xc7frames2bit" \
    --part_file "${DB}/${FAM}/${PART}/part.yaml" \
    --part_name "$PART" \
    --frm_file "${OUT}/blink.frames" \
    --output_file "${OUT}/blink.bit"

echo "== bitread round trip"
"${XRAY}/build/tools/bitread" \
    --part_file "${DB}/${FAM}/${PART}/part.yaml" \
    -o "${OUT}/blink.readback.txt" "${OUT}/blink.bit"

ls -l "${OUT}/blink.bit"
