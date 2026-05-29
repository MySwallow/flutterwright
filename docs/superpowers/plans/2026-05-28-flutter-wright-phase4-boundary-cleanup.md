# flutter-wright Phase 4 — 边界清理 Implementation Plan

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收敛 skill 边界——`logs` 改 `adb logcat`(去 `run` 依赖)、移除进程托管簇 `run`/`reload`/`stop`、SKILL.md/methods.md 方法面收敛,并把 5 个 SDK 文档里残留的已删 API `enableInDebugOnly` 同步到 `enabled`。

**Architecture:** 设计 7/8/10(skill 侧)+ Phase 2 遗留文档债。`logs.sh` 从「读 run 持有的 daemon `app.log`」改为「`adb logcat -d`,package 来自目标注册表(`pidof`/`--pid`),无则 `-s flutter`」;删 `run.sh`/`reload.sh`/`stop.sh` 及其唯一依赖 `fw_locate_flutter`;SKILL.md/methods.md 移除这三个方法的所有引用、退出码段 33-38 退役、方法计数 18→**16**(Phase 3 已加 `targets`,故非 spec 早先写的 15);5 个 SDK 文档 `enableInDebugOnly`→`enabled`。不动 SDK Dart 代码。

**Tech Stack:** Bash 3.2(macOS,`set -euo pipefail`;**裸 `[ -n "$x" ] && cmd` 作为语句在 false 时返回 1,会被 set -e 杀掉——一律用 `if/then`**;数组 `arr+=(...)`、`"${arr[@]}"`)、`adb logcat`、`adb shell pidof`;TDD 验收用 bash 测试(`mock_sdk.py` + fake adb 垫片,无真机)。

---

## 文件结构

| 文件 | 角色 | 本期动作 |
|---|---|---|
| `skills/flutter-wright/scripts/logs.sh` | logs 方法 | 重写为 `adb logcat`(去 run 依赖,registry 取 package) |
| `skills/flutter-wright/test/_helpers.sh` | 测试 harness | 扩 `fw_test_fake_adb`:应答 `shell pidof` / `logcat` |
| `skills/flutter-wright/test/logs_test.sh` | **新** logs 验收 | TDD |
| `skills/flutter-wright/scripts/run.sh` `reload.sh` `stop.sh` | 进程托管簇 | **删除** |
| `skills/flutter-wright/scripts/_lib.sh` | 共享 helper | 删 `fw_locate_flutter`(run 专用,已死)+ 改头注释 |
| `skills/flutter-wright/SKILL.md` | skill 说明 | 移除 run/reload/stop 引用 + 方法面收敛 + 迁移说明 |
| `skills/flutter-wright/references/methods.md` | 方法参考 | 删 run/stop/reload 段 + 目录;重写 logs 段 |
| `SECURITY.md` · `docs/integration-guide-for-ai.md` · `docs/integration-guide.md` · `docs/api-reference.md` · `packages/flutter_wright_sdk/README.md` | SDK 文档 | `enableInDebugOnly` → `enabled` |

**任务依赖与顺序**:Task 1(logs)独立先行。Task 2(SKILL.md 移除方法表行)→ Task 3(删脚本):先移表行,`dispatch_naming_test` 只校验「表里每个方法→脚本存在」,表行没了就不查那几个脚本,磁盘上多余脚本不被标记,故两步各自结束时测试都绿。Task 4(methods.md)、Task 5(SDK 文档)独立。Task 6 回归收尾。按序执行。

**明确不做**:不改 SDK Dart 代码(Phase 2 已定 0.8.0 API);不动 CHANGELOG / spec / 历史 plan 里的 `enableInDebugOnly`(那是正确的历史/迁移记录);不引入新交互能力。

---

### Task 1: `logs.sh` → `adb logcat`(去 run 依赖)

**Files:**
- Rewrite: `skills/flutter-wright/scripts/logs.sh`
- Modify: `skills/flutter-wright/test/_helpers.sh`(扩 `fw_test_fake_adb`)
- Test: `skills/flutter-wright/test/logs_test.sh`

`logs` 不再读 run 持有的 daemon 日志,改 `adb logcat -d`:目标注册表(`$FW_TARGETS`)能解析出 `package` 时按 `pidof <package>` 精确过滤(`--pid`),否则回退 `-s flutter`;`since=<n>`→`logcat -t <n>`,`grep=<pat>`→ERE 管道。adb-only、不走 SDK、无 run 依赖。

- [ ] **Step 1: 扩 `fw_test_fake_adb` 应答 `shell pidof` / `logcat`**

把 `skills/flutter-wright/test/_helpers.sh` 中 `fw_test_fake_adb` 内嵌的 here-doc(`cat > "$FW_FAKE_BIN/adb" <<'SH' ... SH`)整体替换为下面这版(新增 `shell pidof` 回 `${FW_FAKE_PIDOF-12345}`、`logcat` 回两行含 `ERROR` 的样例;`devices`/`forward` 行为不变):

