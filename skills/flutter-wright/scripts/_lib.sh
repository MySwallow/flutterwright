#!/usr/bin/env bash
# _lib.sh — shared helpers for flutter-wright scripts. Source, don't execute.
#   source "$(dirname "$0")/_lib.sh"
#   fw_need_adb        # methods that only need a device (screenshot/setViewport/logs)
#   fw_need_sdk        # methods that talk to the in-app SDK (goto/reset/health)

# fw_need_adb — adb on PATH + at least one connected device.
#   Exits 10 (no adb) / 11 (no device). Exports FW_DEVICE_ID (first device).
fw_need_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "ERR: adb not installed. Install via 'brew install --cask android-platform-tools' (macOS) or Android SDK." >&2
    exit 10
  fi
  local n
  n=$(adb devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')
  if [ "$n" -eq 0 ]; then
    echo "ERR: no adb device connected. Plug a device or start an emulator." >&2
    exit 11
  fi
  [ "$n" -gt 1 ] && echo "WARN: $n devices connected; using first." >&2
  FW_DEVICE_ID=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
  export FW_DEVICE_ID
}

# fw_need_sdk — the in-app SDK is reachable. Requires FW_BASE (set by fw_resolve_target).
#   Probes GET $FW_BASE/health (unauthenticated, design 9). No adb/device dependency.
#   Exits 13 (no curl) / 14 (no target resolved) / 12 (SDK unreachable).
fw_need_sdk() {
  command -v curl >/dev/null 2>&1 || { echo "ERR: curl not installed." >&2; exit 13; }
  [ -n "${FW_BASE:-}" ] || { echo "ERR: no target resolved — call fw_resolve_target first." >&2; exit 14; }
  if ! curl -sf "$FW_BASE/health" >/dev/null; then
    echo "ERR: SDK not reachable at $FW_BASE/health. Is the app running with FlutterWright.start(enabled: true)?" >&2
    exit 12
  fi
}

# fw_registry_lines — load the registry's data lines (comments/blanks stripped) from
#   $FW_TARGETS into FW_REGISTRY_LINES, or exit 14 if missing/empty. Single source of the
#   registry-file contract (pipe-delimited name|base|token|package[|deviceport]). Sets a
#   global (not a subshell echo) so the `exit 14` propagates to the caller's process.
fw_registry_lines() {
  local reg="${FW_TARGETS:-}"
  if [ -z "$reg" ] || [ ! -f "$reg" ]; then
    echo "ERR: target registry not found. Set FW_TARGETS to a registry file (see «目标» in SKILL.md)." >&2
    exit 14
  fi
  FW_REGISTRY_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$reg" || true)"
  [ -n "$FW_REGISTRY_LINES" ] || { echo "ERR: target registry '$reg' has no entries." >&2; exit 14; }
}

# fw_base_port — echo the TCP port from a base URL like http://127.0.0.1:9123[/...].
#   Drops a trailing slash, takes everything after the last colon, then drops any path.
#   The loopback convention always carries an explicit port.
fw_base_port() {
  local b="${1%/}"        # drop one trailing slash
  b="${b##*:}"            # everything after the last colon
  printf '%s' "${b%%/*}"  # drop any trailing path
}

# fw_resolve_target — resolve the SDK target from the registry at $FW_TARGETS.
#   Registry: pipe-delimited lines `name|base|token|package[|deviceport]` (# comments /
#   blanks skipped; pipe is non-whitespace so empty middle fields survive). Reads an
#   optional `target=<name>` from "$@" (does NOT touch positional args). Single entry =>
#   default; multiple entries require target=. Sets+exports FW_BASE/FW_TOKEN/FW_PACKAGE/
#   FW_DEVICE_PORT/FW_TARGET_NAME and the FW_AUTH array (curl -H args; empty when no
#   token). FW_DEVICE_PORT defaults to the base's port when the 5th field is empty.
#   Exits 14 (no usable registry) / 15 (target not found or ambiguous).
fw_resolve_target() {
  local want="" a
  for a in "$@"; do case "$a" in target=*) want="${a#target=}";; esac; done

  fw_registry_lines             # sets FW_REGISTRY_LINES, or exits 14
  local lines="$FW_REGISTRY_LINES"

  local line
  if [ -n "$want" ]; then
    line="$(printf '%s\n' "$lines" | awk -F'|' -v n="$want" '$1==n{print; exit}')"
    [ -n "$line" ] || { echo "ERR: target '$want' not found in '${FW_TARGETS}'." >&2; exit 15; }
  else
    local count
    count="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
    [ "$count" = "1" ] || { echo "ERR: registry has $count targets; pass target=<name> to choose one." >&2; exit 15; }
    line="$lines"
  fi

  local _n
  IFS='|' read -r _n FW_BASE FW_TOKEN FW_PACKAGE FW_DEVICE_PORT <<< "$line"
  [ -n "${FW_BASE:-}" ] || { echo "ERR: registry entry '${_n:-?}' has empty base." >&2; exit 14; }
  [ -n "${FW_DEVICE_PORT:-}" ] || FW_DEVICE_PORT="$(fw_base_port "$FW_BASE")"
  [ -n "$FW_DEVICE_PORT" ] || { echo "ERR: cannot derive device port from base '$FW_BASE' — base must include a port (e.g. http://127.0.0.1:9123)." >&2; exit 14; }
  FW_TARGET_NAME="$_n"
  export FW_BASE FW_TOKEN FW_PACKAGE FW_DEVICE_PORT FW_TARGET_NAME
  # if/then (not `[ ] && ...`): under the callers' `set -e`, a false `[ -n "" ]` as the
  # function's LAST statement would make fw_resolve_target return 1 and abort the script
  # on the common no-token path. `if` with no else returns 0 when the token is empty.
  FW_AUTH=()
  if [ -n "${FW_TOKEN:-}" ]; then
    FW_AUTH=(-H "X-FW-Token: $FW_TOKEN")
  fi
}
