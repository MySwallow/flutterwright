---
name: flutter-wright
description: Playwright 风格的 Flutter 应用驱动器，针对在 Android 设备/模拟器上运行、并集成了 flutter_wright_sdk SDK 的 Flutter app。Use when you need to programmatically navigate routes, screenshot, hot-reload, or lock viewport. Skill 提供 7 个方法（health/goto/screenshot/reload/setViewport/resetViewport/reset），是一个 Claude Code skill。
---

# FlutterWright — Flutter on Android 的 Playwright

给定一个集成了 `flutter_wright_sdk` 并运行在已连接 Android 设备（真机或模拟器）上的 Flutter app，本 skill 暴露一套 Playwright 风格的 API，让 Claude（或更上层的编排 skill）远程驱动它。

v1 仅支持 Android。iOS、UI 交互（tap/swipe/输入）、widget 树自省不在范围内。

入口声明：**"Using flutter-wright to <method> <target>."**

## 它的核心是「程序化导航」

7 个方法里，真正不可替代的是 **`goto`（程序化跳转任意路由）** —— 让 AI 无人值守地把 app 切到任意页面。其余方法是「观察」与「环境」：

- `screenshot` 走 `adb screencap`，截的是**当前屏幕上的任何东西**，跟页面是怎么打开的无关 —— 人工手点进去的页面，照样能截。
- `reload` 走 SDK `/reload` 热重载当前源码，也与导航无关。
- `setViewport` / `resetViewport` 走 `adb wm`，纯设备侧。

含义：如果你的流程是「人工把 app 开到某页 → 截图 / 改代码 reload」，那 `goto` 用不上，甚至不需要这个 skill（直接 `adb screencap` + 在 `flutter run` 控制台按 `r` 即可）。**这个 skill 的价值，集中在「把人从导航循环里拿掉」。**

> ## ⚠️ 强依赖：目标 app 必须集成并运行 `flutter_wright_sdk`
>
> 所有方法都通过 HTTP 把指令发到目标 app 进程内的 SDK 服务（`127.0.0.1:9123`）。
>
> - app **未集成 SDK** 或 **未 `flutter run`** → 任何方法返回 `SDK unreachable`。
> - app **已集成 + 运行 + 9123 已 `adb forward`** → 正常工作。
> - app 集成了 SDK 但**没接导航**（没给 `MaterialApp` 传 navigatorKey、也没传 `navigationAdapter`）→ `screenshot` / `reload` 照常，但 `goto` / `reset` 返回 503 `navigator not ready`。
>
> 集成步骤见 [`integration-guide.md`](../../docs/integration-guide.md)（人类版）/ [`integration-guide-for-ai.md`](../../docs/integration-guide-for-ai.md)（AI 版）。

## 环境检查（自动）

任意方法在本 job 内**首次调用**时，skill 会自动跑一遍环境链路检查：`adb` 在 PATH → `curl` 在 PATH → 至少一台 adb 设备 → `adb forward tcp:9123 tcp:9123` → `GET /health`。任意一步失败时，该方法以 `health` 的退出码（`10` adb / `11` device / `12` SDK / `13` curl）退出，**不会**再走到方法本身的 "SDK unreachable" 分支。

检查通过后写入标记 `$CLAUDE_JOB_DIR/fw_health_done`，本 job 后续调用走 fast-path 直接跳过链路检查。

**上层 skill 因此不需要感知 `health` 的存在** —— 直接调任何方法就能得到等价的环境保证；环境问题统一收口在退出码 10-13。`health` 方法本身仍保留，作为显式 dry-run 或刷新标记的入口（见下方 `health` 段）。

## 何时使用

