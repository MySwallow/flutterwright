# flutter-wright Phase 3 — 多 App / 目标管理 Implementation Plan

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 skill 增加目标注册/发现能力——注册表加可选 `deviceport` 字段、新增 `targets` 方法(列举+探活)与 `targets forward`(注册时一次性建 `adb forward`),让一套 SDK 集成进多个 app 时 AI 能列出/探活/选择驱动哪个。

**Architecture:** 纯 skill 侧改动(scripts + docs),**不动 SDK / Dart**。Phase 2 已落地注册表读取(`fw_resolve_target`:单条目默认、多条目 `target=` 消歧、退出码 14/15)与「`fw_need_sdk` 不再自动 `adb forward`」。Phase 3 在此之上补「注册时建可达性」与「探活/列举」:`_lib.sh` 抽出 `fw_registry_lines`/`fw_base_port` 两个 helper、`fw_resolve_target` 多解析一个可选 `deviceport` 字段并导出 `FW_DEVICE_PORT`/`FW_TARGET_NAME`;新增只读 `targets.sh`(列举+探活 / `forward` 子命令)。注册表仍由 operator 手写在 git 外(`$FW_TARGETS`),工具**只读不改写**(token 绝不经自动流程写入)。

**Tech Stack:** Bash 3.2(macOS,`set -euo pipefail`;空数组用 `"${a[@]+"${a[@]}"}"`、pipe `|` 作分隔符)、`curl`、`adb`;TDD 验收用 bash 测试(`mock_sdk.py` 仿 SDK 控制面 + fake adb 垫片,真机/真 adb 不需要)。

---

## 文件结构

| 文件 | 角色 | 本期动作 |
|---|---|---|
| `skills/flutter-wright/scripts/_lib.sh` | 共享 helper | 加 `fw_registry_lines`/`fw_base_port`;`fw_resolve_target` 解析 `deviceport` + 导出 `FW_DEVICE_PORT`/`FW_TARGET_NAME` |
| `skills/flutter-wright/scripts/targets.sh` | **新** `targets` 方法脚本 | 列举+探活 / `forward` 子命令 |
| `skills/flutter-wright/test/_helpers.sh` | 测试 harness | 加 `fw_test_fake_adb`(fake adb 垫片) |
| `skills/flutter-wright/test/resolve_target_test.sh` | `fw_resolve_target` 单测 | 扩 deviceport / name / `fw_base_port` 断言 |
| `skills/flutter-wright/test/targets_list_test.sh` | **新** 列举+探活验收 | TDD |
| `skills/flutter-wright/test/targets_forward_test.sh` | **新** forward 端口映射验收 | TDD(fake adb) |
| `skills/flutter-wright/SKILL.md` | skill 说明 | 方法表 + 派发约定 + 退出码 + 目标段 |
| `skills/flutter-wright/references/methods.md` | 方法参考 | 新增 `targets` 段 + 目录 |

**任务依赖**:Task 1(lib)→ Task 2(列举,用 `fw_registry_lines`)→ Task 3(forward,用 `FW_DEVICE_PORT`/`fw_base_port`/`FW_TARGET_NAME`)→ Task 4/5(文档,`dispatch_naming_test` 依赖 `targets.sh` 存在)→ Task 6(回归)。按序执行。

**范围边界(明确不做,留给 Phase 4 = 设计 7/8/10)**:不改 SKILL.md 第 3 行 description 的方法计数/`127.0.0.1:9123` 陈旧文案、不改第 17 行前提里残留的 `adb forward tcp:9123` / `fw_health_done` marker 文案、不移除 `run`/`reload`/`stop`、不改 `logs`。本期只**新增** `targets` 的功能面与其文档,不做全局方法面收敛。

---

### Task 1: `_lib.sh` — deviceport 字段 + `fw_registry_lines`/`fw_base_port` helper

**Files:**
- Modify: `skills/flutter-wright/scripts/_lib.sh:54-97`(`fw_resolve_target` 区段)
- Test: `skills/flutter-wright/test/resolve_target_test.sh`(在末尾 `[ "$fail" -eq 0 ]` 行前追加断言)

