# flutter_wright_sdk SDK 接入指引(AI 专用)

> **受众**:Claude / Cursor / Copilot 等 AI 编码助手。
> **任务**:把 `flutter_wright_sdk` SDK 集成到一个**已存在**的 Flutter app,使得它可被 `flutter_wright` skill 远程驱动。
>
> 给人类看的版本在 [`integration-guide.md`](./integration-guide.md)。

## 0. 阅读须知(给 AI)

执行规则:

1. **按顺序执行每个 Step**;每个 Step 都给出了"检测"(决定走哪条路径)和"验证"(做完后应该看到的产物)。
2. **不要发明额外抽象**。SDK 已经管理了 server / handler / mock,你只负责接线。
3. **不要加 try/catch 包 `FlutterWright.start(...)`**。它在 release 模式下是 no-op,debug 模式下失败应该让 app crash(暴露问题,而不是悄悄静默)。
4. **不要把 SDK 加进 `dependencies:`** 如果它本应在 `dev_dependencies:`(看 Step 1 决策)。
5. **如果检测发现与本指引矛盾的既有代码**(例:已有 `navigatorKey` 用于别的用途),**停下**,把发现报告给人类后再继续。

## 1. 前置检测(必须先全部跑完)

跑下面每条命令,把结果记下来 — 后续 Step 会基于它分流。

| 检测项 | 命令 | 影响 |
|---|---|---|
| ① 是否已接入 | `grep -l flutter_wright_sdk pubspec.yaml` | 已接入 → 跳到 Step 7 验证 |
| ② 入口文件 | `find lib -maxdepth 2 -name 'main*.dart'` | 决定 Step 2/3 编辑哪个文件 |
| ③ Flutter 版本 | `flutter --version` 或读 `pubspec.yaml` 的 `environment.flutter` | 必须 ≥ 3.24.0(SDK 要求) |
| ④ App 形态 | `grep -nE 'MaterialApp\.router\|MaterialApp\(\|CupertinoApp\|GetMaterialApp' lib/main.dart lib/app.dart 2>/dev/null` | 决定 Step 3 用模板 A/B/C |
| ⑤ 路由方案 | `grep -nE 'GoRouter\|AutoRoute\|Beamer\|fluro' lib/ -r 2>/dev/null` | 影响 Step 3 + Step 4 |
| ⑥ navigatorKey 占用 | `grep -nE 'navigatorKey[: ]\s*=\|GlobalKey<NavigatorState>' lib/ -r 2>/dev/null` | 若已占用 → 报告人类决策 |
| ⑦ Mock 层是否存在 | `grep -nirE 'class.*MockProvider\|fakeApi\|stub.*repo' lib/ 2>/dev/null` | 决定 Step 5 是否需要做 |
| ⑧ 端口 9123 是否被占 | 检查 host app 的网络配置,确保没有别的服务用 9123 | 冲突 → 改 SDK 配置 |

**报告格式**(集成开始前先输出给人类):

```
Pre-check 报告:
  ① 已接入 SDK: <yes/no>
  ② 入口文件: <path>
  ③ Flutter 版本: <version>
  ④ App 形态: <MaterialApp / MaterialApp.router / CupertinoApp / GetMaterialApp / 其他>
  ⑤ 路由方案: <Navigator-1 / Navigator-2 / GoRouter / 其他>
  ⑥ navigatorKey 占用: <文件:行号 或 无>
  ⑦ Mock 层: <已有 / 无>
  ⑧ 端口 9123: <空闲 / 占用>
```

