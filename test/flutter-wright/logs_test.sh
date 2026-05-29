#!/usr/bin/env bash
# logs_test.sh — logs.sh runs `adb logcat -d` (设计 7: no run/daemon dependency). With a
# registry package → pidof + --pid; without FW_TARGETS → -s flutter. since→-t, grep→ERE
# pipe. package set but not running → 93; bad arg → 92. Uses fake adb (no device).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_test_fake_adb
FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"; export FW_TARGETS
trap 'rm -rf "${FW_FAKE_BIN:-}"; rm -f "${FW_FAKE_ADB_LOG:-}" "${FW_TARGETS:-}"' EXIT
printf 'shop|http://127.0.0.1:9123||com.acme.shop\n' > "$FW_TARGETS"
fail=0

# --- registry package → pidof + logcat --pid=<pid> ---
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/logs.sh" 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: logs(pkg) exit $code" >&2; fail=1; }
grep -q -- 'shell pidof -s com.acme.shop' "$FW_FAKE_ADB_LOG" || { echo "FAIL: no pidof for package: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
grep -q -- 'logcat -d --pid=12345' "$FW_FAKE_ADB_LOG" || { echo "FAIL: logcat not --pid filtered: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *hello*) ;; *) echo "FAIL: logs output missing canned line: $out" >&2; fail=1;; esac

# --- since=N → logcat -t N ; grep=ERROR keeps only the ERROR line ---
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/logs.sh" since=50 grep=ERROR 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: logs(since/grep) exit $code" >&2; fail=1; }
grep -q -- 'logcat -d -t 50 --pid=12345' "$FW_FAKE_ADB_LOG" || { echo "FAIL: -t 50 not passed: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *ERROR*) ;; *) echo "FAIL: grep=ERROR dropped the ERROR line: $out" >&2; fail=1;; esac
case "$out" in *hello*) echo "FAIL: grep=ERROR should have dropped 'hello': $out" >&2; fail=1;; *) ;; esac

# --- package set but not running (pidof empty) → 93 ---
FW_FAKE_PIDOF= bash "$FW_SCRIPTS_DIR/logs.sh" >/dev/null 2>&1; code=$?
[ "$code" -eq 93 ] || { echo "FAIL: package-not-running expected 93, got $code" >&2; fail=1; }

# --- no registry → fall back to -s flutter ---
( unset FW_TARGETS; : > "$FW_FAKE_ADB_LOG"
  out="$(bash "$FW_SCRIPTS_DIR/logs.sh" 2>/dev/null)"; c=$?
  [ "$c" -eq 0 ] || { echo "FAIL: logs(no reg) exit $c" >&2; exit 1; }
  grep -q -- 'logcat -d -s flutter' "$FW_FAKE_ADB_LOG" || { echo "FAIL: no -s flutter fallback: $(cat "$FW_FAKE_ADB_LOG")" >&2; exit 1; } ) || fail=1

# --- unknown arg → 92 ---
bash "$FW_SCRIPTS_DIR/logs.sh" bogus=1 >/dev/null 2>&1; code=$?
[ "$code" -eq 92 ] || { echo "FAIL: bad arg expected 92, got $code" >&2; fail=1; }

# --- FW_TARGETS set but file missing → 14 (misconfig, not silent -s flutter) ---
FW_TARGETS=/nonexistent/fw-registry bash "$FW_SCRIPTS_DIR/logs.sh" >/dev/null 2>&1; code=$?
[ "$code" -eq 14 ] || { echo "FAIL: missing registry file expected 14, got $code" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: logs adb logcat (pid / fallback / since / grep / 93 / 92 / 14)"
exit "$fail"
