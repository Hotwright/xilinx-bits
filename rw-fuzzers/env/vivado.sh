#!/bin/bash
# Run Vivado for the fuzzers.
#
# Two installs are supported, selected by XRAY_VIVADO_LINUX:
#
#  * A NATIVE LINUX install (the default). Vivado is exec'd directly. Nothing
#    needs translating: the fuzzers' paths, the environment and the working
#    directory are already in the form the tool expects.
#
#  * A WINDOWS install, driven from WSL through cmd.exe, used when
#    XRAY_VIVADO_LINUX is set empty. This needs two translations and is kept
#    because the rest of the tree's results were produced with it:
#      - file arguments -> Windows paths, so the Tcl interpreter can open them;
#      - the environment -> WSLENV, since Windows processes do not inherit the
#        WSL environment and prjxray's Tcl reads $::env(XRAY_*) throughout.
#        WSLENV's "/p" flag also path-translates the vars that need it.
#    WSLENV is used in preference to emitting "set VAR=..." into the cmd.exe
#    command line: values such as XRAY_ROI contain spaces and colons, and the
#    resulting nested quoting is not reliably parsed by "cmd.exe /c".
set -e

# Default: the Linux 2026.1.1 install. Set XRAY_VIVADO_LINUX="" to fall back to
# the Windows launcher below.
XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-/mnt/e/Xilinx/2026.1.1/Vivado}"

if [ -n "$XRAY_VIVADO_LINUX" ]; then
    settings="$XRAY_VIVADO_LINUX"
    # Accept either the install root or the settings64.sh itself.
    [ -d "$settings" ] && settings="${settings%/}/settings64.sh"
    if [ ! -r "$settings" ]; then
        echo "vivado.sh: no Vivado settings script at $settings" >&2
        echo "  (set XRAY_VIVADO_LINUX to the install root, or to \"\" to use" >&2
        echo "   the Windows install via XRAY_VIVADO_BAT)" >&2
        exit 1
    fi
    # settings64.sh is not written for "set -e" - it dereferences unset vars.
    set +e
    # shellcheck disable=SC1090
    source "$settings"
    set -e
    exec vivado "$@"
fi

# --- Windows install --------------------------------------------------------
VIVADO_BAT="${XRAY_VIVADO_BAT:-E:\\Xilinx\\Vivado\\2024.2\\bin\\vivado.bat}"

# Vars whose value is a single path, so WSLENV should rewrite it for Windows.
PATH_VARS="${XRAY_VIVADO_PATH_VARS:-TMP_FILE XRAY_PART_YAML XRAY_DIR XRAY_FAMILY_DIR XRAY_DATABASE_DIR FUZDIR SPECDIR}"
# Vars passed through verbatim (part names, ROI ranges, pin names, seeds).
PLAIN_VARS="${XRAY_VIVADO_PLAIN_VARS:-$(compgen -v | grep -E '^XRAY_(PART|DATABASE|ROI|EXCLUDE|IOI3|PIN|DEVICE|PACKAGE|SPEED|FABRIC)' | tr '\n' ' ') SEED SEEDN}"

spec=""
for v in $PATH_VARS; do
    [ -n "${!v-}" ] || continue
    spec+="${spec:+:}$v/p"
done
for v in $PLAIN_VARS; do
    # -v, not -n: a variable that is set but empty still has to be forwarded.
    [ -v "$v" ] || continue
    # Windows cannot hold an empty environment variable - "set VAR=" deletes it -
    # so a var exported as "" arrives on the far side undefined, and unguarded
    # Tcl blows up rather than seeing an empty string. 005-tilegrid's
    # make_project_roi reads $::env(XRAY_EXCLUDE_ROI_TILEGRID) with no
    # "info exists" guard, and settings/spartan7.sh sets exactly that to "".
    # A single space keeps the variable defined and still iterates zero times
    # in the "foreach roi $::env(...)" that consumes it.
    [ -n "${!v}" ] || export "${v}= "
    # A var already listed as a path var must not be listed twice.
    case ":$spec:" in *":$v/p:"*) continue ;; esac
    spec+="${spec:+:}$v"
done
export WSLENV="${WSLENV:+$WSLENV:}$spec"

args=()
for a in "$@"; do
    if [ -e "$a" ]; then
        args+=("$(wslpath -w "$a")")
    else
        args+=("$a")
    fi
done

# cmd.exe does not inherit the WSL cwd, so cd explicitly. Specimen directories
# must therefore live on a Windows-visible drive (/mnt/...).
win_cwd="$(wslpath -w "$PWD")"

exec cmd.exe /c "cd /d $win_cwd && $VIVADO_BAT ${args[*]}"
