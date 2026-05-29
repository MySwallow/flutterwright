#!/usr/bin/env bash
# health.sh — explicit SDK probe.
#
# Resolves the target (fw_resolve_target) and checks the in-app SDK is reachable
# (GET $base/health, unauthenticated). No adb/device dependency. Callers rarely need
# this explicitly — the SDK-talking methods run the same check implicitly.
#
# Exits non-zero with a single "ERR: <reason>" line on failure
# (12 SDK unreachable / 13 no curl / 14 no/invalid target registry / 15 ambiguous target).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

fw_resolve_target "$@"
fw_need_sdk

echo "ok: base=$FW_BASE${FW_PACKAGE:+ package=$FW_PACKAGE}"
