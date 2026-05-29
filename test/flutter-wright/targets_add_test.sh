#!/usr/bin/env bash
# targets_add_test.sh — `targets.sh add name= base= [package=] [deviceport=]` appends ONE
# token-less registry line to $FW_TARGETS (guided entry; 设计 4). The token field is left
# empty on purpose (a secret must never transit the agent transcript), so `token=` is
# refused (18). Validates required args / bad base / duplicate / pipe-injection (18) and
# missing FW_TARGETS (14). The written line must round-trip through fw_resolve_target.
# No device / SDK / curl needed — pure local file write.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"
source "$DIR/../../skills/flutter-wright/scripts/_lib.sh"   # for the fw_resolve_target round-trip check below

reg="$(mktemp -t fw-reg.XXXXXX)"; rm -f "$reg"   # start from a non-existent file: add must create it
trap 'rm -f "$reg"' EXIT
fail=0
T="$FW_SCRIPTS_DIR/targets.sh"

# --- add creates the file + writes name|base||package|deviceport (token empty) ---
out="$(FW_TARGETS="$reg" bash "$T" add name=shop base=http://127.0.0.1:9123 package=com.acme.shop 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: add exit $code" >&2; fail=1; }
[ -f "$reg" ] || { echo "FAIL: add did not create $reg" >&2; fail=1; }
grep -qx 'shop|http://127.0.0.1:9123||com.acme.shop|' "$reg" || { echo "FAIL: written line wrong: $(cat "$reg")" >&2; fail=1; }
case "$out" in *"token left empty"*) ;; *) echo "FAIL: stdout lacks token-empty notice: $out" >&2; fail=1;; esac

# --- the line round-trips through fw_resolve_target (single entry => default) ---
( FW_TARGETS="$reg" fw_resolve_target
  { [ "$FW_BASE" = "http://127.0.0.1:9123" ] && [ -z "$FW_TOKEN" ] && [ "$FW_PACKAGE" = "com.acme.shop" ]; } \
    || { echo "FAIL: resolve mismatch base=$FW_BASE token=$FW_TOKEN pkg=$FW_PACKAGE" >&2; exit 1; } ) || fail=1

# --- explicit deviceport is written as field 5 ---
out="$(FW_TARGETS="$reg" bash "$T" add name=qa base=http://127.0.0.1:9200 deviceport=9123 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: add(deviceport) exit $code" >&2; fail=1; }
grep -qx 'qa|http://127.0.0.1:9200|||9123' "$reg" || { echo "FAIL: deviceport line wrong: $(grep '^qa' "$reg")" >&2; fail=1; }

# --- duplicate name → 18 ---
FW_TARGETS="$reg" bash "$T" add name=shop base=http://127.0.0.1:9999 >/dev/null 2>&1; code=$?
[ "$code" -eq 18 ] || { echo "FAIL: duplicate name expected 18, got $code" >&2; fail=1; }

# --- token= on the command line is refused → 18 (security: never transit the transcript) ---
FW_TARGETS="$reg" bash "$T" add name=sec base=http://127.0.0.1:9001 token=hunter2 >/dev/null 2>&1; code=$?
[ "$code" -eq 18 ] || { echo "FAIL: token= expected 18, got $code" >&2; fail=1; }
grep -q 'hunter2' "$reg" && { echo "FAIL: refused token still leaked into $reg" >&2; fail=1; }

# --- missing name/base → 18 ---
FW_TARGETS="$reg" bash "$T" add name=onlyname >/dev/null 2>&1; code=$?
[ "$code" -eq 18 ] || { echo "FAIL: missing base expected 18, got $code" >&2; fail=1; }

# --- base without a port → 18 ---
FW_TARGETS="$reg" bash "$T" add name=noport base=http://127.0.0.1 >/dev/null 2>&1; code=$?
[ "$code" -eq 18 ] || { echo "FAIL: port-less base expected 18, got $code" >&2; fail=1; }

# --- pipe injection in a field → 18 ---
FW_TARGETS="$reg" bash "$T" add name='a|b' base=http://127.0.0.1:9002 >/dev/null 2>&1; code=$?
[ "$code" -eq 18 ] || { echo "FAIL: pipe in field expected 18, got $code" >&2; fail=1; }

# --- FW_TARGETS unset → 14 ---
( unset FW_TARGETS; bash "$T" add name=x base=http://127.0.0.1:9003 ) >/dev/null 2>&1; code=$?
[ "$code" -eq 14 ] || { echo "FAIL: unset FW_TARGETS expected 14, got $code" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: targets add appends a token-less entry (+ validation 18 / 14)"
exit "$fail"