注册表行从 4 字段 `name|base|token|package` 扩到可选 5 字段 `name|base|token|package|deviceport`。`deviceport` 留空 → 默认 = `base` 解析出的本地端口(`fw_base_port`)。`fw_resolve_target` 额外导出 `FW_DEVICE_PORT` 与 `FW_TARGET_NAME`。把「读注册表数据行」的契约抽成 `fw_registry_lines`(供 `targets.sh` 列举复用,DRY)。向后兼容:旧 4 字段行 `deviceport` 读空 → 走默认。

- [ ] **Step 1: Write the failing tests**

在 `skills/flutter-wright/test/resolve_target_test.sh` 的这一行之前:

```bash
[ "$fail" -eq 0 ] && echo "PASS: fw_resolve_target registry resolution"
```

插入以下断言块:

```bash
# --- deviceport: explicit 5th field is used verbatim; name is exported ---
printf 'shop|http://127.0.0.1:9124|tok|com.acme.shop|9123\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_DEVICE_PORT" = "9123" ] || { echo "FAIL: explicit deviceport=$FW_DEVICE_PORT (want 9123)" >&2; fail=1; }
[ "$FW_TARGET_NAME" = "shop" ] || { echo "FAIL: target name=$FW_TARGET_NAME (want shop)" >&2; fail=1; }

# --- deviceport: omitted (4-field line) defaults to the port parsed from base ---
printf 'shop|http://127.0.0.1:9124|tok|com.acme.shop\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_DEVICE_PORT" = "9124" ] || { echo "FAIL: defaulted deviceport=$FW_DEVICE_PORT (want 9124)" >&2; fail=1; }

# --- fw_base_port: strips scheme/host + trailing slash, keeps the port ---
[ "$(fw_base_port 'http://127.0.0.1:9123')" = "9123" ] || { echo "FAIL: fw_base_port plain" >&2; fail=1; }
[ "$(fw_base_port 'http://127.0.0.1:9124/')" = "9124" ] || { echo "FAIL: fw_base_port trailing slash" >&2; fail=1; }

# --- port-less base is a misconfig: device port cannot be derived → exit 14 ---
printf 'bad|http://127.0.0.1||com.acme.bad\n' > "$reg"
( FW_TARGETS="$reg" fw_resolve_target ) 2>/dev/null; rc=$?
[ "$rc" -eq 14 ] || { echo "FAIL: port-less base expected 14, got $rc" >&2; fail=1; }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash skills/flutter-wright/test/resolve_target_test.sh`
Expected: FAIL —— 当前 `fw_resolve_target` 不设 `FW_DEVICE_PORT`/`FW_TARGET_NAME`,测试在 `set -u` 下读未绑定变量即非零退出(且 `fw_base_port` 未定义)。

- [ ] **Step 3: Implement in `_lib.sh`**

把 `_lib.sh` 中从 `# fw_resolve_target — resolve the SDK target...` 注释到文件末尾(当前 54-97 行整段)替换为:

```bash
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash skills/flutter-wright/test/resolve_target_test.sh`
Expected: `PASS: fw_resolve_target registry resolution`(退出 0)。已有断言(base/token/package/FW_AUTH/14/15/set-e 守卫)与新增 deviceport/name/base_port 断言全过。

- [ ] **Step 5: Stage changes for user review**

```bash
git add skills/flutter-wright/scripts/_lib.sh skills/flutter-wright/test/resolve_target_test.sh
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 2: `targets.sh`(列举 + 探活)

**Files:**
- Create: `skills/flutter-wright/scripts/targets.sh`
- Test: `skills/flutter-wright/test/targets_list_test.sh`

无参 `targets` 列举注册表所有条目并对每条 `GET <base>/health`(免 token)探活,打印 `NAME/BASE/PACKAGE/HEALTH`。未知子命令 → 退 17;缺注册表 → 退 14(经 `fw_registry_lines`)。本任务先不实现 `forward`(由 Task 3 加),`targets forward` 暂落 `*` → 17。

- [ ] **Step 1: Write the failing test**

Create `skills/flutter-wright/test/targets_list_test.sh`:

```bash
#!/usr/bin/env bash
# targets_list_test.sh — `targets.sh` (list) prints every registry row and probes each
# /health (ok / unreachable). Unknown subcommand → 17; missing registry → 14. (设计 4/6,
# Phase 3 探活/列举.) The mock backs the reachable entry; a closed port is unreachable.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_mock_start || exit 1   # /health always returns 200; the POST-status arg is irrelevant here
FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"; export FW_TARGETS
# 'up' points at the live mock; 'down' at a closed port (1) → unreachable.
printf 'up|http://127.0.0.1:%s||com.test.up\ndown|http://127.0.0.1:1||com.test.down\n' "$FW_MOCK_PORT" > "$FW_TARGETS"
trap 'fw_mock_stop; rm -f "${FW_TARGETS:-}"' EXIT

