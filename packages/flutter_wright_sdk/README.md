# flutter_wright_sdk

> 作为 [flutter-wright](../../README.md) monorepo 的一部分发布。

嵌进 Flutter app 的 HTTP 控制服务,默认关闭(`enabled: false`),仅在宿主显式传
`enabled: true` 时绑定——是否启用由宿主决定(常见 `enabled: kDebugMode`,提测 release
包用 `enabled: AppEnv.isTestBuild`)。给配套的
[`flutter-wright`](../../skills/flutter-wright/SKILL.md) Claude Code skill 用,
但任何能讲 HTTP 的客户端(curl、Postman、你自己的脚本)都能调。

> **`enabled` 默认 `false`；不传或传 `enabled: kDebugMode` 时,release 下 `start()` 是 no-op、不绑 socket。**
> 启用与否由调用方控制(非 SDK 自动识别构建类型);正式包让判断为 `false` 即彻底关闭。可以放心留在生产代码里。
> release 提测包可用 `enabled: AppEnv.isTestBuild` 之类自有判断启用。

## 安装

推荐放 `dev_dependencies`(配合独立 debug 入口,生产 `lib/` 零 SDK 引用、release 零残留):

```yaml
dev_dependencies:
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
```

> 图省事也可放 `dependencies` 直接在 `lib/main.dart` 里 import —— 传 `enabled: kDebugMode` 时 release 下为 no-op,但 SDK 仍被编进生产包。两种范式详见 [`docs/integration-guide.md`](../../docs/integration-guide.md);`packages/example` 已按 dev_dependencies 范式组织。

## 集成(3 行,图省事路径)

```dart
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(enabled: kDebugMode); // 1. 启动控制 server(debug 为 true;release 为 false → no-op)
  runApp(FlutterWrightRoot(child: const MyApp()));     // 2. 让 /screenshot 可用
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FlutterWright.navigatorKey, // 3.(可选)把 navigator 让出来
      onGenerateRoute: appRouter,
    );
  }
}

// 可选:传入路由名列表,让 GET /routes 可发现
await FlutterWright.start(enabled: kDebugMode, routes: appRoutes.keys);
```

> 第 3 步是**可选**的:仅当需要 `/navigate`、`/reset`、`/routes` 时才让出 `navigatorKey`(或给 `start()` 传 `navigationAdapter`)。
> `start()` 不传 `navigatorKey`/`navigationAdapter` 时,这三个端点返回 `501`;交互层(`/snapshot`、`/tap`、`/type` 等)照常可用。

## 不同路由架构(GoRouter / GetX)

第 3 步的 `navigatorKey` 只适用 Navigator 1.0 命名路由。其它栈给 `start()` 传 `CallbackNavigationAdapter`,SDK 只回调你的闭包:

```dart
// GoRouter(附 routesProvider,让 GET /routes 可发现)
await FlutterWright.start(
  enabled: kDebugMode, // debug 为 true;release 为 false → no-op
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (route, args, _) => router.go(route, extra: args),
    onReset: () => router.go('/'),
    routesProvider: () => goRouterPaths(router.configuration.routes),
  ),
);

// GetX
await FlutterWright.start(
  enabled: kDebugMode,
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (route, args, _) => Get.toNamed(route, arguments: args),
    onReset: () => Get.until((r) => r.isFirst),
    routesProvider: () => getPages.map((p) => p.name),
  ),
);
```

## HTTP API

