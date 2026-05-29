#!/usr/bin/env bash
# goto_exit_code_test.sh — goto.sh maps SDK 501 (navigation not configured) to exit 41
# with a human-readable message (设计 2). Uses the mock SDK; no device needed.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_mock_start 501 || exit 1
fw_test_setup_target
trap 'fw_mock_stop; rm -f "${FW_TARGETS:-}"' EXIT

# Capture stderr (the error message); discard stdout. Order matters: 2>&1 points stderr
# at the capture pipe, THEN >/dev/null sends stdout away. $? = goto.sh exit code.
err="$(bash "$FW_SCRIPTS_DIR/goto.sh" /order/detail 2>&1 >/dev/null)"
code=$?

fail=0
if [ "$code" -ne 41 ]; then
  echo "FAIL: expected exit 41 for HTTP 501, got $code" >&2; fail=1
fi
# NOTE: "One-time host setup" is intentionally NOT in mock_sdk.py's NAV_BODY — only
# goto.sh's 501 branch emits it, so this asserts the branch ran (not mock passthrough).
# If you add that phrase to NAV_BODY this assertion goes vacuous. Keep them distinct.
case "$err" in
  *"One-time host setup"*) ;;
  *) echo "FAIL: stderr lacks the actionable 'One-time host setup' guidance: $err" >&2; fail=1;;
esac
[ "$fail" -eq 0 ] && echo "PASS: goto 501 → exit 41 + human message"
exit "$fail"
