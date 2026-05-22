# FlutterWright v1 设计 spec

> **日期:** 2026-05-22
> **状态:** Brainstorm 结束,待 plan
> **作者:** xiandan7045 + Claude(Opus 4.7,1M context)
> **目标读者:** 接手实施 v1 的 plan 作者 / agentic worker

---

## 1. 目标与背景

### 1.1 一句话

把 `flutter-visual-loop` 仓库里已经写过的 7 个 bash 脚本(`env_check / setup / navigate / capture / hot_reload / mock_set / reset_device`)**抽象成一个 Playwright 风的 Claude Code skill**,叫 `flutterwright`(Flutter + Playwright),让 Claude(或上层 skill)用方法调用语义而不是脚本路径来驱动 Flutter app。

### 1.2 起因

`flutter-visual-loop` 上一轮 brainstorm 收尾时,设计文档中把"设备/Flutter 驱动层"识别为 Layer 2b,但当时这层 skill 还不存在。用户决定:

- 命名为 `flutterwright` skill
- 7 个脚本从 flutter-visual-loop 迁移过来作为实现起点
- 命名灵感: Flutter + Playwright
- 外部参考: mobile-next/mobile-mcp(多平台 native 自动化 MCP)— 但 flutterwright 不抄它的"native accessibility tree"路径,而是继续走 SDK-in-app 路径(保留 Flutter 语义)

### 1.3 目标

**v1 必须:**

- 提供一个独立的 monorepo `flutterwright/`,容纳 skill + SDK + example + 技术文档
- 8 个 Playwright 风方法(7 个 rename + 2 个新),完整覆盖 flutter-visual-loop 当前需要的设备驱动能力
- 重写 hot reload: 抛弃 fifo + stdin 'r' 模式,改走 SDK 内部的 VM service `reloadSources` RPC
- SKILL.md 是唯一对外接口;上层 skill 调用必须走 `Skill flutterwright "method args..."`,不允许 bash 直调内部脚本

**v1 非目标:**

- iOS 支持(adb-only)
- UI 交互(tap / swipe / text input)— 留 v2
- Widget tree / locator(`getByText` / `getByKey`)— 留 v2
- 多设备并行 / app 生命周期管理 — 留 v2
- 重构 `flutter-visual-loop` 上层 skill(本 spec 只交付 flutterwright,上层 skill 迁移是后续独立工作)

---

## 2. 决策快速参考

| # | 决策 | 选项 | 选择 |
|---|---|---|---|
| 1 | v1 能力面 | (a) 7 脚本 + 小改进 (b) 加 UI 交互 (c) 加 iOS (d) 加 widget tree | **(a) 7 脚本 + 小改进** |
| 2 | v1 B 类改进 | 4 条多选 | **VM service hot reload + reset.sh + mock.sh 统一入口**(去掉:错误码集中) |
| 3 | 使用形态 | (a) skill+工具库 (b) 只 skill (c) 只工具库 | **只 skill,上层未来也走 SKILL** |
| 4 | SKILL 风格 | 极简 / 中等接口表 / Playwright 风 reference | **Playwright 风(全采命名 + 双轨文档)** |
| 5 | reload 实现 | (A) SDK 内部 (B) 外部 (C) daemon (D) 留 fifo | **A. SDK 内部 talk VM service** |
| 6 | repo 定位 | (a) monorepo 一切都拥有 (b) 仅参考 (c) 双仓库合并 | **(a) monorepo:skill + SDK + example + docs 都拥有** |
| 7 | Dart package 名 | 改名 flutterwright / 保 flutter_visual_loop | **保 flutter_visual_loop**(品牌与包名解耦) |
| 8 | 目录组织 | SKILL/scripts 独立目录 + SDK/example 入 packages/ | **skills/flutterwright/ + packages/{flutter_visual_loop,example}** |
| 9 | docs/ 6 篇处理 | A 全留改 B 瘦身合并 C 极简 D 全删 | **B. README 吃 getting-started、troubleshooting 吃 e2e-checklist** |
| 10 | Flutter 版本约束 | 收紧 3.24+ / 保 3.10+ | **收紧 flutter:>=3.24.0 / sdk:>=3.5.0** |
| 11 | VL_PORT env 名 | 保 VL_ / 改 FW_ | **保 VL_PORT**(SDK 文档已有约定) |
| 12 | 临时文件 prefix | fw_ / vl_ | **fw_**(脱 visual-loop) |
| 13 | mock_set.sh 处理 | 删 / alias | **直接删,不留 alias** |
| 14 | setup.sh skip 模式 | 删 / 保 | **删**(不调即等同 skip) |

---

## 3. 架构与定位

### 3.1 整体调用链

