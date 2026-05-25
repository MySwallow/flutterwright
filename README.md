# FlutterWright

像驱动浏览器那样,程序化驱动一个**真实运行在 Android 上的 Flutter app** —— 通过一个 Claude Code skill + 一个仅 debug 启用的 Dart SDK。仅支持 Android。

## 是什么

两块拼在一起:

- **`flutter_wright_sdk`**(Dart SDK)—— 加进你的 app,debug 下在 `127.0.0.1:9123` 开一个本地 HTTP 控制服务;release 自动 no-op。
- **`flutter-wright`**(Claude Code skill)—— 通过 `adb forward` + `curl`(以及持有 `flutter run`)驱动那个 app,暴露 9 个 Playwright 风格的方法:

| 方法 | 作用 |
|---|---|
| `goto <route> [args]` | **程序化跳转**到任意路由(核心能力) |
| `screenshot <path>` | 设备整帧截图(含状态栏)→ PNG |
| `run` | AI 后台启动 flutter run 并持有(reload 前提) |
| `stop` | 停止 owned flutter run |
| `reload` | 热重载 AI 持有的 flutter run(不经 SDK) |
| `setViewport <w> <h> <dpi>` / `resetViewport` | 锁定 / 恢复设备分辨率(像素对齐用) |
| `reset` | navigator pop 回根 |
| `health` | SDK 探针(`goto`/`reset` 的前提) |

导航**架构无关**:经可插拔 `NavigationAdapter` 适配,Navigator 1.0 / GoRouter / GetX 都行。路由**无需预先注册**——`goto` 直接把路由名交给你的路由器。

## 你需要它吗?

关键看**哪些动作要交给 AI 程序化执行**——AI 没法在 `flutter run` 控制台手动按 `r`、也没法手点屏幕。但这些未必都要 SDK:`reload` 走 `run` 起的 flutter daemon、截图走 adb,只有程序化导航(`goto`/`reset`)才需要 SDK:

| 你的流程 | 要不要这个 SDK |
|---|---|
| 只要 **AI 截图 + AI reload + AI 改码**(不要程序化跳转) | **不需要 SDK**。AI `run` 起你的 app → `reload` + `screenshot`。reload 走 flutter daemon、截图走 adb,均不经 SDK。 |
| 还要 **AI 程序化跳转任意路由(`goto`)** | **需要集成 SDK**(接 navigatorKey/adapter + `start()`)。SDK 只为解锁 `goto`/`reset`。 |
| 想让 **AI 自己跳到任意页面**(全自动循环) | **需要** + 接导航(navigatorKey 或 adapter) |
| 想要"纯 Flutter 渲染树截图(不含状态栏)" | 需要 SDK + `FlutterWrightRoot`;adb 整帧截图则不需要 |

一句话:**SDK 是「把某个动作从人手里交给 AI」的那一层。** 哪个动作要自动化,就接哪一块;全程人工,它就是纯可选项。

### 典型工作流:人工导航 + AI 改码迭代

最常见的一种:**AI `run` 起 app → 人工把 app 点到目标页 → AI 改 Dart → AI `reload` → AI `screenshot` 看效果 → 再改**。这条循环里 AI 不碰导航(人来点),只需 `run` + `reload` + `screenshot`,**完全不需要集成 SDK**。

> reload 说明:AI 的 `reload` 驱动的是 `run` 起的 `flutter run --machine` daemon(`app.restart`),稳定可靠。前提是用 `run` 起 app;你自己终端起的 flutter run 本 skill 持有不了,reload 返回退出码 33,自己按 `r` 即可。

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

1. app 集成 `flutter_wright_sdk`,debug 启动后在 `127.0.0.1:9123` 开 HTTP 服务。
2. 电脑上 `adb forward tcp:9123 tcp:9123` 把设备端口转发到本机。
3. 调用**需要 SDK 的方法**(`goto`/`reset`)时,bash 脚本经 `curl` 把命令发到 SDK,SDK 在 app 内执行。
4. release 构建里 SDK 是 no-op,不绑 socket、不暴露任何东西。

