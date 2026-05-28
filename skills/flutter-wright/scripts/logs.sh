#!/usr/bin/env bash
# logs.sh — print app.log lines captured by the run-owned flutter daemon.
# Usage: logs.sh [since=<n>] [grep=<pat>]
set -euo pipefail

LOG="${CLAUDE_JOB_DIR:-/tmp}/fw_daemon.log"
[ -f "$LOG" ] || { echo "ERR: no daemon log at $LOG — start the app first (run)." >&2; exit 92; }

SINCE=""; PAT=""
for arg in "$@"; do
  case "$arg" in
    since=*) SINCE="${arg#since=}";;
    grep=*)  PAT="${arg#grep=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 92;;
  esac
done

LINES=$(grep '"app.log"' "$LOG" || true)
[ -n "$PAT" ]   && LINES=$(printf '%s\n' "$LINES" | grep -E "$PAT" || true)
[ -n "$SINCE" ] && LINES=$(printf '%s\n' "$LINES" | tail -n "$SINCE")
printf '%s\n' "$LINES"
