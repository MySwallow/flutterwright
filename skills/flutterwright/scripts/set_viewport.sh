#!/usr/bin/env bash
# set_viewport.sh — lock device wm size + density to match design resolution.
# Usage: set_viewport.sh <width> <height> <dpi>   (e.g. 1080 2400 480)
# Records originals to $CLAUDE_JOB_DIR/fw_original.env for reset_viewport.sh.
# Caller responsibility: always call reset_viewport.sh on completion (best-effort).

set -euo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
mkdir -p "$JOB_DIR"
ORIG_FILE="$JOB_DIR/fw_original.env"

W="${1:?width required (positional arg 1)}"
H="${2:?height required (positional arg 2)}"
D="${3:?density required (positional arg 3)}"

# Record originals once (don't overwrite on repeated calls in same job)
if [ ! -f "$ORIG_FILE" ]; then
  ORIG_SIZE=$(adb shell wm size | tr -d '\r' | awk -F': ' '/Physical size|Override size/{print $2; exit}')
  ORIG_DENSITY=$(adb shell wm density | tr -d '\r' | awk -F': ' '/Physical density|Override density/{print $2; exit}')
  {
    echo "ORIG_SIZE=$ORIG_SIZE"
    echo "ORIG_DENSITY=$ORIG_DENSITY"
  } > "$ORIG_FILE"
  echo "recorded originals: size=$ORIG_SIZE density=$ORIG_DENSITY -> $ORIG_FILE"
fi

adb shell wm size "${W}x${H}"
adb shell wm density "$D"

# Readback validation (some vendor ROMs silently reject wm overrides)
ACTUAL_SIZE=$(adb shell wm size | tr -d '\r' | awk -F': ' '/Override size/{print $2; exit}')
ACTUAL_DENSITY=$(adb shell wm density | tr -d '\r' | awk -F': ' '/Override density/{print $2; exit}')

if [ "$ACTUAL_SIZE" != "${W}x${H}" ]; then
  echo "ERR: wm size override rejected (vendor ROM?). Got '$ACTUAL_SIZE', expected '${W}x${H}'" >&2
  exit 61
fi
if [ "$ACTUAL_DENSITY" != "$D" ]; then
  echo "ERR: wm density override rejected. Got '$ACTUAL_DENSITY', expected '$D'" >&2
  exit 61
fi

echo "viewport: ${W}x${H} @ ${D}dpi"
