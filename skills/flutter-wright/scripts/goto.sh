#!/usr/bin/env bash
# goto.sh — push a named route on the device via SDK /navigate.
# Usage: goto.sh <route> [args=<json>] [popUntilRoot=<bool>]
#   goto.sh /order/detail args='{"id":"ORD-001"}'
#   goto.sh /home popUntilRoot=false

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_resolve_target "$@"
fw_need_sdk

ROUTE="${1:?route required (positional arg 1)}"
shift

ARGS="null"
POP_UNTIL_ROOT="true"
for arg in "$@"; do
  case "$arg" in
    args=*) ARGS="${arg#args=}";;
    popUntilRoot=*) POP_UNTIL_ROOT="${arg#popUntilRoot=}";;
    target=*) ;;
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
  "$FW_BASE/navigate" \
  -H 'content-type: application/json' \
  "${FW_AUTH[@]+"${FW_AUTH[@]}"}" \
  -d "$PAYLOAD") || HTTP_CODE="000"

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 43;;
  503) echo "ERR: navigator not ready (app not mounted yet?)" >&2; cat "$TMP" >&2; exit 41;;
  500) echo "ERR: push failed (route '$ROUTE' not in onGenerateRoute? args type mismatch?)" >&2; cat "$TMP" >&2; exit 42;;
  # 501 (navigation not configured, permanent) intentionally shares exit 41 with 503
  # (navigator not ready, transient) per spec; the stderr message distinguishes them.
  501) echo "ERR: navigation not configured — host must pass navigatorKey/navigationAdapter to FlutterWright.start(). One-time host setup; retrying won't help." >&2; cat "$TMP" >&2; exit 41;;
  *)   echo "ERR: /navigate returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 43;;
esac