```
┌─────────────────────────────────────────────┐
│ Upper layer                                 │
│   - flutter-visual-loop skill(未来)        │
│   - 用户 ad-hoc 会话                        │
│   - 未来 flutter-e2e 等                     │
└───────────────────┬─────────────────────────┘
                    │ Skill flutterwright "method args..."
                    ▼
┌─────────────────────────────────────────────┐
│ skills/flutterwright/SKILL.md               │
│   Claude 阅读后:                            │
│   - 解析 method + key=value args            │
│   - bash skills/flutterwright/scripts/      │
│     <method>.sh <args>                      │
└───────────────────┬─────────────────────────┘
                    │ bash
                    ▼
┌─────────────────────────────────────────────┐
│ skills/flutterwright/scripts/*.sh           │
│   - 8 个脚本,逻辑分散                       │
│   - adb / curl / printf 拼 JSON             │
└───────────────────┬─────────────────────────┘
                    │ adb forward + HTTP / adb exec-out
                    ▼
┌─────────────────────────────────────────────┐
│ packages/flutter_visual_loop SDK            │
│   - HTTP server on 127.0.0.1:9123           │
│   - /health /routes /navigate /reset        │
│   - /mock /screenshot /reload (NEW)         │
│   跑在宿主 Flutter app 进程内               │
└─────────────────────────────────────────────┘
```

### 3.2 双仓库职责对比

| 仓库 | 内容 | 职责层 |
|---|---|---|
| `flutterwright/`(本 spec 交付) | SKILL + 8 scripts + SDK + example + 4 docs | **Layer 2b** 设备/Flutter app 驱动 |
| `flutter-visual-loop/`(瘦身后,后续工作) | SKILL + 极少量编排逻辑 | **Layer 2a** UI 还原循环编排 |

---

## 4. 目标文件结构(v1 完成态)

```
flutterwright/
├── README.md                          [NEW]   使用方门面 + quickstart(吸收 getting-started)
├── LICENSE                            [CP]    MIT,从 ../flutter-visual-loop/LICENSE cp(原作者 MySwallow,保留版权头)
├── CHANGELOG.md                       [NEW]   repo 级
├── .gitignore                         [NEW]   Dart/Flutter + macOS
├── CONTRIBUTING.md                    [HAVE]  ✓
├── SECURITY.md                        [HAVE]  ✓
│
├── docs/
│   ├── api-reference.md               [EDIT]  小改:加 /reload section
│   ├── architecture.md                [EDIT]  中改:加 flutterwright 分层 + 双仓库职责图
│   ├── integration-guide.md           [EDIT]  小改:git url + path 改 flutterwright/
│   ├── troubleshooting.md             [EDIT]  大改:改方法名、去 fifo 段、并入 e2e-checklist
│   └── superpowers/specs/
│       └── 2026-05-22-flutterwright-design.md   [本文件]
│
├── packages/
│   ├── flutter_visual_loop/           SDK,包名/类名保持
│   │   ├── pubspec.yaml               [EDIT]  + vm_service:>=14<16; bump 0.1.0→0.2.0;
│   │   │                                       env: flutter>=3.24, sdk>=3.5
│   │   ├── CHANGELOG.md               [EDIT]  + 0.2.0 entry
│   │   ├── README.md                  [EDIT]  小改 — "shipped as part of flutterwright"
│   │   ├── lib/
│   │   │   ├── flutter_visual_loop.dart      [HAVE]
│   │   │   └── src/
│   │   │       ├── visual_loop.dart, config.dart, http_server.dart, ...   [HAVE]
│   │   │       └── handlers/
│   │   │           ├── handler.dart                  [HAVE]
│   │   │           ├── health_handler.dart           [HAVE]
│   │   │           ├── routes_handler.dart           [HAVE]
│   │   │           ├── navigate_handler.dart         [HAVE]
│   │   │           ├── reset_handler.dart            [HAVE]
│   │   │           ├── mock_handler.dart             [HAVE]
│   │   │           ├── screenshot_handler.dart       [HAVE]
│   │   │           └── reload_handler.dart           [NEW]
│   │   └── test/
│   │       ├── route_registry_test.dart              [HAVE]
│   │       ├── mock_provider_test.dart               [HAVE]
│   │       └── reload_handler_test.dart              [NEW]
│   └── example/                       Demo Flutter app
│       ├── pubspec.yaml               [EDIT]  path dep 改 ../flutter_visual_loop(已修)
│       ├── analysis_options.yaml      [HAVE]
│       ├── README.md, PLATFORM_NOTE.md [HAVE]
│       ├── design/                    [HAVE]
│       └── lib/...                    [HAVE]
│
└── skills/
    └── flutterwright/                 THE SKILL
        ├── SKILL.md                   [NEW]   主入口,Playwright 风,见 §5
        └── scripts/
            ├── health.sh              [RENAME from env_check.sh, 不动逻辑]
            ├── goto.sh                [RENAME from navigate.sh, 小补丁]
            ├── screenshot.sh          [RENAME from capture.sh, 不动逻辑]
            ├── reload.sh              [REWRITE from hot_reload.sh — 完全改]
            ├── set_viewport.sh        [RENAME from setup.sh, 小改]
            ├── reset_viewport.sh      [RENAME from reset_device.sh, 不动逻辑]
            ├── mock.sh                [REWRITE from mock_set.sh — 5 action dispatch]
            └── reset.sh               [NEW]
```

