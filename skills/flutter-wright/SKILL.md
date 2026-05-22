---
name: flutter-wright
description: Playwright 风格的 Flutter 应用驱动器，针对在 Android 设备/模拟器上运行、并集成了 flutter_wright_sdk SDK 的 Flutter app。Use when you need to navigate routes, screenshot, hot-reload, inject mock data, or lock viewport. Skill 提供 8 个方法（health/goto/screenshot/reload/setViewport/resetViewport/mock/reset），是一个 Claude Code skill。
---

# FlutterWright — Flutter on Android 的 Playwright

一个 Layer 2b 驱动 skill：给定一个集成了 `flutter_wright_sdk` SDK 的宿主 Flutter app，并运行在一台已连接的 Android 设备上（真机或模拟器），本 skill 暴露一套 Playwright 风格的 API，供 Claude 或更上层的编排 skill 驱动它。

v1 仅支持 Android。iOS 支持、UI 交互（tap/swipe/text）以及 widget 树自省不在范围内 — 见 [v1 design spec](../../docs/superpowers/specs/2026-05-22-flutterwright-design.md) §10。

入口声明：**"Using flutter-wright to <method> <target>."**

> ## ⚠️ 强依赖：目标 app 必须集成 `flutter_wright_sdk`
>
> 本 skill 的所有方法（`goto` / `screenshot` / `reload` / `mock` / `reset` / `setViewport` 等）都通过 HTTP 把指令发到目标 Flutter app 进程内的 `flutter_wright_sdk` HTTP 服务（`127.0.0.1:9123`）。
>
> - 目标 app **未集成 SDK** → skill 任何方法都返回 `SDK unreachable` 错误。
> - 目标 app **集成了但未运行**（没执行 `flutter run`） → 同上。
> - 目标 app **已集成 + 正在运行 + 9123 已 `adb forward`** → skill 正常工作。
>
> 首次使用前请先按 [`integration-guide.md`](../../docs/integration-guide.md) 把 SDK 接进目标 app，AI 集成版本见 [`integration-guide-for-ai.md`](../../docs/integration-guide-for-ai.md)。`health` 方法可用于核验整条链路是否就绪。

## 何时使用

- 临时调用：用户已通过 `flutter run` 启动了 Flutter app，希望 Claude 来驱动（"导航到 /order，截图"）。
- 组合调用：更上层的 skill（如 flutter-visual-loop UI 还原循环）通过 `Skill flutter-wright "..."` 把 flutter-wright 的方法作为构件来调用。

不要使用的场景：宿主 app 未集成 `flutter_wright_sdk` SDK（没有 嵌入 app 的 HTTP 服务 → 没东西可对话）。把用户引到 [integration-guide.md](../../docs/integration-guide.md)。

## 概念

- **Page** = 当前运行在已连接 Android 设备上的 Flutter app。
- **Route** = 一个命名应用路由（如 `/order/detail`）。
- **Mock** = 通过 `flutter_wright_sdk.MockDataProvider` 注入的数据。
- **Viewport** = 通过 `wm size` + `wm density` 覆盖，把设备锁定到设计分辨率。
- **Reload** = 通过 SDK `/reload` 端点触发的 Flutter 热重载（`vm_service.reloadSources`）。

## 方法