fail=0

out="$(bash "$FW_SCRIPTS_DIR/targets.sh" 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: targets list exit $code" >&2; fail=1; }
printf '%s\n' "$out" | grep -qE '^up[[:space:]].*ok$'           || { echo "FAIL: 'up' row not reachable: $out" >&2; fail=1; }
printf '%s\n' "$out" | grep -qE '^down[[:space:]].*unreachable$' || { echo "FAIL: 'down' row not unreachable: $out" >&2; fail=1; }

# unknown subcommand → 17
( bash "$FW_SCRIPTS_DIR/targets.sh" bogus ) >/dev/null 2>&1; code=$?
[ "$code" -eq 17 ] || { echo "FAIL: unknown subcommand expected 17, got $code" >&2; fail=1; }

# missing registry → 14
( unset FW_TARGETS; bash "$FW_SCRIPTS_DIR/targets.sh" ) >/dev/null 2>&1; code=$?
[ "$code" -eq 14 ] || { echo "FAIL: missing registry expected 14, got $code" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: targets list + probe + exit codes"
exit "$fail"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash skills/flutter-wright/test/targets_list_test.sh`
Expected: FAIL —— `targets.sh` 还不存在,`bash .../targets.sh` 退 127,断言不满足。

- [ ] **Step 3: Write `targets.sh`**

Create `skills/flutter-wright/scripts/targets.sh`(`forward` 模式由 Task 3 补,此处先只有 list + 未知子命令):

```bash
#!/usr/bin/env bash
# targets.sh — inspect the SDK target registry. Modes:
#   targets.sh [list]                  list every entry + probe each /health
#   targets.sh forward target=<name>   adb forward tcp:<local> tcp:<deviceport> for one
# List needs curl. forward needs adb + a device. The registry is operator-authored
# (never mutated here); base/deviceport come from it via fw_resolve_target.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

case "${1:-}" in
  list|"")
    command -v curl >/dev/null 2>&1 || { echo "ERR: curl not installed." >&2; exit 13; }
    fw_registry_lines           # sets FW_REGISTRY_LINES (exits 14)
    printf '%-12s %-28s %-18s %s\n' NAME BASE PACKAGE HEALTH
    while IFS='|' read -r name base _ package _; do
      [ -n "$name" ] || continue
      if curl -sf --max-time 3 -o /dev/null "$base/health"; then health="ok"; else health="unreachable"; fi
      printf '%-12s %-28s %-18s %s\n' "$name" "$base" "${package:-—}" "$health"
    done <<< "$FW_REGISTRY_LINES"
    ;;
  *)
    echo "ERR: unknown 'targets' subcommand '$1' (use: targets | targets forward target=<name>)" >&2
    exit 17
    ;;
esac
```

> 说明:`read -r name base _ package _` 用两个 `_` 丢弃 token(第 3 字段)与 deviceport(第 5 字段);末位变量必须存在,否则 `read` 会把 `package|deviceport` 整段塞进 `package`。列举只需 name/base/package,探活走免 token 的 `/health`。

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash skills/flutter-wright/test/targets_list_test.sh`
Expected: `PASS: targets list + probe + exit codes`(退出 0)。

- [ ] **Step 5: Stage changes for user review**

