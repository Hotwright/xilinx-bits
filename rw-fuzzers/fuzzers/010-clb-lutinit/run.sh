#!/bin/bash
# RapidWright port of prjxray fuzzers/010-clb-lutinit.
#
# Upstream runs generate.tcl, which builds a design, permutes every LUT6 INIT
# three ways and writes a bitstream plus a tag file for each. Here Vivado runs
# once to produce a placed-and-routed base checkpoint, RapidWright derives the
# three variants from it, and Vivado is called back only to turn each variant
# checkpoint into a bitstream. Everything downstream - bitread, segmaker,
# segmatch - is stock prjxray.
#
# Steps are separable so a failure can be isolated:
#   A  Vivado baseline: design.dcp + Vivado's own bitstream/tag file.
#   B  Round trip: RapidWright rewrites the design unmodified; the resulting
#      bitstream must be identical to Vivado's. This is the load-bearing test.
#   C  The remaining variants (upstream's two, plus extra pseudo-random ones
#      to fully constrain segmatch), then segmaker and segmatch.
#   pushdb  Merge the solved bits into database/<family>/ and diff against
#      prjxray-db.
#
# usage: run.sh [A|B|C|pushdb|all] [config]
set -e

STEP="${1:-all}"

# Exported: base.tcl reads $::env(FUZDIR) to locate top.v, and env/vivado.sh
# path-translates it for the Windows side.
export FUZDIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Second argument selects the device, e.g. "run.sh all zynq7010". Anything
# already exported (by run_all.sh) wins.
RWF_CONFIG="${2:-${RWF_CONFIG:-artix7}}"
source "${FUZDIR}/../../env/xray_env.sh" "$RWF_CONFIG" > /dev/null

# Keyed on the part, so devices do not overwrite each other's specimens and the
# per-specimen seed differs per device (giving a different placement each time).
SPECDIR="${FUZDIR}/build/${XRAY_PART}/specimen_001"
mkdir -p "$SPECDIR"
cd "$SPECDIR"

RW_RUN=(java -cp "${RW_CLASSPATH}:${RWF_DIR}/build/classes" com.hotwright.rwfuzz.LutInitFuzzer)

run_step_a() {
    echo "== Step A: Vivado baseline =="
    echo '`define SEED 32'"'h$(echo "$SPECDIR" | md5sum | cut -c1-8)" > setseed.vh
    if ! "$XRAY_VIVADO" -mode batch -source "${FUZDIR}/base.tcl" > base_run.log 2>&1; then
        echo "   FAIL: Vivado returned non-zero. Last error:"
        grep -m3 '^ERROR' vivado.log 2>/dev/null | sed 's/^/     /'
        exit 1
    fi
    test -f design.dcp || { echo "FAIL: no design.dcp; see $SPECDIR/vivado.log"; exit 1; }
    $XRAY_BITREAD -F "$XRAY_ROI_FRAMES" -o design_0_vivado.bits -z -y design_0_vivado.bit
    echo "   base checkpoint and Vivado ground truth written"
}

# Turn one variant checkpoint into a .bits file.
bitstream_for() {
    local v="$1"
    if ! "$XRAY_VIVADO" -mode batch -source "${FUZDIR}/bitstream.tcl" -tclargs "$v" > "bitstream_${v}.log" 2>&1; then
        echo "   FAIL: write_bitstream for variant $v returned non-zero. Last error:"
        grep -m3 '^ERROR' vivado.log 2>/dev/null | sed 's/^/     /'
        exit 1
    fi
    test -f "design_${v}.bit" || { echo "FAIL: no design_${v}.bit; see $SPECDIR/vivado.log"; exit 1; }
    $XRAY_BITREAD -F "$XRAY_ROI_FRAMES" -o "design_${v}.bits" -z -y "design_${v}.bit"
}

run_step_b() {
    echo "== Step B: RapidWright round trip =="
    "${RW_RUN[@]}" design.dcp . 0
    bitstream_for 0
    if diff -q design_0_vivado.bits design_0.bits > /dev/null; then
        echo "   PASS: RapidWright round trip is bit identical to Vivado"
    else
        echo "   FAIL: bitstreams differ:"
        diff design_0_vivado.bits design_0.bits | head -20
        exit 1
    fi
    # The tag files should agree too, modulo Vivado's "SLICEL." BEL prefix.
    sed 's/\r$//; s/ SLICE[LM]\./ /' design_0_vivado.txt | sort > tags_vivado.tmp
    sort design_0.txt > tags_rw.tmp
    if diff -q tags_vivado.tmp tags_rw.tmp > /dev/null; then
        echo "   PASS: tag files agree"
    else
        echo "   NOTE: tag files differ (first 10 lines):"
        diff tags_vivado.tmp tags_rw.tmp | head -10
    fi
    rm -f tags_vivado.tmp tags_rw.tmp
}

