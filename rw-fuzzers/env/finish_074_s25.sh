#!/bin/bash
# The whole post-074 chain for xc7s25, in order, in one place.
#
# Run this once fuzzer 074-dump_all has produced output/tileconn.json. Until
# now xray-db-local/spartan7/xc7s25/tileconn.json has been the xc7s50 file,
# borrowed because env/check_tileconn_cover.py showed it covers every tile
# adjacency on this die except the three MONITOR_*_FUJI2 XADC tiles. This
# replaces it with the one measured on the xc7s25 die itself.
#
# Every step here has a trap that has already caught us once, so none of them
# are optional and none can be reordered:
#
#   1. push       - NOT 074's own "make pushdb": that one cp's through the
#                   overlay symlinks into the read-only prjxray-db.
#   2. cover      - re-run the coverage probe. The MONITOR_*_FUJI2 misses are
#                   the reason 074 was run at all, so if they are still there
#                   the run did not achieve what it was for.
#   3. chipdb     - FORCE_CHIPDB=xc7s25, because cmake's bba rule lists only
#                   xilinx_gen.py and constids.inc as INPUTS and therefore does
#                   not rebuild when the database changes.
#   4. bitstream  - rebuild the Arty S7-25 .bit end to end and check the frame
#                   count and IDCODE are what the earlier runs produced.
#   5. wasm       - same chipdb into the WASI build, then the package's own
#                   checks.
#
# usage: env/finish_074_s25.sh [step ...]      (default: all of the above)
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ROOT="$( dirname "$RWF_DIR" )"
STEPS="${*:-push cover chipdb bitstream wasm}"
PY3="${XRAY_PYTHON:-${ROOT}/prjxray/env/bin/python3}"

OUT="${ROOT}/prjxray/fuzzers/074-dump_all/build_xc7s25csga324-1/output"
DB="${ROOT}/xray-db-local/spartan7/xc7s25"

# What the native flow produced from the borrowed xc7s50 tileconn. The point of
# re-checking is that swapping in the real one must not change the bitstream's
# shape - tileconn drives the wire graph, not the frame layout.
EXPECT_FRAMES=3060
EXPECT_IDCODE=0x37c4093

