#!/usr/bin/env bash
# reset_viewport.sh — restore wm size/density saved by set_viewport.sh.
# Always exits 0 (idempotent / best-effort) so it's safe to call from a trap.
# Usage: reset_viewport.sh

set -uo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
ORIG_FILE="$JOB_DIR/fw_original.env"

if [ ! -f "$ORIG_FILE" ]; then
  echo "no originals recorded; running 'wm size reset' + 'wm density reset' as fallback"
  adb shell wm size reset 2>/dev/null || true
  adb shell wm density reset 2>/dev/null || true
  exit 0
fi

# shellcheck disable=SC1090
source "$ORIG_FILE"

if [ -n "${ORIG_SIZE:-}" ]; then
  adb shell wm size "$ORIG_SIZE" 2>/dev/null || adb shell wm size reset 2>/dev/null || true
fi
if [ -n "${ORIG_DENSITY:-}" ]; then
  adb shell wm density "$ORIG_DENSITY" 2>/dev/null || adb shell wm density reset 2>/dev/null || true
fi
rm -f "$ORIG_FILE"
echo "restored: size=${ORIG_SIZE:-?} density=${ORIG_DENSITY:-?}"
