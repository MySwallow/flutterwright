#!/usr/bin/env bash
# targets_list_test.sh — `targets.sh` (list) prints every registry row and probes each
# /health (ok / unreachable). Unknown subcommand → 17; missing registry → 14. (设计 4/6,
# Phase 3 探活/列举.) The mock backs the reachable entry; a closed port is unreachable.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_mock_start || exit 1   # /health always returns 200; the POST-status arg is irrelevant here
FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"; export FW_TARGETS
# 'up' points at the live mock; 'down' at a closed port (1) → unreachable.
printf 'up|http://127.0.0.1:%s||com.test.up\ndown|http://127.0.0.1:1||com.test.down\n' "$FW_MOCK_PORT" > "$FW_TARGETS"
trap 'fw_mock_stop; rm -f "${FW_TARGETS:-}"' EXIT

fail=0

out="$(bash "$FW_SCRIPTS_DIR/targets.sh" 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: targets list exit $code" >&2; fail=1; }
printf '%s\n' "$out" | grep -qE '^up[[:space:]].*ok$'           || { echo "FAIL: 'up' row not reachable: $out" >&2; fail=1; }
printf '%s\n' "$out" | grep -qE '^down[[:space:]].*unreachable$' || { echo "FAIL: 'down' row not unreachable: $out" >&2; fail=1; }

# unknown subcommand → 17
( bash "$FW_SCRIPTS_DIR/targets.sh" bogus ) >/dev/null 2>&1; code=$?
[ "$code" -eq 17 ] || { echo "FAIL: unknown subcommand expected 17, got $code" >&2; fail=1; }

# missing registry → 14
( unset FW_TARGETS; bash "$FW_SCRIPTS_DIR/targets.sh" ) >/dev/null 2>&1; code=$?
[ "$code" -eq 14 ] || { echo "FAIL: missing registry expected 14, got $code" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: targets list + probe + exit codes"
exit "$fail"
