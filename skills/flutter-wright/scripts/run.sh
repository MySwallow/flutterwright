#!/usr/bin/env bash
# run.sh — launch `flutter run --machine` in the background and hold the daemon
# so later reload.sh / stop.sh can drive it. State lives in $CLAUDE_JOB_DIR.
#
# Usage: run.sh [target] [device=<id>] [project=<dir>]
#   run.sh                              # target=lib/main.dart, first device, cwd
#   run.sh dev/main_dev.dart            # SDK-integrated dev entry (enables goto)
#   run.sh lib/main.dart device=emulator-5554
#
# Exit: 0 ok / 10 adb / 11 device / 36 flutter not found / 37 already running / 38 app didn't start

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_adb   # adb on PATH + >=1 device; exports FW_DEVICE_ID

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
mkdir -p "$JOB_DIR"
FIFO="$JOB_DIR/fw_daemon.in"
LOG="$JOB_DIR/fw_daemon.log"
ENV_FILE="$JOB_DIR/fw_daemon.env"

# Refuse to double-launch.
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [ -n "${DAEMON_PID:-}" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "ERR: daemon already running (appId=${APP_ID:-?} pid=$DAEMON_PID). Call 'stop' first." >&2
    exit 37
  fi
fi

# Parse args: bare token = target; key=value pairs for device/project.
TARGET="lib/main.dart"
DEVICE="$FW_DEVICE_ID"
PROJECT_DIR="$PWD"
for arg in "$@"; do
  case "$arg" in
    device=*)  DEVICE="${arg#device=}";;
    project=*) PROJECT_DIR="${arg#project=}";;
    *)         TARGET="$arg";;
  esac
done

FLUTTER_BIN="$(fw_locate_flutter)" || {
  echo "ERR: flutter not found. Set FLUTTER_BIN or add flutter to PATH." >&2; exit 36;
}

# Fresh pipe + log.
rm -f "$FIFO" "$LOG"
mkfifo "$FIFO"

# Holder keeps the FIFO write-end open so the daemon's stdin never sees EOF
# between commands. `tail -f /dev/null` is the portable (macOS/Linux) no-op writer
# — note `sleep infinity` is NOT portable to macOS BSD sleep.
tail -f /dev/null > "$FIFO" 2>/dev/null &
HOLDER_PID=$!
disown "$HOLDER_PID" 2>/dev/null || true

# Launch the daemon detached: cwd=PROJECT_DIR, stdin<-FIFO, stdout/stderr->LOG.
# `exec` so DAEMON_PID is the flutter process itself (clean kill -0 / kill later).
( cd "$PROJECT_DIR" && exec "$FLUTTER_BIN" run --machine -t "$TARGET" -d "$DEVICE" ) < "$FIFO" > "$LOG" 2>&1 &
DAEMON_PID=$!
disown "$DAEMON_PID" 2>/dev/null || true

# Persist state early so stop.sh can always clean up, even on timeout below.
{
  echo "DAEMON_PID=$DAEMON_PID"
  echo "HOLDER_PID=$HOLDER_PID"
  echo "DEVICE=$DEVICE"
  echo "FIFO=$FIFO"
  echo "LOG=$LOG"
} > "$ENV_FILE"

# Wait for app.start (carries appId) then app.started (first frame), with timeout.
APP_ID=""
DEADLINE=$(( $(date +%s) + 180 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "ERR: flutter run exited early. Last log lines:" >&2
    tail -n 20 "$LOG" >&2 || true
    exit 38
  fi
  if [ -z "$APP_ID" ]; then
    APP_ID=$(grep -m1 '"app.start"' "$LOG" 2>/dev/null \
      | grep -o '"appId":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  fi
  if grep -q '"app.started"' "$LOG" 2>/dev/null; then
    break
  fi
  sleep 1
done

# Persist any appId we parsed, so stop.sh can do a polite app.stop even on timeout.
[ -n "$APP_ID" ] && echo "APP_ID=$APP_ID" >> "$ENV_FILE"

if [ -z "$APP_ID" ] || ! grep -q '"app.started"' "$LOG" 2>/dev/null; then
  echo "ERR: app did not start within 180s. Last log lines:" >&2
  tail -n 20 "$LOG" >&2 || true
  exit 38
fi

echo "ok: appId=$APP_ID device=$DEVICE target=$TARGET"
