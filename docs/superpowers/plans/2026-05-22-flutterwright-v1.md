# FlutterWright v1 Implementation Plan

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `flutterwright` — a monorepo containing a Claude Code skill (Playwright-style API for Flutter on Android), the `flutter_visual_loop` Dart SDK (with new `/reload` endpoint), an example app, and reference docs.

**Architecture:** Skill (`skills/flutterwright/`) dispatches Playwright-style methods (goto/screenshot/reload/mock/...) into 8 internal bash scripts which talk to the SDK's debug-only HTTP control plane (on host Flutter app) via `adb forward` + `curl`. Hot reload is triggered by the SDK calling `vm_service.reloadSources` against its own VM service — no more fifo.

**Tech Stack:**
- Dart 3.5+ / Flutter 3.24+ (SDK)
- `vm_service: >=14.0.0 <16.0.0` (Dart package, for hot reload RPC)
- bash 4+ (scripts, no jq/python deps)
- adb, curl
- Claude Code skill (markdown SKILL.md)

**Spec reference:** `docs/superpowers/specs/2026-05-22-flutterwright-design.md`

**Repo path:** `/Users/mini/Documents/dev/github/flutterwright/`

---

## Phase 1 — Repository Infrastructure

### Task 1: Initialize git repository

**Files:**
- Create: `.git/` (via `git init`)

- [ ] **Step 1: Initialize git in the repo root**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git init
git branch -M main
```

- [ ] **Step 2: Verify**

```bash
git status
```
Expected: shows `On branch main` and lists all current files as untracked.

- [ ] **Step 3: Don't stage anything yet — Task 2 stages the scaffolding files together**

---

### Task 2: Repo scaffolding (LICENSE / .gitignore / root CHANGELOG)

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Copy LICENSE from flutter-visual-loop (MIT, same author)**

```bash
cp /Users/mini/Documents/dev/github/flutter-visual-loop/LICENSE /Users/mini/Documents/dev/github/flutterwright/LICENSE
```

- [ ] **Step 2: Create `.gitignore` for Dart/Flutter monorepo**

```gitignore
# Dart / Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/
pubspec.lock

# IDE
.idea/
.vscode/
*.iml

# macOS
.DS_Store

# Build artifacts
*.dart.js
*.dart.js.map
*.info

# Local job temp
/tmp/fw-job/
```

- [ ] **Step 3: Create root `CHANGELOG.md`**

```markdown
# CHANGELOG

## Unreleased

### Added
- Initial repo scaffold (monorepo: skill + SDK + example + docs).
- Skill `flutterwright` with 8 Playwright-style methods.
- SDK `flutter_visual_loop` 0.2.0 with `POST /reload` endpoint.

See `docs/superpowers/specs/2026-05-22-flutterwright-design.md` for design rationale.
```

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add LICENSE .gitignore CHANGELOG.md
```

**Do not commit** — user reviews and commits.

---

## Phase 2 — SDK Changes

### Task 3: SDK `pubspec.yaml` — bump version, tighten env, add `vm_service`

**Files:**
- Modify: `packages/flutter_visual_loop/pubspec.yaml`

- [ ] **Step 1: Replace `pubspec.yaml` contents**

```yaml
name: flutter_visual_loop
description: Debug-only HTTP control plane for Flutter apps — powers Playwright-style automation via the flutterwright skill.
version: 0.2.0
homepage: https://github.com/MySwallow/flutterwright
repository: https://github.com/MySwallow/flutterwright

environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.24.0"

dependencies:
  flutter:
    sdk: flutter
  vm_service: '>=14.0.0 <16.0.0'

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

- [ ] **Step 2: Run `flutter pub get` to validate constraints solve**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_visual_loop
flutter pub get
```
Expected: `Got dependencies!` (or similar success). If `pub solver` errors, the version range in `vm_service` needs widening or narrowing.

- [ ] **Step 3: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add packages/flutter_visual_loop/pubspec.yaml
```

---

### Task 4: SDK `CHANGELOG.md` — add 0.2.0 entry

**Files:**
- Modify: `packages/flutter_visual_loop/CHANGELOG.md`

- [ ] **Step 1: Prepend 0.2.0 entry**

```markdown
# 更新日志

## 0.2.0 - 2026-05-22

### Added
- `POST /reload` endpoint:Flutter hot reload via `vm_service.reloadSources`(VM service in-process RPC)。
- `vm_service: >=14.0.0 <16.0.0` 依赖。

### Changed
- SDK 环境约束收紧:`flutter: >=3.24.0`,`sdk: >=3.5.0`(原 `3.10.0` / `3.0.0`)。
- "shipped as part of [flutterwright](../../README.md) monorepo"。

## 0.1.0 (首次发布)

- 仅 debug 启用的 HTTP server,默认绑 `127.0.0.1:9123`(可配置)。
- Endpoints: `/health`, `/routes`, `/navigate`, `/reset`, `/mock`, `/screenshot`。
- `MockDataProvider` 接口 + `InMemoryMockDataProvider` 默认实现。
- `VisualLoopRoot` Widget 包装,让 app 内截图更可靠。
- Release 构建是 no-op(由 `kDebugMode` 守门)。
```

- [ ] **Step 2: Stage**

```bash
git add packages/flutter_visual_loop/CHANGELOG.md
```

---

### Task 5: Add `ReloadHandler` (`packages/flutter_visual_loop/lib/src/handlers/reload_handler.dart`)

**Files:**
- Create: `packages/flutter_visual_loop/lib/src/handlers/reload_handler.dart`

**Note:** Uses the SDK's actual `Handler` interface (`extends Handler` with `path`/`method`/`handle(ctx)`); writes response via `ctx.request.writeJson/writeOk/writeError`. Does NOT use a `HandlerResult` return value (the spec's draft code was schematic; this task uses the real API matching `navigate_handler.dart`).

- [ ] **Step 1: Create the handler file**

```dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../logger.dart';
import 'handler.dart';

class ReloadHandler extends Handler {
  ReloadHandler();

  @override
  String get path => '/reload';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final info = await developer.Service.getInfo();
    final serverUri = info.serverUri;
    if (serverUri == null) {
      await ctx.request.writeError(503, 'VM service is not enabled in this process');
      return;
    }

    final wsUri = _toWsUri(serverUri);
    VmService? vm;
    try {
      vm = await vmServiceConnectUri(wsUri.toString());
      final vmInfo = await vm.getVM();
      final isolates = vmInfo.isolates ?? const <IsolateRef>[];
      if (isolates.isEmpty) {
        await ctx.request.writeError(500, 'no isolates found');
        return;
      }
      final mainIso = isolates.firstWhere(
        (i) => i.name == 'main',
        orElse: () => isolates.first,
      );
      final result = await vm.reloadSources(mainIso.id!);
      final success = result.success ?? false;
      vlLog('reload success=$success');
      if (success) {
        await ctx.request.writeOk();
      } else {
        await ctx.request.writeError(500, 'reloadSources returned success=false');
      }
    } catch (e, st) {
      vlError('reload failed', e, st);
      await ctx.request.writeError(500, e.toString());
    } finally {
      await vm?.dispose();
    }
  }

  Uri _toWsUri(Uri http) {
    final path = http.path.endsWith('/') ? '${http.path}ws' : '${http.path}/ws';
    return http.replace(scheme: 'ws', path: path);
  }
}
```

- [ ] **Step 2: Run `flutter analyze` to check syntax/types**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_visual_loop
flutter analyze
```
Expected: `No issues found!` (or only pre-existing unrelated warnings).

