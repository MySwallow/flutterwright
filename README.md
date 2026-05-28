# FlutterWright

像 Playwright 驱动浏览器那样,程序化驱动一个**真实运行在 Android 上的 Flutter app**:让 AI 自己起 app、热重载、截图、(可选)程序化跳页。仅支持 Android。

## 是什么

FlutterWright 是一个 **Claude Code skill**,让 AI 像驱动浏览器一样驱动真机 / 模拟器上的 Flutter app —— 改完代码自己热重载、自己截图看效果、自己跳到任意页面,形成 **「改码 → 重载 → 截图看 → 再改」** 的自动闭环。

它暴露一组 Playwright 风格的方法 —— `run` / `reload` / `screenshot` / `goto` / `setViewport` 等 —— **完整清单、签名与退出码见 [`SKILL.md`](skills/flutter-wright/SKILL.md)**。

v0.7.0 新增 **snapshot-first 交互闭环**(对齐 Playwright MCP):先拿语义树快照(`snapshot`)、得到带 `[ref=sN]` 的节点,再用 ref 精确操作元素(`tap` / `type` / `scroll` / `longPress` / `waitFor`)。无需坐标、无需 UI 层级知识。

> 截图、热重载、视口锁定**开箱即用,不需要任何集成**(经 `adb` + skill 持有的 `flutter run` daemon 实现)。**接入 SDK(`FlutterWright.start()`)即解锁全套语义交互**(snapshot/tap/type/scroll/longPress/waitFor),无需 navigatorKey。只有还要让 AI 程序化跳页(`goto`/`reset`)才需要额外传 navigatorKey 或 adapter —— 见下方「SDK 集成(可选)」。导航**架构无关**,Navigator 1.0 / GoRouter / GetX 都行。

## 怎么用

你不用自己敲命令 —— **在 Claude Code 会话里用大白话告诉 Claude 想干嘛,它替你调 skill。**

> **一次性准备**:Flutter 3.24+、`adb` 在 PATH、Android 真机(开 USB 调试)或模拟器;`git clone` 本仓库后给示例 app 补 Android 脚手架(`cd packages/example && flutter create . --platforms=android && flutter pub get`)。skill 在仓库的 `skills/flutter-wright/`。

一段典型对话(cwd 在 `packages/example`):

> **你**:把 example 这个 app 起起来。
>
> **Claude**:*(调用 `run lib/main.dart`)* 起好了。
>
> **你**:截个图看看现在长啥样。
>
> **Claude**:*(调用 `screenshot`)* 给你 → `before.png`。
>
> **你**:我把首页标题改了,热重载一下再截一张。
>
> **Claude**:*(调用 `reload` + `screenshot`)* 重载完,新图 → `after.png`。
>
> **你**:收工。
>
> **Claude**:*(调用 `stop`)* 已停。

这条「起 app → 截图 → 改码 → 重载 → 再截图」的闭环**完全不需要 SDK**。想精确点名某个方法,直接显式调用也行:

```
Skill flutter-wright "run lib/main.dart"
Skill flutter-wright "reload"
Skill flutter-wright "screenshot $CLAUDE_JOB_DIR/cur.png"
```

**想让 AI 自己跳页面?** 跳到任意路由(`goto`)要先给 app 集成 SDK(见下节),然后让它用集成入口 `dev/main_dev.dart` 起 app:

> **你**:用集成 SDK 的入口起 app,跳到订单详情页。
>
> **Claude**:*(调用 `run dev/main_dev.dart` + `goto /order/detail args={"id":"ORD-001"}`)* 已跳转到 `/order/detail`。

## SDK 集成(可选)

**只要 AI 截图 + 热重载?跳过这节。** 用 skill 的 `run` 起 app 即可:reload 走它持有的 `flutter run` daemon、截图走 `adb screencap`,都不经 SDK。

**要让 AI 看语义树 + 操作元素(`snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`)**,把 SDK 加进 app,核心只需 `await FlutterWright.start()` — 无需传 navigatorKey。

**要让 AI 程序化跳页(`goto`/`reset`)** 才需要在 `start()` 额外传 navigatorKey 或 navigationAdapter。

推荐放进 **`dev_dependencies`** + 一个独立的 `dev/main_dev.dart` 入口,让生产 `lib/` 对 SDK 零引用、release 零残留(`packages/example` 就是这么组织的)。

完整集成 recipe(dev_dependencies 范式、Navigator 1.0 / GoRouter / GetX 各自的接法、多 flavor):

- **人类版** → [`docs/integration-guide.md`](docs/integration-guide.md)
- **让 AI 帮你集成** → [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md)(决策树 + 前置检查 + 验证步骤)

## 工作原理

```
+-----------------------------+              +--------------------------------------+
|  Claude Code 会话            |              |  Android 设备 / 模拟器                |
|                             |              |                                      |
|  Skill flutter-wright "..."  |              |  ┌────────────────────────────────┐  |
|         │                   |              |  │  你的 Flutter app                │  |
|         ▼                   |              |  │                                │  |
|  bash 脚本 (skills/.../)    |   HTTP/JSON  |  │   flutter_wright_sdk (debug)   │  |
|         │     ──────────────┼──────────────┼─▶│   绑 127.0.0.1:9123             │  |
|         ▼                   |  via adb     |  │   /navigate /screenshot /...   │  |
|  adb / curl                 |  forward     |  └────────────────────────────────┘  |
+-----------------------------+              +--------------------------------------+
```

- **不经 SDK 的方法**(`run`/`reload`/`stop`/`screenshot`/`setViewport`/`pressKey`/`back`/`logs`):`run` 起一个 `flutter run --machine` daemon 并持有,`reload` 给它发 `app.restart` 热重载;截图走 `adb screencap`、视口走 `adb shell wm`。
- **需要 SDK 的方法** — 分两层:
  - **交互层**(`snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`/`health`):只需 `FlutterWright.start()`,无需 navigatorKey。app 在 debug 下于 `127.0.0.1:9123` 开 HTTP 服务,bash 脚本经 `adb forward` + `curl` 把命令发进去。
  - **导航层**(`goto`/`reset`):需要额外传 navigatorKey 或 navigationAdapter。release 构建里 SDK 是 no-op,不绑 socket、不暴露任何东西。

## 项目结构

```
flutterwright/
├── skills/flutter-wright/    <- Claude Code skill (SKILL.md + scripts)
├── packages/
│   ├── flutter_wright_sdk/   <- Dart SDK(可选集成)
│   └── example/              <- 示例 app(lib/ 零 SDK;dev/main_dev.dart 是集成入口)
└── docs/                     <- API 参考 / 架构 / 集成 / 故障排查
```

| 文档 | 内容 |
|---|---|
| [`skills/flutter-wright/SKILL.md`](skills/flutter-wright/SKILL.md) | 9 个方法:签名、退出码、示例 |
| [`docs/api-reference.md`](docs/api-reference.md) | SDK HTTP 协议 —— 面向直接 curl 调用方与贡献者 |
| [`docs/architecture.md`](docs/architecture.md) | 分层、组件、安全约束 |
| [`docs/integration-guide.md`](docs/integration-guide.md) | Dart 集成模式(人类版) |
| [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md) | **面向 AI** 的集成指南:决策树 + 验证步骤 |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | 按症状分类的故障模式 + E2E 检查清单 |

## 许可证

MIT —— 见 [`LICENSE`](LICENSE)。
