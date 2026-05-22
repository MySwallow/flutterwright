#!/usr/bin/env bash
# health.sh — flutter_wright health check: adb, device, port forward, SDK reachability.
# Exits non-zero with a single line "ERR: <reason>" on failure.

set -euo pipefail

PORT="${VL_PORT:-9123}"

if ! command -v adb >/dev/null 2>&1; then
  echo "ERR: adb not installed. Install via 'brew install android-platform-tools' (macOS) or Android SDK."
  exit 10
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERR: curl not installed."
  exit 13
fi

DEVICE_COUNT=$(adb devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')
if [ "$DEVICE_COUNT" -eq 0 ]; then
  echo "ERR: no adb device connected. Plug a device or start an emulator."
  exit 11
fi
if [ "$DEVICE_COUNT" -gt 1 ]; then
  echo "WARN: $DEVICE_COUNT devices connected; using first."
fi

DEVICE_ID=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
echo "device: $DEVICE_ID"

# Ensure port forward exists (idempotent)
adb -s "$DEVICE_ID" forward tcp:"$PORT" tcp:"$PORT" >/dev/null

# Probe /health
if ! curl -sf "http://127.0.0.1:$PORT/health" >/dev/null; then
  echo "ERR: SDK not reachable on 127.0.0.1:$PORT. Is 'flutter run' active with FlutterWright.start()?"
  exit 12
fi

echo "ok: device=$DEVICE_ID port=$PORT"