若 ① yes → 直接跳到 [Step 7 验证](#step-7-验证)。否则继续 Step 2。

## 2. Step 1:加依赖

**编辑** `pubspec.yaml`,在 `dependencies:` 节点下加(**不是** `dev_dependencies` — SDK 在 release 里会自降为 no-op,且生产代码会引用 `FlutterWright.navigatorKey`):

```yaml
dependencies:
  flutter:
    sdk: flutter
  # ... 既有依赖 ...
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
      ref: main
```

**运行**:`flutter pub get`
**验证**:命令退出 0,`pubspec.lock` 出现 `flutter_wright_sdk` 条目。

⚠️ **如果项目用 monorepo 或 melos**:把 SDK 路径声明也加到 `melos.yaml` / 父级 `pubspec.yaml` 的 `packages:` 列表里(若适用)。否则跳过。

## 3. Step 2:在 main() 启动 SDK

**编辑** Step 1 检测出的入口文件(通常 `lib/main.dart`)。

定位 `void main()` / `Future<void> main()`,改造为以下结构:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';
// ... 既有 imports ...

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // flutter_wright_sdk: debug 启用,release 自动 no-op
  await FlutterWright.start(
    testRoutes: const [
      // TODO: 写入此 app 的已知路由,后续 skill 通过 GET /routes 发现
      '/',
    ],
  );

  runApp(const MyApp());  // 保留原有 runApp 调用
}
```

**规则**:
- 如原 `main` 是同步的 `void main() { runApp(...); }`,改为 `Future<void> main() async { ... }`。
- 如原 `main` 已有其他异步 init(Firebase、DI、SharedPreferences),`FlutterWright.start` 放在**它们之后**,`runApp` **之前**。
- 不要把 `start` 包进 `if (kDebugMode)` — SDK 内部已经判断,重复判断只会让代码更乱。

**验证**:
1. `flutter analyze lib/main.dart` 退出 0(无 import 缺失、无类型错)。
2. `grep -c FlutterWright.start lib/main.dart` 输出 `1`(不能调用两次)。

## 4. Step 3:共享 navigatorKey

基于 pre-check ④/⑤ 选模板。

### 模板 A — `MaterialApp(...)` + onGenerateRoute

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FlutterWright.navigatorKey,  // ← 加这行
      onGenerateRoute: appRouter,  // 既有
      // ... 其他既有参数 ...
    );
  }
}
```

### 模板 B — `MaterialApp.router(...)` + GoRouter

把 `navigatorKey` 移到 `GoRouter`,**不要**同时设在 `MaterialApp.router` 上(GoRouter 自己接管 root navigator)。

```dart
final _router = GoRouter(
  navigatorKey: FlutterWright.navigatorKey,  // ← 加这行
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    // ... 既有路由 ...
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      // 不要在这里设 navigatorKey
    );
  }
}
```

### 模板 C — `CupertinoApp(...)`

跟模板 A 一样,把 `navigatorKey: FlutterWright.navigatorKey` 加到 `CupertinoApp(...)`。

### 模板 D — `GetMaterialApp`(GetX)

```dart
return GetMaterialApp(
  navigatorKey: FlutterWright.navigatorKey,  // ← 加这行,与 GetX 的 Get.key 不同
  // ...
);
```

但 GetX 自己有 `Get.key`,可能需要把 `Get.key = FlutterWright.navigatorKey;` 加到 `main()` 里(在 `runApp` 前)。

### 冲突处理

如 pre-check ⑥ 发现已有 `navigatorKey`(比如已声明为顶层 `final navigatorKey = GlobalKey<NavigatorState>();`):

**不要**直接覆盖。改为:

```dart
// 把原来的:
// final navigatorKey = GlobalKey<NavigatorState>();
// 改为:
final navigatorKey = FlutterWright.navigatorKey;
```

这样既有代码引用 `navigatorKey` 仍然成立,SDK 也拿到了同一个 key。

**验证**:
1. `grep -nE 'navigatorKey[:\s]+FlutterWright\.navigatorKey\|FlutterWright\.navigatorKey' lib/ -r` 至少 1 个匹配。
2. `flutter analyze lib/` 退出 0。

## 5. Step 4:注册路由(可选但强烈推荐)

让 skill 通过 `GET /routes` 发现 app 有哪些可被驱动的路由。

**首选**:在 `FlutterWright.start(testRoutes: [...])` 里一次性传入(已在 Step 2 完成)。

**也支持运行时注册**(如路由是动态生成的):

```dart
// 任何在 start() 之后的代码点:
FlutterWright.routes.register('/order/detail');
FlutterWright.routes.register('/cart');
```

**收集路由的查找命令**:

```bash
# GoRouter
grep -oE "GoRoute\(\s*path:\s*'[^']+" lib/ -r | grep -oE "'[^']+$" | tr -d "'" | sort -u

# Navigator-1 onGenerateRoute case
grep -oE "case\s*'[^']+'" lib/ -r | grep -oE "'[^']+'" | tr -d "'" | sort -u
```

