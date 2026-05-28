#!/usr/bin/env bash
# _helpers.sh — shared harness for flutter-wright script tests. Source, don't execute.
FW_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_SCRIPTS_DIR="$(cd "$FW_TEST_DIR/../scripts" && pwd)"
export FW_SCRIPTS_DIR

# fw_test_setup_target [token] — write a one-entry registry pointing at the running mock
# and export FW_TARGETS. Call AFTER fw_mock_start (needs FW_MOCK_PORT). The trap should
# also `rm -f "${FW_TARGETS:-}"`.
fw_test_setup_target() {
  local token="${1:-}"
  [ -n "${FW_MOCK_PORT:-}" ] || { echo "ERR: FW_MOCK_PORT not set — call fw_mock_start first." >&2; return 1; }
  FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"
  export FW_TARGETS
  printf 'local-mock|http://127.0.0.1:%s|%s|com.test.app\n' "$FW_MOCK_PORT" "$token" > "$FW_TARGETS"
}

# fw_mock_start [status] — launch mock_sdk.py on an OS-assigned free port returning
# <status> (default 501) for /navigate and /reset. The mock binds port 0 and prints
# its real port on stdout (no TOCTOU race). Exports FW_MOCK_PORT, sets FW_MOCK_PID,
# waits until /health responds. On failure prints the mock's stderr for diagnosis.
fw_mock_start() {
  local status="${1:-501}"
  [ -n "${FW_MOCK_PID:-}" ] && fw_mock_stop  # avoid leaking a mock from a prior call
  local port_file err_file i
  port_file="$(mktemp -t fw-port.XXXXXX)"
  err_file="$(mktemp -t fw-mockerr.XXXXXX)"
  FW_MOCK_STATUS="$status" python3 "$FW_TEST_DIR/mock_sdk.py" 0 >"$port_file" 2>"$err_file" &
  FW_MOCK_PID=$!
  FW_MOCK_PORT=""
  for i in $(seq 1 50); do
    FW_MOCK_PORT="$(cat "$port_file" 2>/dev/null)"
    [ -n "$FW_MOCK_PORT" ] && break
    sleep 0.1
  done
  if [ -z "$FW_MOCK_PORT" ]; then
    echo "ERR: mock did not report a port:" >&2; cat "$err_file" >&2
    rm -f "$port_file" "$err_file"; return 1
  fi
  export FW_MOCK_PORT
  for i in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:$FW_MOCK_PORT/health" && { rm -f "$port_file" "$err_file"; return 0; }
    sleep 0.1
  done
  echo "ERR: mock on $FW_MOCK_PORT not responding:" >&2; cat "$err_file" >&2
  rm -f "$port_file" "$err_file"; return 1
}

# fw_mock_stop — kill the mock if running and reap it quietly (the explicit `wait`
# suppresses the shell's async "Terminated" job notice). Safe in a trap / called twice.
fw_mock_stop() {
  [ -n "${FW_MOCK_PID:-}" ] || return 0
  kill "$FW_MOCK_PID" 2>/dev/null
  wait "$FW_MOCK_PID" 2>/dev/null
  FW_MOCK_PID=""
  return 0
}

# fw_test_fake_adb — install a fake `adb` on PATH that logs every invocation (space-joined
# args) to FW_FAKE_ADB_LOG and answers `adb devices` with one device (emulator-5554), so
# adb-dependent scripts run device-free. Set FW_FAKE_ADB_FAIL=1 (per-invocation) to make
# `forward` calls exit 1. Set FW_FAKE_PIDOF=<pid> to override the fake `shell pidof` reply
# (default 12345; empty string makes pidof print nothing and exit 1, like a not-running pkg).
# Caller's trap should: rm -rf "$FW_FAKE_BIN"; rm -f "$FW_FAKE_ADB_LOG".
# NOTE: prepends $FW_FAKE_BIN to PATH for the life of the sourcing shell; after the trap
# removes that dir, `adb` falls through to the next PATH entry. Test-only — don't source
# outside a test.
fw_test_fake_adb() {
  FW_FAKE_BIN="$(mktemp -d -t fw-fakebin.XXXXXX)"
  FW_FAKE_ADB_LOG="$(mktemp -t fw-adblog.XXXXXX)"
  export FW_FAKE_ADB_LOG
  cat > "$FW_FAKE_BIN/adb" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FW_FAKE_ADB_LOG"
if [ "${FW_FAKE_ADB_FAIL:-}" = "1" ]; then
  case "$*" in *forward*) exit 1;; esac
fi
case "$1" in
  devices) printf 'List of devices attached\nemulator-5554\tdevice\n';;
esac
case "$*" in
  *"shell pidof"*) if [ -n "${FW_FAKE_PIDOF-12345}" ]; then printf '%s\n' "${FW_FAKE_PIDOF-12345}"; else exit 1; fi;;
  *logcat*)        printf 'I/flutter ( 1234): hello\nE/flutter ( 1234): boom ERROR\n';;
esac
exit 0
SH
  chmod +x "$FW_FAKE_BIN/adb"
  export PATH="$FW_FAKE_BIN:$PATH"
}
