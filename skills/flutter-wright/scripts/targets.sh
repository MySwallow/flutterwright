#!/usr/bin/env bash
# targets.sh — inspect the SDK target registry. Modes:
#   targets.sh [list]                  list every entry + probe each /health
#   targets.sh forward target=<name>   adb forward tcp:<local> tcp:<deviceport> for one
# List needs curl. forward needs adb + a device. The registry is operator-authored
# (never mutated here); base/deviceport come from it via fw_resolve_target.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

case "${1:-}" in
  forward)
    shift
    fw_resolve_target "$@"      # sets FW_BASE / FW_DEVICE_PORT / FW_TARGET_NAME (exits 14/15)
    fw_need_adb                 # sets FW_DEVICE_ID (exits 10/11)
    lport="$(fw_base_port "$FW_BASE")"
    if ! adb -s "$FW_DEVICE_ID" forward "tcp:$lport" "tcp:$FW_DEVICE_PORT" >/dev/null; then
      echo "ERR: 'adb forward tcp:$lport tcp:$FW_DEVICE_PORT' failed." >&2; exit 16
    fi
    echo "forwarded tcp:$lport -> device tcp:$FW_DEVICE_PORT (${FW_TARGET_NAME})"
    ;;
  list|"")
    command -v curl >/dev/null 2>&1 || { echo "ERR: curl not installed." >&2; exit 13; }
    fw_registry_lines           # sets FW_REGISTRY_LINES (exits 14)
    printf '%-12s %-28s %-18s %s\n' NAME BASE PACKAGE HEALTH
    while IFS='|' read -r name base _ package _; do
      [ -n "$name" ] || continue
      if curl -sf --max-time 3 -o /dev/null "$base/health"; then health="ok"; else health="unreachable"; fi
      printf '%-12s %-28s %-18s %s\n' "$name" "$base" "${package:-—}" "$health"
    done <<< "$FW_REGISTRY_LINES"
    ;;
  *)
    echo "ERR: unknown 'targets' subcommand '$1' (use: targets | targets forward target=<name>)" >&2
    exit 17
    ;;
esac