- 临时驱动：用户已 `flutter run` 起了 app，希望 Claude 来跳转、截图、reload。
- **人工导航 + AI 改码迭代**(常见):`flutter run` 起好 → 人工把 app 点到目标页 → AI 改 Dart → `reload` → `screenshot` 看效果 → 再改。这条循环里 AI 不碰导航(人来点),只用 `reload` + `screenshot`。
- 编排构件：更上层的 skill（如 UI 还原循环）通过 `Skill flutter-wright "..."` 把这些方法当原子操作调用。

不要使用：目标 app 没集成 `flutter_wright_sdk`（没有进程内 HTTP 服务，没东西可对话）；或你的流程里导航和 reload/截图**全程人工**(那直接 `adb exec-out screencap` + 在 `flutter run` 控制台按 `r` 更省事)。

## 概念

- **Page** = 当前运行在已连接 Android 设备上的 Flutter app。
- **Route** = 一个应用路由名（如 `/order/detail`）。**无需预先注册** —— `goto` 直接把路由名交给 app 的路由器，能否跳成功取决于路由器认不认（见 `goto`）。注册（`testRoutes`）只影响 `GET /routes` 的可发现性。
- **Viewport** = 通过 `wm size` + `wm density` 覆盖，把设备锁定到设计分辨率。
- **Reload** = 通过 SDK `/reload` 触发的 Flutter 热重载（`vm_service.reloadSources`）。

## 方法