```bash
git add skills/flutter-wright/scripts/targets.sh skills/flutter-wright/test/targets_list_test.sh
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 3: `targets forward` + fake adb 测试垫片

**Files:**
- Modify: `skills/flutter-wright/test/_helpers.sh`(末尾追加 `fw_test_fake_adb`)
- Modify: `skills/flutter-wright/scripts/targets.sh`(`case` 中插入 `forward)` 分支)
- Test: `skills/flutter-wright/test/targets_forward_test.sh`

`targets forward target=<name>` 解析该目标 → `adb -s <device> forward tcp:<本地> tcp:<deviceport>`。本地端口取自 `base`(`fw_base_port`),设备端口取 `FW_DEVICE_PORT`(Task 1:第 5 字段或默认本地端口)。测试用 fake adb 垫片(记录调用、应答 `adb devices`、可注入 `forward` 失败),无需真机。

- [ ] **Step 1: Add the fake-adb helper to `_helpers.sh`**

在 `skills/flutter-wright/test/_helpers.sh` 末尾(`fw_mock_stop` 之后)追加:

```bash
# fw_test_fake_adb — install a fake `adb` on PATH that logs every invocation (space-joined
# args) to FW_FAKE_ADB_LOG and answers `adb devices` with one device (emulator-5554), so
# adb-dependent scripts run device-free. Set FW_FAKE_ADB_FAIL=1 (per-invocation) to make
# `forward` calls exit 1. Caller's trap should: rm -rf "$FW_FAKE_BIN"; rm -f "$FW_FAKE_ADB_LOG".
# NOTE: prepends $FW_FAKE_BIN to PATH for the life of the sourcing shell; after the trap
# removes that dir, `adb` falls through to the next PATH entry. Test-only — don't source
# outside a test.
fw_test_fake_adb() {
  FW_FAKE_BIN="$(mktemp -d -t fw-fakebin.XXXXXX)"
  FW_FAKE_ADB_LOG="$(mktemp -t fw-adblog.XXXXXX)"
  export FW_FAKE_ADB_LOG
  cat > "$FW_FAKE_BIN/adb" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FW_FAKE_ADB_LOG"
if [ "${FW_FAKE_ADB_FAIL:-}" = "1" ]; then
  case "$*" in *forward*) exit 1;; esac
fi
case "$1" in
  devices) printf 'List of devices attached\nemulator-5554\tdevice\n';;
esac
exit 0
SH
  chmod +x "$FW_FAKE_BIN/adb"
  export PATH="$FW_FAKE_BIN:$PATH"
}
```

- [ ] **Step 2: Write the failing test**

Create `skills/flutter-wright/test/targets_forward_test.sh`:

```bash
#!/usr/bin/env bash
# targets_forward_test.sh — `targets.sh forward target=<name>` runs
# `adb -s <dev> forward tcp:<local> tcp:<deviceport>`, mapping the base's local port to
# the registry deviceport (explicit 5th field, else defaulting to the local port). adb
# failure → exit 16. Uses a fake adb (no device). 设计 6 / Phase 3.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_test_fake_adb
FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"; export FW_TARGETS
trap 'rm -rf "${FW_FAKE_BIN:-}"; rm -f "${FW_FAKE_ADB_LOG:-}" "${FW_TARGETS:-}"' EXIT

fail=0

# --- explicit deviceport: local 9124 maps to device 9123 ---
printf 'shop|http://127.0.0.1:9124||com.acme.shop|9123\n' > "$FW_TARGETS"
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/targets.sh" forward target=shop 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: forward exit $code" >&2; fail=1; }
grep -q -- '-s emulator-5554 forward tcp:9124 tcp:9123' "$FW_FAKE_ADB_LOG" || { echo "FAIL: explicit mapping wrong: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *"(shop)"*) ;; *) echo "FAIL: forward stdout lacks target name: $out" >&2; fail=1;; esac

# --- omitted deviceport: defaults to the base's local port (9200 -> 9200) ---
printf 'qa|http://127.0.0.1:9200||com.acme.qa\n' > "$FW_TARGETS"
: > "$FW_FAKE_ADB_LOG"
out="$(bash "$FW_SCRIPTS_DIR/targets.sh" forward target=qa 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: forward(default) exit $code" >&2; fail=1; }
grep -q -- '-s emulator-5554 forward tcp:9200 tcp:9200' "$FW_FAKE_ADB_LOG" || { echo "FAIL: default mapping wrong: $(cat "$FW_FAKE_ADB_LOG")" >&2; fail=1; }
case "$out" in *"(qa)"*) ;; *) echo "FAIL: forward(default) stdout lacks target name: $out" >&2; fail=1;; esac

