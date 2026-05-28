#!/usr/bin/env bash
# type.sh — set text on a field by ref via SDK /type; optional submit (ENTER).
# Usage: type.sh "<element>" ref=<ref> text=<text> [submit=<bool>]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk   # also sets FW_DEVICE_ID for the optional ENTER keyevent

PORT="${VL_PORT:-9123}"
ELEMENT="${1:?element description required (positional arg 1)}"
shift
REF=""; TEXT=""; SUBMIT="false"
for arg in "$@"; do
  case "$arg" in
    ref=*) REF="${arg#ref=}";;
    text=*) TEXT="${arg#text=}";;
    submit=*) SUBMIT="${arg#submit=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 53;;
  esac
done
[ -n "$REF" ] || { echo "ERR: ref= required" >&2; exit 50; }
for v in "$ELEMENT" "$REF" "$TEXT"; do
  if [[ "$v" == *'"'* || "$v" == *'\'* || "$v" == *$'\n'* ]]; then
    echo "ERR: value contains unsupported characters (quotes/backslash/newline)." >&2; exit 53
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s","text":"%s"}' "$ELEMENT" "$REF" "$TEXT")
TMP=$(mktemp -t fw-type.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/type" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) ;;
  404) echo "ERR: ref '$REF' not in latest snapshot — re-run snapshot." >&2; cat "$TMP" >&2; exit 51;;
  422) echo "ERR: '$ELEMENT' (ref $REF) is not an editable text field." >&2; cat "$TMP" >&2; exit 54;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /type returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 55;;
esac
if [ "$SUBMIT" = "true" ]; then
  adb -s "$FW_DEVICE_ID" shell input keyevent 66 >/dev/null   # KEYCODE_ENTER
fi
cat "$TMP"; echo
