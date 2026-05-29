# FlutterWright

像 Playwright 驱动浏览器那样,程序化驱动一个**已运行在 Android 上的 Flutter app**:让 AI 看语义树、点按 / 输入、截图、(可选)程序化跳页。仅支持 Android。

## 是什么

FlutterWright 是一个 **Claude Code skill**,让 AI 像驱动浏览器一样驱动真机 / 模拟器上**已运行**的 Flutter app:拿语义树快照看页面、按 ref 精确点按 / 输入 / 滚动、截图看效果、跳到任意页面,形成 **「看 → 操作 → 再看」** 的自动闭环。(起 app / 热重载由你自己 `flutter run` 完成,本 skill 只驱动,不托管进程。)

它暴露一组 Playwright 风格的方法(`snapshot` / `tap` / `type` / `goto` / `screenshot` / `setViewport` 等)。**完整清单(16 个方法)、签名与退出码见 [`SKILL.md`](skills/flutter-wright/SKILL.md)**。

当前版本 **v0.8.0**。**snapshot-first 交互闭环**(对齐 Playwright MCP)自 v0.7.0 起提供:先拿语义树快照(`snapshot`)、得到带 `[ref=sN]` 的节点,再用 ref 精确操作元素(`tap` / `type` / `scroll` / `longPress` / `waitFor`)。无需坐标、无需 UI 层级知识。v0.8.0 起,启用改为宿主显式控制(`enabled` 默认 `false` / fail-safe),并新增可选 `token` 鉴权。

> 截图、视口锁定**经 `adb` 开箱即用,不需要任何集成**(驱动一个你已 `flutter run` 起来的 app)。**接入 SDK(`FlutterWright.start(enabled: kDebugMode)`)即解锁全套语义交互**(snapshot/tap/type/scroll/longPress/waitFor),无需 navigatorKey。只有还要让 AI 程序化跳页(`goto`/`reset`)才需要额外传 navigatorKey 或 adapter,见下方「SDK 集成(可选)」。导航**架构无关**,Navigator 1.0 / GoRouter / GetX 都行。

## 怎么用

你不用自己敲命令。**在 Claude Code 会话里用大白话告诉 Claude 想干嘛,它替你调 skill。**

> **一次性准备**:Flutter 3.24+、`adb` 在 PATH、Android 真机(开 USB 调试)或模拟器;`git clone` 本仓库后给示例 app 补 Android 脚手架(`cd packages/example && flutter create . --platforms=android && flutter pub get`)。skill 在仓库的 `skills/flutter-wright/`。

一段典型对话(cwd 在 `packages/example`):

> **你**:(你已在终端 `flutter run` 起了 example)截个图看看现在长啥样。
>
> **Claude**:*(调用 `screenshot`)* 给你 → `before.png`。
>
> **你**:我把首页标题改了,在 flutter 控制台按了 `r` 热重载,再截一张。
>
> **Claude**:*(调用 `screenshot`)* 新图 → `after.png`。

这条「截图 → 改码 → 按 `r` 重载 → 再截图」的闭环**完全不需要 SDK**(起 app、热重载是你自己的 `flutter run` 在做)。想精确点名某个方法,直接显式调用也行:

```
Skill flutter-wright "screenshot $CLAUDE_JOB_DIR/cur.png"
Skill flutter-wright "logs since=50"
```

**想让 AI 自己跳页面?** 跳到任意路由(`goto`)要先给 app 集成 SDK(见下节);你自己用集成入口起 app(`flutter run -t dev/main_dev.dart`),再让 Claude 跳:

> **你**:跳到订单详情页。
>
> **Claude**:*(调用 `goto /order/detail args={"id":"ORD-001"}`)* 已跳转到 `/order/detail`。

## SDK 集成(可选)

**只要截图?跳过这节。** 你自己 `flutter run` 起 app,截图走 `adb screencap`、热重载在你的 flutter 控制台按 `r`,都不经 SDK。

**要让 AI 看语义树 + 操作元素(`snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`)**,把 SDK 加进 app,核心只需 `await FlutterWright.start(enabled: kDebugMode)`,无需传 navigatorKey。

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
|  bash 脚本 (skills/.../)    |   HTTP/JSON  |  │ flutter_wright_sdk (enabled)   │  |
|         │     ──────────────┼──────────────┼─▶│   绑 127.0.0.1:9123             │  |
|         ▼                   |  via adb     |  │   /navigate /screenshot /...   │  |
|  adb / curl                 |  forward     |  └────────────────────────────────┘  |
+-----------------------------+              +--------------------------------------+
```

- **不经 SDK 的方法**(`screenshot`/`setViewport`/`resetViewport`/`pressKey`/`back`/`logs`):截图走 `adb screencap`、视口走 `adb shell wm`、日志走 `adb logcat`;都只需 `adb`。起 app / 热重载是你自己的 `flutter run`(控制台按 `r`),本 skill 不托管进程。
- **需要 SDK 的方法**,分两层:
  - **交互层**(`snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`/`health`/`targets`):只需 `FlutterWright.start(enabled: kDebugMode)`,无需 navigatorKey。app 在 `enabled` 为真时于注册表 `base`(如 `127.0.0.1:9123`)开 HTTP 服务,bash 脚本经目标注册表解析 `base` + `curl` 把命令发进去(可达性用 `targets forward` 建一次 `adb forward`)。
  - **导航层**(`goto`/`reset`):需要额外传 navigatorKey 或 navigationAdapter。`enabled` 默认 `false` 时 SDK 是 no-op,不绑 socket、不暴露任何东西(由调用方控制,非自动感知构建)。

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
| [`skills/flutter-wright/SKILL.md`](skills/flutter-wright/SKILL.md) | 16 个方法:签名、退出码、示例 |
| [`docs/api-reference.md`](docs/api-reference.md) | SDK HTTP 协议 —— 面向直接 curl 调用方与贡献者 |
| [`docs/architecture.md`](docs/architecture.md) | 分层、组件、安全约束 |
| [`docs/integration-guide.md`](docs/integration-guide.md) | Dart 集成模式(人类版) |
| [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md) | **面向 AI** 的集成指南:决策树 + 验证步骤 |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | 按症状分类的故障模式 + E2E 检查清单 |

## 许可证

MIT,见 [`LICENSE`](LICENSE)。
