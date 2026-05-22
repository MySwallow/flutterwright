#!/usr/bin/env bash
# reload.sh — Flutter hot reload via SDK /reload endpoint (vm_service.reloadSources).
# Requires SDK >= 0.2.0 in the host app. No fifo / no stdin handling.
# Usage: reload.sh

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_ensure_health

PORT="${VL_PORT:-9123}"

TMP=$(mktemp -t fw-reload.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/reload" \
  -H 'content-type: application/json' \
  -d '{}') || HTTP_CODE="000"

case "$HTTP_CODE" in
  200) echo "reloaded";;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 30;;
  503) echo "ERR: VM service not available (release build? or SDK < 0.2.0)" >&2; cat "$TMP" >&2; exit 31;;
  *)   echo "ERR: /reload returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 32;;
esac

sleep 1   # give Flutter a beat to apply the reload before returning
