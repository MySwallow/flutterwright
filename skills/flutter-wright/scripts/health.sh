#!/usr/bin/env bash
# health.sh — explicit env dry-run.
#
# Implicit health runs on first invocation of any flutter-wright method in a job,
# so callers rarely need to invoke this. Use it to:
#   - hands-on debug an environment issue
#   - refresh the session marker after the SDK was restarted mid-job
#
# Exits non-zero with a single line "ERR: <reason>" on failure
# (10 adb / 11 device / 12 SDK / 13 curl).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# Always run the full chain + refresh marker, regardless of any prior marker.
FW_HEALTH_FORCE=1 fw_ensure_health

echo "ok: device=${FW_DEVICE_ID:-?} port=${VL_PORT:-9123}"