# --- adb forward failure → exit 16 ---
printf 'shop|http://127.0.0.1:9124||com.acme.shop|9123\n' > "$FW_TARGETS"
: > "$FW_FAKE_ADB_LOG"
FW_FAKE_ADB_FAIL=1 bash "$FW_SCRIPTS_DIR/targets.sh" forward target=shop >/dev/null 2>&1; code=$?
[ "$code" -eq 16 ] || { echo "FAIL: adb forward failure expected 16, got $code" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: targets forward maps local->device port via fake adb"
exit "$fail"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash skills/flutter-wright/test/targets_forward_test.sh`
Expected: FAIL —— Task 2 的 `targets.sh` 没有 `forward)` 分支,`targets forward` 落 `*` → 退 17(非 0),且 fake adb 日志里没有 `forward tcp:...`。

- [ ] **Step 4: Implement the `forward)` arm in `targets.sh`**

用 Edit 在 `targets.sh` 的 `case` 中插入 `forward)` 分支。

old_string:

```bash
case "${1:-}" in
  list|"")
```

new_string:

```bash
case "${1:-}" in
  forward)
    shift
    fw_resolve_target "$@"      # sets FW_BASE / FW_DEVICE_PORT / FW_TARGET_NAME (exits 14/15)
    fw_need_adb                 # sets FW_DEVICE_ID (exits 10/11)
    lport="$(fw_base_port "$FW_BASE")"
    if ! adb -s "$FW_DEVICE_ID" forward "tcp:$lport" "tcp:$FW_DEVICE_PORT" >/dev/null; then
      echo "ERR: 'adb forward tcp:$lport tcp:$FW_DEVICE_PORT' failed." >&2; exit 16
    fi
    echo "forwarded tcp:$lport -> device tcp:$FW_DEVICE_PORT (${FW_TARGET_NAME})"
    ;;
  list|"")
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash skills/flutter-wright/test/targets_forward_test.sh`
Expected: `PASS: targets forward maps local->device port via fake adb`(退出 0)。

- [ ] **Step 6: Re-run the list test to confirm no regression**

Run: `bash skills/flutter-wright/test/targets_list_test.sh`
Expected: `PASS: targets list + probe + exit codes`(插入 `forward)` 分支不影响 list / 17 / 14)。

- [ ] **Step 7: Stage changes for user review**

```bash
git add skills/flutter-wright/test/_helpers.sh skills/flutter-wright/scripts/targets.sh skills/flutter-wright/test/targets_forward_test.sh
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 4: SKILL.md —— 方法表 / 派发约定 / 退出码 / 目标段

**Files:**
- Modify: `skills/flutter-wright/SKILL.md`(方法表 79 行附近、派发约定 104 行、退出码表 118 行附近、目标段 61 行附近)

把 `targets` 接入方法表、派发同名清单、退出码表,并在「目标(target)」段补注册表格式与「注册一个目标」工作法(设计 6)。`dispatch_naming_test`(Task 6 会跑)会校验「方法表里每个方法 → 推导出的脚本存在且名一致」,故方法表行须与 `targets.sh` 对齐。

- [ ] **Step 1: 方法表加 `targets` 行**

old_string:

```markdown
| `health` | 显式 SDK 探针(交互/导航相关) | `health.sh` |
```

new_string:

```markdown
| `health` | 显式 SDK 探针(交互/导航相关) | `health.sh` |
| `targets [forward target=<name>]` | 列举注册表目标 + 逐条探活;`forward` 建立 adb 端口转发 | `targets.sh` |
```

- [ ] **Step 1b: 「按意图选方法」路由表加 `targets` 行**

方法表加了方法,意图路由表也要加对应行,否则 AI 无法把「列目标/探活/建转发」的诉求路由到 `targets`。

old_string:

```markdown
| 起 app / 停 app | `run [target]` / `stop` | adb |
```

new_string:

```markdown
| 起 app / 停 app | `run [target]` / `stop` | adb |
| 看有哪些目标 app / 哪个连得上 / 建端口转发 | `targets` / `targets forward target=<name>` | 列举需 curl,forward 需 adb |
```