- [ ] **Step 3: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add packages/flutter_visual_loop/lib/src/handlers/reload_handler.dart
```

---

### Task 6: Register `ReloadHandler` + bump SDK version constant in `visual_loop.dart`

**Files:**
- Modify: `packages/flutter_visual_loop/lib/src/visual_loop.dart`

- [ ] **Step 1: Add import for `reload_handler.dart`**

In `packages/flutter_visual_loop/lib/src/visual_loop.dart`, find the imports block (around line 6-11):

```dart
import 'handlers/handler.dart';
import 'handlers/health_handler.dart';
import 'handlers/mock_handler.dart';
import 'handlers/navigate_handler.dart';
import 'handlers/reset_handler.dart';
import 'handlers/routes_handler.dart';
import 'handlers/screenshot_handler.dart';
```

Add this line right after `screenshot_handler.dart` import:

```dart
import 'handlers/reload_handler.dart';
```

- [ ] **Step 2: Bump `version` constant from `'0.1.0'` to `'0.2.0'`**

Find:

```dart
  static const String version = '0.1.0';
```

Replace with:

```dart
  static const String version = '0.2.0';
```

- [ ] **Step 3: Register `ReloadHandler()` in the `handlers` list**

Find the `handlers = <Handler>[...]` block in the `start()` method (around line 57-67). It currently ends:

```dart
      ScreenshotHandler(config.screenshotMode),
    ];
```

Replace with:

```dart
      ScreenshotHandler(config.screenshotMode),
      ReloadHandler(),
    ];
```

- [ ] **Step 4: Run `flutter analyze`**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_visual_loop
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 5: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add packages/flutter_visual_loop/lib/src/visual_loop.dart
```

---

### Task 7: Add `reload_handler_test.dart`

**Files:**
- Create: `packages/flutter_visual_loop/test/reload_handler_test.dart`

- [ ] **Step 1: Create the test file**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_visual_loop/src/handlers/reload_handler.dart';

void main() {
  group('ReloadHandler', () {
    test('is registered on POST /reload', () {
      final h = ReloadHandler();
      expect(h.method, 'POST');
      expect(h.path, '/reload');
    });
  });
}
```

> **Note:** This test verifies registration only. End-to-end behavior (actual `vm_service.reloadSources` call) is verified in the manual smoke test (Task 24); it requires a live `flutter run` and isn't feasible as a unit test.

- [ ] **Step 2: Run `flutter test`**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_visual_loop
flutter test
```
Expected: `All tests passed!` (existing 2 + new 1 = 3 tests).

- [ ] **Step 3: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add packages/flutter_visual_loop/test/reload_handler_test.dart
```

---

## Phase 3 — Scripts (`skills/flutterwright/scripts/`)

### Task 8: `health.sh` (rename from `env_check.sh`, update top comment)

**Files:**
- Rename: `skills/flutterwright/scripts/env_check.sh` → `skills/flutterwright/scripts/health.sh`
- Modify: `skills/flutterwright/scripts/health.sh` (top comment)

- [ ] **Step 1: Rename**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts
mv env_check.sh health.sh
```

- [ ] **Step 2: Update the top comment**

Find lines 1-3:

```bash
#!/usr/bin/env bash
# env_check.sh — verify adb, device, port, server health.
# Exits non-zero with a single line "ERR: <reason>" on failure.
```

Replace with:

```bash
#!/usr/bin/env bash
# health.sh — flutterwright health check: adb, device, port forward, SDK reachability.
# Exits non-zero with a single line "ERR: <reason>" on failure.
```

- [ ] **Step 3: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/health.sh
```
Expected: no output (clean).

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/health.sh
git rm --cached skills/flutterwright/scripts/env_check.sh 2>/dev/null || true
```

> The `git rm --cached` only matters if `env_check.sh` was previously tracked (it's not in this fresh repo, but kept for safety).

---

### Task 9: `goto.sh` (rename from `navigate.sh`, support `popUntilRoot` + exit codes)

**Files:**
- Rename: `skills/flutterwright/scripts/navigate.sh` → `skills/flutterwright/scripts/goto.sh`
- Modify: `skills/flutterwright/scripts/goto.sh` (full rewrite for arg parsing + exit codes)

- [ ] **Step 1: Rename**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts
mv navigate.sh goto.sh
```

- [ ] **Step 2: Overwrite `goto.sh` with the v1 content**

```bash
#!/usr/bin/env bash
# goto.sh — push a named route on the device via SDK /navigate.
# Usage: goto.sh <route> [args=<json>] [popUntilRoot=<bool>]
#   goto.sh /order/detail args='{"id":"ORD-001"}'
#   goto.sh /home popUntilRoot=false

set -euo pipefail

PORT="${VL_PORT:-9123}"
ROUTE="${1:?route required (positional arg 1)}"
shift

ARGS="null"
POP_UNTIL_ROOT="true"
for arg in "$@"; do
  case "$arg" in
    args=*) ARGS="${arg#args=}";;
    popUntilRoot=*) POP_UNTIL_ROOT="${arg#popUntilRoot=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 40;;
  esac
done

# Validate route: only allow safe characters in v1 (path-style routes are the spec contract).
# Anything else fails early so we avoid hand-rolling JSON escaping in bash.
if [[ "$ROUTE" == *'"'* || "$ROUTE" == *'\'* || "$ROUTE" == *$'\n'* ]]; then
  echo "ERR: route '$ROUTE' contains unsupported characters (quotes/backslash/newline). Use simple path-style routes." >&2
  exit 40
fi

PAYLOAD=$(printf '{"route":"%s","args":%s,"popUntilRoot":%s}' "$ROUTE" "$ARGS" "$POP_UNTIL_ROOT")

TMP=$(mktemp -t fw-goto.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -sf -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/navigate" \
  -H 'content-type: application/json' \
  -d "$PAYLOAD") || { echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 43; }

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  503) echo "ERR: navigator not ready (app not mounted yet?)" >&2; cat "$TMP" >&2; exit 41;;
  500) echo "ERR: push failed (route '$ROUTE' not in onGenerateRoute? args type mismatch?)" >&2; cat "$TMP" >&2; exit 42;;
  *)   echo "ERR: /navigate returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 43;;
esac
```

> **Note:** Route is validated to contain only path-safe chars (no `"` / `\` / newline) before JSON-embedding via `printf`. v1 contract per spec §6.2 — routes are path-style names (`/order/detail`). No `python3` / `jq` / `dart` per spec §8.1.

- [ ] **Step 3: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/goto.sh
```
Expected: no output.

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/goto.sh
```

---

### Task 10: `screenshot.sh` (rename from `capture.sh`, update top comment)

**Files:**
- Rename: `skills/flutterwright/scripts/capture.sh` → `skills/flutterwright/scripts/screenshot.sh`
- Modify: `skills/flutterwright/scripts/screenshot.sh` (top comment)

