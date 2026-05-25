# SDK 可选化 + AI 持有 flutter run Implementation Plan

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `flutter_wright_sdk` 从「所有 skill 方法的硬前提」降级为「只为 `goto`/`reset` 服务的可选增项」——截图走 adb、热重载由 AI 持有的 `flutter run --machine` daemon 驱动,均不依赖 SDK。

**Architecture:** skill 新增 `run`/`stop` 两个方法管理一个后台 `flutter run --machine` daemon(经 `$CLAUDE_JOB_DIR` 下的 FIFO + 日志 + 状态文件跨无状态 bash 调用通信);`reload` 重写为向该 daemon 发 `app.restart`;`_lib.sh` 的全局 `/health` 闸门拆成逐方法前提(`fw_need_adb` / `fw_need_sdk`);SDK 删除冗余的 `ReloadHandler` + `vm_service` 依赖。

**Tech Stack:** Bash(coreutils + adb + curl,**不引 jq/tmux**)、Flutter daemon JSON 协议(`--machine`)、Dart/Flutter SDK、`dart:io HttpServer`。

**Spec:** `docs/superpowers/specs/2026-05-25-sdk-optional-ai-owned-flutter-run-design.md`

**排序决策 (b):** 本批 0.6.0 改动**叠加进** `feat/route-discovery-redesign` 分支上当前已 staged 的路由发现批次。每个任务只 `git add`(汇入同一批),**全程不 commit**;最终由用户把整批作为**一次提交**(0.6.0)落地。

**验证命令(全程复用):**
- SDK 静态检查:`cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/dart analyze`
- example 测试:`cd packages/example && /Users/mini/development/flutter/bin/flutter test`
- bash 静态检查:`shellcheck skills/flutter-wright/scripts/*.sh`(未装 shellcheck 时退回 `bash -n <script>` 语法检查)

---

### Task 1: SDK —— 删除 ReloadHandler + vm_service 依赖 + bump 0.6.0

**Files:**
- Delete: `packages/flutter_wright_sdk/lib/src/handlers/reload_handler.dart`
- Delete: `packages/flutter_wright_sdk/test/reload_handler_test.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`(import 第 11 行、handler 列表第 71 行、version 第 19 行)
- Modify: `packages/flutter_wright_sdk/pubspec.yaml`(第 3 行 version、第 14 行 vm_service)

`ReloadHandler` 未被 `lib/flutter_wright_sdk.dart` barrel 导出(已核实),故无需改 export。`vm_service` 仅 `reload_handler.dart` 用到(已核实),可整条移除。

- [ ] **Step 1: 删除两个 reload 文件**

```bash
git rm packages/flutter_wright_sdk/lib/src/handlers/reload_handler.dart
git rm packages/flutter_wright_sdk/test/reload_handler_test.dart
```

- [ ] **Step 2: 从 `flutter_wright.dart` 移除 import 与 handler,并 bump version**

删除第 11 行:

```dart
import 'handlers/reload_handler.dart';
```

删除 handler 列表里的 `ReloadHandler()` 行(原第 71 行),使列表变为:

```dart
    final handlers = <Handler>[
      HealthHandler(version),
      RoutesHandler(adapter),
      NavigateHandler(adapter),
      ResetHandler(adapter),
      ScreenshotHandler(config.screenshotMode),
    ];
```

把第 19 行版本常量改为:

```dart
  static const String version = '0.6.0';
```

- [ ] **Step 3: 从 `pubspec.yaml` 移除 vm_service 并 bump version**

第 3 行改为:

```yaml
version: 0.6.0
```

删除第 14 行整行:

```yaml
  vm_service: '>=14.0.0 <16.0.0'
```

删除后 `dependencies:` 块应只剩:

```yaml
dependencies:
  flutter:
    sdk: flutter
```

- [ ] **Step 4: 运行静态检查 + 测试**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/dart pub get && /Users/mini/development/flutter/bin/dart analyze`
Expected: `No issues found!`(无对已删 `vm_service` / `ReloadHandler` 的悬空引用)

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test`
Expected: 通过(只剩 `navigation_adapter_test.dart`,`reload_handler_test` 已删)

- [ ] **Step 5: Stage(汇入现有批次,不 commit)**

```bash
git add packages/flutter_wright_sdk/lib/src/flutter_wright.dart packages/flutter_wright_sdk/pubspec.yaml
# 上面 git rm 已自动 stage 删除
```

**不要 commit**——汇入同一批,由用户最终统一提交。

---

### Task 2: skill —— 重构 `_lib.sh`(逐方法前提 + flutter 定位)

**Files:**
- Modify(整文件替换): `skills/flutter-wright/scripts/_lib.sh`

废掉 `fw_ensure_health`(全局 `/health` 闸门),拆成 `fw_need_adb`(只查设备)、`fw_need_sdk`(查 SDK,含 marker fast-path)、`fw_locate_flutter`。`fw_need_sdk` 保留原 `$CLAUDE_JOB_DIR/fw_health_done` fast-path 语义(现表示「SDK 探针已过」),使 e2e 测试注入 marker 跳过 adb 的技巧继续有效。

- [ ] **Step 1: 用以下内容整体替换 `_lib.sh`**