把输出的路由数组手工(或脚本)填进 `testRoutes:`。

**验证**:`testRoutes` 数组里至少含 1 个真实路由(不是 placeholder `/`)。

## 6. Step 5:Mock 数据接入(条件性)

**仅当 pre-check ⑦ 显示 app 没有 mock 层、且人类要求 "skill 能控 mock 数据"时**做这步。否则跳过。

### 5.1 创建 mock provider 字段

`flutter_wright_sdk` 自带 `InMemoryMockDataProvider`。直接用:

```dart
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

// 顶层 final(或放到你的 DI 容器里):
final _mock = InMemoryMockDataProvider();
```

### 5.2 传给 SDK + 暴露给 repo 层

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterWright.start(
    mockProvider: _mock,  // ← 加这个参数
    testRoutes: const ['/', /* ... */],
  );

  runApp(MyApp(mock: _mock));
}
```

### 5.3 在 Repository 层读 mock

**典型 mock-aware repository 模式**:

```dart
class UserRepo {
  UserRepo({MockDataProvider? mock, required HttpClient http})
      : _mock = mock,
        _http = http;

  final MockDataProvider? _mock;
  final HttpClient _http;

  Future<User> fetch(String id) async {
    // mock.enabled 由 skill 通过 POST /mock {action:enable} 控制
    if (_mock?.enabled == true) {
      final raw = _mock!.get('user.$id') as Map<String, Object?>?;
      if (raw != null) return User.fromJson(raw);
    }
    return _httpFetch(id);
  }

  Future<User> _httpFetch(String id) async { /* 既有真实网络代码 */ }
}
```

### 5.4 在 DI 容器里注入

| DI 方案 | 注入位置 |
|---|---|
| Provider | `Provider.value(value: _mock)` |
| Riverpod | `final mockProvider = Provider<MockDataProvider>((ref) => _mock);` |
| get_it | `GetIt.I.registerSingleton<MockDataProvider>(_mock);` |
| 手 prop drilling | `MyApp(mock: _mock)` 然后下传 |

**验证**:`grep -rn 'MockDataProvider' lib/` 至少 2 个匹配(SDK 注入处 + 至少 1 个 repo 读取处)。

## 7. Step 6:Android 平台要求

flutter_wright v1 是 **Android-only**。检查 `android/app/build.gradle` 的 `minSdkVersion` ≥ 21(已是 Flutter 默认)。

**不需要**改 `AndroidManifest.xml`:HTTP server 绑在 `127.0.0.1`(loopback),不需要 `INTERNET` permission(虽然多数 app 已有)。

**iOS**:SDK 代码能编但 flutter_wright v1 不驱动 iOS。若 host app 同时跑 iOS,不影响。

## 8. Step 7:验证

按顺序跑下面 4 个检查,任何一条不过都停下来报错。

### 7.1 编译通过

```bash
flutter analyze
# 期望:0 issues
```

### 7.2 启动 app 看 banner

```bash
flutter run -d <android_device_or_emulator>
# 期望日志:
#   [flutter_wright_sdk] listening on http://127.0.0.1:9123
```

如未看到该 banner,说明 SDK 没启动 — 检查:
- Step 2 的 `await FlutterWright.start(...)` 是否真在 `main` 里、`runApp` 之前
- 是不是 release/profile 构建(SDK 自动 no-op)
- `kDebugMode` 是否为 true

### 7.3 端口转发 + 健康检查

```bash
adb forward tcp:9123 tcp:9123
curl -s http://127.0.0.1:9123/health
# 期望:{"ok":true,"version":"0.2.0"}
```

### 7.4 路由可发现

```bash
curl -s http://127.0.0.1:9123/routes
# 期望:{"ok":true,"routes":["/","/order/detail", ...]}  ← 含 Step 2 注册的路由
```

### 7.5(可选,有 mock)Mock 流路

```bash
curl -s -X POST http://127.0.0.1:9123/mock \
  -H 'content-type: application/json' \
  -d '{"action":"set","key":"user.U1","value":{"id":"U1","name":"Alice"}}'
# 期望:{"ok":true,"key":"user.U1"}

curl -s -X POST http://127.0.0.1:9123/mock \
  -H 'content-type: application/json' \
  -d '{"action":"get","key":"user.U1"}'