```bash
  cat > "$FW_FAKE_BIN/adb" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FW_FAKE_ADB_LOG"
if [ "${FW_FAKE_ADB_FAIL:-}" = "1" ]; then
  case "$*" in *forward*) exit 1;; esac
fi
case "$1" in
  devices) printf 'List of devices attached\nemulator-5554\tdevice\n';;
esac
case "$*" in
  *"shell pidof"*) if [ -n "${FW_FAKE_PIDOF-12345}" ]; then printf '%s\n' "${FW_FAKE_PIDOF-12345}"; else exit 1; fi;;
  *logcat*)        printf 'I/flutter ( 1234): hello\nE/flutter ( 1234): boom ERROR\n';;
esac
exit 0
SH
```

> 注:`FW_FAKE_PIDOF=` 显式设空时,pidof 分支 **不输出且 exit 1**(贴近真机 toybox `pidof` 找不到进程),逼出 logs.sh 的 93 路径;不设时输出 `12345`。并在 `fw_test_fake_adb` 注释块补一行说明 `FW_FAKE_PIDOF`。

> 说明:`${FW_FAKE_PIDOF-12345}` 用 `-`(非 `:-`),所以测试把 `FW_FAKE_PIDOF=` 显式设空时输出空(模拟「package 未运行」);不设时输出 `12345`。`devices`/`forward` 分支未变,`targets_forward_test` 不受影响。

- [ ] **Step 2: 写失败的测试**

Create `skills/flutter-wright/test/logs_test.sh`:

```bash
#!/usr/bin/env bash
# logs_test.sh — logs.sh runs `adb logcat -d` (设计 7: no run/daemon dependency). With a
# registry package → pidof + --pid; without FW_TARGETS → -s flutter. since→-t, grep→ERE
# pipe. package set but not running → 93; bad arg → 92. Uses fake adb (no device).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_test_fake_adb
FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"; export FW_TARGETS
trap 'rm -rf "${FW_FAKE_BIN:-}"; rm -f "${FW_FAKE_ADB_LOG:-}" "${FW_TARGETS:-}"' EXIT
printf 'shop|http://127.0.0.1:9123||com.acme.shop\n' > "$FW_TARGETS"
fail=0

# --- registry package → pidof + logcat --pid=<pid> ---
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/logs.sh" 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: logs(pkg) exit $code" >&2; fail=1; }
grep -q -- 'shell pidof -s com.acme.shop' "$FW_FAKE_ADB_LOG" || { echo "FAIL: no pidof for package: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
grep -q -- 'logcat -d --pid=12345' "$FW_FAKE_ADB_LOG" || { echo "FAIL: logcat not --pid filtered: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *hello*) ;; *) echo "FAIL: logs output missing canned line: $out" >&2; fail=1;; esac

# --- since=N → logcat -t N ; grep=ERROR keeps only the ERROR line ---
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/logs.sh" since=50 grep=ERROR 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: logs(since/grep) exit $code" >&2; fail=1; }
grep -q -- 'logcat -d -t 50 --pid=12345' "$FW_FAKE_ADB_LOG" || { echo "FAIL: -t 50 not passed: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *ERROR*) ;; *) echo "FAIL: grep=ERROR dropped the ERROR line: $out" >&2; fail=1;; esac
case "$out" in *hello*) echo "FAIL: grep=ERROR should have dropped 'hello': $out" >&2; fail=1;; *) ;; esac

# --- package set but not running (pidof empty) → 93 ---
FW_FAKE_PIDOF= bash "$FW_SCRIPTS_DIR/logs.sh" >/dev/null 2>&1; code=$?
[ "$code" -eq 93 ] || { echo "FAIL: package-not-running expected 93, got $code" >&2; fail=1; }

# --- no registry → fall back to -s flutter ---
( unset FW_TARGETS; : > "$FW_FAKE_ADB_LOG"
  out="$(bash "$FW_SCRIPTS_DIR/logs.sh" 2>/dev/null)"; c=$?
  [ "$c" -eq 0 ] || { echo "FAIL: logs(no reg) exit $c" >&2; exit 1; }
  grep -q -- 'logcat -d -s flutter' "$FW_FAKE_ADB_LOG" || { echo "FAIL: no -s flutter fallback: $(cat "$FW_FAKE_ADB_LOG")" >&2; exit 1; } ) || fail=1

# --- unknown arg → 92 ---
bash "$FW_SCRIPTS_DIR/logs.sh" bogus=1 >/dev/null 2>&1; code=$?
[ "$code" -eq 92 ] || { echo "FAIL: bad arg expected 92, got $code" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: logs adb logcat (pid / fallback / since / grep / 93 / 92)"
exit "$fail"
```

- [ ] **Step 3: 跑测试确认失败**

Run: `bash skills/flutter-wright/test/logs_test.sh`
Expected: FAIL —— 旧 `logs.sh` 读 `$CLAUDE_JOB_DIR/fw_daemon.log`、无该文件直接退 92,断言(pidof/logcat/-t/93 等)全不满足。

