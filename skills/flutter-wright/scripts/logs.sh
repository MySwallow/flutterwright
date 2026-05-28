#!/usr/bin/env bash
# logs.sh — dump device logs via `adb logcat -d` (no run/daemon dependency, 设计 7). If the
# target registry resolves a package, filter by its pid (logcat --pid); else `-s flutter`.
# since=<n> → logcat -t <n>; grep=<pat> → ERE pipe filter; target=<name> picks the entry.
# Usage: logs.sh [since=<n>] [grep=<pat>] [target=<name>]
set -euo pipefail
# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_adb   # adb on PATH + >=1 device; exports FW_DEVICE_ID (exits 10/11)

# Package comes from the registry (for precise --pid). With FW_TARGETS unset, logs stays
# usable via `-s flutter`. With FW_TARGETS set, resolve it — a missing/empty registry then
# fails 14 (and ambiguity 15), surfacing the misconfig instead of silently mis-filtering.
if [ -n "${FW_TARGETS:-}" ]; then
  fw_resolve_target "$@"   # sets FW_PACKAGE (+ FW_BASE… unused here); exits 14/15
fi

SINCE=""; PAT=""
for arg in "$@"; do
  case "$arg" in
    since=*)  SINCE="${arg#since=}";;
    grep=*)   PAT="${arg#grep=}";;
    target=*) ;;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 92;;
  esac
done

# if/then (not `[ ] && ...`): a false test as a bare statement returns 1 and would abort
# under set -e.
LOGCAT=(adb -s "$FW_DEVICE_ID" logcat -d)
if [ -n "$SINCE" ]; then LOGCAT+=(-t "$SINCE"); fi

PKG="${FW_PACKAGE:-}"
if [ -n "$PKG" ]; then
  pid="$(adb -s "$FW_DEVICE_ID" shell pidof -s "$PKG" 2>/dev/null | tr -d '\r\n ' || true)"
  [ -n "$pid" ] || { echo "ERR: package '$PKG' not running on device $FW_DEVICE_ID." >&2; exit 93; }
  LOGCAT+=(--pid="$pid")
else
  LOGCAT+=(-s flutter)
fi

OUT="$("${LOGCAT[@]}")"
if [ -n "$PAT" ]; then OUT="$(printf '%s\n' "$OUT" | grep -E -- "$PAT" || true)"; fi
printf '%s\n' "$OUT"
