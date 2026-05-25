#!/usr/bin/env bash
# stop.sh — stop the AI-owned flutter daemon and clean up. Always exits 0
# (safe to call from a trap / cleanup hook).
# Usage: stop.sh

set -uo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
ENV_FILE="$JOB_DIR/fw_daemon.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "no AI-owned flutter run to stop"
  exit 0
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# Polite app.stop first (best-effort), then kill the processes.
if [ -n "${APP_ID:-}" ] && [ -n "${FIFO:-}" ] && [ -p "${FIFO:-}" ]; then
  printf '[{"id":0,"method":"app.stop","params":{"appId":"%s"}}]\n' "$APP_ID" > "$FIFO" 2>/dev/null || true
  sleep 1
fi
[ -n "${DAEMON_PID:-}" ] && kill "$DAEMON_PID" 2>/dev/null || true
[ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null || true
rm -f "${FIFO:-}" "${LOG:-}" "$ENV_FILE"
echo "stopped: appId=${APP_ID:-?}"
exit 0
