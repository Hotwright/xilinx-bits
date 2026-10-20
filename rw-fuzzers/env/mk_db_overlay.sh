#!/bin/bash
# Build the writable database overlay used by parts that prjxray-db does not
# ship: xc7s25 (its own die, fully characterised here) and xc7z007s (which
# shares the xc7z010 die, so it needs no fabric of its own - only a part entry
# and a part.yaml carrying its true IDCODE).
#
# The tree-wide rule is that prjxray-db is the READ ONLY reference we validate
# against; nothing may push into it. But prjxray's own fuzzers push: both
# 001-part-yaml and 005-tilegrid have `pushdb` targets that cp into
# ${XRAY_FAMILY_DIR}, and 005's Makefile symlinks ${XRAY_DATABASE_DIR}/<fam>/mapping
# into its basicdb. A part that is absent upstream therefore needs a database
# directory that is writable *and* still carries the family-level files.
#
# The overlay is that directory: every file is a relative symlink back into
# prjxray-db, except `mapping/` (copied, so new parts can be registered) and
# the new part's own directories (real, so fuzzer output lands somewhere).
# Reading it is identical to reading prjxray-db; writing it never touches the
# reference.
#
# Idempotent: re-running refreshes the symlinks and leaves real dirs alone.
set -e

RWF_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ROOT="$( dirname "$RWF_DIR" )"
REF="${ROOT}/prjxray-db"
OVL="${ROOT}/xray-db-local"

# family:part directories that must be real (writable) rather than symlinked.
# The 2026-10-19 device campaign adds: the kintex7 dies being characterised
# (k160t/k325t/k355t/k410t/k420t and their first package each), the zynq7
# dies (z012s/z030/z035/z100), and the spartan7 dies (s6/s75).
REAL_DIRS="spartan7/xc7s25 spartan7/xc7s25csga324-1 zynq7/xc7z007sclg400-1 kintex7/xc7k160t kintex7/xc7k160tffg676-2 kintex7/xc7k325t kintex7/xc7k325tffg676-1 kintex7/xc7k355t kintex7/xc7k355tffg901-1 kintex7/xc7k410t kintex7/xc7k410tffg676-1 kintex7/xc7k420t kintex7/xc7k420tffg901-1 zynq7/xc7z012s zynq7/xc7z012sclg485-1 zynq7/xc7z030 zynq7/xc7z030fbg676-1 zynq7/xc7z035 zynq7/xc7z035fbg676-1 zynq7/xc7z100 zynq7/xc7z100ffg900-1 spartan7/xc7s6 spartan7/xc7s6cpga196-1 spartan7/xc7s75 spartan7/xc7s75fgga484-1"
# families whose directory is rebuilt entry-by-entry rather than symlinked whole.
OVERLAY_FAMILIES="artix7 kintex7 spartan7 zynq7"

[ -d "$REF" ] || { echo "mk_db_overlay.sh: no reference db at $REF" >&2; exit 1; }

mkdir -p "$OVL"

is_overlay_family() {
    for f in $OVERLAY_FAMILIES; do [ "$1" = "$f" ] && return 0; done
    return 1
}

# --- top level ---------------------------------------------------------------
for entry in "$REF"/*; do
    name="$(basename "$entry")"
    if is_overlay_family "$name"; then continue; fi
    ln -sfn "../prjxray-db/$name" "$OVL/$name"
done

# --- overlay families --------------------------------------------------------
for fam in $OVERLAY_FAMILIES; do
    # Clear a stale symlink first, for the same reason the real part dirs below
    # do. This is not hypothetical: a family promoted from symlinked to
    # overlaid still has last run's symlink here, "mkdir -p" on a symlink to a
    # directory succeeds silently, and every ln/cp in this loop then resolves
    # THROUGH it and rewrites the read-only reference in place.
    [ -L "$OVL/$fam" ] && rm -f "$OVL/$fam"
    mkdir -p "$OVL/$fam"
    for entry in "$REF/$fam"/*; do
        name="$(basename "$entry")"
        [ "$name" = "mapping" ] && continue
        # Family-level files (tile_type_*.json, site_type_*.json) are INPUTS
        # to chipdb generation, but the 074 fuzzer also REGENERATES them as
        # part of characterising a new die. They must therefore be real copies,
        # not symlinks: a link would resolve through into the read-only
        # reference. Everything else stays a symlink (read-only inputs).
        case "$name" in
            tile_type_*.json|site_type_*.json)
                if [ -L "$OVL/$fam/$name" ]; then
                    tgt="$(readlink -f "$OVL/$fam/$name")"
                    rm -f "$OVL/$fam/$name"
                    cp "$tgt" "$OVL/$fam/$name"
                    chmod u+w "$OVL/$fam/$name"
                elif [ ! -e "$OVL/$fam/$name" ]; then
                    cp -r "$entry" "$OVL/$fam/$name"
                    chmod -R u+w "$OVL/$fam/$name"
                fi
                ;;
            *)
                [ -e "$OVL/$fam/$name" ] || ln -sfn "../../prjxray-db/$fam/$name" "$OVL/$fam/$name"
                ;;
        esac
    done
    # mapping/ is copied, not linked: create_environment.py resolves the part
    # through mapping/parts.yaml and mapping/devices.yaml, so a new part has to
    # be registered there, and that registration must not land in prjxray-db.
    if [ ! -d "$OVL/$fam/mapping" ]; then
        cp -r "$REF/$fam/mapping" "$OVL/$fam/mapping"
        chmod -R u+w "$OVL/$fam/mapping"
        echo "  $fam/mapping: copied from reference"
    else
        echo "  $fam/mapping: kept (already extended)"
    fi
done

# --- real part directories ---------------------------------------------------
for d in $REAL_DIRS; do
    # A stale symlink from an earlier run would make mkdir a no-op that writes
    # through into prjxray-db, so clear it first.
    [ -L "$OVL/$d" ] && rm -f "$OVL/$d"
    mkdir -p "$OVL/$d"
done

# --- the standing rule -------------------------------------------------------
# Belt and braces: whatever the logic above did, nothing in the overlay may
# resolve into the reference, and the reference must still be pristine.
for fam in $OVERLAY_FAMILIES; do
    if [ "$(cd -P "$OVL/$fam" && pwd)" = "$(cd -P "$REF/$fam" && pwd)" ]; then
        echo "mk_db_overlay.sh: ERROR - $OVL/$fam resolves to the reference" >&2
        exit 1
    fi
done
if [ -d "$REF/.git" ] && [ -n "$(git -C "$REF" status --porcelain 2>/dev/null)" ]; then
    echo "mk_db_overlay.sh: ERROR - $REF is no longer pristine:" >&2
    git -C "$REF" status --short 2>/dev/null | head -5 >&2
    echo "  restore it with: git -C $REF checkout -- ." >&2
    exit 1
fi

echo "overlay ready: $OVL"