# 期望:{"ok":true,"key":"user.U1","value":{"id":"U1","name":"Alice"}}
```

## 9. 必须避免的常见错误

| 错误 | 为什么是错的 | 正确做法 |
|---|---|---|
| ❌ 把 `FlutterWright` 调用包进 `try/catch` | 隐藏问题,debug 模式下应崩溃以暴露集成 bug | 不要包,让 app 直接 crash |
| ❌ 在 `start()` 之前调 `bind()` | 抛 `StateError` | 必须先 `start()` |
| ❌ 重复声明 `GlobalKey<NavigatorState>` | 多个 key 会让一个 navigator 失效 | 复用 `FlutterWright.navigatorKey` |
| ❌ 把 `enableInDebugOnly: false` 设到 release | 生产包开 HTTP 端口 = 安全风险 | 默认值就是对的,**不要**改 |
| ❌ 在 `GoRouter` + `MaterialApp.router` 上**同时**设 `navigatorKey` | GoRouter 自己接管 root navigator,双 key 报错 | 只在 `GoRouter(...)` 上设 |
| ❌ 把 SDK 加到 `dev_dependencies` | 生产代码引用 `FlutterWright.navigatorKey` 会编译失败 | 必须 `dependencies` |
| ❌ 改 SDK package 名 / 用 path 但忘了写 `pubspec_overrides.yaml` | Dart pub 解析失败 | 按 Step 1 的 git 依赖写法 |
| ❌ 在 `flutter_test` 里调 `start()` 不跳过 | 测试进程绑 9123 端口跟主 app 冲突 | 用 `Platform.environment.containsKey('FLUTTER_TEST')` 守卫(参考人类版指引 §9) |
| ❌ skill 调用前忘了 `adb forward tcp:9123 tcp:9123` | curl 全部 connection refused | flutter_wright skill 自动做了,但手动 curl 调试时记得 |

## 10. 失败排查 recipe

| 现象 | grep / 命令 | 含义 |
|---|---|---|
| `flutter analyze` 报 `FlutterWright is not defined` | `grep flutter_wright_sdk pubspec.yaml` 无输出 | Step 1 没做或 `pub get` 失败 |
| 启动后看不到 listening banner | `grep FlutterWright.start lib/main.dart` 应为 1 | Step 2 漏了 |
| `curl /navigate` 永远 503 "navigator not ready" | `grep navigatorKey lib/ -r` 看是不是没接 `FlutterWright.navigatorKey` | Step 3 漏了 |
| `curl /mock` 返回 501 "no MockDataProvider" | 看 `start(mockProvider: ...)` 是否传了 | Step 5.2 漏了 |
| `flutter run` 时 `bind: address already in use` | `lsof -i :9123` 在主机侧 / `netstat` 在设备侧 | 改 SDK config 的 `port` 或杀冲突进程 |
| GoRouter 报 `Multiple navigatorKeys` | `grep -nE 'navigatorKey[:\s]' lib/ -r` 应只有 1 个赋值点 | Step 3 模板 B 没遵守 |

## 11. 完成报告模板

接入完成后,把下面这段给人类(填实际值):

```
✅ flutter_wright_sdk 已接入 <app-name>

变更文件:
  - pubspec.yaml(加 flutter_wright_sdk 依赖)
  - lib/main.dart(加 FlutterWright.start + 共享 navigatorKey)
  - <其他文件,如 mock 注入处>

注册路由:
  - /
  - /home
  - /order/detail
  ...

Mock 数据接入:<yes / no>

验证结果:
  [✓] flutter analyze 0 issues
  [✓] 看到 banner: [flutter_wright_sdk] listening on http://127.0.0.1:9123
  [✓] GET /health → 200 {"ok":true,"version":"0.2.0"}
  [✓] GET /routes → 包含 N 条路由
  [✓] POST /mock(若适用) → 200

下一步:
  - 在 Claude Code 里运行 `Skill flutter_wright "health"` 验证 skill 端
  - 跑业务流: `Skill flutter_wright "goto /home"` 等
```

---

**版本对照**:本指引基于 `flutter_wright_sdk 0.2.0`。SDK 升级后 API 不兼容时,Step 2-5 的代码片段会跟着改。