- [ ] **Step 4: 重写 `logs.sh`**

把 `skills/flutter-wright/scripts/logs.sh` 整个文件替换为:

```bash
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
  pid="$(adb -s "$FW_DEVICE_ID" shell pidof -s "$PKG" 2>/dev/null | tr -d '\r\n ' || true)"   # || true: pidof exits 1 when not found; let the `[ -n "$pid" ]` check own the 93
  [ -n "$pid" ] || { echo "ERR: package '$PKG' not running on device $FW_DEVICE_ID." >&2; exit 93; }
  LOGCAT+=(--pid="$pid")
else
  LOGCAT+=(-s flutter)
fi

OUT="$("${LOGCAT[@]}")"
if [ -n "$PAT" ]; then OUT="$(printf '%s\n' "$OUT" | grep -E -- "$PAT" || true)"; fi
printf '%s\n' "$OUT"
```

- [ ] **Step 5: 跑测试确认通过**

Run: `bash skills/flutter-wright/test/logs_test.sh`
Expected: `PASS: logs adb logcat (pid / fallback / since / grep / 93 / 92)`(退出 0)。

- [ ] **Step 6: 复跑 `targets_forward_test` 确认 fake adb 扩展无回归**

Run: `bash skills/flutter-wright/test/targets_forward_test.sh`
Expected: `PASS: targets forward maps local->device port via fake adb`(新增的 pidof/logcat 分支不影响 devices/forward)。

- [ ] **Step 7: 暂存**

```bash
git add skills/flutter-wright/scripts/logs.sh skills/flutter-wright/test/_helpers.sh skills/flutter-wright/test/logs_test.sh
```
**不要 commit**——由用户审阅后自行 commit。

---

### Task 2: SKILL.md —— 移除 run/reload/stop 引用 + 方法面收敛

**Files:**
- Modify: `skills/flutter-wright/SKILL.md`(description / 前提 / 典型用法 / 路由表 / 方法表 / 派发约定 / 退出码表 + 迁移说明)

逐处 Edit。每处 old_string 精确匹配当前文件。`dispatch_naming_test` 在方法表行删掉后仍绿(它只校验「表里的方法→脚本存在」,磁盘上将被删的多余脚本不会被标记)。

- [ ] **Step 1: description(L3)——去「热重载」**

old_string: `截图 / 热重载 / 锁视口(只需 adb)`
new_string: `截图 / 锁视口(只需 adb)`

- [ ] **Step 2: description(L3)——去硬编码端口**

old_string: `需 app 集成 flutter_wright_sdk,服务在 127.0.0.1:9123`
new_string: `需 app 集成 flutter_wright_sdk,服务地址经目标注册表配置`

- [ ] **Step 3: description(L3)——方法计数与清单(18→16,去 run/stop/reload,已含 targets)**

old_string: `仅 Android。18 个方法:run/stop/health/snapshot/tap/type/scroll/longPress/waitFor/pressKey/back/logs/goto/reset/screenshot/reload/setViewport/resetViewport。`
new_string: `仅 Android。16 个方法:health/targets/snapshot/tap/type/scroll/longPress/waitFor/pressKey/back/logs/goto/reset/screenshot/setViewport/resetViewport。`

- [ ] **Step 4: 引言(L8)——去「热重载」**

old_string: `截图、热重载、视口锁定开箱即用`
new_string: `截图、视口锁定开箱即用`

- [ ] **Step 5: 前提段——adb 清单去 run、加 logs;去 fast-path/adb-forward 陈旧文案;删「需先 run」整条**

old_string:

```markdown
- **只需 adb**:`screenshot` / `setViewport` / `resetViewport` / `run` / `pressKey` / `back`。要 `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。
- **需 SDK**(app 集成 `flutter_wright_sdk`,服务在 `127.0.0.1:9123`):`snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor` / `goto` / `reset` / `health`。在上面基础上再要 `curl`(13)+ `adb forward tcp:9123` + `GET /health` 通(SDK 不可达 12)。本 job 首次通过后写 `$CLAUDE_JOB_DIR/fw_health_done`,后续走 fast-path。`goto`/`reset` 还要宿主在 `FlutterWright.start()` 传了 `navigatorKey` 或 `navigationAdapter`,否则回 501(脚本退 41)。
- **需先 `run`**:`reload` / `logs` 读本 skill 持有的 daemon,不查 adb/SDK(无 daemon 退 33/92)。
```

new_string:

```markdown
- **只需 adb**:`screenshot` / `setViewport` / `resetViewport` / `pressKey` / `back` / `logs`。要 `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。`logs` 默认 `adb logcat -s flutter`;设了 `FW_TARGETS` 时按注册表 `package` 精确过滤(注册表不可用则退 14/15)。
- **需 SDK**(app 集成 `flutter_wright_sdk`,服务地址经目标注册表):`snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor` / `goto` / `reset` / `health`。在上面基础上再要 `curl`(13)+ 目标注册表可解析(14/15)+ `GET <base>/health` 通(SDK 不可达 12)。`goto`/`reset` 还要宿主在 `FlutterWright.start()` 传了 `navigatorKey` 或 `navigationAdapter`,否则回 501(脚本退 41)。
- **目标管理 `targets`**:列举需 `curl`(13)+ 注册表可解析(14);`targets forward` 需 `adb`(10/11)+ 注册表(14/15)。
```

