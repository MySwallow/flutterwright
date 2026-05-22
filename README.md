# FlutterWright

Playwright 风格的 Flutter 设备自动化，通过 Claude Code skill 实现，仅支持 Android。

一个 monorepo，包含：

- 一个 **Claude Code skill**（`skills/flutter-wright/`），暴露 8 个方法（goto / screenshot / reload / mock / setViewport / …），
- 一个 **Dart SDK**（`packages/flutter_wright_sdk/`），在任意 Flutter 应用内运行一个仅 debug 启用的 HTTP 控制平面，
- 一个 **示例 Flutter 应用**（`packages/example/`），展示 SDK 集成方式，
- **参考文档**（`docs/`）。

```
flutterwright/
├── skills/flutter-wright/    <- Claude Code skill (SKILL.md + scripts)
├── packages/
│   ├── flutter_wright_sdk/   <- Dart SDK
│   └── example/              <- demo Flutter app
├── docs/                     <- API ref / architecture / integration / troubleshooting
└── ...
```

> ## ⚠️ 重要：skill 和 SDK 必须配对工作
>
> `flutter-wright` skill 通过 HTTP 把跳转/截图/mock 等指令发到目标 Flutter app。**只有当目标 app 集成了 `flutter_wright_sdk` 并正在运行时，这些指令才会被接收和执行**。
>
> - 目标 app **未集成 SDK** → skill 调用永远是 `SDK unreachable`（连接被拒）。
> - 目标 app **已集成但未运行** → 同上。
> - SDK **正常运行** → skill 命令通过 `127.0.0.1:9123` 控制平面执行。
>
> 集成步骤见 [`docs/integration-guide.md`](docs/integration-guide.md)（人类版）或 [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md)（AI 版）。

## 快速上手（5 分钟）

### 前置条件

- Flutter 3.24+（`flutter doctor` 无报错）
- Android 真机（已开启 USB 调试）或 Android 模拟器
- `adb` 在 PATH 中（Android platform-tools）
- `curl`

### 1. 克隆并初始化示例应用

```bash
git clone https://github.com/MySwallow/flutterwright.git
cd flutterwright/packages/example
flutter create . --platforms=android --org com.example.flutterwright
flutter pub get
```

`flutter create .` 只会补齐 `android/` 脚手架，不会改动已存在的文件。

### 2. 运行示例应用（无需 fifo，直接 `flutter run`）

```bash
flutter run -d $(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
```

等待输出：

```
[flutter_wright_sdk] listening on http://127.0.0.1:9123
```

### 3. 转发端口并验证

```bash
adb forward tcp:9123 tcp:9123
curl http://localhost:9123/health
# → {"ok":true,"version":"0.2.0","service":"flutter_wright_sdk"}
```

### 4. 从 Claude Code 驱动应用

在一个 Claude Code 会话中（cwd 任意；skill 位于仓库内 `skills/flutter-wright/`）：

```
Skill flutter-wright "health"
Skill flutter-wright "goto /order/detail args={\"id\":\"ORD-001\"}"
Skill flutter-wright "screenshot $CLAUDE_JOB_DIR/cur.png"
```

完整方法参考见 [`skills/flutter-wright/SKILL.md`](skills/flutter-wright/SKILL.md)。

### 5. 将 SDK 集成进自己的 Flutter 应用

```dart
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(
    testRoutes: const ['/home', '/order/detail', '/login'],
  );
  runApp(FlutterWrightRoot(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FlutterWright.navigatorKey,
      onGenerateRoute: yourRouter,
    );
  }
}
```

完整集成模式（GoRouter、auth token、mock 分层、多 flavor）见 [`docs/integration-guide.md`](docs/integration-guide.md)。

**让 AI 助手来做集成？** 让它读面向 AI 的版本：[`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md) — 内容相同，但重组为决策树，配前置检查、精确代码块和验证步骤，避免助手跑偏。

## 文档

| 文档 | 内容 |
|---|---|
| [`skills/flutter-wright/SKILL.md`](skills/flutter-wright/SKILL.md) | 8 个方法（签名、退出码、示例） |
| [`docs/api-reference.md`](docs/api-reference.md) | SDK HTTP 协议 — 面向直接 curl 调用方与 SDK 贡献者 |
| [`docs/architecture.md`](docs/architecture.md) | 分层、组件、安全约束 |
| [`docs/integration-guide.md`](docs/integration-guide.md) | Dart 集成模式（10 种场景）— 面向人 |
| [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md) | **面向 AI** 的集成指南：前置检查、决策树、验证步骤 |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | 按症状分类的故障模式 + E2E 检查清单 |
| [`docs/superpowers/specs/`](docs/superpowers/specs/) | 设计规格（v1 + 未来） |

## 许可证

MIT — 见 [`LICENSE`](LICENSE)。
