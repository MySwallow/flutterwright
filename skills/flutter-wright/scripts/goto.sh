#!/usr/bin/env bash
# goto.sh — push a named route on the device via SDK /navigate.
# Usage: goto.sh <route> [args=<json>] [popUntilRoot=<bool>]
#   goto.sh /order/detail args='{"id":"ORD-001"}'
#   goto.sh /home popUntilRoot=false

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
ROUTE="${1:?route required (positional arg 1)}"
shift

ARGS="null"
POP_UNTIL_ROOT="true"
for arg in "$@"; do
  case "$arg" in
    args=*) ARGS="${arg#args=}";;
    popUntilRoot=*) POP_UNTIL_ROOT="${arg#popUntilRoot=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 40;;
  esac
done

# Validate route: only allow safe characters in v1 (path-style routes are the spec contract).
# Anything else fails early so we avoid hand-rolling JSON escaping in bash.
if [[ "$ROUTE" == *'"'* || "$ROUTE" == *'\'* || "$ROUTE" == *$'\n'* ]]; then
  echo "ERR: route '$ROUTE' contains unsupported characters (quotes/backslash/newline). Use simple path-style routes." >&2
  exit 40
fi

PAYLOAD=$(printf '{"route":"%s","args":%s,"popUntilRoot":%s}' "$ROUTE" "$ARGS" "$POP_UNTIL_ROOT")

TMP=$(mktemp -t fw-goto.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/navigate" \
  -H 'content-type: application/json' \
  -d "$PAYLOAD") || HTTP_CODE="000"

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 43;;
  503) echo "ERR: navigator not ready (app not mounted yet?)" >&2; cat "$TMP" >&2; exit 41;;
  500) echo "ERR: push failed (route '$ROUTE' not in onGenerateRoute? args type mismatch?)" >&2; cat "$TMP" >&2; exit 42;;
  *)   echo "ERR: /navigate returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 43;;
esac