> 注:`targets`(Phase 3 加)原本不在前提段;Task 2 收敛时补上,使前提段覆盖全部 16 方法。另外两处小改:工作法段 `导航/reload/动作`→`导航/热重载/动作`(reload 不再是方法);派发约定位置参数 `宽高`→`宽高 dpi`(setViewport 三参)。

- [ ] **Step 6: 典型用法——交互闭环示例(不再 `run`,改自己 `flutter run`)**

old_string: `- **交互闭环**(对齐 Playwright):`run` 起集成 SDK 的 dev 入口 → `snapshot` 拿 ref → `tap`/`type`/`scroll` 派发 → 动作自动回吐新 snapshot。`
new_string: `- **交互闭环**(对齐 Playwright):你自己 `flutter run` 起集成 SDK 的 dev 入口 → `snapshot` 拿 ref → `tap`/`type`/`scroll` 派发 → 动作自动回吐新 snapshot。`

- [ ] **Step 7: 典型用法——人工导航迭代示例(去 `run`/`reload`,改按 `r`)**

old_string: `- **人工导航 + AI 改码迭代**(最常见,**不需要 SDK**):`run` → 人工点到目标页 → 改 Dart → `reload` → `screenshot`。`
new_string: `- **人工导航 + AI 改码迭代**(最常见,**不需要 SDK**):你自己 `flutter run` → 人工点到目标页 → 改 Dart → 控制台按 `r` 热重载 → `screenshot`。`

- [ ] **Step 8: 路由表——删「起/停 app」与「reload」行,logs 前提改「仅 adb」**

old_string:

```markdown
| 截图看效果(不用于定位) | `screenshot <out>` | 仅 adb |
| 起 app / 停 app | `run [target]` / `stop` | adb |
| 看有哪些目标 app / 哪个连得上 / 建端口转发 | `targets` / `targets forward target=<name>` | 列举需 curl,forward 需 adb |
| 改了 Dart 代码要生效 | `reload` | 已 `run` |
| 看 app 运行日志 | `logs [since=] [grep=]` | 已 `run` |
```

new_string:

```markdown
| 截图看效果(不用于定位) | `screenshot <out>` | 仅 adb |
| 看有哪些目标 app / 哪个连得上 / 建端口转发 | `targets` / `targets forward target=<name>` | 列举需 curl,forward 需 adb |
| 看 app 运行日志 | `logs [since=] [grep=]` | 仅 adb |
```

- [ ] **Step 9: 方法表——删 run/stop 两行**

old_string:

```markdown
| 方法 | 用途 | 脚本 |
|---|---|---|
| `run [target] [device=<id>] [project=<dir>]` | 后台启 `flutter run --machine` 并持有(reload/logs 的前提) | `run.sh` |
| `stop` | 停止 owned daemon + 清理 | `stop.sh` |
| `health` | 显式 SDK 探针(交互/导航相关) | `health.sh` |
```

new_string:

```markdown
| 方法 | 用途 | 脚本 |
|---|---|---|
| `health` | 显式 SDK 探针(交互/导航相关) | `health.sh` |
```

- [ ] **Step 10: 方法表——logs 行改 logcat 描述**

old_string: `| `logs [since=<n>] [grep=<pat>]` | 读 owned daemon `app.log`(免 SDK) | `logs.sh` |`
new_string: `| `logs [since=<n>] [grep=<pat>] [target=<name>]` | `adb logcat`(按注册表 package 或 `-s flutter`),免 SDK | `logs.sh` |`

- [ ] **Step 11: 方法表——删 reload 行**

old_string: `| `reload` | 热重载 owned daemon(`app.restart`) | `reload.sh` |
`
new_string:(空——删除整行)

> 用 Edit 把上面那一行(含行尾换行)替换为空字符串。

- [ ] **Step 12: 方法表后加迁移说明**

old_string: `**每个方法的完整签名、参数约束、示例与逐条退出码见 [`references/methods.md`](references/methods.md)。**`
new_string:

```markdown
**每个方法的完整签名、参数约束、示例与逐条退出码见 [`references/methods.md`](references/methods.md)。**

> **迁移**:`run` / `reload` / `stop` 已移除——本 skill 不再托管 flutter 进程。你自己 `flutter run`(集成 SDK 时跑 dev 入口),需热重载就在它的控制台按 `r`;`logs` 改用 `adb logcat`(按注册表 `package` 或 `-s flutter`),不再依赖 `run`。
```