待删: `docs/getting-started.md`(并入 README)、`docs/e2e-checklist.md`(并入 troubleshooting)。

---

## 5. SKILL.md 设计

### 5.1 风格定位

Playwright 双轨文档:**Guides**(when/concepts)+ **API reference**(每方法详尽)。SKILL.md 是 Skill 工具派发依据,要同时服务两类读者:

- **Claude in conversation**(`Skill flutterwright "screenshot ..."` 时被读)
- **上层 skill 写作者**(从这里抄方法签名)

### 5.2 骨架

```markdown
---
name: flutterwright
description: Playwright-style driver for Flutter apps running on Android devices/emulators via the flutter_visual_loop SDK. Use when you need to navigate routes, screenshot, hot-reload, inject mock data, or lock viewport. Skill provides 8 methods (health/goto/screenshot/reload/setViewport/resetViewport/mock/reset).
---

# FlutterWright — Playwright for Flutter on Android

<2-3 行简介:Layer 2b driver / Android-only / 依赖 flutter_visual_loop SDK>

## When to use

<3-5 行场景描述:Claude 直接调 / 上层 skill 调用,各举一例>

## Concepts (5 行 max)

- **Page** = 当前在已连接 Android 设备上运行的 Flutter app
- **Route** = 命名路由(如 `/order/detail`)
- **Mock** = 通过 `flutter_visual_loop.MockDataProvider` 注入的数据
- **Viewport** = `wm size` + `wm density` 覆写(把设备锁到设计稿分辨率)
- **Reload** = 经 SDK `/reload` 端点触发的 Flutter hot reload

## Methods 速查表

| Method | 用途 | Script |
|---|---|---|
| `health` | 验环境(adb / device / SDK 可达性 + 自动 forward 9123) | `health.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 跳转命名路由 | `goto.sh` |
| `screenshot <out>` | 设备截图到 `<out>` PNG | `screenshot.sh` |
| `reload` | Flutter hot reload(via SDK `/reload`) | `reload.sh` |
| `setViewport <w> <h> <dpi>` | 锁定 wm size + density | `set_viewport.sh` |
| `resetViewport` | 还原 wm size + density | `reset_viewport.sh` |
| `mock <action> [key=...] [value=...] [enabled=...]` | mock 数据控制 | `mock.sh` |
| `reset [clearMock=<bool>]` | navigator pop 到 root,可选清 mock | `reset.sh` |

## Prerequisites

- macOS / Linux 装了 `adb` 和 `curl`
- 宿主 Flutter app 集成 `flutter_visual_loop` ≥ 0.2.0(含 `/reload`)且 `flutter run -d <id>` 处 active(无需 fifo)
- 详见 [`README.md#quickstart`](../../README.md)

## Method reference

### health
<args / 退出码表 / 一行示例 / 错误时下一步>

### goto
<args / 退出码 / 一行示例>

... (每方法 6-10 行,共 8 个方法)

## Dispatch convention

When invoked as `Skill flutterwright "<method> <args...>"`:
1. parse first whitespace-separated token as method name
2. parse remaining as positional + `key=value` pairs
3. invoke `bash skills/flutterwright/scripts/<method>.sh <args>`

JSON values must be single-quote-friendly. Example:
- `Skill flutterwright "goto /order/detail args={\"id\":\"X\"}"`
- → `bash skills/flutterwright/scripts/goto.sh /order/detail '{"id":"X"}'`

## Exit code map