```bash
#!/usr/bin/env bash
# _lib.sh — shared helpers for flutter-wright scripts. Source, don't execute.
#   source "$(dirname "$0")/_lib.sh"
#   fw_need_adb        # methods that only need a device (screenshot/setViewport/run)
#   fw_need_sdk        # methods that talk to the in-app SDK (goto/reset/health)
#   fw_locate_flutter  # echo path to the flutter binary, or return 1

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

# fw_need_sdk — everything fw_need_adb checks, plus the in-app SDK is reachable:
#   adb forward tcp:$VL_PORT + GET /health. Exits 12 (SDK unreachable) / 13 (no curl).
#   Fast-path: if $CLAUDE_JOB_DIR/fw_health_done exists (and FW_HEALTH_FORCE unset),
#   the SDK was already validated this job — return immediately.
fw_need_sdk() {
  local marker="${CLAUDE_JOB_DIR:-/tmp}/fw_health_done"
  local port="${VL_PORT:-9123}"

  if [ -z "${FW_HEALTH_FORCE:-}" ] && [ -f "$marker" ]; then
    if [ -z "${FW_DEVICE_ID:-}" ]; then
      FW_DEVICE_ID=$(awk -F= '/^device=/{print $2; exit}' "$marker" 2>/dev/null || true)
      export FW_DEVICE_ID
    fi
    return 0
  fi

  fw_need_adb
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERR: curl not installed." >&2
    exit 13
  fi
  adb -s "$FW_DEVICE_ID" forward tcp:"$port" tcp:"$port" >/dev/null
  if ! curl -sf "http://127.0.0.1:$port/health" >/dev/null; then
    echo "ERR: SDK not reachable on 127.0.0.1:$port. Is the app running with FlutterWright.start()?" >&2
    exit 12
  fi
  mkdir -p "$(dirname "$marker")"
  printf 'device=%s\nport=%s\nts=%s\n' "$FW_DEVICE_ID" "$port" "$(date +%s)" > "$marker"
}

# fw_locate_flutter — echo the flutter binary path, or return 1.
#   Order: $FLUTTER_BIN → PATH → common install locations.
fw_locate_flutter() {
  if [ -n "${FLUTTER_BIN:-}" ] && [ -x "$FLUTTER_BIN" ]; then
    echo "$FLUTTER_BIN"; return 0
  fi
  if command -v flutter >/dev/null 2>&1; then
    command -v flutter; return 0
  fi
  local c
  for c in "$HOME/development/flutter/bin/flutter" "$HOME/flutter/bin/flutter" "/usr/local/bin/flutter" "/opt/homebrew/bin/flutter"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
```

- [ ] **Step 2: 静态检查**

Run: `shellcheck skills/flutter-wright/scripts/_lib.sh`(未装则 `bash -n skills/flutter-wright/scripts/_lib.sh`)
Expected: 无错误(注:此时其它脚本仍调用 `fw_ensure_health`,会在 Task 6 修正;`shellcheck` 单独检查 `_lib.sh` 不报未定义函数)

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/_lib.sh
```

**不要 commit。**

---

### Task 3: skill —— 新增 `run.sh`(后台启 flutter daemon)

**Files:**
- Create: `skills/flutter-wright/scripts/run.sh`

后台启 `flutter run --machine`,用 FIFO + holder(`tail -f /dev/null`,**不能用 `sleep infinity` —— macOS 的 BSD sleep 不接受 `infinity`**)保持 stdin 常开,解析 `app.start` 的 appId、等 `app.started` 就绪,状态写 `$CLAUDE_JOB_DIR/fw_daemon.env`。

- [ ] **Step 1: 创建 `run.sh`**

```bash
#!/usr/bin/env bash
# run.sh — launch `flutter run --machine` in the background and hold the daemon
# so later reload.sh / stop.sh can drive it. State lives in $CLAUDE_JOB_DIR.
#
# Usage: run.sh [target] [device=<id>] [project=<dir>]
#   run.sh                              # target=lib/main.dart, first device, cwd
#   run.sh dev/main_dev.dart            # SDK-integrated dev entry (enables goto)
#   run.sh lib/main.dart device=emulator-5554
#
# Exit: 0 ok / 10 adb / 11 device / 36 flutter not found / 37 already running / 38 app didn't start

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_adb   # adb on PATH + >=1 device; exports FW_DEVICE_ID

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
mkdir -p "$JOB_DIR"
FIFO="$JOB_DIR/fw_daemon.in"
LOG="$JOB_DIR/fw_daemon.log"
ENV_FILE="$JOB_DIR/fw_daemon.env"

# Refuse to double-launch.
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [ -n "${DAEMON_PID:-}" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "ERR: daemon already running (appId=${APP_ID:-?} pid=$DAEMON_PID). Call 'stop' first." >&2
    exit 37
  fi
fi

# Parse args: bare token = target; key=value pairs for device/project.
TARGET="lib/main.dart"
DEVICE="$FW_DEVICE_ID"
PROJECT_DIR="$PWD"
for arg in "$@"; do
  case "$arg" in
    device=*)  DEVICE="${arg#device=}";;
    project=*) PROJECT_DIR="${arg#project=}";;
    *)         TARGET="$arg";;
  esac
done

FLUTTER_BIN="$(fw_locate_flutter)" || {
  echo "ERR: flutter not found. Set FLUTTER_BIN or add flutter to PATH." >&2; exit 36;
}

# Fresh pipe + log.
rm -f "$FIFO" "$LOG"
mkfifo "$FIFO"

# Holder keeps the FIFO write-end open so the daemon's stdin never sees EOF
# between commands. `tail -f /dev/null` is the portable (macOS/Linux) no-op writer
# — note `sleep infinity` is NOT portable to macOS BSD sleep.
tail -f /dev/null > "$FIFO" 2>/dev/null &
HOLDER_PID=$!
disown "$HOLDER_PID" 2>/dev/null || true

# Launch the daemon detached: cwd=PROJECT_DIR, stdin<-FIFO, stdout/stderr->LOG.
# `exec` so DAEMON_PID is the flutter process itself (clean kill -0 / kill later).
( cd "$PROJECT_DIR" && exec "$FLUTTER_BIN" run --machine -t "$TARGET" -d "$DEVICE" ) < "$FIFO" > "$LOG" 2>&1 &
DAEMON_PID=$!
disown "$DAEMON_PID" 2>/dev/null || true

# Persist state early so stop.sh can always clean up, even on timeout below.
{
  echo "DAEMON_PID=$DAEMON_PID"
  echo "HOLDER_PID=$HOLDER_PID"
  echo "DEVICE=$DEVICE"
  echo "FIFO=$FIFO"
  echo "LOG=$LOG"
} > "$ENV_FILE"