- [ ] **Step 13: 派发约定 step 2——去 run 的位置参数 target / device / project,简化 target= 说明**

old_string: `2. 把剩余 token 解析为位置参数(`element` / `route` / `out_path` / `target` / 宽高 / key 名),随后是 `key=value` 对(`ref`/`text`/`dir`/`args`/`popUntilRoot`/`out`/`since`/`grep`/`timeout`/`submit`/`device`/`project`/`target`)。`<element>` 用引号位置参数(`tap "登录" ref=s12`)。**两个 `target` 含义不同**:位置参数 `target` 是 `run` 的 dart 入口文件;`key=value` 的 `target=<name>` 是「目标注册表」条目名(选驱动哪个 app),作为 `key=value` 排在位置参数之后(写 `goto /route target=shop`,**不要**写 `goto target=shop /route`)。`
new_string: `2. 把剩余 token 解析为位置参数(`element` / `route` / `out_path` / 宽高 / key 名),随后是 `key=value` 对(`ref`/`text`/`dir`/`args`/`popUntilRoot`/`out`/`since`/`grep`/`timeout`/`submit`/`target`)。`<element>` 用引号位置参数(`tap "登录" ref=s12`)。`target=<name>` 是「目标注册表」条目名(选驱动哪个 app),作为 `key=value` 排在位置参数之后(写 `goto /route target=shop`)。`

- [ ] **Step 14: 派发约定 step 3——同名清单去 run/stop/reload**

old_string: `其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`health`/`logs`/`back`/`screenshot`/`run`/`stop`/`reload`/`targets`)名一致。`
new_string: `其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`health`/`logs`/`back`/`screenshot`/`targets`)名一致。`

- [ ] **Step 15: 退出码表——删 33-36 / 37-38 两行**

old_string:

```markdown
| 20-22 | 截图 | screenshot.sh |
| 33-36 | reload / run | 33 未 run / 34 daemon 已死 / 35 重载失败或超时 / 36 找不到 flutter |
| 37-38 | run | 37 已在运行 / 38 app 未启动 |
| 40-43 | 导航 | goto.sh(需 SDK + navigatorKey/adapter,未配置 → 41/501) |
```

new_string:

```markdown
| 20-22 | 截图 | screenshot.sh |
| 40-43 | 导航 | goto.sh(需 SDK + navigatorKey/adapter,未配置 → 41/501) |
```

- [ ] **Step 16: 退出码表——logs 行扩到 90-93**

old_string: `| 90-92 | 按键 / 日志 | press_key/back(90/91)/ logs(92) |`
new_string: `| 90-93 | 按键 / 日志 | press_key/back(90 未知 key / 91 失败)/ logs(92 参数错 / 93 指定 package 未运行;另用 adb 10/11、注册表 14/15) |`

- [ ] **Step 17: 验证 dispatch_naming_test 仍绿**

Run: `bash skills/flutter-wright/test/dispatch_naming_test.sh; echo "RC=$?"`
Expected: `PASS: dispatch naming rule consistent & documented` + `RC=0`(方法表已无 run/stop/reload 行,故不再校验那三个脚本;`run.sh`/`reload.sh`/`stop.sh` 此刻仍在磁盘但不被该测试标记)。

- [ ] **Step 18: 暂存**

```bash
git add skills/flutter-wright/SKILL.md
```
**不要 commit。**

---

### Task 3: 删除 `run.sh`/`reload.sh`/`stop.sh` + 清理死代码 `fw_locate_flutter`

**Files:**
- Delete: `skills/flutter-wright/scripts/run.sh` `skills/flutter-wright/scripts/reload.sh` `skills/flutter-wright/scripts/stop.sh`
- Modify: `skills/flutter-wright/scripts/_lib.sh`(删 `fw_locate_flutter` + 改头注释)

`run.sh` 是 `fw_locate_flutter` 的唯一调用方,删 run 后它变死代码,一并清除。

- [ ] **Step 1: 删三个脚本**

```bash
git rm skills/flutter-wright/scripts/run.sh skills/flutter-wright/scripts/reload.sh skills/flutter-wright/scripts/stop.sh
```

- [ ] **Step 2: `_lib.sh` 头注释去掉 `fw_locate_flutter` 行、`run` 字样**

old_string:

```bash
#   fw_need_adb        # methods that only need a device (screenshot/setViewport/run)
#   fw_need_sdk        # methods that talk to the in-app SDK (goto/reset/health)
#   fw_locate_flutter  # echo path to the flutter binary, or return 1
```

new_string:

```bash
#   fw_need_adb        # methods that only need a device (screenshot/setViewport/logs)
#   fw_need_sdk        # methods that talk to the in-app SDK (goto/reset/health)
```

- [ ] **Step 3: `_lib.sh` 删 `fw_locate_flutter` 函数**

old_string:

```bash
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

new_string:(空——删除整个函数及其后空行)

> 用 Edit 把上面整块(函数 + 其后的一个空行)替换为空字符串。删后 `fw_resolve_target` 区段紧跟在 `fw_need_sdk` 之后。

- [ ] **Step 4: 验证——语法、命名一致、registry 测试无回归、无悬挂引用**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutter-wright
for s in scripts/*.sh; do bash -n "$s" || echo "SYNTAX FAIL: $s"; done
bash test/dispatch_naming_test.sh
bash test/resolve_target_test.sh
grep -rn -E 'fw_locate_flutter|run\.sh|reload\.sh|stop\.sh' scripts test SKILL.md references || echo "NO_DANGLING_REFS"
ls scripts/run.sh scripts/reload.sh scripts/stop.sh 2>&1 | grep -c 'No such file'
```
Expected: 无 `SYNTAX FAIL`;`PASS: dispatch naming...`;`PASS: fw_resolve_target...`;`NO_DANGLING_REFS`(skill 内无残留引用——SDK 的 dart `flutter run` 文案不在此范围);末行 `3`(三脚本均已不存在)。

- [ ] **Step 5: 暂存**

```bash
git add skills/flutter-wright/scripts/_lib.sh
# 三个删除已由 git rm 暂存
```
**不要 commit。**

---

### Task 4: methods.md —— 删 run/stop/reload 段 + 重写 logs 段

**Files:**
- Modify: `skills/flutter-wright/references/methods.md`(目录 + run/stop/reload 段 + logs 段)

- [ ] **Step 1: 目录——删「进程」组、去 reload**

old_string:

```markdown
- 进程:[`run`](#run) · [`stop`](#stop)
- 观察:[`health`](#health) · [`snapshot`](#snapshot) · [`screenshot`](#screenshot) · [`logs`](#logs)
```

new_string:

```markdown
- 观察:[`health`](#health) · [`snapshot`](#snapshot) · [`screenshot`](#screenshot) · [`logs`](#logs)
```

old_string: `- 环境/进程:[`reload`](#reload) · [`setViewport` / `resetViewport`](#setviewport--resetviewport)`
new_string: `- 环境:[`setViewport` / `resetViewport`](#setviewport--resetviewport)`(同时去掉 reload 与「/进程」遗留标签)

- [ ] **Step 2: 删 `run` + `stop` 两段(保留 `### \`health\``)**

old_string:

`````markdown
### `run`

```
Skill flutter-wright "run [target] [device=<id>] [project=<dir>]"
```

后台启动 `flutter run --machine`(Flutter 官方 daemon 协议),持有进程供后续 `reload` 驱动。`target` 默认 `lib/main.dart`;要用 snapshot/tap/type/goto 时传集成了 SDK 的 dev 入口(如 `dev/main_dev.dart`)。`device` 默认第一台已连接设备;`project` 默认当前工作目录。状态存于 `$CLAUDE_JOB_DIR/fw_daemon.{in,log,env}`。

等到 app 首帧(`app.started`)才返回,超时 180s。

示例:`Skill flutter-wright "run dev/main_dev.dart"`

退出码:0 成功 / 10 adb 缺失 / 11 无设备 / 36 找不到 flutter(设 `FLUTTER_BIN`)/ 37 已在运行(先 `stop`)/ 38 app 未在 180s 内启动(看 `$CLAUDE_JOB_DIR/fw_daemon.log`)。

### `stop`

```
Skill flutter-wright "stop"
```

向 owned daemon 发 `app.stop`,再终止进程、清理状态文件。**总是退出 0**,可安全用于清理钩子。没有 owned daemon 时打印提示并退出 0。

### `health`
`````

new_string:

`````markdown
### `health`
`````

- [ ] **Step 3: 重写 `logs` 段为 logcat**

old_string:

`````markdown
### `logs`

```
Skill flutter-wright "logs [since=<n>] [grep=<pat>]"
```

读本 skill `run` 持有的 daemon `app.log` 行(对应 `print`/`debugPrint`)。`since=<n>` 取最后 N 行;`grep=<pat>` 用 ERE 过滤。**不需要 SDK**;未 `run` 时退 92。

示例:`Skill flutter-wright "logs since=50 grep=ERROR"`

退出码:0 / 92 未 run(无 daemon log)或参数错。
`````

new_string:

`````markdown
### `logs`

```
Skill flutter-wright "logs [since=<n>] [grep=<pat>] [target=<name>]"
```

`adb logcat -d` 读设备日志,**不托管 flutter 进程、不走 SDK**(进程由调用方自行 `flutter run`)。若目标注册表(`$FW_TARGETS`)可解析出 `package`,按 `adb shell pidof -s <package>` 取 pid 后 `logcat --pid` 精确过滤;否则回退 `logcat -d -s flutter`(多 app 会混)。`since=<n>` → `logcat -t <n>`(最后 N 行);`grep=<pat>` → ERE 管道过滤;`target=<name>` 选注册表条目(决定用哪个 app 的 package)。未设 `FW_TARGETS` 时直接走 `-s flutter`。

示例:`Skill flutter-wright "logs since=50 grep=ERROR"`

退出码:0 / 10 adb 缺失 / 11 无设备 / 14 已设 `FW_TARGETS` 但注册表缺失或空 / 15 目标歧义或未找到 / 92 参数错 / 93 指定 `package` 未在设备上运行。
`````