- [ ] **Step 2: 派发约定同名清单加 `targets`**

old_string:

```markdown
其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`health`/`logs`/`back`/`screenshot`/`run`/`stop`/`reload`)名一致。
```

new_string:

```markdown
其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`health`/`logs`/`back`/`screenshot`/`run`/`stop`/`reload`/`targets`)名一致。
```

- [ ] **Step 3: 退出码表加「目标 / 注册表」行**

old_string:

```markdown
| 10-13 | 环境 / 设备 | 10 adb / 11 设备 / 12 SDK 不可达 / 13 curl |
```

new_string:

```markdown
| 10-13 | 环境 / 设备 | 10 adb / 11 设备 / 12 SDK 不可达 / 13 curl |
| 14-17 | 目标 / 注册表 | 14 注册表缺失或空 / 15 目标歧义或未找到 / 16 adb forward 失败 / 17 targets 未知子命令 |
```

- [ ] **Step 4: 目标段补注册表格式 + 「注册一个目标」工作法**

old_string:

```markdown
SDK 方法(snapshot/tap/type/scroll/longPress/waitFor/goto/reset/health)不再硬编码 `127.0.0.1:9123`,而是经**目标注册表**解析出 `base`(本地可达地址)、可选 `token`、可选 `package`。注册表由集成方/operator 维护在 **git 外**(环境变量 `FW_TARGETS` 指向的文件),**token 绝不进仓库**。单条目即默认;多条目时用 `target=<name>` 选择,未选则报错提示。base 配错只是连不上(快速失败),不引入安全风险。
```

new_string:

```markdown
SDK 方法(snapshot/tap/type/scroll/longPress/waitFor/goto/reset/health)不再硬编码 `127.0.0.1:9123`,而是经**目标注册表**解析出 `base`(本地可达地址)、可选 `token`、可选 `package`。注册表由集成方/operator 维护在 **git 外**(环境变量 `FW_TARGETS` 指向的文件),**token 绝不进仓库**。单条目即默认;多条目时用 `target=<name>` 选择,未选则报错提示。base 配错只是连不上(快速失败),不引入安全风险。

**注册表格式**:每行一条 `name|base|token|package|deviceport`,`#` 开头或空行忽略;`token`/`package`/`deviceport` 可留空(用 `|` 占位)。`deviceport` 留空时默认 = `base` 端口,仅在「同机多 app 各占不同本地端口、转发到各自设备端口」时才需显式填。

**注册一个目标 = 写一条 + 建可达性**(可达性不再每次自动建):① 在 `$FW_TARGETS` 写一行;② 需要时 `targets forward target=<name>` 跑一次 `adb forward tcp:<本地> tcp:<设备>`(emulator 直连 / 已有 forward / 隧道场景免此步)。`targets`(无参)列举所有条目并逐条探活(免 token 的 `/health`),用于发现「有哪些目标、哪个连得上」。
```

- [ ] **Step 5: Stage changes for user review**

```bash
git add skills/flutter-wright/SKILL.md
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 5: references/methods.md —— 新增 `targets` 段

**Files:**
- Modify: `skills/flutter-wright/references/methods.md`(目录 11 行、`health` 段后 49 行附近)

- [ ] **Step 1: 目录加「目标」组**

old_string:

```markdown
- 环境/进程:[`reload`](#reload) · [`setViewport` / `resetViewport`](#setviewport--resetviewport)
```

new_string:

```markdown
- 环境/进程:[`reload`](#reload) · [`setViewport` / `resetViewport`](#setviewport--resetviewport)
- 目标:[`targets`](#targets)
```

- [ ] **Step 2: 在 `health` 段后插入 `targets` 段**

old_string(`health` 段结尾的输出行):

```markdown
输出:`ok: base=<base>`(若注册表条目带 package,追加 ` package=<pkg>`)。
```

new_string:

