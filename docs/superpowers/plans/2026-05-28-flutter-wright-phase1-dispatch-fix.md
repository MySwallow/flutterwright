# flutter-wright Phase 1（派发修复）Implementation Plan

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修掉两个经探针实证的真实缺陷——方法名→脚本名拼写导致的 `127` 链路断（设计 1），以及 `goto`/`reset` 在「导航未配置」时退出码/提示名不副实（设计 2）——并用 TDD 为两者各建一道回归护栏。

**Architecture:** 纯 shell + 文档改动，**不碰任何 Dart 代码**。验收走 TDD：脚本目录此前无任何测试，本计划新建一个极轻量 bash 测试 harness（`skills/flutter-wright/test/`）。退出码测试的关键技巧——预写 `fw_need_sdk` 的 fast-path 标记 `$CLAUDE_JOB_DIR/fw_health_done`，让脚本跳过 adb/设备探测，再用一个返回 501 的 mock SDK（python `http.server`）在**无真机**下驱动真实脚本，断言退出码与 stderr。

**Tech Stack:** bash 3.2（macOS 默认，**不可用** bash4 的 `${x,,}` 或 GNU sed 的 `\L`；命名推导用 `sed 's/\([A-Z]\)/_\1/g' | tr '[:upper:]' '[:lower:]'`）、python3 `http.server`、curl。

> **范围说明：** 本计划只覆盖 spec 的 **Phase 1（设计 1、2）**。设计 3-10（SDK enable/token、端点外置、多 App、logs 改 logcat、移除 run/reload/stop）属 Phase 2-4，将各自单独成计划。Phase 1 不改 Dart、不改退出码对照表/方法参考（经核实它们已写 41，是 `goto.sh` 代码落后于文档）。

---

### Task 1: 派发命名映射规则 + 一致性测试（设计 1，TDD）

把「派发约定」第 3 步从字面 `<method>.sh` 升级为显式的 camelCase→snake_case 规则 + 全量示例 + 「以方法表为准」，并用一个解析 `SKILL.md` 方法表的测试守护它：每个方法按规则推导出的脚本名既要与表中「脚本」列一致、对应文件也要真实存在。

**Files:**
- Create: `skills/flutter-wright/test/dispatch_naming_test.sh`
- Modify: `skills/flutter-wright/SKILL.md:100`（「派发约定」第 3 步）

- [ ] **Step 1: 写失败的测试**

创建 `skills/flutter-wright/test/dispatch_naming_test.sh`：

```bash
#!/usr/bin/env bash
# dispatch_naming_test.sh — guards the 派发约定 camelCase→snake_case rule (设计 1).
#   Part A (durable invariant): every method in SKILL.md's 方法 table maps — via the
#           rule — to an existing script whose name equals the table's 脚本 column.
#   Part B (设计 1 deliverable): SKILL.md documents the rule (keyword "snake_case").
# No device / SDK needed. Exit 0 = pass.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL="$DIR/../SKILL.md"
SCRIPTS="$DIR/../scripts"
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash skills/flutter-wright/test/dispatch_naming_test.sh`
Expected: FAIL，输出 `FAIL: SKILL.md 派发约定 missing the snake_case dispatch rule`（Part A 已绿，Part B 因 `SKILL.md` 尚无 `snake_case` 关键字而红）。

- [ ] **Step 3: 实现——改 SKILL.md「派发约定」第 3 步**

把 `skills/flutter-wright/SKILL.md` 当前第 100 行：

```
3. 调用 `bash skills/flutter-wright/scripts/<method>.sh <args>`。
```

替换为：