- [ ] **Step 4: 删 `reload` 段(保留 `### \`setViewport\` / \`resetViewport\``)**

old_string:

`````markdown
### `reload`

```
Skill flutter-wright "reload"
```

向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart {fullRestart:false}`(热重载)。源文件改动由调用方在调用前完成。**前提是先 `run` 过** —— 没有 owned daemon 时退 33。

退出码:0 / 33 没有 owned daemon(先 `run`,或自己按 `r`)/ 34 daemon 已死 / 35 重载失败或超时。

### `setViewport` / `resetViewport`
`````

new_string:

`````markdown
### `setViewport` / `resetViewport`
`````

- [ ] **Step 5: 验证 + 暂存**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright
grep -n '^### ' skills/flutter-wright/references/methods.md
grep -c -E '`run`|`stop`|`reload`|fw_daemon|app\.log|app\.restart|owned daemon' skills/flutter-wright/references/methods.md
```
Expected:`### ` 标题列表里**没有** run/stop/reload;第二条计数为 `0`(无残留引用)。
```bash
git add skills/flutter-wright/references/methods.md
```
**不要 commit。**

---

### Task 5: SDK 文档 —— `enableInDebugOnly` → `enabled`

**Files:**
- Modify: `SECURITY.md`
- Modify: `docs/integration-guide-for-ai.md`
- Modify: `docs/integration-guide.md`
- Modify: `docs/api-reference.md`
- Modify: `packages/flutter_wright_sdk/README.md`

Phase 2 已把 `FlutterWright.start()` 改为顶层 `enabled`(默认 `false`,fail-safe)、移除 `FlutterWrightConfig.enableInDebugOnly`。这 5 个**在用文档**仍引用已删 API,逐处改正。迁移语义:`enableInDebugOnly: true` ≈ `enabled: kDebugMode`;默认值从「debug 才开」变为「默认关、显式 `enabled: true` 才开」。

- [ ] **Step 1: `SECURITY.md` 威胁表 + 加固建议**

old_string: `| 误把HTTP 服务带到生产用户手里                  | 默认 `enableInDebugOnly: true` — release 构建里 `start()` 是 no-op |`
new_string: `| 误把HTTP 服务带到生产用户手里                  | `enabled` 默认 `false` — 不传 `enabled: true` 时 `start()` 是 no-op、不绑端口;集成方用 `enabled: kDebugMode` 或自己的「测试包?」判断接线 |`

old_string: `- 保持 `enableInDebugOnly: true`（默认）。`
new_string: `- 用 `enabled: kDebugMode`（或你自己的「测试包?」判断）接线,正式包让它为 `false`(默认)。`

- [ ] **Step 2: `docs/integration-guide-for-ai.md` 易错表**

old_string: `| ❌ 把 `enableInDebugOnly: false` 设到 release | 生产包开 HTTP 端口 = 安全风险 | 默认值就是对的,**不要**改 |`
new_string: `| ❌ 在 release 包传 `enabled: true` | 生产包开 HTTP 端口 = 安全风险 | 用 `enabled: kDebugMode` 或「测试包?」判断;正式包必须 `false`(默认) |`

- [ ] **Step 3: `docs/integration-guide.md` 第 6 节**

old_string:

````markdown
## 6. 在 profile/release 里禁用 SDK

默认 `enableInDebugOnly: true` 已经做了。如果你想在 profile 构建里也开(给 QA 用):

```dart
await FlutterWright.start(
  config: const FlutterWrightConfig(enableInDebugOnly: false),
);
```
````

new_string:

````markdown
## 6. 控制 SDK 启用(profile/release)

`enabled` 默认 `false`,`start()` 直接 no-op、不绑端口。用你自己的「测试包?」判断接线:

```dart
await FlutterWright.start(
  enabled: AppEnv.isTestBuild,   // 或 kDebugMode
);
```

正式包让该判断为假即彻底关闭、零运行时攻击面;profile/QA 包想开就让它为真。
````

- [ ] **Step 4: `docs/api-reference.md` start() 参数表(改 config 行 + 补 enabled/token)**

old_string:

```markdown
| `routes` | `Iterable<String>?` | 路由名列表,喂给 `GET /routes`;不传则由 adapter 的 `discoverableRoutes` 决定(可能为 `[]`) |
| `config` | `FlutterWrightConfig?` | host/port/enableInDebugOnly 等配置 |
```

new_string:

