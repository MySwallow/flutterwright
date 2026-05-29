#!/usr/bin/env bash
# snapshot_smoke_test.sh — GET-script migration smoke (Phase 2): snapshot.sh and
# wait_for.sh resolve the target, hit $FW_BASE with the auth header, and return the
# mock's YAML. The registry carries a token, so the scripts must send X-FW-Token.
set -uo pipefail  # no -e: out=$(...) captures a non-zero script exit; we inspect $code manually
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_mock_start 200 || exit 1            # GET /snapshot & /wait_for → mock returns 200
fw_test_setup_target tok123 || exit 1  # registry carries a token → scripts send X-FW-Token
trap 'fw_mock_stop; rm -f "${FW_TARGETS:-}"' EXIT

fail=0

out="$(bash "$FW_SCRIPTS_DIR/snapshot.sh" 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: snapshot.sh exit $code" >&2; fail=1; }
case "$out" in
  *"[ref=s1]"*) ;;
  *) echo "FAIL: snapshot stdout missing mock ref: $out" >&2; fail=1;;
esac

out="$(bash "$FW_SCRIPTS_DIR/wait_for.sh" text=mock 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: wait_for.sh exit $code" >&2; fail=1; }
case "$out" in
  *"[ref=s1]"*) ;;
  *) echo "FAIL: wait_for stdout missing mock ref: $out" >&2; fail=1;;
esac

[ "$fail" -eq 0 ] && echo "PASS: snapshot.sh + wait_for.sh resolve target + fetch via GET"
exit "$fail"