- [ ] **Step 1: Rename**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts
mv capture.sh screenshot.sh
```

- [ ] **Step 2: Update the top comment**

Find lines 1-3:

```bash
#!/usr/bin/env bash
# capture.sh — screencap via adb. Writes to $1 (path).
# Usage: capture.sh /path/to/out.png
```

Replace with:

```bash
#!/usr/bin/env bash
# screenshot.sh — adb screencap to <out_path>. Captures full device frame (incl. status bar).
# Usage: screenshot.sh /path/to/out.png
```

- [ ] **Step 3: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/screenshot.sh
```
Expected: no output.

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/screenshot.sh
```

---

### Task 11: `reload.sh` (rename + full rewrite — no more fifo)

**Files:**
- Rename: `skills/flutterwright/scripts/hot_reload.sh` → `skills/flutterwright/scripts/reload.sh`
- Modify: `skills/flutterwright/scripts/reload.sh` (full rewrite)

- [ ] **Step 1: Rename**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts
mv hot_reload.sh reload.sh
```

- [ ] **Step 2: Overwrite with the v1 content**

```bash
#!/usr/bin/env bash
# reload.sh — Flutter hot reload via SDK /reload endpoint (vm_service.reloadSources).
# Requires SDK >= 0.2.0 in the host app. No fifo / no stdin handling.
# Usage: reload.sh

set -euo pipefail

PORT="${VL_PORT:-9123}"

TMP=$(mktemp -t fw-reload.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -sf -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/reload" \
  -H 'content-type: application/json' \
  -d '{}') || { echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 30; }

case "$HTTP_CODE" in
  200) echo "reloaded";;
  503) echo "ERR: VM service not available (release build? or SDK < 0.2.0)" >&2; cat "$TMP" >&2; exit 31;;
  *)   echo "ERR: /reload returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 32;;
esac

sleep 1   # give Flutter a beat to apply the reload before returning
```

- [ ] **Step 3: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/reload.sh
```
Expected: no output.

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/reload.sh
```

---

### Task 12: `set_viewport.sh` (rename from `setup.sh`, remove skip mode, state file rename, readback check)

**Files:**
- Rename: `skills/flutterwright/scripts/setup.sh` → `skills/flutterwright/scripts/set_viewport.sh`
- Modify: `skills/flutterwright/scripts/set_viewport.sh` (full rewrite)

- [ ] **Step 1: Rename**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts
mv setup.sh set_viewport.sh
```

- [ ] **Step 2: Overwrite with the v1 content**

```bash
#!/usr/bin/env bash
# set_viewport.sh — lock device wm size + density to match design resolution.
# Usage: set_viewport.sh <width> <height> <dpi>   (e.g. 1080 2400 480)
# Records originals to $CLAUDE_JOB_DIR/fw_original.env for reset_viewport.sh.
# Caller responsibility: always call reset_viewport.sh on completion (best-effort).

set -euo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
mkdir -p "$JOB_DIR"
ORIG_FILE="$JOB_DIR/fw_original.env"

W="${1:?width required (positional arg 1)}"
H="${2:?height required (positional arg 2)}"
D="${3:?density required (positional arg 3)}"

# Record originals once (don't overwrite on repeated calls in same job)
if [ ! -f "$ORIG_FILE" ]; then
  ORIG_SIZE=$(adb shell wm size | tr -d '\r' | awk -F': ' '/Physical size|Override size/{print $2; exit}')
  ORIG_DENSITY=$(adb shell wm density | tr -d '\r' | awk -F': ' '/Physical density|Override density/{print $2; exit}')
  {
    echo "ORIG_SIZE=$ORIG_SIZE"
    echo "ORIG_DENSITY=$ORIG_DENSITY"
  } > "$ORIG_FILE"
  echo "recorded originals: size=$ORIG_SIZE density=$ORIG_DENSITY -> $ORIG_FILE"
fi

adb shell wm size "${W}x${H}"
adb shell wm density "$D"

# Readback validation (some vendor ROMs silently reject wm overrides)
ACTUAL_SIZE=$(adb shell wm size | tr -d '\r' | awk -F': ' '/Override size/{print $2; exit}')
ACTUAL_DENSITY=$(adb shell wm density | tr -d '\r' | awk -F': ' '/Override density/{print $2; exit}')

if [ "$ACTUAL_SIZE" != "${W}x${H}" ]; then
  echo "ERR: wm size override rejected (vendor ROM?). Got '$ACTUAL_SIZE', expected '${W}x${H}'" >&2
  exit 61
fi
if [ "$ACTUAL_DENSITY" != "$D" ]; then
  echo "ERR: wm density override rejected. Got '$ACTUAL_DENSITY', expected '$D'" >&2
  exit 61
fi

echo "viewport: ${W}x${H} @ ${D}dpi"
```

> **Changes vs. old `setup.sh`:** (1) removed `setup.sh skip` mode (callers just don't call), (2) state file renamed `vl_original.env` → `fw_original.env`, (3) added readback validation that fails with exit 61 on vendor-ROM silent rejection.

- [ ] **Step 3: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/set_viewport.sh
```
Expected: no output.

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/set_viewport.sh
```

---

### Task 13: `reset_viewport.sh` (rename from `reset_device.sh`, change env file path)

**Files:**
- Rename: `skills/flutterwright/scripts/reset_device.sh` → `skills/flutterwright/scripts/reset_viewport.sh`
- Modify: `skills/flutterwright/scripts/reset_viewport.sh` (state file path)

- [ ] **Step 1: Rename**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts
mv reset_device.sh reset_viewport.sh
```

- [ ] **Step 2: Overwrite with the v1 content**

```bash
#!/usr/bin/env bash
# reset_viewport.sh — restore wm size/density saved by set_viewport.sh.
# Always exits 0 (idempotent / best-effort) so it's safe to call from a trap.
# Usage: reset_viewport.sh

set -uo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
ORIG_FILE="$JOB_DIR/fw_original.env"

if [ ! -f "$ORIG_FILE" ]; then
  echo "no originals recorded; running 'wm size reset' + 'wm density reset' as fallback"
  adb shell wm size reset 2>/dev/null || true
  adb shell wm density reset 2>/dev/null || true
  exit 0
fi

# shellcheck disable=SC1090
source "$ORIG_FILE"

if [ -n "${ORIG_SIZE:-}" ]; then
  adb shell wm size "$ORIG_SIZE" 2>/dev/null || adb shell wm size reset 2>/dev/null || true
fi
if [ -n "${ORIG_DENSITY:-}" ]; then
  adb shell wm density "$ORIG_DENSITY" 2>/dev/null || adb shell wm density reset 2>/dev/null || true
fi
rm -f "$ORIG_FILE"
echo "restored: size=${ORIG_SIZE:-?} density=${ORIG_DENSITY:-?}"
```

> **Changes vs. old `reset_device.sh`:** state file `vl_original.env` → `fw_original.env`. Logic otherwise unchanged.

- [ ] **Step 3: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/reset_viewport.sh
```
Expected: no output.

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/reset_viewport.sh
```

---

### Task 14: `mock.sh` (replaces `mock_set.sh`, 5-action dispatch)

**Files:**
- Delete: `skills/flutterwright/scripts/mock_set.sh`
- Create: `skills/flutterwright/scripts/mock.sh`

