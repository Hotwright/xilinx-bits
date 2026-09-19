# Environment for the RapidWright-based fuzzers.
#
# Replaces prjxray's utils/environment.sh. Four deliberate differences:
#   1. No Vivado 2017.2 version gate. Upstream trashes XRAY_DIR when the
#      version does not match; the check also shells out to a Linux Vivado
#      launcher that does not exist under WSL.
#   2. XRAY_DATABASE_DIR points at the prjxray-db checkout, which supplies
#      tilegrid.json / part.yaml. It is READ ONLY - it is the reference we
#      validate against, so never run pushdb/mergedb into it.
#   3. The part/ROI definitions are lifted out of prjxray's own settings/*.sh
#      rather than copied, so they stay in sync with upstream.
#   4. PYTHONPATH includes XRAY_DIR, so the fuzzers can import prjxray's
#      "utils" package - the editable install does not expose it.
#
# usage: source env/xray_env.sh [config]     (default: artix7)
#
# config is the basename of a prjxray settings file: artix7, artix7_50t,
# artix7_200t, kintex7, kintex7_160t, spartan7, zynq7, zynq7010.

RWF_CONFIG="${1:-${RWF_CONFIG:-artix7}}"

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
export RWF_DIR RWF_CONFIG
export RWF_ROOT="$( dirname "$RWF_DIR" )"

export XRAY_DIR="${RWF_ROOT}/prjxray"
export XRAY_UTILS_DIR="${XRAY_DIR}/utils"
export XRAY_TOOLS_DIR="${XRAY_DIR}/build/tools"
export XRAY_FUZZERS_DIR="${XRAY_DIR}/fuzzers"

# Reference database (read only).
export XRAY_DATABASE_DIR="${RWF_ROOT}/prjxray-db"
# Where our fuzzers write their own results.
export RWF_OUTPUT_DIR="${RWF_DIR}/database"

# --- part selection ---------------------------------------------------------
# Take every "export XRAY_..." line from the upstream settings file. This picks
# up XRAY_PART, XRAY_DATABASE, XRAY_ROI, XRAY_ROI_FRAMES, XRAY_ROI_TILEGRID,
# XRAY_IOI3_TILES and the grid bounds without duplicating any of them here.
# The rest of the settings file is skipped: it sources utils/environment.sh
# (the version gate) and runs create_environment.py, both handled below.
RWF_SETTINGS="${XRAY_DIR}/settings/${RWF_CONFIG}.sh"
if [ ! -f "$RWF_SETTINGS" ]; then
    echo "xray_env.sh: no such config '${RWF_CONFIG}' (${RWF_SETTINGS})" >&2
    echo "  available: $(cd ${XRAY_DIR}/settings && ls *.sh | sed 's/\.sh$//' | tr '\n' ' ')" >&2
    return 1
fi
# Not all configs define every variable (artix7_200t has no XRAY_ROI, meaning
# whole device), so clear them first rather than inheriting a previous config.
unset XRAY_PART XRAY_DATABASE XRAY_ROI XRAY_ROI_FRAMES XRAY_ROI_TILEGRID \
      XRAY_EXCLUDE_ROI_TILEGRID XRAY_IOI3_TILES \
      XRAY_ROI_GRID_X1 XRAY_ROI_GRID_X2 XRAY_ROI_GRID_Y1 XRAY_ROI_GRID_Y2
eval "$(grep '^export XRAY_' "$RWF_SETTINGS")"

export XRAY_FAMILY_DIR="${XRAY_DATABASE_DIR}/${XRAY_DATABASE}"
export XRAY_PART_YAML="${XRAY_DATABASE_DIR}/${XRAY_DATABASE}/${XRAY_PART}/part.yaml"

# --- python ----------------------------------------------------------------
if [ -e "${XRAY_DIR}/env/bin/activate" ]; then
    source "${XRAY_DIR}/env/bin/activate"
fi
export PYTHONWARNINGS=ignore::DeprecationWarning:distutils
export LC_ALL=C
# prjxray's setup.py declares packages=['prjxray'], so the editable install does
# not expose the sibling "utils" package. 001-part-yaml runs
# "python3 -m utils.xyaml" from inside the fuzzer directory and fails with
# ModuleNotFoundError unless XRAY_DIR is on the path.
export PYTHONPATH="${XRAY_DIR}${PYTHONPATH:+:$PYTHONPATH}"

# --- tools -----------------------------------------------------------------
export XRAY_GENHEADER="${XRAY_UTILS_DIR}/genheader.sh"
export XRAY_BITREAD="${XRAY_TOOLS_DIR}/bitread --part_file ${XRAY_PART_YAML}"
export XRAY_SEGMATCH="${XRAY_TOOLS_DIR}/segmatch"
export XRAY_MERGEDB="bash ${XRAY_UTILS_DIR}/mergedb.sh"
export XRAY_DBFIXUP="python3 ${XRAY_UTILS_DIR}/dbfixup.py"
export XRAY_SEGPRINT="python3 ${XRAY_UTILS_DIR}/segprint.py"
export XRAY_PARSEDB="python3 ${XRAY_UTILS_DIR}/parsedb.py"
export XRAY_VIVADO="${RWF_DIR}/env/vivado.sh"

# --- RapidWright -----------------------------------------------------------
export RW_DIR="${RWF_ROOT}/RapidWright"
if [ -e "${RWF_DIR}/env/rw_classpath.txt" ]; then
    export RW_CLASSPATH="$(cat ${RWF_DIR}/env/rw_classpath.txt)"
fi

# Pin assignments (XRAY_PIN_*) and device/package/speed come from the part
# resources in the database. Clear them first: when create_environment.py
# fails, stale values from a previously sourced config would otherwise look
# like a successful load.
unset XRAY_PIN_00 XRAY_PIN_01 XRAY_PIN_02 XRAY_PIN_03 \
      XRAY_DEVICE XRAY_PACKAGE XRAY_SPEED_GRADE XRAY_FABRIC
rwf_env_extra=$(python3 ${XRAY_UTILS_DIR}/create_environment.py 2>&1)
if [ $? -ne 0 ]; then
    echo "xray_env.sh: create_environment.py failed for ${XRAY_PART}:" >&2
    echo "$rwf_env_extra" | tail -3 >&2
    echo "  (run env/gen_resources.sh to create settings/${XRAY_DATABASE}/resources.yaml)" >&2
else
    eval "$rwf_env_extra"
fi
unset rwf_env_extra
