# flutter_wright_sdk

> 作为 [flutter-wright](../../README.md) monorepo 的一部分发布。

为 Flutter app 提供的"仅 debug 启用"的 嵌入 app 的 HTTP 服务。给配套的
[`flutter-wright`](../../skills/flutter-wright/SKILL.md) Claude Code skill 用,
但任何能讲 HTTP 的客户端(curl、Postman、你自己的脚本)都能调。

> **Release 构建里这个包是 no-op。** `start()` 直接返回,不绑任何 socket。可以放心留在生产代码里。

## 安装

推荐放 `dev_dependencies`(配合独立 debug 入口,生产 `lib/` 零 SDK 引用、release 零残留):

```yaml
dev_dependencies:
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
```

> 图省事也可放 `dependencies` 直接在 `lib/main.dart` 里 import —— release 是 no-op,但 SDK 仍被编进生产包。两种范式详见 [`docs/integration-guide.md`](../../docs/integration-guide.md);`packages/example` 已按 dev_dependencies 范式组织。

## 集成(3 行,图省事路径)

```dart
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start();                  // 1. 启动控制 server(仅 debug)
  runApp(FlutterWrightRoot(child: const MyApp()));     // 2. 让 /screenshot 可用
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FlutterWright.navigatorKey, // 3. 把 navigator 让出来
      onGenerateRoute: appRouter,
    );
  }
}

// 可选:传入路由名列表,让 GET /routes 可发现
await FlutterWright.start(routes: appRoutes.keys);
```

## 不同路由架构(GoRouter / GetX)

第 3 步的 `navigatorKey` 只适用 Navigator 1.0 命名路由。其它栈给 `start()` 传 `CallbackNavigationAdapter`,SDK 只回调你的闭包:

```dart
// GoRouter(附 routesProvider,让 GET /routes 可发现)
await FlutterWright.start(navigationAdapter: CallbackNavigationAdapter(
  onNavigate: (route, args, _) => router.go(route, extra: args),
  onReset: () => router.go('/'),
  routesProvider: () => goRouterPaths(router.configuration.routes),
));

// GetX
await FlutterWright.start(navigationAdapter: CallbackNavigationAdapter(
  onNavigate: (route, args, _) => Get.toNamed(route, arguments: args),
  onReset: () => Get.until((r) => r.isFirst),
  routesProvider: () => getPages.map((p) => p.name),
));
```

## HTTP API

| 方法   | 路径        | Body                                                          | Response                          |
|--------|-------------|---------------------------------------------------------------|-----------------------------------|
| GET    | /health     | —                                                             | `{"ok":true,"version":"..."}`     |
| GET    | /routes     | —                                                             | `{"ok":true,"routes":[...]}`      |
| POST   | /navigate   | `{"route":"/x","args":{...},"popUntilRoot":true}`             | `{"ok":true,"route":"/x"}`        |
| POST   | /reset      | `{}`                                                          | `{"ok":true}`                     |
| GET    | /screenshot | —                                                             | `image/png` 字节(mode=flutter 时) |

所有错误响应统一格式:`{"ok":false,"error":"..."}`。

## 从笔记本连(Android 设备)

```bash
adb forward tcp:9123 tcp:9123
curl http://localhost:9123/health
curl -X POST http://localhost:9123/navigate \
  -H 'content-type: application/json' \
  -d '{"route":"/order/detail","args":{"id":"ORD-001"}}'
```

## 配置

```dart
await FlutterWright.start(
  config: const FlutterWrightConfig(
    host: '127.0.0.1',                    // 真实 app 里别用 0.0.0.0
    port: 9123,
    enableInDebugOnly: true,              // false 时 profile 也启
    autoStart: true,
    screenshotMode: ScreenshotMode.flutter, // 或 .external(让 adb 截)
    maxBodyBytes: 1024 * 1024,
  ),
);
```