- [ ] **Step 1: Delete old `mock_set.sh`**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts
rm mock_set.sh
```

- [ ] **Step 2: Create `mock.sh`**

```bash
#!/usr/bin/env bash
# mock.sh — control SDK mock state via POST /mock. Unified dispatch for 5 actions.
# Usage:
#   mock.sh set    key=<k> value=<json>
#   mock.sh get    key=<k>
#   mock.sh reset
#   mock.sh enable enabled=<true|false>
#   mock.sh list

set -euo pipefail

PORT="${VL_PORT:-9123}"
ACTION="${1:?action required: set|get|reset|enable|list (positional arg 1)}"; shift

KEY=""
VALUE=""
ENABLED=""
for arg in "$@"; do
  case "$arg" in
    key=*)     KEY="${arg#key=}";;
    value=*)   VALUE="${arg#value=}";;
    enabled=*) ENABLED="${arg#enabled=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 51;;
  esac
done

case "$ACTION" in
  set)
    [ -n "$KEY" ]   || { echo "ERR: 'set' requires key=" >&2; exit 52; }
    [ -n "$VALUE" ] || { echo "ERR: 'set' requires value=" >&2; exit 53; }
    PAYLOAD=$(printf '{"action":"set","key":"%s","value":%s}' "$KEY" "$VALUE")
    ;;
  get)
    [ -n "$KEY" ] || { echo "ERR: 'get' requires key=" >&2; exit 52; }
    PAYLOAD=$(printf '{"action":"get","key":"%s"}' "$KEY")
    ;;
  reset)
    PAYLOAD='{"action":"reset"}'
    ;;
  enable)
    [ -n "$ENABLED" ] || { echo "ERR: 'enable' requires enabled=" >&2; exit 54; }
    PAYLOAD=$(printf '{"action":"enable","enabled":%s}' "$ENABLED")
    ;;
  list)
    PAYLOAD='{"action":"list"}'
    ;;
  *)
    echo "ERR: invalid action '$ACTION' (expected: set|get|reset|enable|list)" >&2
    exit 51
    ;;
esac

TMP=$(mktemp -t fw-mock.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -sf -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/mock" \
  -H 'content-type: application/json' \
  -d "$PAYLOAD") || { echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 56; }

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  501) echo "ERR: no MockDataProvider configured (call FlutterVisualLoop.start(mockProvider:...))" >&2; cat "$TMP" >&2; exit 55;;
  *)   echo "ERR: /mock returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 56;;
esac
```

- [ ] **Step 3: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/mock.sh
```
Expected: no output.

- [ ] **Step 4: Make executable**

```bash
chmod +x /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/mock.sh
```

- [ ] **Step 5: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/mock.sh
git rm --cached skills/flutterwright/scripts/mock_set.sh 2>/dev/null || true
```

---

### Task 15: `reset.sh` (new — SDK /reset endpoint)

**Files:**
- Create: `skills/flutterwright/scripts/reset.sh`

- [ ] **Step 1: Create `reset.sh`**

```bash
#!/usr/bin/env bash
# reset.sh — navigator pop to root, optionally clearing mock data, via SDK /reset.
# Usage: reset.sh [clearMock=<true|false>]
#   reset.sh                       # defaults to clearMock=true
#   reset.sh clearMock=false       # keep mock data, just pop navigator

set -euo pipefail

PORT="${VL_PORT:-9123}"

CLEAR_MOCK="true"
for arg in "$@"; do
  case "$arg" in
    clearMock=*) CLEAR_MOCK="${arg#clearMock=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 70;;
  esac
done

PAYLOAD=$(printf '{"clearMock":%s}' "$CLEAR_MOCK")

TMP=$(mktemp -t fw-reset.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -sf -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/reset" \
  -H 'content-type: application/json' \
  -d "$PAYLOAD") || { echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 70; }

case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  *)   echo "ERR: /reset returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 71;;
esac
```

- [ ] **Step 2: Syntax check**

```bash
bash -n /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/reset.sh
```
Expected: no output.

- [ ] **Step 3: Make executable**

```bash
chmod +x /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/reset.sh
```

- [ ] **Step 4: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/scripts/reset.sh
```

---

## Phase 4 — SKILL.md

### Task 16: Write `skills/flutterwright/SKILL.md`

**Files:**
- Create: `skills/flutterwright/SKILL.md`

- [ ] **Step 1: Create `SKILL.md`**

```markdown
---
name: flutterwright
description: Playwright-style driver for Flutter apps running on Android devices/emulators via the flutter_visual_loop SDK. Use when you need to navigate routes, screenshot, hot-reload, inject mock data, or lock viewport. Skill provides 8 methods (health/goto/screenshot/reload/setViewport/resetViewport/mock/reset).
---

# FlutterWright — Playwright for Flutter on Android

A Layer 2b driver skill: given a host Flutter app that integrates the `flutter_visual_loop` SDK and is running on a connected Android device (real or emulator), this skill exposes a Playwright-style API to drive it from Claude or higher-layer orchestration skills.

Android-only in v1. iOS support, UI interaction (tap/swipe/text), and widget tree introspection are out of scope — see [v1 design spec](../../docs/superpowers/specs/2026-05-22-flutterwright-design.md) §10.

Declare on entry: **"Using flutterwright to <method> <target>."**

## When to use

- Ad-hoc: user has a Flutter app already running via `flutter run` and wants Claude to drive it ("navigate to /order, screenshot it").
- Composition: a higher-layer skill (e.g. flutter-visual-loop UI restoration loop) invokes flutterwright methods as building blocks via `Skill flutterwright "..."`.

Don't use if: the host app hasn't integrated `flutter_visual_loop` SDK (no HTTP control plane → nothing to talk to). Refer the user to [integration-guide.md](../../docs/integration-guide.md).

## Concepts

- **Page** = the Flutter app currently running on a connected Android device.
- **Route** = a named app route (e.g. `/order/detail`).
- **Mock** = data injected via `flutter_visual_loop.MockDataProvider`.
- **Viewport** = `wm size` + `wm density` override locking the device to design resolution.
- **Reload** = Flutter hot reload triggered via SDK `/reload` endpoint (`vm_service.reloadSources`).

## Methods

| Method | Purpose | Script |
|---|---|---|
| `health` | Verify env (adb / device / SDK reachability + auto `adb forward` 9123) | `health.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | Push a named route | `goto.sh` |
| `screenshot <out_path>` | Device screenshot (full frame incl. status bar) to PNG | `screenshot.sh` |
| `reload` | Flutter hot reload via SDK `/reload` | `reload.sh` |
| `setViewport <w> <h> <dpi>` | Lock `wm size` + `wm density` | `set_viewport.sh` |
| `resetViewport` | Restore `wm size` + `wm density` to device defaults | `reset_viewport.sh` |
| `mock <action> [key=<k>] [value=<json>] [enabled=<bool>]` | Mock data control (action ∈ set/get/reset/enable/list) | `mock.sh` |
| `reset [clearMock=<bool>]` | Pop navigator to root, optionally clear mock | `reset.sh` |

## Prerequisites

- macOS / Linux with `adb` and `curl` in `PATH`.
- Host Flutter app integrates `flutter_visual_loop` ≥ 0.2.0 (containing `/reload` endpoint).
- `flutter run -d <device>` is active. **No fifo needed** — v1 dropped the stdin-fifo hot-reload path.

