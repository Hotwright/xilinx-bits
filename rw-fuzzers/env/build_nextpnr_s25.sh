#!/bin/bash
# Build the NATIVE nextpnr-himbaechel-xilinx plus chipdbs for the parts this
# tree targets. Devices are a cmake-style ;-separated list:
#
#     env/build_nextpnr_s25.sh                  # xc7s25 and xc7s50
#     DEVICES=xc7s25 env/build_nextpnr_s25.sh   # just one
#
# xc7z007s has no entry of its own: it aliases onto the xc7z010 die, so
# building xc7z010's chipdb is what makes xc7z007s work.
#
# Kept separate from the existing build-xilinx tree, which is configured against
# the read-only prjxray-db and builds xc7a50t/xc7z010/xc7z020. This one reads
# the xc7s25 overlay instead, and builds exactly one chipdb, so a rebuild is
# minutes rather than an hour.
#
# HIMBAECHEL_SPLIT=ON so the binary is named nextpnr-himbaechel-xilinx, matching
# the WASI build - the two are diffed against each other by
# hotc/web/nextpnr-xilinx-wasm/diff_native.mjs, and having them agree on argv
# and on the chipdb is the whole point of that test.
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ROOT="$( dirname "$RWF_DIR" )"
NEXTPNR_SRC="${NEXTPNR_SRC:-/mnt/i/Hotwright/eda-tools/nextpnr}"
BUILD="${BUILD:-${NEXTPNR_SRC}/build-s25}"

cmake -B "$BUILD" -S "$NEXTPNR_SRC" \
    -DCMAKE_BUILD_TYPE=Release \
    -DARCH=himbaechel \
    -DHIMBAECHEL_SPLIT=ON \
    -DHIMBAECHEL_UARCH=xilinx \
    -DHIMBAECHEL_PRJXRAY_DB="${ROOT}/xray-db-local" \
    -DHIMBAECHEL_XILINX_DEVICES="${DEVICES:-xc7s25;xc7s50;xc7z010}" \
    -DBUILD_GUI=OFF \
    -DBUILD_PYTHON=OFF \
    -DBUILD_TESTS=OFF

# The bba rule lists only xilinx_gen.py and constids.inc as INPUTS, so cmake
# does NOT notice when the database underneath changes - re-running 074 and
# then rebuilding would silently keep the old chipdb. Delete it when the
# database has moved.
# FORCE_CHIPDB names which chipdbs to discard: a ;-separated device list, or
# 1 for all of them. Naming them matters - xc7s50's bba alone is 116 MB and
# takes minutes, so regenerating it because xc7s25's database changed is pure
# waste. "1" stays the safe answer when unsure.
if [ -n "${FORCE_CHIPDB:-}" ]; then
    if [ "${FORCE_CHIPDB}" = 1 ]; then _fc='*'; else _fc="${FORCE_CHIPDB}"; fi
    for _d in $( echo "$_fc" | tr ';' ' ' ); do
        rm -f "${BUILD}"/himbaechel/uarch/xilinx/chipdb-$_d.bb[a] \
              "${BUILD}"/himbaechel/uarch/xilinx/chipdb-$_d.bin \
              "${BUILD}"/share/himbaechel/xilinx/chipdb-$_d.bin
    done
fi

cmake --build "$BUILD" -j"${JOBS:-8}"

# Report what actually exists, not what was asked for. The chipdb rule is a
# custom command, so a device that failed to generate leaves the build exit
# code at 0 and just does not produce a .bin.
echo "== chipdbs in ${BUILD}:"
for d in $( echo "${DEVICES:-xc7s25;xc7s50;xc7z010}" | tr ';' ' ' ); do
    bin="${BUILD}/himbaechel/uarch/xilinx/chipdb-${d}.bin"
    if [ -f "$bin" ]; then
        echo "   $(printf '%-10s' "$d") $(stat -c%s "$bin") bytes"
    else
        echo "   $(printf '%-10s' "$d") MISSING"
    fi
done
echo "== binary: $( ls -l "${BUILD}/nextpnr-himbaechel-xilinx" 2>/dev/null || echo MISSING )"
