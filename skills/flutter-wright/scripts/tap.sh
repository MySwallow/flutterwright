#!/usr/bin/env bash
# tap.sh — tap an element by ref (from a prior snapshot) via SDK /tap.
# Usage: tap.sh "<element>" ref=<ref>
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
ELEMENT="${1:?element description required (positional arg 1)}"
shift
REF=""
for arg in "$@"; do
  case "$arg" in
    ref=*) REF="${arg#ref=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 50;;
  esac
done
[ -n "$REF" ] || { echo "ERR: ref= required" >&2; exit 50; }
for v in "$ELEMENT" "$REF"; do
  if [[ "$v" == *'"'* || "$v" == *'\'* || "$v" == *$'\n'* ]]; then
    echo "ERR: value contains unsupported characters (quotes/backslash/newline)." >&2; exit 50
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s"}' "$ELEMENT" "$REF")
TMP=$(mktemp -t fw-tap.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/tap" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  404) echo "ERR: ref '$REF' not in latest snapshot — re-run snapshot." >&2; cat "$TMP" >&2; exit 51;;
  422) echo "ERR: '$ELEMENT' (ref $REF) has no tap action." >&2; cat "$TMP" >&2; exit 52;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /tap returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 57;;
esac
