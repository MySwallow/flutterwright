#!/usr/bin/env bash
# targets_forward_test.sh — `targets.sh forward target=<name>` runs
# `adb -s <dev> forward tcp:<local> tcp:<deviceport>`, mapping the base's local port to
# the registry deviceport (explicit 5th field, else defaulting to the local port). adb
# failure → exit 16. Uses a fake adb (no device). 设计 6 / Phase 3.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_test_fake_adb
FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"; export FW_TARGETS
trap 'rm -rf "${FW_FAKE_BIN:-}"; rm -f "${FW_FAKE_ADB_LOG:-}" "${FW_TARGETS:-}"' EXIT

fail=0

# --- explicit deviceport: local 9124 maps to device 9123 ---
printf 'shop|http://127.0.0.1:9124||com.acme.shop|9123\n' > "$FW_TARGETS"
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/targets.sh" forward target=shop 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: forward exit $code" >&2; fail=1; }
grep -q -- '-s emulator-5554 forward tcp:9124 tcp:9123' "$FW_FAKE_ADB_LOG" || { echo "FAIL: explicit mapping wrong: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *"(shop)"*) ;; *) echo "FAIL: forward stdout lacks target name: $out" >&2; fail=1;; esac

# --- omitted deviceport: defaults to the base's local port (9200 -> 9200) ---
printf 'qa|http://127.0.0.1:9200||com.acme.qa\n' > "$FW_TARGETS"
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/targets.sh" forward target=qa 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: forward(default) exit $code" >&2; fail=1; }
grep -q -- '-s emulator-5554 forward tcp:9200 tcp:9200' "$FW_FAKE_ADB_LOG" || { echo "FAIL: default mapping wrong: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *"(qa)"*) ;; *) echo "FAIL: forward(default) stdout lacks target name: $out" >&2; fail=1;; esac

# --- adb forward failure → exit 16 ---
printf 'shop|http://127.0.0.1:9124||com.acme.shop|9123\n' > "$FW_TARGETS"
: > "$FW_FAKE_ADB_LOG"
FW_FAKE_ADB_FAIL=1 bash "$FW_SCRIPTS_DIR/targets.sh" forward target=shop >/dev/null 2>&1; code=$?
[ "$code" -eq 16 ] || { echo "FAIL: adb forward failure expected 16, got $code" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: targets forward maps local->device port via fake adb"
exit "$fail"