```
3. 调用对应脚本 `bash skills/flutter-wright/scripts/<script>.sh <args>`。**脚本文件名是方法名的 snake_case**——驼峰里每个大写字母转 `_<小写>`:`waitFor`→`wait_for.sh`、`longPress`→`long_press.sh`、`pressKey`→`press_key.sh`、`setViewport`→`set_viewport.sh`、`resetViewport`→`reset_viewport.sh`;其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`health`/`logs`/`back`/`screenshot`/`run`/`stop`/`reload`)名一致。**以「方法」表脚本列为准。**
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash skills/flutter-wright/test/dispatch_naming_test.sh`
Expected: PASS，输出 `PASS: dispatch naming rule consistent & documented`。

- [ ] **Step 5: 暂存变更，等用户审阅**

```bash
git add skills/flutter-wright/test/dispatch_naming_test.sh skills/flutter-wright/SKILL.md
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 2: 退出码测试 harness（mock SDK + 共享 helper）

设计 2 的两个测试（goto/reset）共用同一套基础设施：一个返回可配置状态码的 mock SDK，以及让 `fw_need_sdk` fast-path 跳过 adb 的标记 + mock 启停 helper。先单独建好，Task 3/4 直接复用。

**Files:**
- Create: `skills/flutter-wright/test/mock_sdk.py`
- Create: `skills/flutter-wright/test/_helpers.sh`

- [ ] **Step 1: 实现 mock SDK**

创建 `skills/flutter-wright/test/mock_sdk.py`：

```python
#!/usr/bin/env python3
"""Minimal mock of the flutter_wright_sdk control plane for Phase 1 script tests.

  GET  /health             -> 200 "ok"
  POST /navigate, /reset    -> status from env FW_MOCK_STATUS (default 501) + the
                               SDK's real "navigation not configured" body
Usage: mock_sdk.py [port]   # omit or pass 0 => OS picks a free port (no TOCTOU race)
On startup prints the actual bound port (one line) to stdout, then serves forever.
"""
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STATUS = int(os.environ.get("FW_MOCK_STATUS", "501"))
NAV_BODY = (
    "navigation not configured — pass navigatorKey or navigationAdapter "
    "to FlutterWright.start() to enable goto/reset"
)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body):
        b = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, "ok")
        return self._send(404, "not found")

    def do_POST(self):
        if self.path in ("/navigate", "/reset"):
            return self._send(STATUS, NAV_BODY)
        return self._send(404, "not found")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = HTTPServer(("127.0.0.1", port), H)
    print(server.server_address[1], flush=True)  # tell the caller the real port
    server.serve_forever()
```

- [ ] **Step 2: 实现共享 helper**

创建 `skills/flutter-wright/test/_helpers.sh`：

```bash
#!/usr/bin/env bash
# _helpers.sh — shared harness for flutter-wright Phase 1 script tests. Source, don't execute.
FW_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_SCRIPTS_DIR="$(cd "$FW_TEST_DIR/../scripts" && pwd)"
export FW_SCRIPTS_DIR

# fw_test_setup_marker — fresh CLAUDE_JOB_DIR + health marker so fw_need_sdk fast-paths
# (no adb/device needed). Call before invoking any SDK-talking script.
fw_test_setup_marker() {
  CLAUDE_JOB_DIR="$(mktemp -d -t fw-test.XXXXXX)"
  export CLAUDE_JOB_DIR
  # fw_need_sdk's fast-path reads device= only; the port comes from VL_PORT at call
  # time, so port= here is just a placeholder (0) — don't read meaning into it.
  printf 'device=test\nport=0\nts=0\n' > "$CLAUDE_JOB_DIR/fw_health_done"
}

