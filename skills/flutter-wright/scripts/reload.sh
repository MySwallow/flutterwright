#!/usr/bin/env bash
# reload.sh — hot reload the AI-owned flutter daemon (app.restart, fullRestart=false).
# Requires a prior `run`. Does NOT touch the SDK.
# Usage: reload.sh
# Exit: 0 ok / 33 no owned daemon / 34 daemon dead / 35 reload failed or timed out

set -euo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
ENV_FILE="$JOB_DIR/fw_daemon.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERR: no AI-owned flutter run. Call 'run' first, or press 'r' in your own flutter run console." >&2
  exit 33
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${DAEMON_PID:-}" ] || ! kill -0 "$DAEMON_PID" 2>/dev/null; then
  echo "ERR: flutter daemon not alive (pid=${DAEMON_PID:-?}). Call 'run' again." >&2
  exit 34
fi

REQ_ID=$$
OFFSET=$(wc -l < "$LOG" 2>/dev/null | tr -d ' '); OFFSET="${OFFSET:-0}"

printf '[{"id":%d,"method":"app.restart","params":{"appId":"%s","fullRestart":false,"pause":false,"reason":"manual"}}]\n' \
  "$REQ_ID" "$APP_ID" > "$FIFO"

DEADLINE=$(( $(date +%s) + 60 ))
LINE=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  LINE=$(tail -n "+$((OFFSET + 1))" "$LOG" 2>/dev/null | grep -m1 "\"id\":$REQ_ID," || true)
  [ -n "$LINE" ] && break
  sleep 1
done

if [ -z "$LINE" ]; then
  echo "ERR: reload timed out after 60s (no response id=$REQ_ID)" >&2
  exit 35
fi
if printf '%s' "$LINE" | grep -q '"code":0'; then
  sleep 1   # let Flutter apply the reload before returning
  echo "reloaded"
else
  echo "ERR: reload failed: $LINE" >&2
  exit 35
fi
