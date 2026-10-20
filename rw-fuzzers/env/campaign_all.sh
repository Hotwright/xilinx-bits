#!/bin/bash
# Run the full Series-7 characterisation campaign: every die that needs a new
# chipdb, one at a time. Dies that share a fabric with one already built are
# handled by nextpnr die aliases, not by this script.
#
# usage: env/campaign_all.sh [stage ...]   (pass stages through to each die)
#
# Invoke from cron or a terminal; each die logs to work/campaign/<config>.
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STAGES="${*:-001 005 072 074 finish}"

CONFIGS="
kintex7_k160t
kintex7_325t
kintex7_355t
kintex7_410t
kintex7_420t
zynq7_012s
zynq7_030
zynq7_035
zynq7_100
spartan7_6
spartan7_75
"

for cfg in $CONFIGS; do
    echo "######## $cfg ########"
    "${RWF_DIR}/env/campaign_die.sh" "$cfg" $STAGES 2>&1 \
        | tee "${RWF_DIR}/work/campaign/${cfg}.run.log"
done
echo "== campaign: all dies complete"