# fw_mock_start [status] — launch mock_sdk.py on an OS-assigned free port returning
# <status> (default 501) for /navigate and /reset. The mock binds port 0 and prints
# its real port on stdout (no TOCTOU race). Exports FW_MOCK_PORT, sets FW_MOCK_PID,
# waits until /health responds. On failure prints the mock's stderr for diagnosis.
fw_mock_start() {
  local status="${1:-501}"
  [ -n "${FW_MOCK_PID:-}" ] && fw_mock_stop  # avoid leaking a mock from a prior call
  local port_file err_file i
  port_file="$(mktemp -t fw-port.XXXXXX)"
  err_file="$(mktemp -t fw-mockerr.XXXXXX)"
  FW_MOCK_STATUS="$status" python3 "$FW_TEST_DIR/mock_sdk.py" 0 >"$port_file" 2>"$err_file" &
  FW_MOCK_PID=$!
  FW_MOCK_PORT=""
  for i in $(seq 1 50); do
    FW_MOCK_PORT="$(cat "$port_file" 2>/dev/null)"
    [ -n "$FW_MOCK_PORT" ] && break
    sleep 0.1
  done
  if [ -z "$FW_MOCK_PORT" ]; then
    echo "ERR: mock did not report a port:" >&2; cat "$err_file" >&2
    rm -f "$port_file" "$err_file"; return 1
  fi
  export FW_MOCK_PORT
  for i in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:$FW_MOCK_PORT/health" && { rm -f "$port_file" "$err_file"; return 0; }
    sleep 0.1
  done
  echo "ERR: mock on $FW_MOCK_PORT not responding:" >&2; cat "$err_file" >&2
  rm -f "$port_file" "$err_file"; return 1
}

# fw_mock_stop — kill the mock if running and reap it quietly (the explicit `wait`
# suppresses the shell's async "Terminated" job notice). Safe in a trap / called twice.
fw_mock_stop() {
  [ -n "${FW_MOCK_PID:-}" ] || return 0
  kill "$FW_MOCK_PID" 2>/dev/null
  wait "$FW_MOCK_PID" 2>/dev/null
  FW_MOCK_PID=""
  return 0
}
```

- [ ] **Step 3: 运行项目的静态检查**

Run: `bash -n skills/flutter-wright/test/_helpers.sh && python3 -m py_compile skills/flutter-wright/test/mock_sdk.py`
Expected: 通过，无输出。

- [ ] **Step 4: 暂存变更，等用户审阅**

```bash
git add skills/flutter-wright/test/mock_sdk.py skills/flutter-wright/test/_helpers.sh
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 3: goto.sh 501 → exit 41 + 人话（设计 2，TDD）

`NavNotConfiguredHandler` 在未配置导航时返回 **501**，但 `goto.sh` 的 `case` 只显式处理 503/500，501 落到通配 `*` → 退 **43**（语义为「SDK 不可达」，名不副实；其退出码对照表与 `acceptance/2026-05-27-interaction-acceptance.md` 都已写 41）。补一个显式 `501)` 分支映射到 41 并给出可操作提示。

**Files:**
- Create: `skills/flutter-wright/test/goto_exit_code_test.sh`
- Modify: `skills/flutter-wright/scripts/goto.sh:44-50`（`case "$HTTP_CODE"` 块）

- [ ] **Step 1: 写失败的测试**

创建 `skills/flutter-wright/test/goto_exit_code_test.sh`：

```bash
#!/usr/bin/env bash
# goto_exit_code_test.sh — goto.sh maps SDK 501 (navigation not configured) to exit 41
# with a human-readable message (设计 2). Uses the mock SDK; no device needed.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_test_setup_marker
fw_mock_start 501 || exit 1
trap 'fw_mock_stop; rm -rf "${CLAUDE_JOB_DIR:-}"' EXIT

# Capture stderr (the error message); discard stdout. Order matters: 2>&1 points stderr
# at the capture pipe, THEN >/dev/null sends stdout away. $? = goto.sh exit code.
err="$(VL_PORT="$FW_MOCK_PORT" bash "$FW_SCRIPTS_DIR/goto.sh" /order/detail 2>&1 >/dev/null)"
code=$?

fail=0
if [ "$code" -ne 41 ]; then
  echo "FAIL: expected exit 41 for HTTP 501, got $code" >&2; fail=1
fi
# NOTE: "One-time host setup" is intentionally NOT in mock_sdk.py's NAV_BODY — only
# goto.sh's 501 branch emits it, so this asserts the branch ran (not mock passthrough).
# If you add that phrase to NAV_BODY this assertion goes vacuous. Keep them distinct.
case "$err" in
  *"One-time host setup"*) ;;
  *) echo "FAIL: stderr lacks the actionable 'One-time host setup' guidance: $err" >&2; fail=1;;
esac
[ "$fail" -eq 0 ] && echo "PASS: goto 501 → exit 41 + human message"
exit "$fail"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash skills/flutter-wright/test/goto_exit_code_test.sh`
Expected: FAIL。salient 行 `FAIL: expected exit 41 for HTTP 501, got 43`（当前 501 落通配 → 43）；同时也会打 `FAIL: stderr lacks the actionable 'One-time host setup' guidance`（旧通配分支无此提示）。两条任一即判红。

