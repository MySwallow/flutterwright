#!/usr/bin/env bash
# screenshot.sh — adb screencap to <out_path>. Captures full device frame (incl. status bar).
# Usage: screenshot.sh /path/to/out.png

set -euo pipefail

OUT="${1:?output path required}"
mkdir -p "$(dirname "$OUT")"

# exec-out keeps it binary-clean (no \r\n translation on Windows-y adb)
adb exec-out screencap -p > "$OUT"

# Sanity: must be > 1KB and start with PNG magic (89 50 4E 47)
if [ ! -s "$OUT" ]; then
  echo "ERR: empty screenshot" >&2
  exit 20
fi
SIZE=$(wc -c < "$OUT" | tr -d ' ')
if [ "$SIZE" -lt 1024 ]; then
  echo "ERR: screenshot too small ($SIZE bytes)" >&2
  exit 21
fi
# Verify PNG magic
MAGIC=$(head -c 4 "$OUT" | xxd -p)
if [ "$MAGIC" != "89504e47" ]; then
  echo "ERR: file is not a PNG (magic=$MAGIC). Device may be locked." >&2
  exit 22
fi
echo "captured: $OUT ($SIZE bytes)"