```markdown
| `routes` | `Iterable<String>?` | 路由名列表,喂给 `GET /routes`;不传则由 adapter 的 `discoverableRoutes` 决定(可能为 `[]`) |
| `enabled` | `bool` | 默认 `false`;为 `false` 时 `start()` 直接 no-op、不绑端口。集成方接线为 `kDebugMode` 或自己的「测试包?」判断 |
| `token` | `String?` | 非空时除 `/health` 外所有请求校验 `X-FW-Token`,不符回 401(常量时间比对);为空 = 不鉴权(仅 loopback) |
| `config` | `FlutterWrightConfig?` | host/port/screenshotMode/maxBodyBytes 等配置(不再含 `enableInDebugOnly`) |
```

- [ ] **Step 5: `packages/flutter_wright_sdk/README.md` 示例**

old_string: `    enableInDebugOnly: true,              // false 时 profile 也启`
new_string:(删除整行——`enabled` 是 `start()` 顶层参数而非 `config` 字段)

> 用 Edit 把这一行(含行尾换行)替换为空字符串。该行在 `FlutterWrightConfig(...)` 示例块内,而 `enableInDebugOnly` 已从 config 移除;`enabled` 改在 `start(enabled: ...)` 顶层传,故此处直接删行。

- [ ] **Step 6: 验证——在用文档里不再出现 `enableInDebugOnly`**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright
grep -rIl 'enableInDebugOnly' --exclude-dir=.git . | grep -vE 'CHANGELOG|docs/superpowers/(specs|plans)/' || echo "NO_LIVE_REFS"
```
Expected: `NO_LIVE_REFS`(只剩 CHANGELOG / spec / 历史 plan 这类正当历史记录)。

- [ ] **Step 7: 暂存**

```bash
git add SECURITY.md docs/integration-guide-for-ai.md docs/integration-guide.md docs/api-reference.md packages/flutter_wright_sdk/README.md
```
**不要 commit。**

---

### Task 6: 回归

**Files:** 无改动(仅运行检查)

- [ ] **Step 1: 全脚本语法 + 全 bash 测试**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutter-wright
for s in scripts/*.sh; do bash -n "$s" && echo "ok: $s" || echo "SYNTAX FAIL: $s"; done
rc=0
for t in test/*_test.sh; do echo "== $t =="; bash "$t" || rc=1; done
echo "ALL_TESTS_RC=$rc"
```
Expected:无 `SYNTAX FAIL`(脚本数比之前少 3,无 run/reload/stop);`dispatch_naming` / `resolve_target` / `goto_exit_code` / `reset_exit_code` / `snapshot_smoke` / `targets_list` / `targets_forward` / **`logs`** 全 `PASS`;`ALL_TESTS_RC=0`。

- [ ] **Step 2: 无残留引用核对**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright
echo "--- skill 内 run/reload/stop 残留 ---"
grep -rn -E 'run\.sh|reload\.sh|stop\.sh|fw_locate_flutter' skills/flutter-wright/scripts skills/flutter-wright/test skills/flutter-wright/SKILL.md skills/flutter-wright/references || echo "NONE"
echo "--- 在用文档 enableInDebugOnly 残留 ---"
grep -rIl 'enableInDebugOnly' --exclude-dir=.git . | grep -vE 'CHANGELOG|docs/superpowers/(specs|plans)/' || echo "NONE"
```
Expected: 两处均 `NONE`。

- [ ] **Step 3:(无需 stage)**

本任务不产生文件改动。前 5 个任务已各自暂存(含 `git rm` 的三个删除)。最终由用户审阅 `git status` 后统一 commit。

> 注:Phase 4 不动 SDK Dart 代码(仅改 SDK 文档),两包 `flutter test` 无须复跑;若想额外保险:`/Users/mini/development/flutter/bin/flutter test`(SDK 24 / example 14,应与 Phase 2 末态一致)。

---

## 验收对照(spec §验收 / Phase 4)

| spec 要求 | 对应任务 |
|---|---|
| 设计 7:`logs` 改 `adb logcat`(package→pidof/--pid;无→`-s flutter`;since→-t;grep→管道;去 run 依赖) | Task 1 |
| 设计 8:删 run/reload/stop;退出码 33-38 退役;SKILL.md 加迁移说明 | Task 2(SKILL.md 引用 + 33-38 + 迁移)、Task 3(删脚本 + 死代码) |
| 设计 10:方法数收敛(18→**16**,含 Phase 3 的 targets);logs 文档改 logcat;退出码表去 33-38;methods.md 删 run/reload/stop + 改 logs | Task 2、Task 4 |
| 移除验收:run/reload/stop 脚本不存在;SKILL.md/methods.md 无残留引用 | Task 3 Step 4、Task 6 Step 2 |
| 文档债(Phase 2 HIGH-2):5 个在用文档 `enableInDebugOnly`→`enabled` | Task 5 |
| 回归:全脚本 `bash -n`;bash 测试全绿(含新 logs);无残留引用 | Task 6 |