Full setup: see [`README.md` Quickstart](../../README.md#quickstart).

## Method reference

### `health`

```
Skill flutterwright "health"
```

Validates `adb` + at least one connected device + `curl` available, then performs `adb forward tcp:9123 tcp:9123` (idempotent) and probes `GET /health`.

Exit codes: 0 ok / 10 adb missing / 11 no device / 12 SDK unreachable / 13 curl missing.

Output: `ok: device=<id> port=9123`.

### `goto`

```
Skill flutterwright "goto <route> [args=<json>] [popUntilRoot=<bool>]"
```

Push `<route>` via `Navigator.pushNamed`. `args` is an arbitrary JSON value passed as `arguments:`. `popUntilRoot` defaults to `true` (pop to root first, avoiding state pollution across loop iterations).

Example: `Skill flutterwright "goto /order/detail args={\"id\":\"ORD-001\"}"`

Exit codes: 0 ok / 40 missing route or unknown arg / 41 navigator not ready (HTTP 503) / 42 push failed (HTTP 500) / 43 SDK unreachable.

### `screenshot`

```
Skill flutterwright "screenshot <out_path>"
```

`adb exec-out screencap -p > <out>` followed by PNG magic-byte check. Captures **full device frame including status bar**. For Flutter-only render tree, use SDK `GET /screenshot` directly (not exposed as a method in v1).

Exit codes: 0 ok / 20 empty file / 21 file < 1KB / 22 not a PNG (device locked?).

### `reload`

```
Skill flutterwright "reload"
```

Triggers `vm_service.reloadSources` via SDK `POST /reload`. Assumes source files on the device-side dart isolate have been updated (typically the upper-layer skill or user edited Dart files before invoking).

Exit codes: 0 ok / 30 SDK unreachable / 31 VM service not available (release build? SDK < 0.2.0?) / 32 `/reload` returned non-200.

Implementation detail: sleeps 1s after success to let Flutter apply the reload.

### `setViewport`

```
Skill flutterwright "setViewport <width> <height> <dpi>"
```

Records original `wm size` and `wm density` to `$CLAUDE_JOB_DIR/fw_original.env`, then applies the override and validates via readback (some vendor ROMs silently reject `wm` overrides — readback detects this).

Example: `Skill flutterwright "setViewport 1080 2400 480"`

Exit codes: 0 ok / 60 missing args / 61 override rejected (readback mismatch).

### `resetViewport`

```
Skill flutterwright "resetViewport"
```

Restores `wm size` + `wm density` from `$CLAUDE_JOB_DIR/fw_original.env`. If the file is missing, falls back to `wm size reset` + `wm density reset`. **Always exits 0** — safe to call from a `trap` or any cleanup hook.

### `mock`

```
Skill flutterwright "mock <action> [key=<k>] [value=<json>] [enabled=<bool>]"
```

Dispatches `POST /mock` with the right body for each action:

- `mock set key=<k> value=<json>` — inject a value
- `mock get key=<k>` — read a value
- `mock reset` — clear all
- `mock enable enabled=<true|false>` — toggle global mock mode
- `mock list` — list current state

Examples:
- `Skill flutterwright "mock set key=user value={\"name\":\"Alice\"}"`
- `Skill flutterwright "mock enable enabled=false"`
- `Skill flutterwright "mock list"`

Exit codes: 0 / 50 missing action / 51 invalid action or unknown arg / 52 missing key (set/get) / 53 missing value (set) / 54 missing enabled (enable) / 55 SDK returned 501 (no MockDataProvider configured) / 56 SDK unreachable.

### `reset`

```
Skill flutterwright "reset [clearMock=<bool>]"
```

`POST /reset` with `{"clearMock":<bool>}`. Defaults to `clearMock=true`.

Exit codes: 0 / 70 SDK unreachable or unknown arg / 71 `/reset` returned non-200.

## Dispatch convention

When invoked as `Skill flutterwright "<method> <args...>"`:

1. Parse the first whitespace-separated token as the **method name**.
2. Parse remaining tokens as positional (for `goto`/`screenshot`/`setViewport`) followed by `key=value` pairs.
3. Invoke `bash skills/flutterwright/scripts/<method>.sh <args>`.

JSON values in `key=value` must escape internal `"` as `\"` (so they survive shell + curl). Example:

- Skill call: `goto /order/detail args={\"id\":\"X\"}`
- Bash exec:  `bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## Exit code map

| Range | Category | Notes |
|---|---|---|
| 0 | success | — |
| 10-13 | env / device | health.sh — see [troubleshooting](../../docs/troubleshooting.md) |
| 20-22 | screenshot | screenshot.sh |
| 30-32 | reload | reload.sh |
| 40-43 | navigate | goto.sh |
| 50-56 | mock | mock.sh |
| 60-61 | viewport | set_viewport.sh / reset_viewport.sh (rare — reset always exits 0) |
| 70-71 | reset | reset.sh |

## See also

- [api-reference.md](../../docs/api-reference.md) — SDK HTTP protocol
- [integration-guide.md](../../docs/integration-guide.md) — integrating the SDK into your Flutter app
- [troubleshooting.md](../../docs/troubleshooting.md) — failure modes by symptom
```

- [ ] **Step 2: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add skills/flutterwright/SKILL.md
```

---

## Phase 5 — Docs

### Task 17: `docs/api-reference.md` — add `/reload` section

**Files:**
- Modify: `docs/api-reference.md`

- [ ] **Step 1: Find the existing `## POST /reset` section in `docs/api-reference.md` (around line 63). After that section ends (before `## POST /mock` at around line 81), insert a new section**

Insert this block between `## POST /reset` and `## POST /mock`:

```markdown
## POST /reload

触发 Flutter hot reload(经 VM service `reloadSources`)。Source 改动由调用方完成(Claude/上层 skill 编辑 Dart 文件之后调本端点)。

**Request body:** 无(或空 `{}`)。

**Response 200**
```json
{ "ok": true }
```

**错误**
- `503` — VM service 未在本进程开启(release/profile 构建);或 SDK < 0.2.0(端点尚不存在,会落到 404)
- `500` — `reloadSources` 失败(常见:语法错误、`main()` 改了需 hot restart)

实现:`ReloadHandler` 用 `dart:developer Service.getInfo()` 拿本进程 VM service URI,再用 `package:vm_service` 连回自己,对 main isolate 调 `reloadSources`。
```

- [ ] **Step 2: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add docs/api-reference.md
```

---

### Task 18: `docs/architecture.md` — add flutterwright layering + dual-repo positioning

**Files:**
- Modify: `docs/architecture.md`

- [ ] **Step 1: Replace `docs/architecture.md` entirely with the v1 content**

```markdown
# 架构

## 整体分层

flutterwright 是 monorepo,既是 Claude Code skill,也拥有 `flutter_visual_loop` SDK + demo + 技术文档。在更大的"Flutter UI 自动化"分层里它是 **Layer 2b**(设备/Flutter app 驱动)。

```
+--------------------------------------+
|  Layer 1: Higher-level user goals    |
|  - "UI 还原循环",E2E 测试,etc.        |
+--------------------------------------+
                  |
                  v
+--------------------------------------+
|  Layer 2a: Orchestration skills      |  (本仓库外:flutter-visual-loop 等)
|  - 读设计稿、视觉对比、改 Dart        |
+--------------------------------------+
                  |  Skill flutterwright "..."
                  v
+--------------------------------------+
|  Layer 2b: flutterwright (本仓库)    |
|  - 8 Playwright-style methods        |
|  - skills/flutterwright/SKILL.md     |
+--------------------------------------+
                  |  bash scripts/*.sh
                  v
+--------------------------------------+
|  adb forward + curl                  |
|  adb exec-out screencap              |
+--------------------------------------+
                  |
                  v
+--------------------------------------+
|  Host Flutter app + flutter_visual_loop SDK |
|  - HTTP server on 127.0.0.1:9123     |
|  - /health /routes /navigate /reset  |
|  - /mock /screenshot /reload (新)    |
+--------------------------------------+
```

## 组件

### SDK (`packages/flutter_visual_loop`)

- **`FlutterVisualLoop`** 门面 — start/stop,暴露 `navigatorKey`、`routes`。
- **`VisualLoopHttpServer`** — `dart:io HttpServer` 绑 `127.0.0.1:9123`(可配置),按 `path + method` 分发请求给 handler。
- **Handlers** — 每个 endpoint 一个文件,继承 `Handler` 抽象基类,通过 `ctx.request.writeJson/writeOk/writeError` 写响应。
- **`RouteRegistry`** — 包装宿主 app 的命名路由表;`GET /routes` 列出注册的路由。
- **`MockDataProvider`** — 宿主实现的接口。默认提供 `InMemoryMockDataProvider`。SDK 自身不读 mock 数据 — 只把控制命令路由给 provider。
- **`VisualLoopRoot`** — 可选 Widget 包装,让 `/screenshot` 可靠工作(提供 `RepaintBoundary`)。
- **`ReloadHandler` (0.2.0+)** — 调 `vm_service.reloadSources` 触发本进程的 Flutter hot reload。

### Skill (`skills/flutterwright`)

- **`SKILL.md`** — 唯一对外接口,Playwright-style 8 methods 定义 + dispatch convention。
- **`scripts/`** — 8 个 bash 脚本(`health.sh / goto.sh / screenshot.sh / reload.sh / set_viewport.sh / reset_viewport.sh / mock.sh / reset.sh`),封装 adb / curl / printf 细节。

## 双仓库职责

| 仓库 | 内容 | 职责层 |
|---|---|---|
| `flutterwright/`(本仓库) | SKILL + 8 scripts + SDK + example + 4 docs | Layer 2b 设备/Flutter app 驱动 |
| `flutter-visual-loop/`(瘦身后) | SKILL + 极少量编排逻辑 | Layer 2a UI 还原循环编排 |

## 安全约束

- 当 `kDebugMode == false` 时,SDK 拒绝启动(默认 config 守门)。
- Server 仅绑 `127.0.0.1`,不暴露到 LAN。
- `adb wm size` / `wm density` 覆写由 skill 记录到 `$CLAUDE_JOB_DIR/fw_original.env`,任务结束或任何失败路径必须调 `Skill flutterwright "resetViewport"` 还原。
- `/reload` 端点要求本进程 VM service 可用 — release 构建下 VM service 自动关闭,端点返 503,无安全暴露。
- 每个 endpoint 在 debug console 输出一行汇总;超 `maxBodyBytes`(默认 1 MiB)的请求返 413。

## 故意**不**做的事(v1)

- iOS 支持 — 全 adb-only。
- UI 交互(tap/swipe/text input) — 留 v2。
- Widget tree 检视 / locator — 留 v2。
- 视觉对比 — 在上层 Layer 2a 由 LLM 完成。
- Figma 客户端 — 上层 skill 用现有的 `figma-context` MCP。
```

- [ ] **Step 2: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add docs/architecture.md
```

---

### Task 19: `docs/integration-guide.md` — fix git url + package path references

**Files:**
- Modify: `docs/integration-guide.md`

- [ ] **Step 1: Find and replace the `git:` dependency snippet (around lines 9-16)**

Find:

```yaml
dependencies:
  flutter_visual_loop:
    git:
      url: https://github.com/MySwallow/flutter-visual-loop
      path: packages/flutter_visual_loop
```

Replace with:

```yaml
dependencies:
  flutter_visual_loop:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_visual_loop
```

- [ ] **Step 2: Find and replace the local `path:` snippet (around lines 22-23)**

Find:

```yaml
dependencies:
  flutter_visual_loop:
    path: ../flutter-visual-loop/packages/flutter_visual_loop
```

Replace with:

```yaml
dependencies:
  flutter_visual_loop:
    path: ../flutterwright/packages/flutter_visual_loop
```

- [ ] **Step 3: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add docs/integration-guide.md
```

---

### Task 20: `docs/troubleshooting.md` — rewrite for new method names + drop fifo + merge e2e-checklist

**Files:**
- Modify: `docs/troubleshooting.md`

- [ ] **Step 1: Replace `docs/troubleshooting.md` entirely with the v1 content**

```markdown
# 故障排查

按 "现象在哪一层暴露" 分组。所有方法名为 flutterwright v1 命名(`health/goto/screenshot/reload/setViewport/resetViewport/mock/reset`)。

## `health` 失败

### exit 10:adb 未安装

```bash
# macOS
brew install --cask android-platform-tools
# Ubuntu
sudo apt install adb
# 验证
adb --version
```

### exit 11:无 adb 设备

```bash
adb devices
# 空 → 手机开 USB 调试,接受 RSA 指纹弹窗。
```

模拟器:

```bash
emulator -list-avds
emulator -avd <name> -no-snapshot-load &
```

### exit 12:SDK 在 `127.0.0.1:9123` 不可达

- `flutter run` 还在跑吗?  `pgrep -f 'flutter run'`
- 端口转发?  `adb forward --list | grep 9123`(没有就 `adb forward tcp:9123 tcp:9123`)
- SDK 真的 bind 了?`flutter run` 输出应有 `[flutter_visual_loop] listening on http://127.0.0.1:9123`
- 主机上 9123 被占?  `lsof -i :9123`

### exit 13:curl 未安装

`brew install curl` / `sudo apt install curl`。

## `goto` 失败

### exit 41 (HTTP 503): navigator not ready

App 在启动。两选一:
- 等 ~500ms 重试。
- `FlutterVisualLoop.start(autoStart: false)` + 第一帧后调 `FlutterVisualLoop.bind()`。

### exit 42 (HTTP 500): push failed

路由没匹配上 `onGenerateRoute`/`routes` map。查:

```bash
curl http://localhost:9123/routes   # 已注册的路由
```

注册:`FlutterVisualLoop.routes.register('/your/route');`

### 页面切换但 UI 没刷新

通常是 state 没刷。`Skill flutterwright "reset clearMock=true"`,然后重新 `goto`。

## `screenshot` 失败

### exit 20/21 (empty 或 < 1KB)

设备屏幕灭了 → `adb shell input keyevent 26` 唤醒;锁屏 → 测试期间关闭锁屏。

### exit 22 (not PNG)

设备锁屏 / shell 吃掉了二进制流。先唤醒,再重试。

### 截图被缩放

漏了 `adb forward` 或 `wm size`/`wm density` 不匹配。`adb shell wm size` 查当前值。

如果 `setViewport` 后还有 Override 但分辨率不对,直接:

```bash
adb shell wm size reset
adb shell wm density reset
```

## `reload` 失败

### exit 31 (HTTP 503): VM service not available

宿主 app 是 release/profile 构建(VM service 关闭),或 SDK < 0.2.0(没 `/reload` 端点 → 落到 404 → exit 32)。

确认 `flutter run` 是 debug 模式(默认就是);确认 `pubspec.yaml` 里 `flutter_visual_loop` 版本 ≥ 0.2.0。

### exit 32 (其他 HTTP code)

可能是 reload 本身失败(语法错、`main()` 改了需 hot restart)。看 `flutter run` 控制台的 dart compile error。

需要 hot restart 时:目前 v1 没暴露,临时 workaround 是 `adb shell am force-stop <pkg>` + `flutter run` 重启。

## `mock` 失败

### exit 55 (HTTP 501): no MockDataProvider configured

宿主 `start()` 没传 `mockProvider`。加:

```dart
final mock = InMemoryMockDataProvider();
await FlutterVisualLoop.start(mockProvider: mock);
```

### Mock 值改了但 UI 没反应

Repository/service 缓存了。`Skill flutterwright "reset clearMock=false"` + 重新 `goto`,新 mount 读新数据。

## `setViewport` 失败 / 任务结束后设备状态奇怪

### exit 61: wm 覆写被静默拒(厂商 ROM)

MIUI / HarmonyOS / ColorOS 等会拒 `wm size`/`wm density`。绕开:
- 不锁视口,接受设备默认。
- 换一台 stock Android 设备。

### 任务结束后 `wm size` 仍有 Override

```bash
adb shell wm size reset
adb shell wm density reset
```

App 卡在奇怪路由:`Skill flutterwright "reset clearMock=true"` 或 `adb shell am force-stop <pkg>` 重启。

## 平台限制 — "Android 上没问题,iOS 上不行"

v1 是 Android-only。原因:

- iOS Simulator 截图能用(`xcrun simctl io booted screenshot`),但脚本全用 `adb` 还没分流。
- iOS deep-link / port forward 没有 `adb forward` 直接等价物。

v2 计划支持 iOS — 见 spec §10.2。

---

## 附录:E2E 验证清单(release 前手动跑)

> 旧 `docs/e2e-checklist.md` 已并入这里。每次发新版前 clone 仓库后跑一遍。

### 前置条件

- macOS / Linux,装了 Flutter SDK 3.24+(`flutter doctor` 全绿)
- Android 真机 USB 调试已开,或 Android 模拟器在跑
- `adb devices` 显示设备状态为 `device`

### 第 1 步 — example app 生成平台脚手架

```bash
cd packages/example
flutter create . --platforms=android --org com.example.flutterwright
flutter pub get
```

### 第 2 步 — SDK 单元测试

```bash
cd packages/flutter_visual_loop
flutter pub get
flutter test
```

期望:`All tests passed!`(含 `reload_handler_test`)。

### 第 3 步 — 启动 example app(无 fifo)

```bash
cd packages/example
flutter run -d $(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
```

等到看见:

```
[flutter_visual_loop] listening on http://127.0.0.1:9123
```

### 第 4 步 — 端口转发 + 8 方法烟雾测试

在 Claude Code 会话里(任何 cwd 都行,只要安装了 flutterwright skill):

```
Skill flutterwright "health"
# → ok: device=<id> port=9123

Skill flutterwright "goto /home"
# → {"ok":true,"route":"/home"}  设备应跳到 /home

Skill flutterwright "screenshot /tmp/fw-smoke.png"
# → captured: /tmp/fw-smoke.png (<size> bytes)

Skill flutterwright "mock set key=order value={\"id\":\"X\",\"amount\":1.0}"
# → {"ok":true,"key":"order"}

Skill flutterwright "goto /order/detail"
# 设备应显示新的 order 数据

# 改 example/lib/pages/home_page.dart 任一文字(比如"Hello" → "Hi")
Skill flutterwright "reload"
# → reloaded   设备应反映改动

Skill flutterwright "setViewport 1080 2400 480"
# → viewport: 1080x2400 @ 480dpi

Skill flutterwright "reset clearMock=true"
# → {"ok":true,"clearedMock":true}

Skill flutterwright "resetViewport"
# → restored: size=<orig> density=<orig>
```

### 第 5 步 — 确认设备被还原

```bash
adb shell wm size       # 只有 Physical size,无 Override
adb shell wm density    # 只有 Physical density,无 Override
```

### 完成 = 8 方法全部 exit 0 + 设备状态恢复
```

- [ ] **Step 2: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add docs/troubleshooting.md
```

---

### Task 21: Delete `docs/getting-started.md` and `docs/e2e-checklist.md`

**Files:**
- Delete: `docs/getting-started.md`
- Delete: `docs/e2e-checklist.md`

- [ ] **Step 1: Delete both files**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
rm docs/getting-started.md docs/e2e-checklist.md
```

- [ ] **Step 2: Stage deletions**

```bash
git add docs/getting-started.md docs/e2e-checklist.md
```

> Even though we used `rm`, `git add` of a deleted path will record the deletion in the staged tree.

---

### Task 22: Write `README.md` (root) — absorbs getting-started content

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create root `README.md`**

```markdown
# FlutterWright

Playwright-style Flutter device automation via Claude Code skill, on Android.

A monorepo containing:

- a **Claude Code skill** (`skills/flutterwright/`) exposing 8 methods (goto / screenshot / reload / mock / setViewport / …),
- a **Dart SDK** (`packages/flutter_visual_loop/`) that runs a debug-only HTTP control plane inside any Flutter app,
- a **demo Flutter app** (`packages/example/`) showing SDK integration,
- **reference documentation** (`docs/`).

```
flutterwright/
├── skills/flutterwright/   <- Claude Code skill (SKILL.md + scripts)
├── packages/
│   ├── flutter_visual_loop/  <- Dart SDK
│   └── example/              <- demo Flutter app
├── docs/                   <- API ref / architecture / integration / troubleshooting
└── ...
```

## Quickstart (5 minutes)

### Prerequisites

- Flutter 3.24+ (`flutter doctor` clean)
- Android real device (USB debugging on) or Android emulator
- `adb` in PATH (Android platform-tools)
- `curl`

### 1. Clone and bootstrap the demo app

```bash
git clone https://github.com/MySwallow/flutterwright.git
cd flutterwright/packages/example
flutter create . --platforms=android --org com.example.flutterwright
flutter pub get
```

`flutter create .` only fills in `android/` scaffolding; existing files are not touched.

### 2. Run the demo app (no fifo, plain `flutter run`)

```bash
flutter run -d $(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
```

Wait for:

```
[flutter_visual_loop] listening on http://127.0.0.1:9123
```

### 3. Forward the port + verify

```bash
adb forward tcp:9123 tcp:9123
curl http://localhost:9123/health
# → {"ok":true,"version":"0.2.0","service":"flutter_visual_loop"}
```

### 4. Drive the app from Claude Code

In a Claude Code session (cwd anywhere; the skill is repo-local at `skills/flutterwright/`):

```
Skill flutterwright "health"
Skill flutterwright "goto /order/detail args={\"id\":\"ORD-001\"}"
Skill flutterwright "screenshot $CLAUDE_JOB_DIR/cur.png"
```

See [`skills/flutterwright/SKILL.md`](skills/flutterwright/SKILL.md) for the full method reference.

### 5. Integrate the SDK into your own Flutter app

```dart
import 'package:flutter_visual_loop/flutter_visual_loop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterVisualLoop.start(
    testRoutes: const ['/home', '/order/detail', '/login'],
  );
  runApp(VisualLoopRoot(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FlutterVisualLoop.navigatorKey,
      onGenerateRoute: yourRouter,
    );
  }
}
```

Full integration patterns (GoRouter, auth tokens, mock layering, multi-flavor): [`docs/integration-guide.md`](docs/integration-guide.md).

## Documentation

| Doc | What's in it |
|---|---|
| [`skills/flutterwright/SKILL.md`](skills/flutterwright/SKILL.md) | The 8 methods (signature, exit codes, examples) |
| [`docs/api-reference.md`](docs/api-reference.md) | SDK HTTP protocol — for direct curl / SDK contributors |
| [`docs/architecture.md`](docs/architecture.md) | Layering, components, security constraints |
| [`docs/integration-guide.md`](docs/integration-guide.md) | Dart integration patterns (10 scenarios) |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Failure modes by symptom + E2E checklist |
| [`docs/superpowers/specs/`](docs/superpowers/specs/) | Design specs (v1 + future) |

## License

MIT — see [`LICENSE`](LICENSE).
```

- [ ] **Step 2: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add README.md
```

---

### Task 23: `packages/flutter_visual_loop/README.md` — minor update (mention monorepo)

**Files:**
- Modify: `packages/flutter_visual_loop/README.md`

- [ ] **Step 1: Find the top of `packages/flutter_visual_loop/README.md` (lines 1-5)**

Find:

```markdown
# flutter_visual_loop

为 Flutter app 提供的"仅 debug 启用"的 HTTP 控制平面。给配套的
[`flutter-visual-loop`](../../skills/flutter-visual-loop/SKILL.md) Claude Code skill 用,
但任何能讲 HTTP 的客户端(curl、Postman、你自己的脚本)都能调。
```

Replace with:

```markdown
# flutter_visual_loop

> Shipped as part of the [flutterwright](../../README.md) monorepo.

为 Flutter app 提供的"仅 debug 启用"的 HTTP 控制平面。给配套的
[`flutterwright`](../../skills/flutterwright/SKILL.md) Claude Code skill 用,
但任何能讲 HTTP 的客户端(curl、Postman、你自己的脚本)都能调。
```

- [ ] **Step 2: Find the `git:` install snippet (around lines 11-16) and update the URL**

Find:

```yaml
dependencies:
  flutter_visual_loop:
    git:
      url: https://github.com/MySwallow/flutter-visual-loop
      path: packages/flutter_visual_loop
```

Replace with:

```yaml
dependencies:
  flutter_visual_loop:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_visual_loop
```

- [ ] **Step 3: Stage**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git add packages/flutter_visual_loop/README.md
```

---

## Phase 6 — Validation

### Task 24: Final validation (static checks + structure verification)

**Files:** none modified

- [ ] **Step 1: Verify file structure matches spec §4**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
ls -la
ls -la skills/flutterwright/
ls -la skills/flutterwright/scripts/
ls -la packages/flutter_visual_loop/lib/src/handlers/
ls -la docs/
```

Expected files at root: `LICENSE` `README.md` `CHANGELOG.md` `.gitignore` `CONTRIBUTING.md` `SECURITY.md` `docs/` `packages/` `skills/`.

Expected `skills/flutterwright/scripts/`: 8 files (`health.sh / goto.sh / screenshot.sh / reload.sh / set_viewport.sh / reset_viewport.sh / mock.sh / reset.sh`). **No** `env_check.sh / navigate.sh / capture.sh / hot_reload.sh / setup.sh / reset_device.sh / mock_set.sh`.

Expected `packages/flutter_visual_loop/lib/src/handlers/`: 8 files (existing 7 + new `reload_handler.dart`).

Expected `docs/`: 4 user-facing docs (`api-reference / architecture / integration-guide / troubleshooting`) + `superpowers/` subdir. **No** `getting-started.md / e2e-checklist.md`.

- [ ] **Step 2: SDK tests pass**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_visual_loop
flutter pub get && flutter test
```

Expected: `All tests passed!` (existing 2 + new 1 = 3).

- [ ] **Step 3: Flutter analyze clean**

```bash
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_visual_loop
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 4: Bash syntax check on all 8 scripts**

```bash
for f in /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/*.sh; do
  bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done
```

Expected: 8 lines, all `OK: ...`.

- [ ] **Step 5: Confirm all scripts are executable**

```bash
ls -l /Users/mini/Documents/dev/github/flutterwright/skills/flutterwright/scripts/*.sh
```

Expected: all show `-rwxr-xr-x` (executable bit set).

- [ ] **Step 6: Stage status snapshot**

```bash
cd /Users/mini/Documents/dev/github/flutterwright
git status
```

Review the listing. All 23 prior tasks' changes should appear as staged ("Changes to be committed"). Untracked items at this point should only be system files like `.dart_tool/` (which `.gitignore` already excludes).

- [ ] **Step 7: Manual smoke test (deferred — requires live device + Flutter run)**

Manual smoke is **DoD item 7** from the spec. It is NOT automatable in this plan because it requires:

1. A connected Android device (real or emulator).
2. `flutter run` actively running the example app.
3. A live Claude Code session that can invoke `Skill flutterwright "..."`.

After all 23 prior tasks complete and the user has committed, **run the E2E checklist** in [`docs/troubleshooting.md`](../../docs/troubleshooting.md#附录e2e-验证清单release-前手动跑) — that's the canonical DoD verification.

If all 8 methods in the E2E checklist return exit 0 with the expected device-side effects, **v1 is done**.

---

## Acceptance Criteria (mirrors spec §11 DoD)

- [ ] Directory structure matches spec §4 (LICENSE / README / CHANGELOG / .gitignore + 4 top-level dirs in place).
- [ ] 8 scripts implemented per §6 / §8; `mock_set.sh` / `vl_original.env` references no longer exist anywhere.
- [ ] `SKILL.md` written per §5, 8 per-method sections complete.
- [ ] SDK has `reload_handler.dart` + registered + pubspec has `vm_service` + version bumped to 0.2.0 + CHANGELOG entry.
- [ ] `docs/` final state: 4 user docs (api-reference / architecture / integration-guide / troubleshooting) + `superpowers/specs/2026-05-22-flutterwright-design.md`. `getting-started.md` and `e2e-checklist.md` deleted; their content merged into `README.md` and `docs/troubleshooting.md` respectively.
- [ ] `flutter test` in `packages/flutter_visual_loop/` passes (3 tests).
- [ ] `flutter analyze` clean.
- [ ] All 8 scripts pass `bash -n` and are executable.
- [ ] Manual smoke test (E2E checklist in `docs/troubleshooting.md`) — all 8 methods invoked, all return exit 0, device state restored.