| 方法 | 用途 | 脚本 |
|---|---|---|
| `health` | 检查环境（adb / device / SDK 可达性 + 自动 `adb forward` 9123） | `health.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 推入一个命名路由 | `goto.sh` |
| `screenshot <out_path>` | 设备截图（整帧含状态栏）输出为 PNG | `screenshot.sh` |
| `reload` | 通过 SDK `/reload` 触发 Flutter 热重载 | `reload.sh` |
| `setViewport <w> <h> <dpi>` | 锁定 `wm size` + `wm density` | `set_viewport.sh` |
| `resetViewport` | 把 `wm size` + `wm density` 恢复到设备默认值 | `reset_viewport.sh` |
| `mock <action> [key=<k>] [value=<json>] [enabled=<bool>]` | Mock 数据控制（action ∈ set/get/reset/enable/list） | `mock.sh` |
| `reset [clearMock=<bool>]` | 把 navigator pop 到根，可选清空 mock | `reset.sh` |

## 前置条件

- macOS / Linux，`adb` 与 `curl` 都在 `PATH` 中。
- 宿主 Flutter app 集成了 `flutter_wright_sdk` ≥ 0.2.0（包含 `/reload` 端点）。
- `flutter run -d <device>` 处于激活状态。**无需 fifo** — v1 已废弃 stdin-fifo 的热重载路径。

完整环境准备：见 [`README.md` Quickstart](../../README.md#quickstart)。

## 方法参考

### `health`

```
Skill flutter-wright "health"
```

校验 `adb` + 至少一台已连接设备 + `curl` 可用，然后执行 `adb forward tcp:9123 tcp:9123`（幂等），并探测 `GET /health`。

退出码：0 成功 / 10 adb 缺失 / 11 没有设备 / 12 SDK 不可达 / 13 curl 缺失。

输出：`ok: device=<id> port=9123`。

### `goto`

```
Skill flutter-wright "goto <route> [args=<json>] [popUntilRoot=<bool>]"
```

通过 `Navigator.pushNamed` 推入 `<route>`。`args` 是任意 JSON 值，作为 `arguments:` 传入。`popUntilRoot` 默认 `true`（先 pop 到根，避免循环迭代间的状态污染）。

示例：`Skill flutter-wright "goto /order/detail args={\"id\":\"ORD-001\"}"`

退出码：0 成功 / 40 缺少 route 或未知参数 / 41 navigator 未就绪（HTTP 503）/ 42 push 失败（HTTP 500）/ 43 SDK 不可达。

### `screenshot`

```
Skill flutter-wright "screenshot <out_path>"
```

`adb exec-out screencap -p > <out>`，随后做 PNG magic-byte 检查。捕获**整帧设备画面，含状态栏**。若只想要 Flutter render 树，直接调 SDK `GET /screenshot`（v1 没有把它暴露为 skill 方法）。

示例：`Skill flutter-wright "screenshot /tmp/order_detail.png"`

退出码：0 成功 / 20 空文件 / 21 文件 < 1KB / 22 不是 PNG（设备锁屏？）。

### `reload`

```
Skill flutter-wright "reload"
```

通过 SDK `POST /reload` 触发 `vm_service.reloadSources`。前提是设备侧 dart isolate 的源文件已更新（通常是上层 skill 或用户在调用前已编辑了 Dart 文件）。

示例：`Skill flutter-wright "reload"`

退出码：0 成功 / 30 SDK 不可达 / 31 VM service 不可用（release 构建？SDK < 0.2.0？）/ 32 `/reload` 返回非 200。

实现细节：成功后 sleep 1s，让 Flutter 应用 reload。

### `setViewport`

```
Skill flutter-wright "setViewport <width> <height> <dpi>"
```

先把原始 `wm size` 和 `wm density` 记录到 `$CLAUDE_JOB_DIR/fw_original.env`，再应用覆盖，并通过回读校验（某些厂商 ROM 会静默拒绝 `wm` 覆盖 — 回读用于检测）。

示例：`Skill flutter-wright "setViewport 1080 2400 480"`

退出码：0 成功 / 60 缺少参数 / 61 覆盖被拒（回读不一致）。

### `resetViewport`

```
Skill flutter-wright "resetViewport"
```

从 `$CLAUDE_JOB_DIR/fw_original.env` 恢复 `wm size` + `wm density`。文件不存在时，回退到 `wm size reset` + `wm density reset`。**总是退出 0** — 在 `trap` 或任何 cleanup hook 中调用都安全。

示例：`Skill flutter-wright "resetViewport"`

退出码：0 恒为 0。

### `mock`

```
Skill flutter-wright "mock <action> [key=<k>] [value=<json>] [enabled=<bool>]"
```

分发到 `POST /mock`，每个 action 用对应的 body：

- `mock set key=<k> value=<json>` — 注入一个值
- `mock get key=<k>` — 读取一个值
- `mock reset` — 清空全部
- `mock enable enabled=<true|false>` — 切换全局 mock 模式
- `mock list` — 列出当前状态

示例：
- `Skill flutter-wright "mock set key=user value={\"name\":\"Alice\"}"`
- `Skill flutter-wright "mock enable enabled=false"`
- `Skill flutter-wright "mock list"`

退出码：0 / 50 缺少 action / 51 非法 action 或未知参数 / 52 缺少 key（set/get）/ 53 缺少 value（set）/ 54 缺少 enabled（enable）/ 55 SDK 返回 501（未配置 MockDataProvider）/ 56 SDK 不可达。

### `reset`

```
Skill flutter-wright "reset [clearMock=<bool>]"
```

`POST /reset`，body 为 `{"clearMock":<bool>}`。默认 `clearMock=true`。

示例：`Skill flutter-wright "reset"` 或 `Skill flutter-wright "reset clearMock=false"`

退出码：0 / 70 SDK 不可达或未知参数 / 71 `/reset` 返回非 200。

## 派发约定

当以 `Skill flutter-wright "<method> <args...>"` 形式调用时：

1. 把第一个由空白分隔的 token 解析为**方法名**。
2. 把剩余 token 解析为位置参数（用于 `goto`/`screenshot`/`setViewport`），随后是 `key=value` 对。
3. 调用 `bash skills/flutter-wright/scripts/<method>.sh <args>`。

`key=value` 中的 JSON 值必须把内部的 `"` 转义为 `\"`（这样才能穿过 shell + curl）。示例：

- Skill 调用：`goto /order/detail args={\"id\":\"X\"}`
- Bash 执行：`bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## 退出码对照

| 区间 | 类别 | 备注 |
|---|---|---|
| 0 | 成功 | — |
| 10-13 | 环境 / 设备 | health.sh — 见 [troubleshooting](../../docs/troubleshooting.md) |
| 20-22 | 截图 | screenshot.sh |
| 30-32 | 热重载 | reload.sh |
| 40-43 | 导航 | goto.sh |
| 50-56 | Mock | mock.sh |
| 60-61 | Viewport | set_viewport.sh / reset_viewport.sh（罕见 — reset 总是退出 0） |
| 70-71 | 重置 | reset.sh |

## 参见

- [api-reference.md](../../docs/api-reference.md) — SDK HTTP 协议
- [integration-guide.md](../../docs/integration-guide.md) — 把 SDK 集成进你的 Flutter app
- [troubleshooting.md](../../docs/troubleshooting.md) — 按症状分类的故障模式