| 方法   | 路径         | Body                                                          | Response                          |
|--------|--------------|---------------------------------------------------------------|-----------------------------------|
| GET    | /health      | —                                                             | `{"ok":true,"service":"flutter_wright_sdk","version":"0.8.0","name":null,"package":null}` |
| GET    | /routes      | —                                                             | `{"ok":true,"routes":[...]}`      |
| GET    | /snapshot    | —                                                             | `{"ok":true,"snapshot":...}`(带 `[ref=sN]`) |
| GET    | /wait_for    | `?text=...` 等查询参数                                        | `{"ok":true,...}`                 |
| POST   | /navigate    | `{"route":"/x","args":{...},"popUntilRoot":true}`             | `{"ok":true,"route":"/x"}`        |
| POST   | /reset       | `{}`                                                          | `{"ok":true}`                     |
| POST   | /tap         | `{"element":"...","ref":"sN"}`                               | `{"ok":true,"snapshot":...}`      |
| POST   | /long_press  | `{"element":"...","ref":"sN"}`                               | `{"ok":true,"snapshot":...}`      |
| POST   | /scroll      | `{"element":"...","ref":"sN",...}`                           | `{"ok":true,"snapshot":...}`      |
| POST   | /type        | `{"element":"...","ref":"sN","text":"..."}`                 | `{"ok":true,"snapshot":...}`      |
| GET    | /screenshot  | —                                                             | `image/png` 字节(mode=flutter 时) |

动作端点(`/tap`、`/long_press`、`/scroll`、`/type`,以及 `/wait_for` 等)请求体含 `element`(可读标签,便于审计)+ `ref`(目标 ref),成功响应自动回吐最新 `snapshot`,省去再单独调一次 `/snapshot`。

`/health` 响应五键恒为 `ok` / `service`(值恒为 `flutter_wright_sdk`)/ `version` / `name` / `package`;其中 `name`、`package` 由 `start()` 的 `appName`、`package` 参数传入,用于多目标探活(没传则为 `null`)。`/health` 免鉴权。

所有错误响应统一格式:`{"ok":false,"error":"..."}`。

### snapshot-first 工作法

交互层(`/snapshot` `/tap` `/long_press` `/scroll` `/type` `/wait_for`)为 0.7.0 新增。先 `GET /snapshot` 拿到带 `[ref=sN]` 标记的语义树,从中挑出目标元素的 `ref`,再把 `ref` 喂给动作端点。`ref` 是临时句柄,页面一变(导航、列表刷新、重建)即失效——每次交互前重新取 snapshot,不要跨页面复用旧 `ref`。

## 鉴权(可选)

给 `start()` 传 `token:` 即开启鉴权:除 `GET /health` 外所有端点都校验 `X-FW-Token` 请求头,缺失或不匹配返回 `401`。`token` 为空/`null` 时不鉴权(此时仅靠 loopback 绑定保护)。

`token` 只从环境变量 / 本地配置读取,**不要写进仓库**:

```dart
await FlutterWright.start(
  enabled: kDebugMode,
  token: const String.fromEnvironment('FW_TOKEN'),
);
```

调用时带上头:

```bash
curl http://localhost:9123/snapshot -H "X-FW-Token: <token>"
```

## 从笔记本连(Android 设备)

```bash
adb forward tcp:9123 tcp:9123
curl http://localhost:9123/health
curl -X POST http://localhost:9123/navigate \
  -H 'content-type: application/json' \
  -H "X-FW-Token: <token>" \
  -d '{"route":"/order/detail","args":{"id":"ORD-001"}}'
```

## 配置

```dart
await FlutterWright.start(
  enabled: kDebugMode, // debug 为 true;release 为 false → no-op
  // 以下三个是 start() 的顶层参数,不在 FlutterWrightConfig 内:
  token: const String.fromEnvironment('FW_TOKEN'), // 从 env 读,不进仓库
  appName: 'MyApp',                                 // 写进 /health 的 name
  package: 'com.example.myapp',                     // 写进 /health 的 package
  config: const FlutterWrightConfig(
    host: '127.0.0.1',                    // 真实 app 里别用 0.0.0.0
    port: 9123,
    autoStart: true,
    screenshotMode: ScreenshotMode.flutter, // 或 .external(让 adb 截)
    maxBodyBytes: 1024 * 1024,
  ),
);
```
