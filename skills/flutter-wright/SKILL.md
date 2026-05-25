---
name: flutter-wright
description: Playwright 风格的 Flutter 应用驱动器，针对在 Android 设备/模拟器上运行、并集成了 flutter_wright_sdk SDK 的 Flutter app。Use when you need to programmatically navigate routes, screenshot, hot-reload, or lock viewport. Skill 提供 9 个方法（run/stop/health/goto/screenshot/reload/setViewport/resetViewport/reset），是一个 Claude Code skill。
---

# FlutterWright — Flutter on Android 的 Playwright

给定一个运行在已连接 Android 设备（真机或模拟器）上的 Flutter app，本 skill 暴露一套 Playwright 风格的 API，让 Claude（或更上层的编排 skill）远程驱动它 —— 截图、热重载、视口锁定开箱即用;程序化导航（`goto`/`reset`）在 app 集成了 `flutter_wright_sdk` 后解锁。仅支持 Android —— iOS、UI 交互（tap/swipe/输入）、widget 树自省不在范围内。

入口声明：**"Using flutter-wright to <method> <target>."**

> ## ⚠️ 前提:按能力分,不再统一要求 SDK
>
> 各方法依赖不同,SDK **不再是硬前提**:
>
> - **截图 / setViewport** —— 只需 `adb` + 已连接设备。任何在跑的 app 都能截,**不需要 SDK**。
> - **reload** —— 需要由本 skill 的 `run` 启动并持有的 `flutter run` daemon(见 `run` / `reload`)。**不需要 SDK**。你自己终端起的 flutter run,本 skill 持有不了,reload 会返回退出码 33(自己按 `r`)。
> - **goto / reset** —— 需要目标 app 集成了 `flutter_wright_sdk` 且 SDK 服务在 `127.0.0.1:9123` 可达。这是 SDK 唯一不可替代的能力。
>
> 集成 SDK 是宿主 app 的一次性步骤(接 navigatorKey 或 navigationAdapter、`start()`),只为解锁 `goto`/`reset`,不在本 skill 操作范围内。

## 何时使用

这个 skill 把 Flutter app 的「运行 / 导航 / 观察」交给 AI 远程驱动。9 个方法分三类:

- **进程**:`run`(AI 后台起 `flutter run`)、`stop`(停)。持有进程后才能 `reload`。
- **导航**(SDK 专属):`goto`(程序化跳任意路由)、`reset`(回根)。这是集成 SDK 唯一解锁的能力。
- **观察 / 环境**:`screenshot`(adb 截整帧)、`reload`(热重载 owned daemon)、`setViewport`/`resetViewport`(adb 改分辨率)、`health`(SDK 探针)。

适用:

- **全自动循环**:AI `run` 起 app(集成了 SDK 的 dev 入口)→ `goto` 到任意页 → 截图 → 改码 → `reload`。
- **人工导航 + AI 改码迭代**(最常见):AI `run` 起 app → 人工在设备上点到目标页 → AI 改 Dart → `reload` → `screenshot` 看效果。这条循环 **不需要集成 SDK**(不用 `goto`)。
- **编排构件**:上层 skill 把这些方法当原子操作调用。

不要使用:只需 `goto` 但目标 app 没集成 SDK(那 `goto`/`reset` 不可用,但 `run`/`reload`/`screenshot` 仍可用);或你的导航、reload、截图**全程人工** —— 那直接 `adb exec-out screencap` + 在 flutter run 控制台按 `r` 更省事。

## 环境前提(按方法)

不再有「首次调用必过 `/health`」的全局闸门。每个方法只检查自己需要的前提,失败时以对应退出码退出:

- `screenshot` / `setViewport` / `run` → `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。
- `goto` / `reset` / `health` → 上述 + `curl`(13)+ `adb forward tcp:9123` + `GET /health`(SDK 不可达 12)。这些方法在本 job 首次通过后写 `$CLAUDE_JOB_DIR/fw_health_done`,后续走 fast-path。
- `reload` → 不查 adb/SDK,只校验本 skill 已 `run` 且 daemon 存活(33/34)。

## 概念

- **Page** = 当前运行在已连接 Android 设备上的 Flutter app。
- **Route** = 一个应用路由名（如 `/order/detail`）。**无需预先注册** —— `goto` 直接把路由名交给 app 的路由器，能否跳成功取决于路由器认不认（见 `goto`）。提供可发现路由（`start` 的 `routes:` 或 adapter 的 `routesProvider`）只影响 `GET /routes` 的可发现性。
- **Viewport** = 通过 `wm size` + `wm density` 覆盖，把设备锁定到设计分辨率。
- **Reload** = 向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart`(`fullRestart:false`),即热重载。不经 SDK。

## 方法

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

## 方法参考

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

### `health`

```
Skill flutter-wright "health"
```

显式跑一遍 **SDK** 探针(`goto`/`reset` 的前提):`adb` + 至少一台设备 + `curl` + `adb forward tcp:9123`(幂等)+ `GET /health`,并**强制刷新**标记 `$CLAUDE_JOB_DIR/fw_health_done`。

通常不需要手动调 —— `goto`/`reset` 首次调用时会自动跑同一套检查。需要显式调用的场景：

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

`adb exec-out screencap -p > <out>`，随后做 PNG magic-byte 检查。捕获**整帧设备画面，含状态栏**，且**与页面是怎么打开的无关**（人工导航进去的页面照样能截）。若只想要 Flutter 渲染树（不含状态栏），直接调 SDK `GET /screenshot`（需宿主用 `FlutterWrightRoot` 包根；目前没把它暴露为 skill 方法）。

示例：`Skill flutter-wright "screenshot /tmp/order_detail.png"`

退出码：0 成功 / 20 空文件 / 21 文件 < 1KB / 22 不是 PNG（设备锁屏？）。

### `reload`

```
Skill flutter-wright "reload"
```

向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart {fullRestart:false}`(热重载)。源文件改动由调用方(Claude/上层 skill)在调用前完成。**前提是先 `run` 过** —— 没有 owned daemon 时退出码 33。

> 你自己终端起的 `flutter run`,本 skill 持有不了它的 stdin,无法发 reload —— 此时直接在那个控制台按 `r`。本方法只驱动 `run` 起来的 daemon。

示例：`Skill flutter-wright "reload"`

退出码：0 成功 / 33 没有 owned daemon(先 `run`,或自己按 `r`)/ 34 daemon 已死(重新 `run`)/ 35 重载失败或超时(看 daemon 日志的 dart 编译错误)。

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
2. 把剩余 token 解析为位置参数（用于 `goto`/`screenshot`/`setViewport`/`run`），随后是 `key=value` 对（目前仅 `goto` 的 `args`/`popUntilRoot`）。
3. 调用 `bash skills/flutter-wright/scripts/<method>.sh <args>`。

`key=value` 中的 JSON 值必须把内部的 `"` 转义为 `\"`（这样才能穿过 shell + curl）。示例：

- Skill 调用：`goto /order/detail args={\"id\":\"X\"}`
- Bash 执行：`bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## 退出码对照

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
