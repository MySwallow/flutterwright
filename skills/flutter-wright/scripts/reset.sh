#!/usr/bin/env bash
# reset.sh — navigator pop to root, via SDK /reset.
# Usage: reset.sh

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_resolve_target "$@"
fw_need_sdk

for arg in "$@"; do
  case "$arg" in
    target=*) ;;  # consumed by fw_resolve_target
    *) echo "ERR: reset.sh takes no arguments (got '$arg')" >&2; exit 70;;
  esac
done

TMP=$(mktemp -t fw-reset.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "$FW_BASE/reset" \
  -H 'content-type: application/json' \
  "${FW_AUTH[@]+"${FW_AUTH[@]}"}" \
  -d '{}') || HTTP_CODE="000"

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 70;;
  # 501 deliberately stays exit 71 (reset's "non-200" code), NOT goto's 41 — reset keeps its
  # 70/71 scheme. Callers treating "navigation not configured" uniformly must handle goto 41 AND reset 71.
  501) echo "ERR: navigation not configured — host must pass navigatorKey/navigationAdapter to FlutterWright.start(). One-time host setup; retrying won't help." >&2; cat "$TMP" >&2; exit 71;;
  *)   echo "ERR: /reset returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 71;;
esac