# Variants 1 and 2 are the two permutations generate.tcl performs. Variants 3+
# are pseudo-random INITs; three permutations leave segmatch under-constrained
# on a few tags, and extra permutations of the existing checkpoint cost one
# write_bitstream each instead of a whole synth/place/route specimen.
VARIANTS="${VARIANTS:-1,2,3,4,5}"

run_step_c() {
    echo "== Step C: variants and segmatch =="
    "${RW_RUN[@]}" design.dcp . "$VARIANTS"
    for v in ${VARIANTS//,/ }; do bitstream_for "$v"; done

    local all="0 ${VARIANTS//,/ }"
    for v in $all; do
        python3 "${XRAY_FUZZERS_DIR}/010-clb-lutinit/generate.py" "$v"
    done

    # Build the glob that matches exactly the variants just produced.
    local set="[$(echo $all | tr -d ' ')]"
    "$XRAY_SEGMATCH" -o segbits_clbll.db segdata_clbll_[lr]_${set}.txt
    "$XRAY_SEGMATCH" -o segbits_clblm.db segdata_clblm_[lr]_${set}.txt
    echo "   segbits written: $(wc -l < segbits_clbll.db) clbll, $(wc -l < segbits_clblm.db) clblm"

    echo "== Validation against prjxray-db =="
    python3 "${FUZDIR}/compare.py" segbits_clbll.db \
        "${XRAY_DATABASE_DIR}/${XRAY_DATABASE}/segbits_clbll_l.db" LUT.INIT || true
    python3 "${FUZDIR}/compare.py" segbits_clblm.db \
        "${XRAY_DATABASE_DIR}/${XRAY_DATABASE}/segbits_clblm_l.db" LUT.INIT || true
}

# Merge the solved bits into a database, in the same form upstream would.
#
# mergedb.sh writes to $XRAY_DATABASE_DIR/$XRAY_DATABASE/segbits_<type>.db and
# it is also what renames CLB.SLICE_X0 to CLBLL_L.SLICEL_X0. XRAY_DATABASE_DIR
# normally points at the read-only prjxray-db reference, so it is redirected at
# our own output tree for the duration - pushing into the reference would
# destroy the thing we validate against.
run_pushdb() {
    echo "== pushdb: merging into ${RWF_OUTPUT_DIR} =="
    mkdir -p "${RWF_OUTPUT_DIR}/${XRAY_DATABASE}"
    local ref_dir="${XRAY_DATABASE_DIR}/${XRAY_DATABASE}"
    (
        export XRAY_DATABASE_DIR="${RWF_OUTPUT_DIR}"
        for t in clbll_l clbll_r; do
            bash "${XRAY_UTILS_DIR}/mergedb.sh" "$t" segbits_clbll.db
        done
        for t in clblm_l clblm_r; do
            bash "${XRAY_UTILS_DIR}/mergedb.sh" "$t" segbits_clblm.db
        done
    )
    # Now that tags are in upstream spelling, compare with no normalisation.
    for t in clbll_l clblm_l; do
        local ours="${RWF_OUTPUT_DIR}/${XRAY_DATABASE}/segbits_${t}.db"
        local ref="${ref_dir}/segbits_${t}.db"
        [ -f "$ours" ] && [ -f "$ref" ] || continue
        local n_same
        n_same=$(comm -12 <(grep 'LUT\.INIT' "$ours" | sort) \
                          <(grep 'LUT\.INIT' "$ref"  | sort) | wc -l)
        local n_ref
        n_ref=$(grep -c 'LUT\.INIT' "$ref")
        echo "   ${t}: ${n_same}/${n_ref} LUT.INIT lines identical to prjxray-db"
    done
}

echo "### ${RWF_CONFIG}: ${XRAY_PART} (${XRAY_DATABASE})${XRAY_ROI:+, ROI set}"

case "$STEP" in
    A) run_step_a ;;
    B) run_step_b ;;
    C) run_step_c ;;
    pushdb) run_pushdb ;;
    all) run_step_a; run_step_b; run_step_c; run_pushdb ;;
    *) echo "usage: run.sh [A|B|C|pushdb|all] [config]"; exit 1 ;;
esac
