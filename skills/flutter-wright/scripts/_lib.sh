#!/usr/bin/env bash
# _lib.sh — shared helpers for flutter-wright scripts. Source, don't execute.
#   source "$(dirname "$0")/_lib.sh"
#   fw_need_adb        # methods that only need a device (screenshot/setViewport/run)
#   fw_need_sdk        # methods that talk to the in-app SDK (goto/reset/health)
#   fw_locate_flutter  # echo path to the flutter binary, or return 1

# fw_need_adb — adb on PATH + at least one connected device.
#   Exits 10 (no adb) / 11 (no device). Exports FW_DEVICE_ID (first device).
fw_need_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "ERR: adb not installed. Install via 'brew install --cask android-platform-tools' (macOS) or Android SDK." >&2
    exit 10
  fi
  local n
  n=$(adb devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')
  if [ "$n" -eq 0 ]; then
    echo "ERR: no adb device connected. Plug a device or start an emulator." >&2
    exit 11
  fi
  [ "$n" -gt 1 ] && echo "WARN: $n devices connected; using first." >&2
  FW_DEVICE_ID=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
  export FW_DEVICE_ID
}

# fw_need_sdk — everything fw_need_adb checks, plus the in-app SDK is reachable:
#   adb forward tcp:$VL_PORT + GET /health. Exits 12 (SDK unreachable) / 13 (no curl).
#   Fast-path: if $CLAUDE_JOB_DIR/fw_health_done exists (and FW_HEALTH_FORCE unset),
#   the SDK was already validated this job — return immediately.
fw_need_sdk() {
  local marker="${CLAUDE_JOB_DIR:-/tmp}/fw_health_done"
  local port="${VL_PORT:-9123}"

  if [ -z "${FW_HEALTH_FORCE:-}" ] && [ -f "$marker" ]; then
    if [ -z "${FW_DEVICE_ID:-}" ]; then
      FW_DEVICE_ID=$(awk -F= '/^device=/{print $2; exit}' "$marker" 2>/dev/null || true)
      export FW_DEVICE_ID
    fi
    return 0
  fi

  fw_need_adb
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERR: curl not installed." >&2
    exit 13
  fi
  adb -s "$FW_DEVICE_ID" forward tcp:"$port" tcp:"$port" >/dev/null
  if ! curl -sf "http://127.0.0.1:$port/health" >/dev/null; then
    echo "ERR: SDK not reachable on 127.0.0.1:$port. Is the app running with FlutterWright.start()?" >&2
    exit 12
  fi
  mkdir -p "$(dirname "$marker")"
  printf 'device=%s\nport=%s\nts=%s\n' "$FW_DEVICE_ID" "$port" "$(date +%s)" > "$marker"
}

# fw_locate_flutter — echo the flutter binary path, or return 1.
#   Order: $FLUTTER_BIN → PATH → common install locations.
fw_locate_flutter() {
  if [ -n "${FLUTTER_BIN:-}" ] && [ -x "$FLUTTER_BIN" ]; then
    echo "$FLUTTER_BIN"; return 0
  fi
  if command -v flutter >/dev/null 2>&1; then
    command -v flutter; return 0
  fi
  local c
  for c in "$HOME/development/flutter/bin/flutter" "$HOME/flutter/bin/flutter" "/usr/local/bin/flutter" "/opt/homebrew/bin/flutter"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
