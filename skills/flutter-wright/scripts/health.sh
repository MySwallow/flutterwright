#!/usr/bin/env bash
# health.sh — explicit env dry-run.
#
# The SDK probe runs implicitly on the first goto/reset/health in a job (they call
# fw_need_sdk); screenshot/setViewport/run check adb only, reload/stop check neither.
# So callers rarely need to invoke this explicitly. Use it to:
#   - hands-on debug an environment issue
#   - refresh the session marker after the SDK was restarted mid-job
#
# Exits non-zero with a single line "ERR: <reason>" on failure
# (10 adb / 11 device / 12 SDK / 13 curl).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# Always run the full chain + refresh marker, regardless of any prior marker.
FW_HEALTH_FORCE=1 fw_need_sdk

echo "ok: device=${FW_DEVICE_ID:-?} port=${VL_PORT:-9123}"
