#!/usr/bin/env bash
# resolve_target_test.sh — fw_resolve_target reads the FW_TARGETS registry (pipe-delimited
# name|base|token|package[|deviceport]), exports FW_BASE/FW_TOKEN/FW_PACKAGE/FW_DEVICE_PORT/
# FW_TARGET_NAME and builds the FW_AUTH
# curl-header array. Exits 14 (no usable registry) / 15 (ambiguous or unknown target).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../scripts/_lib.sh"

reg="$(mktemp -t fw-reg.XXXXXX)"
trap 'rm -f "$reg"' EXIT
fail=0

# --- single entry, no token: FW_AUTH empty ---
printf 'shop|http://127.0.0.1:9123||com.acme.shop\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_BASE" = "http://127.0.0.1:9123" ] || { echo "FAIL: base=$FW_BASE" >&2; fail=1; }
[ -z "$FW_TOKEN" ] || { echo "FAIL: token should be empty, got '$FW_TOKEN'" >&2; fail=1; }
[ "$FW_PACKAGE" = "com.acme.shop" ] || { echo "FAIL: package=$FW_PACKAGE" >&2; fail=1; }
[ "${#FW_AUTH[@]}" -eq 0 ] || { echo "FAIL: FW_AUTH should be empty (len ${#FW_AUTH[@]})" >&2; fail=1; }

# --- single entry, with token: FW_AUTH = (-H "X-FW-Token: sec") ---
printf 'qa|http://127.0.0.1:9200|sec|com.acme.qa\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_TOKEN" = "sec" ] || { echo "FAIL: token=$FW_TOKEN" >&2; fail=1; }
if [ "${#FW_AUTH[@]}" -eq 2 ] && [ "${FW_AUTH[0]}" = "-H" ] && [ "${FW_AUTH[1]}" = "X-FW-Token: sec" ]; then :; else
  echo "FAIL: FW_AUTH wrong (len ${#FW_AUTH[@]})" >&2; fail=1
fi

# --- two entries, target= selects ---
printf 'a|http://127.0.0.1:1|t1|p1\nb|http://127.0.0.1:2|t2|p2\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target target=b
{ [ "$FW_BASE" = "http://127.0.0.1:2" ] && [ "$FW_TOKEN" = "t2" ]; } || { echo "FAIL: target= base=$FW_BASE token=$FW_TOKEN" >&2; fail=1; }

# --- error paths (function calls exit → run in subshell) ---
( unset FW_TARGETS; fw_resolve_target ) 2>/dev/null; rc=$?
[ "$rc" -eq 14 ] || { echo "FAIL: missing registry expected 14, got $rc" >&2; fail=1; }
( FW_TARGETS="$reg" fw_resolve_target ) 2>/dev/null; rc=$?
[ "$rc" -eq 15 ] || { echo "FAIL: ambiguous expected 15, got $rc" >&2; fail=1; }
( FW_TARGETS="$reg" fw_resolve_target target=zzz ) 2>/dev/null; rc=$?
[ "$rc" -eq 15 ] || { echo "FAIL: unknown target expected 15, got $rc" >&2; fail=1; }

# --- set -e compatibility: empty token must NOT abort the caller (callers run set -euo
#     pipefail; an empty-token registry is the common no-auth path). Regression guard. ---
printf 'shop|http://127.0.0.1:9123||com.acme.shop\n' > "$reg"
FW_TARGETS="$reg" FW_LIB="$DIR/../scripts/_lib.sh" bash -c '
  set -euo pipefail
  source "$FW_LIB"
  fw_resolve_target
  [ -n "$FW_BASE" ]
'
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: empty token aborts fw_resolve_target under set -e (got $rc)" >&2; fail=1; }

# --- deviceport: explicit 5th field is used verbatim; name is exported ---
printf 'shop|http://127.0.0.1:9124|tok|com.acme.shop|9123\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_DEVICE_PORT" = "9123" ] || { echo "FAIL: explicit deviceport=$FW_DEVICE_PORT (want 9123)" >&2; fail=1; }
[ "$FW_TARGET_NAME" = "shop" ] || { echo "FAIL: target name=$FW_TARGET_NAME (want shop)" >&2; fail=1; }

# --- deviceport: omitted (4-field line) defaults to the port parsed from base ---
printf 'shop|http://127.0.0.1:9124|tok|com.acme.shop\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_DEVICE_PORT" = "9124" ] || { echo "FAIL: defaulted deviceport=$FW_DEVICE_PORT (want 9124)" >&2; fail=1; }

# --- fw_base_port: strips scheme/host + trailing slash, keeps the port ---
[ "$(fw_base_port 'http://127.0.0.1:9123')" = "9123" ] || { echo "FAIL: fw_base_port plain" >&2; fail=1; }
[ "$(fw_base_port 'http://127.0.0.1:9124/')" = "9124" ] || { echo "FAIL: fw_base_port trailing slash" >&2; fail=1; }

# --- port-less base is a misconfig: device port cannot be derived → exit 14 ---
printf 'bad|http://127.0.0.1||com.acme.bad\n' > "$reg"
( FW_TARGETS="$reg" fw_resolve_target ) 2>/dev/null; rc=$?
[ "$rc" -eq 14 ] || { echo "FAIL: port-less base expected 14, got $rc" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: fw_resolve_target registry resolution"
exit "$fail"
