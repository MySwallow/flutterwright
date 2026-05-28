#!/usr/bin/env bash
# snapshot.sh — fetch the Playwright-style semantics snapshot (YAML).
# Usage: snapshot.sh [out=<path>]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
OUT=""
for arg in "$@"; do
  case "$arg" in
    out=*) OUT="${arg#out=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 80;;
  esac
done

TMP=$(mktemp -t fw-snap.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" "http://127.0.0.1:$PORT/snapshot") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200)
    if [ -n "$OUT" ]; then mkdir -p "$(dirname "$OUT")"; cp "$TMP" "$OUT"; echo "snapshot -> $OUT" >&2; fi
    cat "$TMP"; echo
    ;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /snapshot returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 80;;
esac