```markdown
输出:`ok: base=<base>`(若注册表条目带 package,追加 ` package=<pkg>`)。

### `targets`

```
Skill flutter-wright "targets"
Skill flutter-wright "targets forward target=<name>"
```

无参时**列举**目标注册表(`$FW_TARGETS`)所有条目,并对每条 `GET <base>/health`(免 token)**探活**,打印 `NAME / BASE / PACKAGE / HEALTH(ok|unreachable)`,用于发现「有哪些目标、哪个连得上」。列举需 `curl`;`forward` 子命令不需要 `curl`,但需要 `adb` + 设备。注册表行格式:`name|base|token|package|deviceport`(后三者可留空,用 `|` 占位)。

`forward target=<name>` 为指定目标建立可达性:`adb -s <device> forward tcp:<本地端口> tcp:<deviceport>`。本地端口 = `base` 里的端口部分;`deviceport` 取自注册表第 5 字段,**留空则默认同本地端口**(仅同机多 app 各占不同本地端口时才需显式填)。emulator 直连 / 已有 forward / 隧道场景不需要此步——可达性改为「注册 target 时一次性建立」,SDK 方法不再每次自动 `adb forward`。

示例:`Skill flutter-wright "targets forward target=shop-qa"`

退出码:0 / 10 adb 缺失 / 11 无设备 / 13 curl 缺失 / 14 注册表缺失或空 / 15 目标歧义或未找到 / 16 adb forward 失败 / 17 未知子命令。
```

- [ ] **Step 3: Stage changes for user review**

```bash
git add skills/flutter-wright/references/methods.md
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 6: 回归 —— 全脚本语法 + 全 bash 测试

**Files:**
- 无改动(仅运行检查)

Phase 3 不动 SDK / Dart,回归聚焦 skill 侧:全脚本 `bash -n` 语法,全 7 个 bash 测试(5 个既有 + 2 个新增)绿,且 `dispatch_naming_test` 确认 `targets` 方法行 ↔ `targets.sh` 一致。

- [ ] **Step 1: 全脚本语法检查**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutter-wright
for s in scripts/*.sh; do bash -n "$s" && echo "ok: $s" || echo "SYNTAX FAIL: $s"; done
```
Expected: 每个脚本 `ok:`,无 `SYNTAX FAIL`(含新 `targets.sh`)。

- [ ] **Step 2: 跑全部 bash 测试**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright/skills/flutter-wright
rc=0
for t in test/*_test.sh; do echo "== $t =="; bash "$t" || rc=1; done
echo "ALL_TESTS_RC=$rc"
```
Expected:`dispatch_naming` / `resolve_target` / `goto_exit_code` / `reset_exit_code` / `snapshot_smoke` / `targets_list` / `targets_forward` 全部 `PASS:`,末行 `ALL_TESTS_RC=0`。(注意是 `*_test.sh` 后缀,别漏 `_test`。)

- [ ] **Step 3:(可选)确认 Dart 两包未受影响**

Phase 3 不改 Dart,两包 `flutter test` 理应仍绿——仅在你想要额外保险时跑(flutter 不在 PATH,用绝对路径):
```bash
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test --concurrency=1
cd /Users/mini/Documents/dev/github/flutterwright/packages/example && /Users/mini/development/flutter/bin/flutter test --concurrency=1
```
Expected: 各自 All tests passed(SDK 24 / example 14,与 Phase 2 末态一致)。

- [ ] **Step 4:(无需 stage)**

本任务不产生文件改动。前 5 个任务已各自 `git add`。最终由用户审阅 `git status` 后统一 commit。

---

## 验收对照(spec §验收 / Phase 3)

| spec 要求 | 对应任务 |
|---|---|
| 设计 4 全集:注册表 `{name,base,token,package}` + `target=` 选择(Phase 2 已成)+ `deviceport` 扩展 | Task 1 |
| 设计 6:可达性 = 注册 target 时建立(`targets forward` 跑 `adb forward`,不再每次自动) | Task 3 |
| line 153:探活 / 列举 | Task 2(`targets` 列举 + `/health` 探活) |
| 多条目省 `target=` → 报错(Phase 2 已成,forward 复用) | Task 1/3(`fw_resolve_target` 退 15) |
| 文档:目标段注册工作法、方法表、methods.md `targets` 段 | Task 4 / Task 5 |
| 回归:全脚本 `bash -n`;bash 测试全绿;Dart 未受影响 | Task 6 |
