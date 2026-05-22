#!/usr/bin/env bash
# _lib.sh — shared helpers for flutter-wright scripts.
# Source this from each method script:
#   source "$(dirname "$0")/_lib.sh"
#   fw_ensure_health
#
# Not meant to be executed directly.

# fw_ensure_health
#   Idempotent env check, run implicitly before every method.
#
#   Fast-path: if $CLAUDE_JOB_DIR/fw_health_done exists, return 0 immediately
#   (the env was already validated earlier in this job).
#
#   First call in a job (or when FW_HEALTH_FORCE is set): runs the full chain:
#     1. adb is on PATH                          (exit 10 on failure)
#     2. curl is on PATH                          (exit 13)
#     3. at least one adb device is connected     (exit 11)
#     4. adb forward tcp:$VL_PORT tcp:$VL_PORT    (idempotent, never fails noisily)
#     5. GET /health on 127.0.0.1:$VL_PORT        (exit 12 — SDK not running)
#
#   On success writes a marker file ($CLAUDE_JOB_DIR/fw_health_done) and exports
#   FW_DEVICE_ID for callers that need it.
#
# Env vars:
#   VL_PORT           Port to forward + probe. Default 9123.
#   CLAUDE_JOB_DIR    Job-scoped scratch dir. Falls back to /tmp.
#   FW_HEALTH_FORCE   If non-empty, skip fast-path and always run full check
#                     (health.sh uses this so explicit `health` is a real dry-run).
fw_ensure_health() {
  local marker="${CLAUDE_JOB_DIR:-/tmp}/fw_health_done"
  local port="${VL_PORT:-9123}"

  if [ -z "${FW_HEALTH_FORCE:-}" ] && [ -f "$marker" ]; then
    # Fast-path: env already validated in this job. Export device id from marker
    # so callers that need it (none today) still have it without re-running adb.
    if [ -z "${FW_DEVICE_ID:-}" ]; then
      FW_DEVICE_ID=$(awk -F= '/^device=/{print $2; exit}' "$marker" 2>/dev/null || true)
      export FW_DEVICE_ID
    fi
    return 0
  fi

  if ! command -v adb >/dev/null 2>&1; then
    echo "ERR: adb not installed. Install via 'brew install android-platform-tools' (macOS) or Android SDK." >&2
    exit 10
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "ERR: curl not installed." >&2
    exit 13
  fi

  local device_count
  device_count=$(adb devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')
  if [ "$device_count" -eq 0 ]; then
    echo "ERR: no adb device connected. Plug a device or start an emulator." >&2
    exit 11
  fi
  if [ "$device_count" -gt 1 ]; then
    echo "WARN: $device_count devices connected; using first." >&2
  fi

  local device_id
  device_id=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')

  adb -s "$device_id" forward tcp:"$port" tcp:"$port" >/dev/null

  if ! curl -sf "http://127.0.0.1:$port/health" >/dev/null; then
    echo "ERR: SDK not reachable on 127.0.0.1:$port. Is 'flutter run' active with FlutterWright.start()?" >&2
    exit 12
  fi

  mkdir -p "$(dirname "$marker")"
  printf 'device=%s\nport=%s\nts=%s\n' "$device_id" "$port" "$(date +%s)" > "$marker"

  export FW_DEVICE_ID="$device_id"
}
