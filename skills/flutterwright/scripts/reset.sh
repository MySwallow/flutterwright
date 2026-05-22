#!/usr/bin/env bash
# reset.sh — navigator pop to root, optionally clearing mock data, via SDK /reset.
# Usage: reset.sh [clearMock=<true|false>]
#   reset.sh                       # defaults to clearMock=true
#   reset.sh clearMock=false       # keep mock data, just pop navigator

set -euo pipefail

PORT="${VL_PORT:-9123}"

CLEAR_MOCK="true"
for arg in "$@"; do
  case "$arg" in
    clearMock=*) CLEAR_MOCK="${arg#clearMock=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 70;;
  esac
done

PAYLOAD=$(printf '{"clearMock":%s}' "$CLEAR_MOCK")

TMP=$(mktemp -t fw-reset.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/reset" \
  -H 'content-type: application/json' \
  -d "$PAYLOAD") || HTTP_CODE="000"

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 70;;
  *)   echo "ERR: /reset returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 71;;
esac
