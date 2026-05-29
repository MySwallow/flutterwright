#!/usr/bin/env bash
# dispatch_naming_test.sh — guards the 派发约定 camelCase→snake_case rule (设计 1).
#   Part A (durable invariant): every method in SKILL.md's 方法 table maps — via the
#           rule — to an existing script whose name equals the table's 脚本 column.
#   Part B (设计 1 deliverable): SKILL.md documents the rule (keyword "snake_case").
# No device / SDK needed. Exit 0 = pass.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL="$DIR/../../skills/flutter-wright/SKILL.md"
SCRIPTS="$DIR/../../skills/flutter-wright/scripts"
fail=0

# --- Part A: structural invariant over the 方法 table ---
# Table data rows start with "| `" and carry a *.sh in the 脚本 column. Parse the
# WHOLE line (do NOT split on IFS='|' — cells contain escaped pipes such as
# dir=<up\|down\|left\|right>). method = first backtick identifier; script = the *.sh token.
while IFS= read -r line; do
  # Assumes the first backtick-quoted token on each row is the method name, and the
  # (only) *.sh token is the script — holds for the 方法 table's column layout.
  method=$(printf '%s' "$line" | sed -E 's/^[^`]*`([A-Za-z]+).*/\1/')
  script=$(printf '%s' "$line" | grep -oE '[a-z_]+\.sh' | tail -1)
  [ -n "$method" ] || continue
  expected="$(printf '%s' "$method" | sed 's/\([A-Z]\)/_\1/g' | tr '[:upper:]' '[:lower:]').sh"
  if [ "$expected" != "$script" ]; then
    echo "FAIL: method '$method' → rule derives '$expected' but table says '$script'" >&2
    fail=1
  fi
  if [ ! -f "$SCRIPTS/$expected" ]; then
    echo "FAIL: derived script '$expected' for method '$method' missing on disk" >&2
    fail=1
  fi
done < <(grep -E '^\| `' "$SKILL" | grep '\.sh')

# --- Part B: the rule is documented in SKILL.md ---
# The sole RED driver is the 'snake_case' keyword check below. The 5 .sh-example
# checks are supplementary: they match the whole file (incl. the method table) so
# they are already green pre-edit — kept as a soft guard against silent removal.
if ! grep -q 'snake_case' "$SKILL"; then
  echo "FAIL: SKILL.md 派发约定 missing the snake_case dispatch rule" >&2
  fail=1
fi
for m in 'wait_for.sh' 'long_press.sh' 'press_key.sh' 'set_viewport.sh' 'reset_viewport.sh'; do
  if ! grep -q "$m" "$SKILL"; then
    echo "FAIL: SKILL.md missing camelCase→snake example '$m'" >&2
    fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "PASS: dispatch naming rule consistent & documented"
exit "$fail"
