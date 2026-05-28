#!/usr/bin/env bash
# back.sh — system back (pop one route) via adb keyevent 4. No SDK needed.
# Usage: back.sh
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_adb

if adb -s "$FW_DEVICE_ID" shell input keyevent 4 >/dev/null; then
  echo "back"
else
  echo "ERR: adb keyevent 4 (BACK) failed" >&2; exit 91
fi
