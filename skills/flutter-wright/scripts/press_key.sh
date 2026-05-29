#!/usr/bin/env bash
# press_key.sh — send a hardware/IME key via adb. No SDK needed.
# Usage: press_key.sh <enter|back|home|tab|del|search|menu>
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_adb

KEY="${1:?key name required (enter|back|home|tab|del|search|menu)}"
case "$KEY" in
  enter)  CODE=66;;
  back)   CODE=4;;
  home)   CODE=3;;
  tab)    CODE=61;;
  del)    CODE=67;;
  search) CODE=84;;
  menu)   CODE=82;;
  *) echo "ERR: unknown key '$KEY'" >&2; exit 90;;
esac
if adb -s "$FW_DEVICE_ID" shell input keyevent "$CODE" >/dev/null; then
  echo "pressed: $KEY (keycode $CODE)"
else
  echo "ERR: adb keyevent $CODE failed" >&2; exit 91
fi
