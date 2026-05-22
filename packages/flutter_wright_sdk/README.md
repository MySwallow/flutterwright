# flutter_wright_sdk

> 作为 [flutter-wright](../../README.md) monorepo 的一部分发布。

为 Flutter app 提供的"仅 debug 启用"的 嵌入 app 的 HTTP 服务。给配套的
[`flutter-wright`](../../skills/flutter-wright/SKILL.md) Claude Code skill 用,
但任何能讲 HTTP 的客户端(curl、Postman、你自己的脚本)都能调。

> **Release 构建里这个包是 no-op。** `start()` 直接返回,不绑任何 socket。可以放心留在生产代码里。

## 安装

```yaml
dependencies:
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
```

## 集成(3 行)

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

// 启动时注册"可被发现"的路由:
FlutterWright.routes.register('/home');
FlutterWright.routes.register('/order/detail');
```

或者启动时一次传入:

```dart
await FlutterWright.start(
  testRoutes: const ['/home', '/login', '/order/detail'],
);
```

## 接入 Mock 数据

```dart
final mock = InMemoryMockDataProvider();
mock.set('user', {'name': 'Alice'});

await FlutterWright.start(mockProvider: mock);

// 在你的 repository 里:
class UserRepo {
  UserRepo(this._mock);
  final MockDataProvider _mock;

  Future<User> fetch() async {
    if (_mock.enabled) {
      return User.fromJson(_mock.get('user') as Map<String, dynamic>);
    }
    return realApiCall();
  }
}
```

## HTTP API

| 方法   | 路径        | Body                                                          | Response                          |
|--------|-------------|---------------------------------------------------------------|-----------------------------------|
| GET    | /health     | —                                                             | `{"ok":true,"version":"..."}`     |
| GET    | /routes     | —                                                             | `{"ok":true,"routes":[...]}`      |
| POST   | /navigate   | `{"route":"/x","args":{...},"popUntilRoot":true}`             | `{"ok":true,"route":"/x"}`        |
| POST   | /reset      | `{"clearMock":true}`                                          | `{"ok":true,"clearedMock":true}`  |
| POST   | /mock       | `{"action":"set"\|"get"\|"reset"\|"enable"\|"list","key":"k","value":...,"enabled":true}` | 依 action 不同 |
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
