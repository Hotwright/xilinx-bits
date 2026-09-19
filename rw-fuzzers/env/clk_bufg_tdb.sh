#!/bin/bash
# Build clk_bufg's segbits_tilegrid.tdb for a part whose CLK_BUFG_BOT_R does not
# start at BUFGCTRL_X0Y0.
#
# Background. 005-tilegrid's clk_bufg fuzzer LOCs a BUFGCTRL and treats the word
# the solved bit lands in as the *tile's* first word - GENERATE_ARGS pins
# "--dword 0", and add_tdb.py computes offset = raw_word - DWORD. That holds only
# when the selected site sits at the tile's first word.
#
# On xc7s25 it does not. CLK_BUFG_BOT_R holds 13 BUFGCTRLs starting at
# BUFGCTRL_X0Y3 (xc7s50's holds 16 starting at X0Y0), and Series-7 packs two
# BUFGCTRLs per configuration word, so X0Y3 sits floor(3/2) = 1 word into the
# tile. CLK_BUFG_TOP_R is unaffected: its lowest site, BUFGCTRL_X0Y16, is at its
# tile's first word.
#
# The two tiles therefore need different deltas, and the Makefile has room for
# only one. So run the fuzzer twice and take each tile from the run whose delta
# is right for it. Both runs measure the same raw bits - 094 for BOT_R, 000 for
# TOP_R - so this selects the correct interpretation of one measurement rather
# than inventing a number.
#
# Corroboration: the result puts BOT_R at offset 93 and TOP_R at 0, identical to
# xc7s50's published tilegrid. 93 + 8 words = 101 fills the frame exactly, and
# pairs with TOP_R occupying words 0..7 of the frame across the half boundary.
#
# Requires clk_bufg/top.py's numeric site sort; a string sort picks X0Y10 here
# ("1" < "3") and the whole thing is off by a further 5 words.
set -e

: "${XRAY_PART:?source env/xray_env.sh spartan7_s25 first}"
FUZ="$(dirname "${BASH_SOURCE[0]}")/../../prjxray/fuzzers/005-tilegrid/clk_bufg"
FUZ="$(cd "$FUZ" && pwd)"
WORK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/work"
OUT="$FUZ/build_${XRAY_PART}/segbits_tilegrid.tdb"

# tile-name prefix -> the --dword that is correct for it
declare -A DWORD=( [CLK_BUFG_TOP_R]=0 [CLK_BUFG_BOT_R]=1 )

cd "$FUZ"
for dw in 0 1; do
    if [ ! -s "$WORK/clk_bufg_dword${dw}.tdb" ]; then
        echo "== clk_bufg run with --dword $dw =="
        rm -rf "build_${XRAY_PART}"
        make GENERATE_ARGS="\"--oneval 1 --design params.csv --dword $dw --dframe 1B\""
        cp "build_${XRAY_PART}/segbits_tilegrid.tdb" "$WORK/clk_bufg_dword${dw}.tdb"
    else
        echo "== clk_bufg --dword $dw: cached =="
    fi
done

mkdir -p "$(dirname "$OUT")"
: > "$OUT"
for tile in "${!DWORD[@]}"; do
    dw="${DWORD[$tile]}"
    grep "^${tile}" "$WORK/clk_bufg_dword${dw}.tdb" >> "$OUT" \
        || { echo "clk_bufg_tdb.sh: no $tile row in the --dword $dw run" >&2; exit 1; }
done
sort -o "$OUT" "$OUT"

echo "wrote $OUT:"
cat "$OUT"