- [ ] **Step 3: 实现——给 goto.sh 加显式 501 分支**

在 `skills/flutter-wright/scripts/goto.sh` 的 `case "$HTTP_CODE" in` 块里，把 `500)` 行与通配 `*)` 行之间插入一个 `501)` 分支。改动后该块为：

```bash
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 43;;
  503) echo "ERR: navigator not ready (app not mounted yet?)" >&2; cat "$TMP" >&2; exit 41;;
  500) echo "ERR: push failed (route '$ROUTE' not in onGenerateRoute? args type mismatch?)" >&2; cat "$TMP" >&2; exit 42;;
  # 501 (navigation not configured, permanent) intentionally shares exit 41 with 503
  # (navigator not ready, transient) per spec; the stderr message distinguishes them.
  501) echo "ERR: navigation not configured — host must pass navigatorKey/navigationAdapter to FlutterWright.start(). One-time host setup; retrying won't help." >&2; cat "$TMP" >&2; exit 41;;
  *)   echo "ERR: /navigate returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 43;;
esac
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash skills/flutter-wright/test/goto_exit_code_test.sh`
Expected: PASS，输出 `PASS: goto 501 → exit 41 + human message`。

- [ ] **Step 5: 暂存变更，等用户审阅**

```bash
git add skills/flutter-wright/test/goto_exit_code_test.sh skills/flutter-wright/scripts/goto.sh
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 4: reset.sh 501 → 人话（退出码维持 71，设计 2，TDD）

`reset.sh` 的 501 本就落通配 `*` → 退 **71**（与其文档一致，退出码不变），但提示是泛泛的 `"/reset returned 501"`。补一个显式 `501)` 分支，退出码保持 71、但给出与 `goto` 一致的「导航未配置」可操作提示。本测试的红驱动来自 **stderr 提示**而非退出码。

**Files:**
- Create: `skills/flutter-wright/test/reset_exit_code_test.sh`
- Modify: `skills/flutter-wright/scripts/reset.sh:26-30`（`case "$HTTP_CODE"` 块）

- [ ] **Step 1: 写失败的测试**

创建 `skills/flutter-wright/test/reset_exit_code_test.sh`：

```bash
#!/usr/bin/env bash
# reset_exit_code_test.sh — reset.sh maps SDK 501 to exit 71 (unchanged) but with a
# human-readable "navigation not configured" message (设计 2). RED driver = the message.
set -uo pipefail  # no -e: the err=$(reset.sh) capture exits 71 by design; we inspect $code manually
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_test_setup_marker
fw_mock_start 501 || exit 1
trap 'fw_mock_stop; rm -rf "${CLAUDE_JOB_DIR:-}"' EXIT

# Capture stderr (the error message); discard stdout. Order matters: 2>&1 points stderr
# at the capture pipe, THEN >/dev/null sends stdout away. $? = reset.sh exit code.
err="$(VL_PORT="$FW_MOCK_PORT" bash "$FW_SCRIPTS_DIR/reset.sh" 2>&1 >/dev/null)"
code=$?

fail=0
if [ "$code" -ne 71 ]; then
  echo "FAIL: expected exit 71 for HTTP 501, got $code" >&2; fail=1
