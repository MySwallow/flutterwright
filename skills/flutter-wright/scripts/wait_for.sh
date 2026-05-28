#!/usr/bin/env bash
# wait_for.sh — wait until a condition holds via SDK /wait_for.
# Usage: wait_for.sh (text=<s> | ref=<s> | gone=<s>) [timeout=<ms>]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
declare -a Q=()
HAS_COND=""
for arg in "$@"; do
  case "$arg" in
    text=*|ref=*|gone=*) Q+=(--data-urlencode "$arg"); HAS_COND="1";;
    timeout=*) Q+=(--data-urlencode "$arg");;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 84;;
  esac
done
[ -n "$HAS_COND" ] || { echo "ERR: need one of text= / ref= / gone=" >&2; exit 84; }

TMP=$(mktemp -t fw-wait.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -G -o "$TMP" -w "%{http_code}" \
  "http://127.0.0.1:$PORT/wait_for" "${Q[@]}") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  408) echo "ERR: condition not met before timeout." >&2; cat "$TMP" >&2; exit 85;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /wait_for returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 85;;
esac
