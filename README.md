# FlutterWright

像 Playwright 驱动浏览器那样,程序化驱动一个**真实运行在 Android 上的 Flutter app**:让 AI 自己起 app、热重载、截图、(可选)程序化跳页。仅支持 Android。

## 是什么

FlutterWright 让 AI(Claude Code)能像操作浏览器一样操作真机 / 模拟器上的 Flutter app —— 改完代码自己热重载、自己截图看效果、自己跳到任意页面,形成 **「改码 → 重载 → 截图看 → 再改」** 的自动闭环。

它由两块组成,**SDK 是可选的**:

- **`flutter-wright`**(Claude Code skill,必需)—— 一组 bash 脚本,经 `adb` + 它持有的 `flutter run` daemon 驱动 app:起停、热重载、截图、锁视口。
- **`flutter_wright_sdk`**(Dart SDK,可选)—— 加进 app 后,**额外解锁程序化导航**,让 AI 直接 `goto` 任意路由。只在 debug 启用,release 自动 no-op。

skill 暴露 9 个 Playwright 风格的方法:

| 方法 | 作用 | 需要 SDK? |
|---|---|---|
| `run` / `stop` | AI 后台起 / 停 `flutter run` 并持有 | 否 |
| `reload` | 热重载持有的 app | 否 |
| `screenshot <path>` | 设备整帧截图(含状态栏)→ PNG | 否 |
| `setViewport <w> <h> <dpi>` / `resetViewport` | 锁定 / 恢复设备分辨率(像素对齐用) | 否 |
| `goto <route> [args]` | **程序化跳转**到任意路由 | **是** |
| `reset` | navigator pop 回根 | **是** |
| `health` | SDK 探针 | **是** |

> 一句话:**截图 + 热重载开箱即用,不碰 SDK;只有要让 AI 自己跳页面(`goto`/`reset`)才集成 SDK。** 导航**架构无关** —— Navigator 1.0 / GoRouter / GetX 都行,路由也**无需预先注册**。

## 怎么用

### 最常见的循环:人工导航 + AI 改码迭代

**AI `run` 起 app → 人工把界面点到目标页 → AI 改 Dart → AI `reload` → AI `screenshot` 看效果 → 再改。** 这条闭环里 AI 不碰导航(你来点),只用 `run` + `reload` + `screenshot`,**完全不需要 SDK**。

要让 AI 连导航也接管(全自动跳页),再集成 SDK(见下节)解锁 `goto`。

### 快速上手(5 分钟)

**前置**:Flutter 3.24+、Android 真机(开 USB 调试)或模拟器、`adb` 在 PATH。

```bash
# 克隆并给示例 app 补齐 Android 脚手架(不改动已有文件)
git clone https://github.com/MySwallow/flutterwright.git
cd flutterwright/packages/example
flutter create . --platforms=android --org com.example.flutterwright
flutter pub get
```

然后在任意 Claude Code 会话里(skill 在仓库的 `skills/flutter-wright/`),cwd 切到 `packages/example`,跑这条**无需 SDK** 的闭环:

```
Skill flutter-wright "run lib/main.dart"            # 起 app(lib/main.dart 是零 SDK 的生产入口)
Skill flutter-wright "screenshot $CLAUDE_JOB_DIR/before.png"
#  …改 lib/ 里的代码…
Skill flutter-wright "reload"                       # 热重载,改动立即生效
Skill flutter-wright "screenshot $CLAUDE_JOB_DIR/after.png"
Skill flutter-wright "stop"
```

集成了 SDK 后,换成集成入口 `dev/main_dev.dart`,额外可让 AI 程序化跳页:

```
Skill flutter-wright "run dev/main_dev.dart"
Skill flutter-wright "goto /order/detail args={\"id\":\"ORD-001\"}"   # 设备跳到订单详情
Skill flutter-wright "screenshot $CLAUDE_JOB_DIR/order.png"
Skill flutter-wright "reset"                                          # 回根
Skill flutter-wright "stop"
```

每个方法的签名、退出码、示例见 [`SKILL.md`](skills/flutter-wright/SKILL.md)。

## SDK 集成(可选)

**只要 AI 截图 + 热重载?跳过这节。** 用 skill 的 `run` 起 app 即可:reload 走它持有的 `flutter run` daemon、截图走 `adb screencap`,都不经 SDK。

**要让 AI 程序化跳页(`goto`/`reset`)** 才需要把 SDK 加进 app —— 核心就是 `await FlutterWright.start(...)` 加上把 navigator 让给它。推荐放进 **`dev_dependencies`** + 一个独立的 `dev/main_dev.dart` 入口,让生产 `lib/` 对 SDK 零引用、release 零残留(`packages/example` 就是这么组织的)。

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

- **不经 SDK 的方法**(`run`/`reload`/`stop`/`screenshot`/`setViewport`):`run` 起一个 `flutter run --machine` daemon 并持有,`reload` 给它发 `app.restart` 热重载;截图走 `adb screencap`、视口走 `adb shell wm`。
- **需要 SDK 的方法**(`goto`/`reset`/`health`):app 集成 SDK 后 debug 下在 `127.0.0.1:9123` 开 HTTP 服务,bash 脚本经 `adb forward` + `curl` 把命令发进去由 app 执行(上图就是这条路径)。release 构建里 SDK 是 no-op,不绑 socket、不暴露任何东西。

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