fi
# NOTE: "One-time host setup" is intentionally NOT in mock_sdk.py's NAV_BODY — only
# reset.sh's 501 branch emits it, so this asserts the branch ran (not mock passthrough).
# If you add that phrase to NAV_BODY this assertion goes vacuous. Keep them distinct.
case "$err" in
  *"One-time host setup"*) ;;
  *) echo "FAIL: stderr lacks the actionable 'One-time host setup' guidance: $err" >&2; fail=1;;
esac
[ "$fail" -eq 0 ] && echo "PASS: reset 501 → exit 71 + human message"
exit "$fail"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash skills/flutter-wright/test/reset_exit_code_test.sh`
Expected: FAIL，输出 `FAIL: stderr lacks the actionable 'One-time host setup' guidance: ERR: /reset returned 501 ...`（退出码 71 已对，红驱动来自缺失的可操作提示——mock 回的 body 含「navigation not configured」但**不含**脚本新增分支才有的「One-time host setup」，故必须走新分支才会绿）。

- [ ] **Step 3: 实现——给 reset.sh 加显式 501 分支**

在 `skills/flutter-wright/scripts/reset.sh` 的 `case "$HTTP_CODE" in` 块里，把 `000)` 行与通配 `*)` 行之间插入一个 `501)` 分支。改动后该块为：

```bash
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 70;;
  # 501 deliberately stays exit 71 (reset's "non-200" code), NOT goto's 41 — reset keeps its
  # 70/71 scheme. Callers treating "navigation not configured" uniformly must handle goto 41 AND reset 71.
  501) echo "ERR: navigation not configured — host must pass navigatorKey/navigationAdapter to FlutterWright.start(). One-time host setup; retrying won't help." >&2; cat "$TMP" >&2; exit 71;;
  *)   echo "ERR: /reset returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 71;;
esac
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash skills/flutter-wright/test/reset_exit_code_test.sh`
Expected: PASS，输出 `PASS: reset 501 → exit 71 + human message`。

- [ ] **Step 5: 暂存变更，等用户审阅**

```bash
git add skills/flutter-wright/test/reset_exit_code_test.sh skills/flutter-wright/scripts/reset.sh
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 5: 回归校验（全脚本语法 + 三测试齐绿）

确认改动没破坏任何脚本语法，三个新测试一起跑全绿。Phase 1 未改任何 Dart，故 `flutter test` 不在必跑范围内（仅作可选信心检查）。

**Files:**
- 无新增/修改（只运行校验）

- [ ] **Step 1: 全脚本 + 测试脚本语法检查**

Run:
```bash
for f in skills/flutter-wright/scripts/*.sh skills/flutter-wright/test/*.sh; do
  bash -n "$f" || echo "SYNTAX FAIL: $f"
done
echo "syntax check done"
```
Expected: 仅输出 `syntax check done`，无 `SYNTAX FAIL` 行。

- [ ] **Step 2: 三个测试齐跑**

Run:
```bash
bash skills/flutter-wright/test/dispatch_naming_test.sh && \
bash skills/flutter-wright/test/goto_exit_code_test.sh && \
bash skills/flutter-wright/test/reset_exit_code_test.sh
```
Expected: 三行 `PASS: ...` 依次输出，命令整体退 0。

- [ ] **Step 3:（可选）确认 Dart 未受影响**

Phase 1 不改 Dart 代码；如需信心检查，运行（flutter 不在默认 PATH，用 `FLUTTER_BIN`）：
```bash
FLUTTER_BIN=/Users/mini/development/flutter/bin/flutter
"$FLUTTER_BIN" test packages/flutter_wright_sdk/test/start_navigation_test.dart
```
Expected: 仍全绿（与 Phase 1 无关，断言的是 HTTP 501，不是 bash 退出码）。

- [ ] **Step 4: 无需暂存**

本任务不产生文件变更；Task 1-4 已各自 `git add`。由用户统一审阅后 commit。
