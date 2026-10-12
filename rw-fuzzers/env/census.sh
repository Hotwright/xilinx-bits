#!/bin/bash
# Census every Xilinx 7-series die: is it a new fabric, or an alias of one we
# already have a chipdb for?
#
# "All the parts in the 7 series" is 42 dies across five families, times many
# packages and speed grades. Characterising a die from scratch is roughly a day
# (xc7s25: 005-tilegrid, then 072+074, whose Python phase alone ran seven
# hours). Characterising a die that turns out to share another's fabric is
# wasted, and xc7a35t/xc7a50t, xc7z007s/xc7z010 and xc7z014s/xc7z020 prove that
# sharing is common.
#
# So: one cheap Vivado run per die first (link_design on an empty netlist, no
# synthesis), dumping the fabric signature - every tile's name, type and grid
# position, the same comparison that established xc7z007s -> xc7z010. Dies whose
# signatures match share a chipdb. That turns "42 dies" into a bounded list of
# distinct fabrics, and it is the only honest way to size the job.
#
# It also collects what each new die's settings file needs (IOI3 tiles, extents,
# clock-capable pins, IDCODE) and, for parts Vivado will not open, the reason -
# which is the licence and install census for free.
#
# Output: work/census/<die>/. Nothing here writes near prjxray-db.
#
# usage: env/census.sh [die ...]          (default: every 7-series die)
set -u

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
OUT="${RWF_DIR}/work/census"
mkdir -p "$OUT"

# One representative part per die: smallest common package, speed grade -1.
# The fabric does not depend on package or speed, so one part per die is enough
# to answer the question this pass exists to answer.
PARTS_ALL="
xc7s6:xc7s6cpga196-1
xc7s15:xc7s15cpga196-1
xc7s25:xc7s25csga324-1
xc7s50:xc7s50csga324-1
xc7s75:xc7s75fgga484-1
xc7s100:xc7s100fgga484-1
xc7a12t:xc7a12tcsg325-1
xc7a15t:xc7a15tcsg324-1
xc7a25t:xc7a25tcsg325-1
xc7a35t:xc7a35tcsg324-1
xc7a50t:xc7a50tcsg324-1
xc7a75t:xc7a75tfgg484-1
xc7a100t:xc7a100tcsg324-1
xc7a200t:xc7a200tfbg484-1
xc7k70t:xc7k70tfbg484-1
xc7k160t:xc7k160tfbg484-1
xc7k325t:xc7k325tffg676-1
xc7k355t:xc7k355tffg901-1
xc7k410t:xc7k410tffg676-1
xc7k420t:xc7k420tffg901-1
xc7k480t:xc7k480tffg901-1
xc7v585t:xc7v585tffg1157-1
xc7v2000t:xc7v2000tflg1925-1
xc7vx330t:xc7vx330tffg1157-1
xc7vx415t:xc7vx415tffg1157-1
xc7vx485t:xc7vx485tffg1157-1
xc7vx550t:xc7vx550tffg1158-1
xc7vx690t:xc7vx690tffg1157-1
xc7vx980t:xc7vx980tffg1926-1
xc7vx1140t:xc7vx1140tflg1926-1
xc7vh580t:xc7vh580thcg1155-1
xc7vh870t:xc7vh870thcg1932-1
xc7z007s:xc7z007sclg400-1
xc7z010:xc7z010clg400-1
xc7z012s:xc7z012sclg485-1
xc7z014s:xc7z014sclg484-1
xc7z015:xc7z015clg485-1
xc7z020:xc7z020clg400-1
xc7z030:xc7z030fbg676-1
xc7z035:xc7z035fbg676-1
xc7z045:xc7z045ffg676-1
xc7z100:xc7z100ffg900-1
"

if [ $# -gt 0 ]; then
    WANT="$*"
else
    WANT="$( echo "$PARTS_ALL" | awk -F: 'NF{print $1}' | tr '\n' ' ' )"
fi

for die in $WANT; do
    part="$( echo "$PARTS_ALL" | awk -F: -v d="$die" '$1==d{print $2}' )"
    if [ -z "$part" ]; then echo "== ${die}: no part mapping, skipped" >&2; continue; fi
    d="${OUT}/${die}"
    if [ -f "${d}/DONE" ] || [ -f "${d}/ERROR" ]; then
        echo "== ${die}: already censused"; continue
    fi
    rm -rf "$d"; mkdir -p "$d"
    echo "== ${die} (${part})"
    CENSUS_PART="$part" CENSUS_OUT="$d" \
        "${RWF_DIR}/env/vivado.sh" -mode batch -nojournal -nolog \
        -source "${RWF_DIR}/env/census.tcl" > "${d}/vivado.log" 2>&1
    if [ -f "${d}/DONE" ]; then
        echo "   $( grep -h '^tiles\|^nodes' "${d}/extents.txt" | tr '\n' ' ' )"
    elif [ -f "${d}/ERROR" ]; then
        echo "   UNAVAILABLE: $( cat "${d}/ERROR" )"
    else
        # Vivado died without writing either marker - record that too, so the
        # sweep is complete rather than silently short.
        echo "vivado exited without writing DONE or ERROR" > "${d}/ERROR"
        echo "   FAILED (see ${d}/vivado.log)"
    fi
done
echo "== census: done"
