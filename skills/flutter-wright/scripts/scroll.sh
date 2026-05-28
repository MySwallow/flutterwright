#!/usr/bin/env bash
# scroll.sh — scroll a scrollable element by ref via SDK /scroll.
# Usage: scroll.sh "<element>" ref=<ref> dir=<up|down|left|right>
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
ELEMENT="${1:?element description required (positional arg 1)}"
shift
REF=""; DIR=""
for arg in "$@"; do
  case "$arg" in
    ref=*) REF="${arg#ref=}";;
    dir=*) DIR="${arg#dir=}";;
    amount=*) : ;;  # reserved; SDK v1 ignores amount
    *) echo "ERR: unknown arg '$arg'" >&2; exit 56;;
  esac
done
[ -n "$REF" ] || { echo "ERR: ref= required" >&2; exit 50; }
case "$DIR" in up|down|left|right) ;; *) echo "ERR: dir must be up|down|left|right" >&2; exit 56;; esac
for v in "$ELEMENT" "$REF"; do
  if [[ "$v" == *'"'* || "$v" == *'\'* || "$v" == *$'\n'* ]]; then
    echo "ERR: value contains unsupported characters." >&2; exit 56
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s","dir":"%s"}' "$ELEMENT" "$REF" "$DIR")
TMP=$(mktemp -t fw-scroll.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/scroll" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  404) echo "ERR: ref '$REF' not in latest snapshot — re-run snapshot." >&2; cat "$TMP" >&2; exit 51;;
  422) echo "ERR: '$ELEMENT' (ref $REF) has no scroll$DIR action." >&2; cat "$TMP" >&2; exit 52;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /scroll returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 57;;
esac
