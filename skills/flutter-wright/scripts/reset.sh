#!/usr/bin/env bash
# reset.sh — navigator pop to root, via SDK /reset.
# Usage: reset.sh

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"

if [ "$#" -gt 0 ]; then
  echo "ERR: reset.sh takes no arguments (got '$*')" >&2
  exit 70
fi

TMP=$(mktemp -t fw-reset.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/reset" \
  -H 'content-type: application/json' \
  -d '{}') || HTTP_CODE="000"

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 70;;
  *)   echo "ERR: /reset returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 71;;
esac