step() { case " $STEPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

if step push; then
    echo "== push"
    [ -f "${OUT}/tileconn.json" ] || {
        echo "   074 has not produced ${OUT}/tileconn.json yet" >&2; exit 1; }
    # tileconn.json appearing is not the finish line: generate_grid.py writes
    # it, and node_names.py and check_nodes.py still run after that -
    # check_nodes.py being the step that validates what was just built.
    # Bracket the patterns: an unbracketed "pgrep -f generate_after_dump.sh"
    # matches this script's own command line and reports the fuzzer alive
    # forever.
    for proc in '[g]enerate_after_dump.sh' '[r]esume_074_s25.sh'; do
        if pgrep -f "$proc" > /dev/null; then
            echo "   074 is still running (${proc//[\[\]]/}) - wait for it" >&2; exit 1
        fi
    done
    # check_nodes.py is the step that validates what was built, and it runs
    # after tileconn.json is written. The run may have been resumed, so accept
    # evidence from either log.
    if ! grep -lq 'check_nodes' "${RWF_DIR}"/work/074_*_s25.log 2>/dev/null; then
        echo "   no 074 log shows check_nodes.py ran - refusing to push" >&2; exit 1
    fi
    # Keep the borrowed file so the two can be compared; this is the only
    # direct evidence of how much the die actually differs.
    if [ -f "${DB}/tileconn.json" ] && [ ! -f "${DB}/tileconn.s50.json" ]; then
        cp "${DB}/tileconn.json" "${DB}/tileconn.s50.json"
    fi
    "${RWF_DIR}/env/push_074.sh" spartan7_s25
    if [ -f "${DB}/tileconn.s50.json" ]; then
        echo "   borrowed s50 tileconn: $(stat -c%s "${DB}/tileconn.s50.json") bytes"
        echo "   measured s25 tileconn: $(stat -c%s "${DB}/tileconn.json") bytes"
        cmp -s "${DB}/tileconn.s50.json" "${DB}/tileconn.json" \
            && echo "   identical - the borrow was exact" \
            || echo "   they differ, as expected (MONITOR_*_FUJI2 at least)"
    fi
fi

if step cover; then
    echo "== cover"
    # Self-check: the tileconn now comes from this die, so the miss set is its
    # own baseline and no miss can be "unexplained" by construction. What is
    # still worth asserting is the second half of the report - that every tile
    # type on the die has a tile_type_<T>.json. That is the actual hole 074 was
    # run to close: read_tile_type_json() returns None for a missing type
    # silently, leaving the tile with no wires and nothing logged.
    "${PY3}" "${RWF_DIR}/env/check_tileconn_cover.py" \
        "$DB" "$DB" "$( dirname "$DB" )"
    # And for the record, what the borrowed xc7s50 file would have missed.
    # The baseline must be xc7s50's own grid - probing it against this die's
    # grid would make the source and the subject the same and report nothing.
    echo "-- for comparison, the borrowed xc7s50 tileconn against this die:"
    "${PY3}" "${RWF_DIR}/env/check_tileconn_cover.py" \
        "${ROOT}/prjxray-db/spartan7/xc7s50" "$DB" "$( dirname "$DB" )" || true
fi

if step chipdb; then
    echo "== chipdb (native)"
    # Only xc7s25's database changed; xc7s50 and xc7z010 are untouched.
    FORCE_CHIPDB=xc7s25 "${RWF_DIR}/env/build_nextpnr_s25.sh"
fi

if step bitstream; then
    echo "== bitstream"
    LOG="${RWF_DIR}/work/finish_bitstream.log"
    "${ROOT}/bitstreams/build_arty_s7.sh" 25 2>&1 | tee "$LOG"
    [ "${PIPESTATUS[0]}" = 0 ] || { echo "   build_arty_s7.sh failed" >&2; exit 1; }

    # Two numbers say the bitstream is for this die and structurally complete.
    #
    # The frame count must come from bitread, which reads the finished .bit -
    # NOT from "wc -l blink.frames". fasm2frames writes only the frames it
    # actually set bits in (2622 here) and xc7frames2bit pads the die out to
    # its full 3060; counting the intermediate measures the design, not the
    # device. That mistake reported a 438-frame regression that did not exist.
    #
    # The IDCODE is whatever part.yaml told xc7frames2bit to write, so this
    # checks part.yaml too - the file xc7z007s proved you can get wrong while
    # everything still appears to build.
    frames="$( grep -oE 'Number of configuration frames: [0-9]+' "$LOG" \
               | grep -oE '[0-9]+$' )"
    yaml="${DB%/xc7s25}/xc7s25csga324-1/part.yaml"
    idcode="$( grep -m1 '^idcode' "$yaml" | grep -oE '0x[0-9a-f]+' )"
    echo "   frames=${frames:-?} (expected ${EXPECT_FRAMES})"
    echo "   idcode=${idcode} (expected ${EXPECT_IDCODE})"
    [ "${frames:-0}" = "$EXPECT_FRAMES" ] || { echo "   ERROR: frame count changed" >&2; exit 1; }
    [ "$idcode" = "$EXPECT_IDCODE" ] || { echo "   ERROR: idcode changed" >&2; exit 1; }
fi

if step wasm; then
    echo "== wasm"
    FORCE_CHIPDB=xc7s25 "${ROOT}/wasm-build/build_nextpnr_xilinx_wasm.sh" nextpnr
    make -C /mnt/i/Hotwright/hotc/web/nextpnr-xilinx-wasm package check
fi

echo "== finish_074_s25: done"
