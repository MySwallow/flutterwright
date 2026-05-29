#!/usr/bin/env bash
# targets.sh — inspect / author the SDK target registry ($FW_TARGETS). Modes:
#   targets.sh [list]                       list every entry + probe each /health
#   targets.sh forward target=<name>        adb forward tcp:<local> tcp:<deviceport>
#   targets.sh add name=<n> base=<url> ...  append one entry (TOKEN LEFT EMPTY)
# list needs curl; forward needs adb + a device; add only writes the local file. The
# registry is operator-owned; `add` appends a token-less line — a token is a secret and
# must never transit the agent transcript, so the integrator fills field 3 by hand.
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
  add)
    shift
    # Guided registry entry. The TOKEN FIELD IS LEFT EMPTY on purpose: a token is a secret
    # and must never pass through the agent transcript. If the SDK needs auth, the integrator
    # fills field 3 (between the 2nd and 3rd '|') by hand afterward. Pure local file write —
    # no adb/curl/SDK; reachability (forward) and probing (list) are separate steps.
    reg="${FW_TARGETS:-}"
    [ -n "$reg" ] || { echo "ERR: FW_TARGETS not set — point it at the registry file to create/append (e.g. export FW_TARGETS=~/.config/flutter-wright/targets)." >&2; exit 14; }
    name=""; base=""; package=""; deviceport=""
    for arg in "$@"; do
      case "$arg" in
        name=*)       name="${arg#name=}";;
        base=*)       base="${arg#base=}";;
        package=*)    package="${arg#package=}";;
        deviceport=*) deviceport="${arg#deviceport=}";;
        token=*) echo "ERR: refusing token= on the command line — it would leak into the transcript. Add the token to field 3 of the line in \$FW_TARGETS by hand." >&2; exit 18;;
        *) echo "ERR: unknown arg '$arg' (use: targets add name=<n> base=<url> [package=<pkg>] [deviceport=<port>])." >&2; exit 18;;
      esac
    done
    [ -n "$name" ] && [ -n "$base" ] || { echo "ERR: name= and base= are required." >&2; exit 18; }
    for f in "$name" "$base" "$package" "$deviceport"; do
      case "$f" in *'|'*|*$'\n'*) echo "ERR: fields may not contain '|' or newlines." >&2; exit 18;; esac
    done
    [ -n "$(fw_base_port "$base")" ] || { echo "ERR: base '$base' has no port — use http://HOST:PORT (e.g. http://127.0.0.1:9123)." >&2; exit 18; }
    if [ -f "$reg" ] && grep -vE '^[[:space:]]*(#|$)' "$reg" | awk -F'|' -v n="$name" '$1==n{f=1} END{exit !f}'; then
      echo "ERR: target '$name' already in $reg — edit it by hand or pick another name." >&2; exit 18
    fi
    mkdir -p "$(dirname "$reg")"
    printf '%s|%s||%s|%s\n' "$name" "$base" "$package" "$deviceport" >> "$reg"
    echo "added '$name' -> $base (token left empty) in $reg"
    echo "NOTE: if the SDK requires auth, edit $reg and put the token in field 3 (between the 2nd and 3rd '|'). Never paste a token through this agent." >&2
    ;;
  *)
    echo "ERR: unknown 'targets' subcommand '$1' (use: targets | targets forward target=<name> | targets add name=<n> base=<url> …)" >&2
    exit 17
    ;;
esac