| 方法 | 用途 | 脚本 |
|---|---|---|
| `health` | 显式 dry-run / 刷新标记（首次调用任何其他方法时会自动隐式跑） | `health.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 程序化跳转到一个路由 | `goto.sh` |
| `screenshot <out_path>` | 设备整帧截图（含状态栏）输出为 PNG | `screenshot.sh` |
| `reload` | 通过 SDK `/reload` 触发 Flutter 热重载 | `reload.sh` |
| `setViewport <w> <h> <dpi>` | 锁定 `wm size` + `wm density` | `set_viewport.sh` |
| `resetViewport` | 把 `wm size` + `wm density` 恢复到设备默认值 | `reset_viewport.sh` |
| `reset` | 把 navigator pop 到根 | `reset.sh` |

## 前置条件

- macOS / Linux，`adb` 与 `curl` 都在 `PATH` 中。
- 宿主 Flutter app 集成了 `flutter_wright_sdk`，并以 `flutter run -d <device>` 运行中（debug 模式）。

完整环境准备：见 [`README.md` 快速上手](../../README.md#快速上手5-分钟)。

## 方法参考

### `health`

```
Skill flutter-wright "health"
```

显式跑一遍环境链路检查：`adb` + 至少一台已连接设备 + `curl` + `adb forward tcp:9123 tcp:9123`（幂等）+ `GET /health`，并**强制刷新**标记 `$CLAUDE_JOB_DIR/fw_health_done`。

通常不需要手动调 —— 任何其他方法首次调用都会自动跑同一套检查（[环境检查（自动）](#环境检查自动)）。需要显式调用的场景：

- 手工 debug 一个环境问题，希望立刻拿到诊断输出。
- SDK 在 job 中途重启过（如 `flutter run` 被 ctrl-c 后重启），想强制重做一次完整检查 + 重新写标记。

退出码：0 成功 / 10 adb 缺失 / 11 没有设备 / 12 SDK 不可达 / 13 curl 缺失。

输出：`ok: device=<id> port=9123`。

### `goto`

```
Skill flutter-wright "goto <route> [args=<json>] [popUntilRoot=<bool>]"
```

跳转到 `<route>`。`args` 是任意 JSON 值，作为路由参数传入。`popUntilRoot` 默认 `true`（先回到根，避免循环迭代间的状态污染）。

**路由无需预先注册。** 具体怎么跳由宿主配置的 `NavigationAdapter` 决定：默认 `NavigatorKeyAdapter` 走 `Navigator.pushNamed`（你的 `onGenerateRoute` 接收 route 名 + args）；GoRouter / GetX 等走宿主提供的 `CallbackNavigationAdapter` 闭包。**能否跳成功，取决于 app 的路由器认不认这个 route 名**，而不是有没有注册。

示例：`Skill flutter-wright "goto /order/detail args={\"id\":\"ORD-001\"}"`

退出码：0 成功 / 40 缺少 route 或未知参数 / 41 navigator 未就绪（HTTP 503：app 没挂载，或宿主没接 navigationAdapter/navigatorKey）/ 42 跳转失败（HTTP 500：路由名 app 不认、args 类型不符等）/ 43 SDK 不可达。

### `screenshot`

```
Skill flutter-wright "screenshot <out_path>"
```

`adb exec-out screencap -p > <out>`，随后做 PNG magic-byte 检查。捕获**整帧设备画面，含状态栏**，且**与页面是怎么打开的无关**（人工导航进去的页面照样能截）。若只想要 Flutter 渲染树（不含状态栏），直接调 SDK `GET /screenshot`（需宿主用 `FlutterWrightRoot` 包根；v1 没把它暴露为 skill 方法）。

示例：`Skill flutter-wright "screenshot /tmp/order_detail.png"`

退出码：0 成功 / 20 空文件 / 21 文件 < 1KB / 22 不是 PNG（设备锁屏？）。

### `reload`

```
Skill flutter-wright "reload"
```

通过 SDK `POST /reload` 触发 `vm_service.reloadSources`。前提是设备侧 dart isolate 的源文件已更新（通常是上层 skill 或用户在调用前已编辑了 Dart 文件）。

> 注：`/reload` 依赖 SDK 进程内自连 VM service，在 `flutter run`（DDS 占用 VM service）下可能连不上而返回 503。最稳的热重载始终是在 `flutter run` 控制台按 `r`；本方法是「无人值守」场景下的尽力而为。

示例：`Skill flutter-wright "reload"`

退出码：0 成功 / 30 SDK 不可达 / 31 VM service 不可用（release 构建？或被 DDS 占用）/ 32 `/reload` 返回非 200。

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

### `reset`

```
Skill flutter-wright "reset"
```

`POST /reset`，把 navigator pop 回根。不接受参数。

示例：`Skill flutter-wright "reset"`

退出码：0 / 70 SDK 不可达或多余参数 / 71 `/reset` 返回非 200。

## 派发约定

当以 `Skill flutter-wright "<method> <args...>"` 形式调用时：

1. 把第一个由空白分隔的 token 解析为**方法名**。
2. 把剩余 token 解析为位置参数（用于 `goto`/`screenshot`/`setViewport`），随后是 `key=value` 对（目前仅 `goto` 的 `args`/`popUntilRoot`）。
3. 调用 `bash skills/flutter-wright/scripts/<method>.sh <args>`。

`key=value` 中的 JSON 值必须把内部的 `"` 转义为 `\"`（这样才能穿过 shell + curl）。示例：

- Skill 调用：`goto /order/detail args={\"id\":\"X\"}`
- Bash 执行：`bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## 退出码对照

| 区间 | 类别 | 备注 |
|---|---|---|
| 0 | 成功 | — |
| 10-13 | 环境 / 设备 | health.sh **或任何方法的首次调用**（[环境检查（自动）](#环境检查自动)）— 见 [troubleshooting](../../docs/troubleshooting.md) |
| 20-22 | 截图 | screenshot.sh |
| 30-32 | 热重载 | reload.sh |
| 40-43 | 导航 | goto.sh |
| 60-61 | Viewport | set_viewport.sh / reset_viewport.sh（罕见 — reset 总是退出 0） |
| 70-71 | 重置 | reset.sh |

## 参见

- [api-reference.md](../../docs/api-reference.md) — SDK HTTP 协议
- [integration-guide.md](../../docs/integration-guide.md) — 把 SDK 集成进你的 Flutter app
- [troubleshooting.md](../../docs/troubleshooting.md) — 按症状分类的故障模式
