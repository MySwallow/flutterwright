# 集成指南

把 `flutter_wright_sdk` 接入到真实 Flutter app 的详细模式 — 包括 mock 数据分层、GoRouter、BLoC/Riverpod、真实 API 切换。

> **让 AI 助手做集成?** 用同名 AI 专用版本 [`integration-guide-for-ai.md`](./integration-guide-for-ai.md) — 指令式 + 决策树 + 检测/验证步骤,AI 不容易在模糊地带走偏。

## 1. 添加依赖

发布到 pub.dev 之前,通过 git 依赖:

```yaml
# your_app/pubspec.yaml
dependencies:
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
```

如果你 vendor 了一份本地拷贝,也可以用 `path:`:

```yaml
dependencies:
  flutter_wright_sdk:
    path: ../flutter_wright/packages/flutter_wright_sdk
```

## 2. 连接 `main()`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // (a) 启动 SDK — release 构建自动跳过
  await FlutterWright.start(
    testRoutes: const ['/home', '/login', '/order/detail'],
  );

  // (b) 用 FlutterWrightRoot 包根,/screenshot 才能可靠工作
  runApp(FlutterWrightRoot(child: const MyApp()));
}
```

如果你不方便用 `FlutterWrightRoot`(比如有自定义 binding 初始化),那就忽略 `/screenshot` endpoint,让 skill 一直走 `adb screencap` — 在 Android 上这反而是更优选择,因为它能截到完整设备帧。

## 3. 把 navigator 让出来

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FlutterWright.navigatorKey,
      onGenerateRoute: appRouter,
    );
  }
}
```

> 为什么要共享 `navigatorKey`? `Navigator.of(context)` 需要 context。SDK 的 HTTP handler 没有 context。`GlobalKey<NavigatorState>` 绕开这个限制。

## 4. 注册路由(可选但推荐)

```dart
// 启动时一次性传入:
await FlutterWright.start(
  testRoutes: const ['/home', '/order/detail', '/login'],
);

// 或之后任何时候:
FlutterWright.routes.register('/cart');
```

注册的路由会出现在 `GET /routes` 里供 skill 发现。未注册的路由仍然能被 `/navigate` push — 注册关乎"可发现性",不是"准入控制"。

## 5. Mock 数据分层

SDK 不规定 mock 数据放哪。一种典型模式:

```dart
// services/user_repo.dart
class UserRepo {
  UserRepo({MockDataProvider? mock}) : _mock = mock;
  final MockDataProvider? _mock;

  Future<User> fetch(String id) async {
    if (_mock?.enabled == true) {
      final raw = _mock!.get('user.$id') as Map<String, Object?>?;
      if (raw != null) return User.fromJson(raw);
    }
    return _httpFetch(id);
  }

  Future<User> _httpFetch(String id) async {
    // 真实网络调用
  }
}
```

接入 SDK:

```dart
final mock = InMemoryMockDataProvider()
  ..set('user.U1', {'id': 'U1', 'name': 'Alice'});

await FlutterWright.start(mockProvider: mock);

final userRepo = UserRepo(mock: mock);
// 用你的 DI(provider / get_it / Riverpod)注入 userRepo ...
```

Skill 通过 `POST /mock` 切换 mock 状态:

```bash
# 关掉 mock 走真实 API
curl -X POST localhost:9123/mock -d '{"action":"enable","enabled":false}'

# 注入不同 fixture
curl -X POST localhost:9123/mock \
  -d '{"action":"set","key":"user.U1","value":{"id":"U1","name":"Bob"}}'
```

## 6. GoRouter 集成

`navigatorKey` 通过 `GoRouter.navigatorKey` 与 GoRouter 协作:

```dart
final router = GoRouter(
  navigatorKey: FlutterWright.navigatorKey,
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(path: '/order/:id', builder: (_, st) => OrderPage(id: st.pathParameters['id']!)),
  ],
);

runApp(MaterialApp.router(routerConfig: router));
```

对于带命名的 GoRouter 路由,有两种选择:

1. 用 URL 风格的 path 作为路由名:
   `POST /navigate {"route":"/order/123"}`。SDK 调 `pushNamed`,GoRouter 解析 URL。

2. 自己桥接一层 — 最简单是包一层自己的 `pushNamed`,基于前缀 dispatch 到 `GoRouter.go(...)`。

## 7. 真实 API 模式 + 鉴权 token

当 skill 关闭 mock 想跑真实 API,通常需要有效的 auth token。两种模式:

**模式 A — 把测试 token 烧进 debug:**
```dart
const debugAuthToken = String.fromEnvironment('TEST_AUTH_TOKEN');
flutter run --dart-define=TEST_AUTH_TOKEN=eyJ...
```

**模式 B — 通过 /mock 注入:**
```bash
curl -X POST localhost:9123/mock \
  -d '{"action":"set","key":"auth.token","value":"eyJ..."}'
```

你的 auth 拦截器在 `mock.enabled == false` 但 key 存在时,优先读 `mock.get('auth.token')`。代价是一点 mock 数据耦合,换来"循环里也能持续打真实 API"。

## 8. 在 profile/release 里禁用 SDK

默认 `enableInDebugOnly: true` 已经做了。如果你想在 profile 构建里也开(给 QA 用):

```dart
await FlutterWright.start(
  config: const FlutterWrightConfig(enableInDebugOnly: false),
);
```

小心 — release+enabled 意味着生产包里 HTTP 端口是开着的。

## 9. 跟 CI / golden test 共存

这个 SDK 是给交互式循环用的,不是 unit/golden test。如果你两个都有:

- `flutter test` 跑在隔离进程里;SDK 的 `dart:io HttpServer` 能跑但跑了也没用。
- 用 `Platform.environment.containsKey('FLUTTER_TEST')` 跳过 bind:

```dart
import 'dart:io';

if (!Platform.environment.containsKey('FLUTTER_TEST')) {
  await FlutterWright.start();
}
```

## 10. 多 flavor app

不同 flavor(dev/staging/prod)需要不同 setup:

```dart
Future<void> mainDev() async {
  await FlutterWright.start(
    config: const FlutterWrightConfig(port: 9123),
    mockProvider: DemoMockProvider(),
  );
  runApp(MyApp());
}

Future<void> mainProd() async {
  // SDK 在 release 里是 no-op;你仍然可以调 start() — 它会立即返回。
  // 或者干脆跳过:
  runApp(MyApp());
}
```
