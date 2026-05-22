#!/usr/bin/env bash
# mock.sh — control SDK mock state via POST /mock. Unified dispatch for 5 actions.
# Usage:
#   mock.sh set    key=<k> value=<json>
#   mock.sh get    key=<k>
#   mock.sh reset
#   mock.sh enable enabled=<true|false>
#   mock.sh list

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_ensure_health

PORT="${VL_PORT:-9123}"
ACTION="${1:?action required: set|get|reset|enable|list (positional arg 1)}"; shift

KEY=""
VALUE=""
ENABLED=""
for arg in "$@"; do
  case "$arg" in
    key=*)     KEY="${arg#key=}";;
    value=*)   VALUE="${arg#value=}";;
    enabled=*) ENABLED="${arg#enabled=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 51;;
  esac
done

case "$ACTION" in
  set)
    [ -n "$KEY" ]   || { echo "ERR: 'set' requires key=" >&2; exit 52; }
    [ -n "$VALUE" ] || { echo "ERR: 'set' requires value=" >&2; exit 53; }
    PAYLOAD=$(printf '{"action":"set","key":"%s","value":%s}' "$KEY" "$VALUE")
    ;;
  get)
    [ -n "$KEY" ] || { echo "ERR: 'get' requires key=" >&2; exit 52; }
    PAYLOAD=$(printf '{"action":"get","key":"%s"}' "$KEY")
    ;;
  reset)
    PAYLOAD='{"action":"reset"}'
    ;;
  enable)
    [ -n "$ENABLED" ] || { echo "ERR: 'enable' requires enabled=" >&2; exit 54; }
    PAYLOAD=$(printf '{"action":"enable","enabled":%s}' "$ENABLED")
    ;;
  list)
    PAYLOAD='{"action":"list"}'
    ;;
  *)
    echo "ERR: invalid action '$ACTION' (expected: set|get|reset|enable|list)" >&2
    exit 51
    ;;
esac

TMP=$(mktemp -t fw-mock.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/mock" \
  -H 'content-type: application/json' \
  -d "$PAYLOAD") || HTTP_CODE="000"

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 56;;
  501) echo "ERR: no MockDataProvider configured (call FlutterWright.start(mockProvider:...))" >&2; cat "$TMP" >&2; exit 55;;
  *)   echo "ERR: /mock returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 56;;
esac