# Wait for app.start (carries appId) then app.started (first frame), with timeout.
APP_ID=""
DEADLINE=$(( $(date +%s) + 180 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "ERR: flutter run exited early. Last log lines:" >&2
    tail -n 20 "$LOG" >&2 || true
    exit 38
  fi
  if [ -z "$APP_ID" ]; then
    APP_ID=$(grep -m1 '"app.start"' "$LOG" 2>/dev/null \
      | grep -o '"appId":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  fi
  if grep -q '"app.started"' "$LOG" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [ -z "$APP_ID" ] || ! grep -q '"app.started"' "$LOG" 2>/dev/null; then
  echo "ERR: app did not start within 180s. Last log lines:" >&2
  tail -n 20 "$LOG" >&2 || true
  exit 38
fi

echo "APP_ID=$APP_ID" >> "$ENV_FILE"
echo "ok: appId=$APP_ID device=$DEVICE target=$TARGET"
```

- [ ] **Step 2: 赋可执行位 + 静态检查**

```bash
chmod +x skills/flutter-wright/scripts/run.sh
```
Run: `shellcheck skills/flutter-wright/scripts/run.sh`(未装则 `bash -n ...`)
Expected: 无错误

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/run.sh
```

**不要 commit。**

---

### Task 4: skill —— 重写 `reload.sh`(驱动 owned daemon)

**Files:**
- Modify(整文件替换): `skills/flutter-wright/scripts/reload.sh`

不再 source `_lib.sh`、不再打 SDK。改为校验 owned daemon → 向 FIFO 发 `app.restart{fullRestart:false}` → 轮询日志取本次 `id` 的响应,`"code":0` 即成功。

- [ ] **Step 1: 用以下内容整体替换 `reload.sh`**

```bash
#!/usr/bin/env bash
# reload.sh — hot reload the AI-owned flutter daemon (app.restart, fullRestart=false).
# Requires a prior `run`. Does NOT touch the SDK.
# Usage: reload.sh
# Exit: 0 ok / 33 no owned daemon / 34 daemon dead / 35 reload failed or timed out

set -euo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
ENV_FILE="$JOB_DIR/fw_daemon.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERR: no AI-owned flutter run. Call 'run' first, or press 'r' in your own flutter run console." >&2
  exit 33
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${DAEMON_PID:-}" ] || ! kill -0 "$DAEMON_PID" 2>/dev/null; then
  echo "ERR: flutter daemon not alive (pid=${DAEMON_PID:-?}). Call 'run' again." >&2
  exit 34
fi

REQ_ID=$$
OFFSET=$(wc -l < "$LOG" 2>/dev/null | tr -d ' '); OFFSET="${OFFSET:-0}"

printf '[{"id":%d,"method":"app.restart","params":{"appId":"%s","fullRestart":false,"pause":false,"reason":"manual"}}]\n' \
  "$REQ_ID" "$APP_ID" > "$FIFO"

DEADLINE=$(( $(date +%s) + 60 ))
LINE=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  LINE=$(tail -n "+$((OFFSET + 1))" "$LOG" 2>/dev/null | grep -m1 "\"id\":$REQ_ID," || true)
  [ -n "$LINE" ] && break
  sleep 1
done

if [ -z "$LINE" ]; then
  echo "ERR: reload timed out after 60s (no response id=$REQ_ID)" >&2
  exit 35
fi
if printf '%s' "$LINE" | grep -q '"code":0'; then
  sleep 1   # let Flutter apply the reload before returning
  echo "reloaded"
else
  echo "ERR: reload failed: $LINE" >&2
  exit 35
fi
```

- [ ] **Step 2: 静态检查**

Run: `shellcheck skills/flutter-wright/scripts/reload.sh`(未装则 `bash -n ...`)
Expected: 无错误

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/reload.sh
```

**不要 commit。**

---

### Task 5: skill —— 新增 `stop.sh`(停 daemon + 清理)

**Files:**
- Create: `skills/flutter-wright/scripts/stop.sh`

- [ ] **Step 1: 创建 `stop.sh`**

```bash
#!/usr/bin/env bash
# stop.sh — stop the AI-owned flutter daemon and clean up. Always exits 0
# (safe to call from a trap / cleanup hook).
# Usage: stop.sh

set -uo pipefail

JOB_DIR="${CLAUDE_JOB_DIR:-/tmp/fw-job}"
ENV_FILE="$JOB_DIR/fw_daemon.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "no AI-owned flutter run to stop"
  exit 0
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# Polite app.stop first (best-effort), then kill the processes.
if [ -n "${APP_ID:-}" ] && [ -n "${FIFO:-}" ] && [ -p "${FIFO:-}" ]; then
  printf '[{"id":0,"method":"app.stop","params":{"appId":"%s"}}]\n' "$APP_ID" > "$FIFO" 2>/dev/null || true
  sleep 1
fi
[ -n "${DAEMON_PID:-}" ] && kill "$DAEMON_PID" 2>/dev/null || true
[ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null || true
rm -f "${FIFO:-}" "${LOG:-}" "$ENV_FILE"
echo "stopped: appId=${APP_ID:-?}"
exit 0
```

- [ ] **Step 2: 赋可执行位 + 静态检查**

```bash
chmod +x skills/flutter-wright/scripts/stop.sh
```
Run: `shellcheck skills/flutter-wright/scripts/stop.sh`(未装则 `bash -n ...`)
Expected: 无错误

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/stop.sh
```

**不要 commit。**

---

### Task 6: skill —— 更新现有脚本的 env-check 调用点

**Files:**
- Modify: `skills/flutter-wright/scripts/screenshot.sh:9`
- Modify: `skills/flutter-wright/scripts/set_viewport.sh:11`
- Modify: `skills/flutter-wright/scripts/goto.sh:11`
- Modify: `skills/flutter-wright/scripts/reset.sh:9`
- Modify: `skills/flutter-wright/scripts/health.sh:18`

`fw_ensure_health` 已不存在,把每个调用点换成对应的逐方法前提。

- [ ] **Step 1: 替换各脚本调用**

`screenshot.sh` —— 把:
```bash
fw_ensure_health
```
换成:
```bash
fw_need_adb
```

`set_viewport.sh` —— 把:
```bash
fw_ensure_health
```
换成:
```bash
fw_need_adb
```

`goto.sh` —— 把:
```bash
fw_ensure_health
```
换成:
```bash
fw_need_sdk
```

`reset.sh` —— 把:
```bash
fw_ensure_health
```
换成:
```bash
fw_need_sdk
```

`health.sh` —— 把:
```bash
FW_HEALTH_FORCE=1 fw_ensure_health
```
换成:
```bash
FW_HEALTH_FORCE=1 fw_need_sdk
```

- [ ] **Step 2: 全仓确认无 `fw_ensure_health` 残留**

Run: `grep -rn 'fw_ensure_health' skills/flutter-wright/`
Expected: 无输出(注释里也不应再有)

- [ ] **Step 3: 静态检查**

Run: `shellcheck skills/flutter-wright/scripts/*.sh`(未装则对每个脚本 `bash -n`)
Expected: 无错误

- [ ] **Step 4: Stage**

```bash
git add skills/flutter-wright/scripts/screenshot.sh skills/flutter-wright/scripts/set_viewport.sh skills/flutter-wright/scripts/goto.sh skills/flutter-wright/scripts/reset.sh skills/flutter-wright/scripts/health.sh
```

**不要 commit。**

---

### Task 7: e2e 测试 —— 重写 reload.sh 测试

**Files:**
- Modify: `packages/example/test/e2e_control_plane_test.dart:253-262`

原断言测 SDK `/reload` 的 exit 0/31。新模型下 reload 走 AI 持有的 daemon、不碰 SDK;测试 job 没 `run` 过(无 `fw_daemon.env`)→ reload.sh 应 exit 33。

- [ ] **Step 1: 替换 reload.sh 测试块**

把原文件第 253-262 行这段:

```dart
    testWidgets('reload.sh：VM service 未启用时按设计返回退出码 31',
        (WidgetTester tester) async {
      await bootApp(tester);
      // flutter test 进程默认不开 VM service → /reload 返回 503 → reload.sh exit 31。
      // 在真实 `flutter run` 下 VM service 总是存在 → exit 0。两者都接受。
      final reload =
          (await tester.runAsync(() => runScript('reload.sh', <String>[])))!;
      expect(reload.exitCode, anyOf(0, 31),
          reason: 'reload.sh 应区分 VM service 可用/不可用，stderr: ${reload.stderr}');
    });
```

替换为:

```dart
    testWidgets('reload.sh：未 run(无 owned daemon)时返回退出码 33',
        (WidgetTester tester) async {
      await bootApp(tester);
      // 新模型:reload 走 AI 持有的 flutter daemon(由 `run` 启动),不再碰 SDK。
      // 测试 job 没 run 过 → 无 $CLAUDE_JOB_DIR/fw_daemon.env → reload.sh 干净报错 exit 33。
      // daemon 驱动的成功路径依赖真机 + 真实 flutter 进程,在设备上手工验证。
      final reload =
          (await tester.runAsync(() => runScript('reload.sh', <String>[])))!;
      expect(reload.exitCode, 33,
          reason: 'reload.sh 无 owned daemon 应 exit 33,stderr: ${reload.stderr}');
    });
```

- [ ] **Step 2: 运行测试**

Run: `cd packages/example && /Users/mini/development/flutter/bin/flutter test`
Expected: 全部通过(goto.sh/reset.sh 测试不变仍绿;新 reload.sh 测试 exit 33)

- [ ] **Step 3: Stage**

```bash
git add packages/example/test/e2e_control_plane_test.dart
```

**不要 commit。**

---

### Task 8: SKILL.md 重写

**Files:**
- Modify: `skills/flutter-wright/SKILL.md`

> 注:该文件当前还有上次会话遗留的未提交 prose 改动(intro / 「何时使用」),本任务在其基础上改;最终一并 stage。

把方法数从 7 改为 9(新增 `run`/`stop`)、硬前提从「SDK 必须运行」改为「按能力分前提」、`reload` 改为 daemon 模型、退出码总表更新、`health` 收窄。

- [ ] **Step 1: 改写「硬前提」块(原 line 12-20)**

把整段 `> ## ⚠️ 硬前提...` 引用块替换为:

```markdown
> ## ⚠️ 前提:按能力分,不再统一要求 SDK
>
> 各方法依赖不同,SDK **不再是硬前提**:
>
> - **截图 / setViewport** —— 只需 `adb` + 已连接设备。任何在跑的 app 都能截,**不需要 SDK**。
> - **reload** —— 需要由本 skill 的 `run` 启动并持有的 `flutter run` daemon(见 `run` / `reload`)。**不需要 SDK**。你自己终端起的 flutter run,本 skill 持有不了,reload 会返回退出码 33(自己按 `r`)。
> - **goto / reset** —— 需要目标 app 集成了 `flutter_wright_sdk` 且 SDK 服务在 `127.0.0.1:9123` 可达。这是 SDK 唯一不可替代的能力。
>
> 集成 SDK 是宿主 app 的一次性步骤(接 navigatorKey 或 navigationAdapter、`start()`),只为解锁 `goto`/`reset`,不在本 skill 操作范围内。
```

- [ ] **Step 2: 改写「何时使用」段(原 line 22-32)**

替换为:

```markdown
## 何时使用

这个 skill 把 Flutter app 的「运行 / 导航 / 观察」交给 AID 远程驱动。9 个方法分三类:

- **进程**:`run`(AI 后台起 `flutter run`)、`stop`(停)。持有进程后才能 `reload`。
- **导航**(SDK 专属):`goto`(程序化跳任意路由)、`reset`(回根)。这是集成 SDK 唯一解锁的能力。
- **观察 / 环境**:`screenshot`(adb 截整帧)、`reload`(热重载 owned daemon)、`setViewport`/`resetViewport`(adb 改分辨率)、`health`(SDK 探针)。

适用:

- **全自动循环**:AI `run` 起 app(集成了 SDK 的 dev 入口)→ `goto` 到任意页 → 截图 → 改码 → `reload`。
- **人工导航 + AI 改码迭代**(最常见):AI `run` 起 app → 人工在设备上点到目标页 → AI 改 Dart → `reload` → `screenshot` 看效果。这条循环 **不需要集成 SDK**(不用 `goto`)。
- **编排构件**:上层 skill 把这些方法当原子操作调用。

不要使用:只需 `goto` 但目标 app 没集成 SDK(那 `goto`/`reset` 不可用,但 `run`/`reload`/`screenshot` 仍可用);或你的导航、reload、截图**全程人工** —— 那直接 `adb exec-out screencap` + 在 flutter run 控制台按 `r` 更省事。
```

- [ ] **Step 3: 删除「环境检查(自动)」段(原 line 34-40)并替换**

原「任意方法首次调用会自动跑 `/health`」的全局闸门已废。替换该段为:

```markdown
## 环境前提(按方法)

不再有「首次调用必过 `/health`」的全局闸门。每个方法只检查自己需要的前提,失败时以对应退出码退出:

- `screenshot` / `setViewport` / `run` → `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。
- `goto` / `reset` / `health` → 上述 + `curl`(13)+ `adb forward tcp:9123` + `GET /health`(SDK 不可达 12)。这些方法在本 job 首次通过后写 `$CLAUDE_JOB_DIR/fw_health_done`,后续走 fast-path。
- `reload` → 不查 adb/SDK,只校验本 skill 已 `run` 且 daemon 存活(33/34)。
```

- [ ] **Step 4: 改写「概念」段的 Reload 行(原 line 47)**

把:
```markdown
- **Reload** = 通过 SDK `/reload` 触发的 Flutter 热重载（`vm_service.reloadSources`）。
```
换成:
```markdown
- **Reload** = 向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart`(`fullRestart:false`),即热重载。不经 SDK。
```

- [ ] **Step 5: 更新方法表(原 line 51-59)**

替换整张表为:

```markdown
| 方法 | 用途 | 脚本 |
|---|---|---|
| `run [target] [device=<id>] [project=<dir>]` | 后台启 `flutter run --machine` 并持有(reload 的前提) | `run.sh` |
| `stop` | 停止 owned daemon + 清理 | `stop.sh` |
| `health` | 显式 SDK 探针(仅 goto/reset 相关) | `health.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 程序化跳转到一个路由(需 SDK) | `goto.sh` |
| `reset` | 把 navigator pop 到根(需 SDK) | `reset.sh` |
| `screenshot <out_path>` | 设备整帧截图(含状态栏)输出 PNG | `screenshot.sh` |
| `reload` | 热重载 owned daemon(`app.restart`) | `reload.sh` |
| `setViewport <w> <h> <dpi>` | 锁定 `wm size` + `wm density` | `set_viewport.sh` |
| `resetViewport` | 恢复 `wm size` + `wm density` 默认值 | `reset_viewport.sh` |
```

- [ ] **Step 6: 新增 `run` / `stop` 方法参考,改写 `reload` 方法参考,收窄 `health`**

在「## 方法参考」下,`health` 段之前插入:

````markdown
### `run`

```
Skill flutter-wright "run [target] [device=<id>] [project=<dir>]"
```

后台启动 `flutter run --machine`(Flutter 官方 daemon 协议),持有进程供后续 `reload` 驱动。`target` 默认 `lib/main.dart`;要用 `goto` 时传集成了 SDK 的 dev 入口(如 `dev/main_dev.dart`)。`device` 默认第一台已连接设备;`project` 默认当前工作目录。状态存于 `$CLAUDE_JOB_DIR/fw_daemon.{in,log,env}`。

等到 app 首帧(`app.started`)才返回,超时 180s。

示例:`Skill flutter-wright "run dev/main_dev.dart"`

退出码:0 成功 / 10 adb 缺失 / 11 无设备 / 36 找不到 flutter(设 `FLUTTER_BIN`)/ 37 已在运行(先 `stop`)/ 38 app 未在 180s 内启动(看 `$CLAUDE_JOB_DIR/fw_daemon.log`)。

### `stop`

```
Skill flutter-wright "stop"
```

向 owned daemon 发 `app.stop`,再终止进程、清理状态文件。**总是退出 0**,可安全用于清理钩子。没有 owned daemon 时打印提示并退出 0。

示例:`Skill flutter-wright "stop"`
````

把 `reload` 方法参考(原 line 106-120)替换为:

````markdown
### `reload`

```
Skill flutter-wright "reload"
```

向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart {fullRestart:false}`(热重载)。源文件改动由调用方(Claude/上层 skill)在调用前完成。**前提是先 `run` 过** —— 没有 owned daemon 时退出码 33。

> 你自己终端起的 `flutter run`,本 skill 持有不了它的 stdin,无法发 reload —— 此时直接在那个控制台按 `r`。本方法只驱动 `run` 起来的 daemon。

示例:`Skill flutter-wright "reload"`

退出码:0 成功 / 33 没有 owned daemon(先 `run`,或自己按 `r`)/ 34 daemon 已死(重新 `run`)/ 35 重载失败或超时(看 daemon 日志的 dart 编译错误)。

实现细节:成功后 sleep 1s,让 Flutter 应用 reload。
````

把 `health` 段首句(原 line 65-69 区域)的描述调整为强调它只与 goto/reset 相关(保留命令与退出码,把开头一句改为):

```markdown
显式跑一遍 **SDK** 探针(`goto`/`reset` 的前提):`adb` + 至少一台设备 + `curl` + `adb forward tcp:9123`(幂等)+ `GET /health`,并**强制刷新**标记 `$CLAUDE_JOB_DIR/fw_health_done`。
```

- [ ] **Step 7: 更新「派发约定」与「退出码对照」**

「派发约定」段第 2 条提到的位置参数方法补上 `run`(`goto`/`screenshot`/`setViewport`/`run`)。

把「退出码对照」表(原 line 173-181)替换为:

```markdown
| 区间 | 类别 | 备注 |
|---|---|---|
| 0 | 成功 | — |
| 10-13 | 环境 / 设备 | 10 adb / 11 设备 / 12 SDK 不可达 / 13 curl |
| 20-22 | 截图 | screenshot.sh |
| 33-36 | reload / run | 33 未 run / 34 daemon 已死 / 35 重载失败或超时 / 36 找不到 flutter |
| 37-38 | run | 37 已在运行 / 38 app 未启动 |
| 40-43 | 导航 | goto.sh(需 SDK) |
| 60-61 | Viewport | set_viewport.sh |
| 70-71 | 重置 | reset.sh(需 SDK) |
```

- [ ] **Step 8: 更新 frontmatter description 的方法数**

把 frontmatter `description:` 里「7 个方法(health/goto/screenshot/reload/setViewport/resetViewport/reset)」改为「9 个方法(run/stop/health/goto/screenshot/reload/setViewport/resetViewport/reset)」。

- [ ] **Step 9: 全文确认无旧模型残留**

Run: `grep -n 'fw_ensure_health\|vm_service\|/reload\|reloadSources\|首次调用' skills/flutter-wright/SKILL.md`
Expected: 无输出(reload 不再描述为 SDK `/reload` 或 vm_service)

- [ ] **Step 10: Stage**

```bash
git add skills/flutter-wright/SKILL.md
```

**不要 commit。**

---

### Task 9: SDK 侧文档更新

**Files:**
- Modify: `docs/api-reference.md`(POST /reload 段、/health 版本号)
- Modify: `docs/architecture.md`(组件图、ReloadHandler、脚本/方法计数、安全约束)
- Modify: `docs/troubleshooting.md`(reload 段、测试步骤、烟雾测试)
- Modify: `packages/flutter_wright_sdk/README.md`(/reload 端点行)

- [ ] **Step 1: `api-reference.md`**

删除整节 `## POST /reload`(原 line 80-94,含其后的实现说明段直到 `## GET /screenshot` 之前)。

把 line 20 的:
```json
{ "ok": true, "version": "0.5.0", "service": "flutter_wright_sdk" }
```
改为:
```json
{ "ok": true, "version": "0.6.0", "service": "flutter_wright_sdk" }
```

- [ ] **Step 2: `architecture.md`**

line 24:`8 Playwright-style methods` → `9 Playwright-style methods`。

line 37,把:
```
|  - /screenshot /reload               |
```
改为:
```
|  - /screenshot                       |
```

删除 line 50 整个 `**ReloadHandler**` 项:
```markdown
- **`ReloadHandler`** — 调 `vm_service.reloadSources` 触发本进程的 Flutter hot reload(在 `flutter run` + DDS 下可能受限,见 troubleshooting)。
```

line 55,把脚本列表改为(新增 run/stop,共 9 个):
```markdown
- **`scripts/`** — 9 个 bash 脚本(`run.sh / stop.sh / health.sh / goto.sh / screenshot.sh / reload.sh / set_viewport.sh / reset_viewport.sh / reset.sh`),封装 flutter daemon / adb / curl 细节。reload 经 `run` 持有的 `flutter run --machine` daemon(`app.restart`),不经 SDK。
```

line 61 表格行,把 `SKILL + 8 scripts + SDK + example + docs` 改为 `SKILL + 9 scripts + SDK + example + docs`。

删除 line 69 的 `/reload` 安全约束项:
```markdown
- `/reload` 端点要求本进程 VM service 可用 — release 构建下 VM service 自动关闭,端点返 503,无安全暴露。
```

- [ ] **Step 3: `troubleshooting.md`**

line 3,把方法名列表改为含 run/stop:`run/stop/health/goto/screenshot/reload/setViewport/resetViewport/reset`。

line 7 的引用块(全局 health 闸门说明)替换为:
```markdown
> **退出码 10-13 来自需要 SDK 的方法(`goto`/`reset`/`health`)** —— 它们检查 `adb` + 设备 + `adb forward` + `GET /health`。`screenshot`/`setViewport`/`run` 只查 `adb` + 设备(10/11)。`reload` 不查这些,只校验 owned daemon(见下方 `reload` 段)。
```

把整节 `## reload 失败`(原 line 88-100,到 `## setViewport 失败` 之前)替换为:
```markdown
## `reload` 失败

新模型:`reload` 向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart`,**不经 SDK**。

### exit 33: 没有 owned daemon

没 `run` 过(无 `$CLAUDE_JOB_DIR/fw_daemon.env`),或你自己终端起了 flutter run(本 skill 持有不了)。两选一:
- 先 `Skill flutter-wright "run dev/main_dev.dart"` 让 AI 起 app;
- 你自己终端起的就在那个控制台按 `r`。

### exit 34: daemon 已死

`run` 起的进程退出了(可能 app crash 或被 kill)。看 `$CLAUDE_JOB_DIR/fw_daemon.log`,重新 `run`。

### exit 35: 重载失败或超时

dart 编译错误(语法错、`main()` 改了需 hot restart),或 60s 内没拿到响应。看 `$CLAUDE_JOB_DIR/fw_daemon.log` 末尾的 reload 结果。需要 hot restart 时 v1 未暴露,临时 workaround:`stop` 后重新 `run`。

### exit 36: 找不到 flutter(`run`)

`run` 定位不到 flutter 二进制。设 `FLUTTER_BIN=/path/to/flutter`,或把 flutter 加进 PATH。

### exit 38: app 未在 180s 内启动(`run`)

看 `$CLAUDE_JOB_DIR/fw_daemon.log`:常见是 build 失败、设备未授权、或 target 入口路径错。
```

line 156,把:
```markdown
期望:`All tests passed!`(含 `reload_handler_test`)。
```
改为:
```markdown
期望:`All tests passed!`。
```

把第 3-4 步烟雾测试(原 line 158-201)中的「手工 flutter run」改为用 skill `run`,并在 reload 前确保已 `run`、结尾 `stop`。具体:把 line 158-170 的「### 第 3 步 — 启动 example app」整段(含手工 `flutter run` 命令与等待 listening 输出)替换为:
```markdown
### 第 3 步 — 用 skill 启动 example app

在 Claude Code 会话里(cwd 切到 `packages/example`):

```
Skill flutter-wright "run dev/main_dev.dart"
# → ok: appId=<id> device=<id> target=dev/main_dev.dart
```

(`dev/main_dev.dart` 是集成了 SDK 的 debug 入口,启用 goto;`lib/main.dart` 是零 SDK 生产入口。)
```
并在第 4 步烟雾序列末尾(原 line 199 `resetViewport` 之后)追加:
```
Skill flutter-wright "stop"
# → stopped: appId=<id>
```
第 4 步开头的 `Skill flutter-wright "health"` 保留(SDK 探针,验证 goto 前提)。

- [ ] **Step 4: `packages/flutter_wright_sdk/README.md`**

删除 line 80 的 `/reload` 端点表格行:
```markdown
| POST   | /reload     | —                                                             | `{"ok":true}`                     |
```
如该文件其它处提到 `/reload` 或 reload 走 SDK,一并删除/改为「reload 由 flutter-wright skill 经 flutter daemon 驱动,不经 SDK」。

- [ ] **Step 5: 确认无残留**

Run: `grep -rn '/reload\|vm_service\|reloadSources\|reload_handler' docs/api-reference.md docs/architecture.md docs/troubleshooting.md packages/flutter_wright_sdk/README.md`
Expected: 无输出

- [ ] **Step 6: Stage**

```bash
git add docs/api-reference.md docs/architecture.md docs/troubleshooting.md packages/flutter_wright_sdk/README.md
```

**不要 commit。**

---

### Task 10: 顶层叙述文档更新(README + 集成指南)

**Files:**
- Modify: `README.md`(line 16, 29-30, 38, 40, 69, 107 附近的「reload 走 SDK」叙述)
- Modify: `docs/integration-guide.md`(line 13 §0 表格行)
- Modify: `docs/integration-guide-for-ai.md`(若有 reload 引用)

核心翻转:AI 的 reload 现在走 `run` 起的 flutter daemon、截图走 adb,**都不需要 SDK**;SDK 只为 `goto`/`reset`。

- [ ] **Step 1: `README.md` 方法表(line 16 附近)**

在 `| `reload` | 触发 Flutter 热重载 |` 行附近补上 run/stop 两行(放表格合适位置):
```markdown
| `run` | AI 后台启动 flutter run 并持有(reload 前提) |
| `stop` | 停止 owned flutter run |
```
并把 reload 行改为:
```markdown
| `reload` | 热重载 AI 持有的 flutter run(不经 SDK) |
```

- [ ] **Step 2: `README.md`「是否需要 SDK」表(line 29-30)**

把两行:
```markdown
| 人工导航,而且**你自己**截图 / 按 `r` reload | **不需要**。`adb exec-out screencap -p > x.png` + `flutter run` 控制台按 `r` |
| 人工导航,但 **AI 改代码 → AI reload → AI 截图看效果** | **需要**(最小集成,只 `start()`)——AI 的 reload/截图得走 SDK |
```
替换为:
```markdown
| 只要 **AI 截图 + AI reload + AI 改码**(不要程序化跳转) | **不需要 SDK**。AI `run` 起你的 app → `reload` + `screenshot`。reload 走 flutter daemon、截图走 adb,均不经 SDK。 |
| 还要 **AI 程序化跳转任意路由(`goto`)** | **需要集成 SDK**(接 navigatorKey/adapter + `start()`)。SDK 只为解锁 `goto`/`reset`。 |
```

- [ ] **Step 3: `README.md` 常见循环叙述(line 38)**

把:
```markdown
最常见的一种:**`flutter run` 起好 → 人工把 app 点到目标页 → AI 改 Dart → AI `reload` → AI `screenshot` 看效果 → 再改**。这条循环里 AI 不碰导航(人来点),只需 `reload` + `screenshot`,所以集成最小化——宿主只 `await FlutterWright.start();` 一行即可。
```
替换为:
```markdown
最常见的一种:**AI `run` 起 app → 人工把 app 点到目标页 → AI 改 Dart → AI `reload` → AI `screenshot` 看效果 → 再改**。这条循环里 AI 不碰导航(人来点),只需 `run` + `reload` + `screenshot`,**完全不需要集成 SDK**。
```

- [ ] **Step 4: `README.md` reload 说明(line 40)**

把:
```markdown
> reload 说明:AI 的 `reload` 走 SDK `/reload`,在 `flutter run` + DDS 下偶尔会被拒(返回 503)。因为这条循环里本就有人在,退化方案很自然——让人在 `flutter run` 控制台按一下 `r`。
```
替换为:
```markdown
> reload 说明:AI 的 `reload` 驱动的是 `run` 起的 `flutter run --machine` daemon(`app.restart`),稳定可靠。前提是用 `run` 起 app;你自己终端起的 flutter run 本 skill 持有不了,reload 返回退出码 33,自己按 `r` 即可。
```

- [ ] **Step 5: `README.md` line 69 / 107 附近**

line 69 表格行 `| `reload` + adb 截图(人工导航) | **仅** `await FlutterWright.start();` |` —— 把「仅 `start()`」改为「**不需要 SDK**;AI `run` 起 app 即可」。

line 107 `最小集成(只要 `reload` + 截图):` 附近的小节 —— 改为说明 reload + 截图**无需集成**,只有 `goto`/`reset` 才需 `start()` + navigatorKey;保留 `goto` 所需的最小集成示例。

- [ ] **Step 6: `docs/integration-guide.md` §0 表格(line 13)**

把:
```markdown
| `reload` + adb 截图(导航靠人工) | **仅** `await FlutterWright.start();` | §1 §2 |
```
替换为:
```markdown
| `reload` + adb 截图(导航靠人工) | **无需集成 SDK** —— 让 flutter-wright skill `run` 起你的 app | — |
```
并在该表顶部或 §0 引言补一句:「`reload`/`screenshot` 不需要 SDK;下表只列**需要集成**的能力(`goto`/`reset` 及可发现路由)。」

- [ ] **Step 7: `docs/integration-guide-for-ai.md`**

Run: `grep -n -i 'reload\|/reload\|vm.service' docs/integration-guide-for-ai.md`
若有命中:把「reload 走 SDK / `start()`」的表述改为「reload 由 skill `run` + flutter daemon 驱动,不需要 SDK」。若无命中(grep 空),跳过本步。

- [ ] **Step 8: 确认无残留**

Run: `grep -rn 'reload.*/reload\|reload.*SDK\|走 SDK.*reload\|/reload' README.md docs/integration-guide.md docs/integration-guide-for-ai.md`
Expected: 无「reload 走 SDK / SDK `/reload`」类残留(出现的 reload 都应指向 flutter daemon)

- [ ] **Step 9: Stage**

```bash
git add README.md docs/integration-guide.md docs/integration-guide-for-ai.md
```

**不要 commit。**

---

### Task 11: CHANGELOG 合并到 0.6.0 + 全量验证

**Files:**
- Modify: `packages/flutter_wright_sdk/CHANGELOG.md`

排序决策 (b):0.5.0 从未发布,与本批合并为一次 0.6.0 提交。把现有 `## 0.5.0` 标题改为 `## 0.6.0`,并把本次「移除 /reload + vm_service」追加进去。

- [ ] **Step 1: 改 CHANGELOG**

把现有第 3 行 `## 0.5.0 - 2026-05-25` 改为 `## 0.6.0 - 2026-05-25`,并在该版本的 `### 移除` 小节(原 line 7-10)末尾追加:
```markdown
- `POST /reload` 端点与 `ReloadHandler`;`vm_service` 依赖。热重载改由 flutter-wright skill
  经 `run` 持有的 `flutter run --machine` daemon(`app.restart`)驱动,不再经 SDK。SDK 自此
  只负责 `goto`/`reset`(导航)与 `/screenshot`(`FlutterWrightRoot`)、`/health`。
```
在 `### 新增` 小节追加:
```markdown
- (skill 侧)`run` / `stop` 方法:AI 持有一个后台 `flutter run --machine` daemon;`reload` 重写为驱动该 daemon。env-check 从全局 `/health` 闸门拆为逐方法前提。
```
在 `### 迁移` 小节追加:
```markdown
- 用过 `POST /reload` 或 skill `reload`(走 SDK)的:改用 flutter-wright skill 的 `run` 起 app,
  `reload` 即驱动该 daemon;或在自己的 flutter run 控制台按 `r`。
```

- [ ] **Step 2: Stage**

```bash
git add packages/flutter_wright_sdk/CHANGELOG.md
```

- [ ] **Step 3: 全量验证**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/dart analyze`
Expected: `No issues found!`

Run: `cd packages/example && /Users/mini/development/flutter/bin/dart analyze`
Expected: `No issues found!`

Run: `cd packages/example && /Users/mini/development/flutter/bin/flutter test`
Expected: `All tests passed!`

Run: `shellcheck skills/flutter-wright/scripts/*.sh`(未装则逐个 `bash -n`)
Expected: 无错误

- [ ] **Step 4: 旧 API grep 闸门(全仓)**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright
grep -rn 'fw_ensure_health' skills/ ; \
grep -rn 'vm_service\|reloadSources\|ReloadHandler\|reload_handler' packages/flutter_wright_sdk/lib packages/flutter_wright_sdk/pubspec.yaml ; \
grep -rn 'POST /reload\|SDK .*/reload\|reload 走 SDK' README.md docs/ skills/flutter-wright/SKILL.md
```
Expected: 三条 grep 全部无输出(reload 旧模型在代码、SDK、文档中清零)

- [ ] **Step 5: 确认最终 staged 范围**

Run: `cd /Users/mini/Documents/dev/github/flutterwright && git status -s`
Expected: 本批新增/修改文件 + 上次路由发现批次,全部 staged;`skills/flutter-wright/SKILL.md` 已含上次遗留 prose 改动一并 staged。**不 commit**——交用户审阅后作为一次 0.6.0 提交。

---

## 实施完成标准

- 两包 `dart analyze` 干净;example `flutter test` 全绿;所有 `.sh` 静态检查通过。
- 旧 reload 模型(`/reload` / `vm_service` / `ReloadHandler` / `fw_ensure_health`)在代码、SDK、9 份文档中清零。
- 新增 `run.sh` / `stop.sh`、重写 `reload.sh` / `_lib.sh`,SKILL.md 反映 9 方法 + 逐方法前提。
- 全部改动 staged 在 `feat/route-discovery-redesign` 分支、与路由发现批次合为一批,**未 commit**(待用户作为单次 0.6.0 提交)。
- daemon 驱动的 `run`/`reload`/`stop` 成功路径需在真机/模拟器上手工烟雾验证(`docs/troubleshooting.md` 附录第 3-4 步)。