> 上图是 **SDK 路径**(`goto`/`reset`、SDK 渲染树截图)。`reload`/`run` 走 flutter-wright 持有的 `flutter run --machine` daemon、`screenshot` 走 `adb screencap`,都**不经**这个 HTTP 服务、不需要 SDK。

## 集成是按需的

你用哪些方法,才需要接哪部分——最小集成就是一行:

| 你想用 | 需要的集成 |
|---|---|
| `reload` + adb 截图(人工导航) | **不需要 SDK**;AI `run` 起 app 即可 |
| `goto` / `reset`(命名路由) | 再把 `FlutterWright.navigatorKey` 传给 `MaterialApp(navigatorKey:)` |
| `goto`(GoRouter / GetX) | 给 `start()` 传一个 `CallbackNavigationAdapter` |
| `GET /routes` 让 AI 发现页面 | 传 `routes:`(路由名列表,可选)或 adapter 的 `routesProvider`(不影响 `goto`) |
| 纯渲染树截图(不含状态栏) | 用 `FlutterWrightRoot` 包根 |

推荐把 SDK 放 **`dev_dependencies`** + 一个独立 `dev/main_dev.dart` 入口,让生产 `lib/` 对 SDK 零引用、release 零残留。`packages/example` 就是这么组织的。完整模式见 [集成指南](docs/integration-guide.md)。

## 快速上手(5 分钟)

**前置**:Flutter 3.24+、Android 真机(开 USB 调试)或模拟器、`adb` 在 PATH、`curl`。

```bash
# 1. 克隆并补齐 Android 脚手架(不改动已有文件)
git clone https://github.com/MySwallow/flutterwright.git
cd flutterwright/packages/example
flutter create . --platforms=android --org com.example.flutterwright
flutter pub get

# 2. 跑 debug 入口(注意 -t:示例的 lib/main.dart 是零 SDK 的生产入口)
flutter run -d "$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')" -t dev/main_dev.dart
# 等待: [flutter_wright_sdk] listening on http://127.0.0.1:9123

# 3. 转发端口并验证
adb forward tcp:9123 tcp:9123
curl http://localhost:9123/health
# → {"ok":true,"version":"0.4.0","service":"flutter_wright_sdk"}
```

然后在任意 Claude Code 会话里(skill 在仓库的 `skills/flutter-wright/`):

```
Skill flutter-wright "goto /order/detail args={\"id\":\"ORD-001\"}"
Skill flutter-wright "screenshot $CLAUDE_JOB_DIR/cur.png"
```

## 集成进你自己的 app

只需要 `reload` + 截图?**无需集成 SDK** —— 用 skill 的 `run` 起 app 即可,reload 走 flutter daemon、截图走 adb,完全不经 SDK。只有需要 `goto`/`reset`(AI 程序化跳转)时才集成 SDK。

最小集成(只要 `goto`/`reset`):

```dart
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start();   // release 自动 no-op
  runApp(const MyApp());
}
```

想用 `goto`,再把 navigator 让出来:

```dart
MaterialApp(
  navigatorKey: FlutterWright.navigatorKey,  // GoRouter/GetX 改用 CallbackNavigationAdapter
  onGenerateRoute: yourRouter,               // curl 传来的 route+args 在这里解析
)
```

完整 recipe(dev_dependencies 范式、不同路由架构、多 flavor)见 [`docs/integration-guide.md`](docs/integration-guide.md);**让 AI 帮你集成**则读 [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md)(决策树 + 前置检查 + 验证步骤)。

## 项目结构

```
flutterwright/
├── skills/flutter-wright/    <- Claude Code skill (SKILL.md + scripts)
├── packages/
│   ├── flutter_wright_sdk/   <- Dart SDK
│   └── example/              <- 示例 app(lib/ 零 SDK;dev/main_dev.dart 是 debug 入口)
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
