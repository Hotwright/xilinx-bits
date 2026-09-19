#!/bin/bash
# Run a ported fuzzer across every Series-7 device this tree supports, and
# print a results table.
#
# usage: run_all.sh [fuzzer] [step]
#        JOBS=2 ./run_all.sh 010-clb-lutinit all
#
# Devices are the prjxray settings configs that have a reference tilegrid.json
# in prjxray-db. kintex7_160t is deliberately absent: upstream ships
# settings/kintex7_160t.sh, but prjxray-db has neither xc7k160t/tilegrid.json
# nor a part.yaml for the part, and segmaker cannot map sites to frames without
# them. Supporting it means characterising the device first (fuzzer
# 005-tilegrid), not fixing anything here.
#
# JOBS controls how many devices run at once. Two concurrent Vivado instances
# were verified to launch fine; each needs roughly 2.5 GB.
set -u

FUZZER="${1:-010-clb-lutinit}"
STEP="${2:-all}"
JOBS="${JOBS:-2}"

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIGS="${CONFIGS:-artix7 artix7_50t artix7_200t kintex7 spartan7 zynq7 zynq7010}"

WORK="${RWF_DIR}/work"
mkdir -p "$WORK"

run_one() {
    local cfg="$1"
    local log="${WORK}/${FUZZER}__${cfg}__${STEP}.log"
    if RWF_CONFIG="$cfg" bash "${RWF_DIR}/fuzzers/${FUZZER}/run.sh" "$STEP" "$cfg" > "$log" 2>&1; then
        echo "ok" > "${WORK}/.status_${cfg}"
    else
        echo "FAILED" > "${WORK}/.status_${cfg}"
    fi
    echo "   [$cfg] done ($(cat "${WORK}/.status_${cfg}"))"
}

echo "running $FUZZER on: $CONFIGS  (JOBS=$JOBS)"
running=0
for cfg in $CONFIGS; do
    run_one "$cfg" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
done
wait

# --- results table ---------------------------------------------------------
RESULTS="${WORK}/results_${FUZZER}.txt"
: > "$RESULTS"
for cfg in $CONFIGS; do
    log="${WORK}/${FUZZER}__${cfg}__${STEP}.log"
    status="$(cat "${WORK}/.status_${cfg}" 2>/dev/null || echo '?')"
    part=$(grep -m1 '^### ' "$log" 2>/dev/null | sed 's/^### [^:]*: \([^ ]*\).*/\1/')
    # Step B is the round-trip check; for other steps fall back to the most
    # recent log that actually ran it.
    rtlog="$log"
    [ -f "${WORK}/${FUZZER}__${cfg}__all.log" ] && rtlog="${WORK}/${FUZZER}__${cfg}__all.log"
    [ -f "${WORK}/${FUZZER}__${cfg}__B.log" ] && rtlog="${WORK}/${FUZZER}__${cfg}__B.log"
    if grep -q 'PASS: RapidWright round trip is bit identical' "$rtlog" 2>/dev/null; then
        roundtrip="identical"
    elif grep -q 'FAIL: bitstreams differ' "$rtlog" 2>/dev/null; then
        roundtrip="DIFFERS"
    else
        roundtrip="not-run"
    fi
    match=$(grep -hoE '[0-9]+/[0-9]+ LUT\.INIT lines identical' "$log" 2>/dev/null \
            | grep -oE '^[0-9]+/[0-9]+' | tr '\n' ' ')
    printf '%-14s %-22s %-8s %-10s %s\n' \
        "$cfg" "${part:-?}" "$status" "$roundtrip" "${match:-none}" >> "$RESULTS"
    rm -f "${WORK}/.status_${cfg}"
done

echo
echo "================== $FUZZER =================="
printf '%-14s %-22s %-8s %-10s %s\n' CONFIG PART STATUS ROUNDTRIP "LUT.INIT vs prjxray-db (clbll clblm)"
cat "$RESULTS"