| Range | 类别 | 详情 |
|---|---|---|
| 0 | success | — |
| 10-19 | env / device | health.sh,详见 [troubleshooting](../../docs/troubleshooting.md#health-failure) |
| 20-29 | screenshot | screenshot.sh |
| 30-39 | reload | reload.sh |
| 40-49 | navigate | goto.sh |
| 50-59 | mock | mock.sh |
| 60-69 | viewport | set_viewport.sh / reset_viewport.sh |
| 70-79 | reset | reset.sh |

## See also

- [api-reference.md](../../docs/api-reference.md) — SDK HTTP 协议
- [integration-guide.md](../../docs/integration-guide.md) — 集成 SDK 到你的 app
- [troubleshooting.md](../../docs/troubleshooting.md) — 故障排查
```

**估算 SKILL.md 长度:** 100-150 行(per-method section 各占 6-10 行 × 8 = 50-80 行,其余 50-70 行)。

### 5.3 重复度约束

SKILL.md 只写: description / when-to-use / concepts(3-5 行)/ Methods 速查表 / per-method 调用约定 / dispatch convention / exit code map。

**不复刻:** HTTP 协议细节(→ link api-reference)、环境搭建步骤(→ link README)、故障矩阵(→ link troubleshooting)、Dart 集成模式(→ link integration-guide)。

---

## 6. Methods API(8 个方法详尽 spec)

### 6.1 `health`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "health"` |
| 脚本 | `health.sh` |
| 内部 | check adb/curl,数 device,`adb forward tcp:9123 tcp:9123` (idempotent),`curl /health` |
| Args | 无 |
| 副作用 | 端口转发被建立 |
| 输出 | `ok: device=<id> port=9123` |
| 退出码 | 0 / 10 adb 缺 / 11 无 device / 12 SDK 不可达 / 13 curl 缺 |

### 6.2 `goto`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "goto <route> [args=<json>] [popUntilRoot=<bool>]"` |
| 脚本 | `goto.sh` |
| 内部 HTTP | `POST /navigate {"route":...,"args":...,"popUntilRoot":...}` |
| Args 必填 | `<route>` |
| Args 可选 | `args=<json>`(默认 null)/ `popUntilRoot=<bool>`(默认 true) |
| 退出码 | 0 / 40 缺 route / 41 navigator 503 / 42 push 异常 500 / 43 SDK 不可达 |
| 例 | `Skill flutterwright "goto /order/detail args={\"id\":\"ORD-001\"}"` |

### 6.3 `screenshot`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "screenshot <out_path>"` |
| 脚本 | `screenshot.sh` |
| 内部 | `adb exec-out screencap -p > <out>` + PNG magic 校验 |
| Args 必填 | `<out_path>` |
| 退出码 | 0 / 20 空文件 / 21 < 1KB / 22 非 PNG(设备锁屏) |
| 例 | `Skill flutterwright "screenshot $CLAUDE_JOB_DIR/round-1.png"` |
| 注 | 走 `adb screencap` 拿**完整设备帧(含状态栏)**;要纯 Flutter 渲染树用 SDK `GET /screenshot`(v1 不暴露为方法) |

### 6.4 `reload`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "reload"` |
| 脚本 | `reload.sh`(**完全重写,旧 fifo 逻辑彻底废弃**) |
| 内部 HTTP | `POST /reload`(SDK 新加 endpoint,见 §7) |
| Args | 无 |
| 副作用 | Flutter app 进程内 VM service `reloadSources` 被触发 |
| 退出码 | 0 / 30 SDK 不可达 / 31 SDK 返 503(VM service 未开)/ 32 SDK 返 500(reload 失败) |
| 例 | `Skill flutterwright "reload"` |

### 6.5 `setViewport`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "setViewport <width> <height> <dpi>"` |
| 脚本 | `set_viewport.sh` |
| 内部 | 记原 size/density 到 `$CLAUDE_JOB_DIR/fw_original.env`;`adb shell wm size <w>x<h>` + `wm density <dpi>`;回读校验(防厂商 ROM 静默拒) |
| Args 必填 | `<width> <height> <dpi>` 全要 |
| 退出码 | 0 / 60 缺 args / 61 wm 命令被静默拒 |
| 例 | `Skill flutterwright "setViewport 1080 2400 480"` |
| 变化 | 删 `setup.sh skip` 模式;状态文件名 `vl_original.env` → `fw_original.env` |

### 6.6 `resetViewport`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "resetViewport"` |
| 脚本 | `reset_viewport.sh` |
| 内部 | 读 `$CLAUDE_JOB_DIR/fw_original.env` → 恢复 size/density → 删 env 文件;文件缺时跑 `wm size reset / wm density reset` 兜底 |
| Args | 无 |
| 退出码 | **始终 0**(best-effort,可在 trap 安全调) |
| 例 | `Skill flutterwright "resetViewport"` |

### 6.7 `mock`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "mock <action> [key=<k>] [value=<json>] [enabled=<bool>]"` |
| 脚本 | `mock.sh`(替换 `mock_set.sh`,**直接删,不留 alias**) |
| 内部 HTTP | `POST /mock {"action":...,...}` |
| Args 必填 | `<action>` ∈ `{set, get, reset, enable, list}` |
| 各 action 必需 key | set:key+value / get:key / reset:无 / enable:enabled / list:无 |
| 退出码 | 0 / 50 缺 action / 51 非法 action 或未知 arg / 52 缺 key / 53 缺 value / 54 缺 enabled / 55 SDK 501 / 56 SDK 不可达 |
| 例 | `Skill flutterwright "mock set key=order value={\"id\":\"X\",\"amount\":42}"` |
| 例 | `Skill flutterwright "mock enable enabled=false"` |
| 例 | `Skill flutterwright "mock list"` |

### 6.8 `reset`

| 项 | 内容 |
|---|---|
| Skill 调用 | `Skill flutterwright "reset [clearMock=<bool>]"` |
| 脚本 | `reset.sh`(**新加**) |
| 内部 HTTP | `POST /reset {"clearMock":...}` |
| Args 可选 | `clearMock=<bool>`(默认 true) |
| 退出码 | 0 / 70 SDK 不可达 / 71 SDK 非 200 |
| 例 | `Skill flutterwright "reset clearMock=true"` |

### 6.9 跨方法约定

- **环境变量**: `VL_PORT`(default 9123)/ `CLAUDE_JOB_DIR`(default `/tmp/fw-job`)/ `ANDROID_SERIAL`(adb 自动 honor)
- **JSON value 转义**: Skill args 里 JSON 用 `\"` 转义内嵌引号
- **失败语义**: 非 0 退出码 + stderr `ERR: <reason>`,不自动 retry
- **依赖**: adb, curl;**不引入** jq / dart / python3

---

## 7. SDK 端改动(`packages/flutter_visual_loop/`)

v1 对 SDK 只有 **1 个新增功能 + 1 个新依赖**,其余不动。

### 7.1 新文件: `lib/src/handlers/reload_handler.dart`

签名与其他 handler 对齐(继承 `Handler` 基类,同 navigate_handler 模式)。骨架:

```dart
import 'dart:async';
import 'dart:developer' as developer;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'handler.dart';
import '../logger.dart';

class ReloadHandler implements Handler {
  @override String get method => 'POST';
  @override String get path => '/reload';

  @override
  Future<HandlerResult> handle(HandlerContext ctx) async {
    final info = await developer.Service.getInfo();
    final serverUri = info.serverUri;
    if (serverUri == null) {
      return HandlerResult.json(503, {'ok': false, 'error': 'VM service is not enabled in this process'});
    }
    final wsUri = _toWsUri(serverUri);
    VmService? vm;
    try {
      vm = await vmServiceConnectUri(wsUri.toString());
      final vmInfo = await vm.getVM();
      final isolates = vmInfo.isolates ?? const [];
      if (isolates.isEmpty) {
        return HandlerResult.json(500, {'ok': false, 'error': 'no isolates found'});
      }
      final mainIso = isolates.firstWhere(
        (i) => i.name == 'main',
        orElse: () => isolates.first,
      );
      final result = await vm.reloadSources(mainIso.id!);
      final success = result.success ?? false;
      VlLogger.log('reload', 'success=$success');
      return HandlerResult.json(
        success ? 200 : 500,
        {'ok': success, if (!success) 'error': 'reloadSources returned false'},
      );
    } catch (e) {
      VlLogger.log('reload', 'error: $e');
      return HandlerResult.json(500, {'ok': false, 'error': e.toString()});
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

### 7.2 改: `lib/src/http_server.dart`

```diff
 import 'handlers/screenshot_handler.dart';
+import 'handlers/reload_handler.dart';

   handlers = [
     HealthHandler(),
     ...
     ScreenshotHandler(screenshotMode),
+    ReloadHandler(),
   ];
```

### 7.3 改: `pubspec.yaml`

```yaml
name: flutter_visual_loop
version: 0.2.0        # 0.1.0 → 0.2.0

environment:
  sdk: ">=3.5.0 <4.0.0"        # was >=3.0.0
  flutter: ">=3.24.0"           # was >=3.10.0

dependencies:
  flutter:
    sdk: flutter
  vm_service: '>=14.0.0 <16.0.0'   # NEW,覆盖 Flutter 3.24/3.29 bundled vm_service
```

### 7.4 新: `test/reload_handler_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_visual_loop/src/handlers/reload_handler.dart';

void main() {
  test('ReloadHandler is registered on POST /reload', () {
    final h = ReloadHandler();
    expect(h.method, 'POST');
    expect(h.path, '/reload');
  });
}
```

不测真实 VM service 调用(integration 行为,放 troubleshooting 内的手动冒烟清单)。

### 7.5 改: `CHANGELOG.md`(SDK 级)

```markdown
## 0.2.0 - 2026-05-22

### Added
- `POST /reload` endpoint:Flutter hot reload via `vm_service.reloadSources`
- `vm_service: >=14.0.0 <16.0.0` dependency

### Changed
- SDK constraint: flutter >=3.24.0, sdk >=3.5.0 (was 3.10/3.0)
```

### 7.6 改: `packages/flutter_visual_loop/README.md`(微调)

加一句"shipped as part of [flutterwright](../../README.md) monorepo"。其他保持。

### 7.7 已知风险

1. **profile 模式行为**: SDK 默认 debug-only。若用户改 config 启了 profile,VM service 默认关,`/reload` 返 503。troubleshooting 要记录。
2. **isolate 选择**: 假设 main isolate 名为 `'main'`;custom 名时 fallback 用 first(已在代码中处理)。
3. **vm_service 版本**: `>=14.0.0 <16.0.0` 覆盖 Flutter 3.24.3(bundled 14.2.x)和 3.29.3(bundled 15.x),pub solver 在两个 toolchain 都能选到匹配版本。

---

## 8. 脚本实现(`skills/flutterwright/scripts/`)

### 8.1 跨脚本约定

| 约定 | 值 |
|---|---|
| **shebang** | `#!/usr/bin/env bash` |
| **strict mode** | `set -euo pipefail`(reset_viewport.sh 用 `set -uo pipefail`,best-effort) |
| **端口 env** | `VL_PORT`(default 9123,**保留 VL_ 前缀**) |
| **临时目录 env** | `CLAUDE_JOB_DIR`(default `/tmp/fw-job`) |
| **状态文件名** | `$CLAUDE_JOB_DIR/fw_original.env` |
| **JSON 解析** | 不依赖 jq;用 printf + 字符串拼接组 JSON |
| **错误输出** | stderr `echo "ERR: ..." >&2` |
| **依赖** | adb, curl |

### 8.2 各脚本

| 脚本 | 改动等级 | 估算行数 | 关键变化 |
|---|---|---|---|
| `health.sh` | rename only | ~30 | 顶部注释更新为"FlutterWright health check" |
| `goto.sh` | rename + 小补丁 | ~40 | 加 `popUntilRoot=<bool>` 解析;curl 失败 → 退出码 43 |
| `screenshot.sh` | rename only | ~30 | 无逻辑变化 |
| `reload.sh` | **完全重写** | ~15 ↓ | 去 fifo;curl POST /reload;状态码分流 |
| `set_viewport.sh` | rename + 小改 | ~40 | 删 `skip` 模式;状态文件改名;回读校验 |
| `reset_viewport.sh` | rename only | ~25 | 状态文件路径改 `fw_original.env` |
| `mock.sh` | **完全重写** | ~60 | 5 action dispatch(set/get/reset/enable/list) |
| `reset.sh` | **NEW** | ~20 | curl POST /reset {clearMock} |

**合计:** ~260 行 bash(原 7 脚本约 250 行,持平)。

### 8.3 mock.sh dispatch 骨架

```bash
#!/usr/bin/env bash
set -euo pipefail
PORT="${VL_PORT:-9123}"
ACTION="${1:?action required: set|get|reset|enable|list}"; shift

KEY=""; VALUE=""; ENABLED=""
for arg in "$@"; do
  case "$arg" in
    key=*) KEY="${arg#key=}";;
    value=*) VALUE="${arg#value=}";;
    enabled=*) ENABLED="${arg#enabled=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 51;;
  esac
done

case "$ACTION" in
  set)    [ -n "$KEY" ] || { echo "ERR: set requires key=" >&2; exit 52; }
          [ -n "$VALUE" ] || { echo "ERR: set requires value=" >&2; exit 53; }
          PAYLOAD=$(printf '{"action":"set","key":"%s","value":%s}' "$KEY" "$VALUE");;
  get)    [ -n "$KEY" ] || { echo "ERR: get requires key=" >&2; exit 52; }
          PAYLOAD=$(printf '{"action":"get","key":"%s"}' "$KEY");;
  reset)  PAYLOAD='{"action":"reset"}';;
  enable) [ -n "$ENABLED" ] || { echo "ERR: enable requires enabled=" >&2; exit 54; }
          PAYLOAD=$(printf '{"action":"enable","enabled":%s}' "$ENABLED");;
  list)   PAYLOAD='{"action":"list"}';;
  *)      echo "ERR: invalid action '$ACTION'" >&2; exit 51;;
esac

HTTP_CODE=$(curl -sf -o /tmp/fw-mock-out -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/mock" \
  -H 'content-type: application/json' \
  -d "$PAYLOAD") || { echo "ERR: SDK unreachable" >&2; exit 56; }

case "$HTTP_CODE" in
  200) cat /tmp/fw-mock-out; echo;;
  501) echo "ERR: no MockDataProvider configured (call FlutterVisualLoop.start(mockProvider:...))" >&2; exit 55;;
  *)   echo "ERR: /mock returned $HTTP_CODE" >&2; cat /tmp/fw-mock-out >&2; exit 56;;
esac
```

### 8.4 reload.sh 完整骨架

```bash
#!/usr/bin/env bash
set -euo pipefail
PORT="${VL_PORT:-9123}"

HTTP_CODE=$(curl -sf -o /tmp/fw-reload-out -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/reload" \
  -H 'content-type: application/json' \
  -d '{}') || { echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 30; }

case "$HTTP_CODE" in
  200) echo "reloaded";;
  503) echo "ERR: VM service not available (release build?)" >&2; exit 31;;
  *)   echo "ERR: /reload returned $HTTP_CODE" >&2; cat /tmp/fw-reload-out >&2; exit 32;;
esac
```

---

## 9. 文档策略(`docs/`)

### 9.1 v1 最终 docs/ 列表(4 篇 + spec)

| 文件 | 状态 | 修改 |
|---|---|---|
| `docs/api-reference.md` | 小改 | 加 `## POST /reload` section,标注 vm_service.reloadSources |
| `docs/architecture.md` | 中改 | 加 flutterwright 分层(Layer 2a/2b)+ 双仓库职责图 + 更新组件描述 |
| `docs/integration-guide.md` | 小改 | git url 改 flutterwright/;path: `../packages/flutter_visual_loop` |
| `docs/troubleshooting.md` | 大改 | 改方法名(env_check.sh→health 等);删 fifo 段;加 /reload 故障(VM service 未开);并入 e2e-checklist |
| `docs/superpowers/specs/2026-05-22-flutterwright-design.md` | 新 | 本文件 |

### 9.2 待删

- `docs/getting-started.md` → 内容并入 `README.md`(repo 根新写)
- `docs/e2e-checklist.md` → 内容并入 `docs/troubleshooting.md` 末尾"## E2E 验证清单"section

### 9.3 README.md(repo 根)结构提案

```
# FlutterWright

<2-3 行简介:Playwright for Flutter on Android via Claude Code skill>

## What's inside (monorepo)

| Path | What |
|---|---|
| skills/flutterwright/ | Claude Code skill — 8 Playwright-style methods |
| packages/flutter_visual_loop/ | Dart SDK — debug-only HTTP control plane |
| packages/example/ | Demo Flutter app showing SDK integration |
| docs/ | Architecture / API ref / Integration guide / Troubleshooting |

## Quickstart

(吸收 getting-started.md 的 5 步流程,**去掉 mkfifo + < fifo** 步骤,改成 `flutter run -d <id>`)

1. clone repo, `flutter create` in example/
2. `flutter run -d $(adb devices ... )`
3. `adb forward tcp:9123 tcp:9123`
4. 在 Claude Code:`Skill flutterwright "health"` 验环境
5. 集成到自己 app — 见 [integration-guide](docs/integration-guide.md)

## Docs

- [skill SKILL.md](skills/flutterwright/SKILL.md) — 方法集
- [api-reference](docs/api-reference.md) — SDK HTTP 协议
- [architecture](docs/architecture.md) — 组件 & 安全
- [integration-guide](docs/integration-guide.md) — 集成模式
- [troubleshooting](docs/troubleshooting.md) — 故障排查 + E2E 验证

## License

MIT
```

---

## 10. v1 范围边界 + 后续路线

### 10.1 v1 明确**不做**

| 不做项 | 原因 |
|---|---|
| iOS 支持 | 全 adb;iOS 需 Xcode CLI / WebDriverAgent / idb,工作量大 |
| UI 交互(tap/swipe/long-press/text input) | Playwright 核心之一,但 v1 用户场景不需 |
| Widget tree 检视 / Locator | 需 SDK 加 `GET /tree`,v1 不需 |
| 等待 / 断言(`waitFor` / `expect`) | 依赖 widget tree |
| App 生命周期(install/launch/uninstall/foreground/back) | v1 假设 app 已经在前台 |
| 多设备显式路由(`ANDROID_SERIAL` 显式 flag) | v1 复用 adb 默认,多设备时 health.sh 仅 WARN |
| `listRoutes` 方法暴露 GET /routes | SDK 已有,v1 不暴露(上层已知 route 名) |
| 视频录制 | 大工作量,无需求 |
| `/screenshot` (SDK PNG) 暴露成方法 | v1 默认走 adb 完整设备帧;两种用途不同 |
| 错误码集中到 `lib/errors.sh` | v1 各脚本自管,SKILL.md 文档化即可 |

### 10.2 v2 方向草图(不锁)

**v2a 交互能力:** SDK + flutterwright 加 `tap / swipe / type / press / waitFor`,引入 Locator 概念,SDK 加 `GET /tree`。

**v2b iOS 支持:** SDK 改 UNIX socket + TCP 双通道;flutterwright 脚本平台分流;iOS 截图走 `xcrun simctl io booted screenshot`。

**v3 测试运行器:** flutterwright 加 `test` 模式,执行 `.fw.yaml` 测试脚本,生成 trace 报告。

### 10.3 flutter-visual-loop 上层迁移(本 spec 外)

flutterwright v1 完成后,flutter-visual-loop 上层 skill 必须迁移:

1. `skills/flutter-visual-loop/SKILL.md` 重写:`bash scripts/xxx.sh` → `Skill flutterwright "method args..."`
2. `skills/flutter-visual-loop/scripts/` 全删
3. flutter-visual-loop 仓库 README/docs 改:不再写"自带脚本",改成"依赖 flutterwright"

**这部分独立后续工作,不在本 spec 范围。**

---

## 11. v1 完成判定(Definition of Done)

下列**全部满足**即 v1 完成:

1. ☐ 目录结构按 §4 完整(LICENSE/README/CHANGELOG/.gitignore + 4 个一级目录就位)
2. ☐ 8 个脚本按 §6 / §8 实现,退出码与 spec 一致,**rename 全部完成,mock_set.sh / vl_original.env 不再存在**
3. ☐ SKILL.md 按 §5 写完,8 方法 per-method section 完整
4. ☐ SDK 加 `reload_handler.dart` + 注册 + pubspec 加 vm_service + bump 到 0.2.0 + CHANGELOG entry
5. ☐ `docs/` 4 篇按 §9 修订(getting-started 并入 README,e2e-checklist 并入 troubleshooting,其他 4 篇改视角)
6. ☐ `flutter test` 在 `packages/flutter_visual_loop/` 全过(含新 reload_handler_test)
7. ☐ 手动冒烟全过(`flutter run` example app + 跑 8 个方法):
   - `Skill flutterwright "health"` → ok
   - `Skill flutterwright "goto /home"` → 设备跳转
   - `Skill flutterwright "screenshot /tmp/a.png"` → PNG 写盘
   - `Skill flutterwright "reload"` → 改一个 Dart 文件后再跑,UI 更新
   - `Skill flutterwright "setViewport 1080 2400 480"` → wm size 改了
   - `Skill flutterwright "mock set key=x value=42"` → /mock 返 200
   - `Skill flutterwright "reset clearMock=true"` → navigator 回 root + mock 清
   - `Skill flutterwright "resetViewport"` → wm size 还原

---

## 12. 风险登记

| 风险 | 严重度 | 缓解 |
|---|---|---|
| vm_service 版本在 Flutter 3.24/3.29 之间漂移导致 pub solver 找不到匹配 | 中 | range `>=14<16` 覆盖两侧;若失败则降回 `^14.0.0`,在 troubleshooting 提示用户用 `pub override` |
| `Service.getInfo()` 在某些罕见 debug 配置下返 null | 低 | 503 错误码 + troubleshooting 指引"确认 `flutter run` 在 debug 模式" |
| 厂商 ROM(MIUI/HarmonyOS)静默拒 `wm size` | 中 | set_viewport.sh 加回读校验,失败时退出 61 + troubleshooting 已有 section |
| 旧 `flutter-visual-loop` 上层 skill 在 flutterwright v1 完成后未迁移,旧用户卡住 | 中 | flutter-visual-loop README 加迁移提示 + 弃用警告;不在 v1 spec 范围 |
| SKILL.md dispatch 解析失败(Claude 解错 method 名) | 低 | SKILL.md per-method 示例字串友好;dispatch convention 段明确 |

---

## 13. 实施路径预告

本 spec 由 `writing-plans` skill 接手,产出 `docs/superpowers/plans/2026-05-22-flutterwright-v1.md` 实施计划。计划应大致拆为:

1. **基础设施**: LICENSE/README/CHANGELOG/.gitignore + repo metadata
2. **SDK reload endpoint**: handler 文件 + 注册 + pubspec + test
3. **脚本 rename + 小改**: health/goto/screenshot/set_viewport/reset_viewport(批量重命名 + 局部 patch)
4. **脚本完全重写**: reload.sh + mock.sh
5. **脚本新增**: reset.sh
6. **SKILL.md 编写**
7. **docs/ 改写**: 4 篇修订 + README 新写 + getting-started/e2e-checklist 内容并入
8. **手动冒烟 + 完成 DoD**

每个阶段可独立验证。

---

**END OF SPEC**
