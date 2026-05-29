# 集成指南

把 `flutter_wright_sdk` 接入到真实 Flutter app 的详细模式:dev_dependencies 范式、不同路由架构(Navigator 1.0 / GoRouter / GetX)、多 flavor。

> **让 AI 助手做集成?** 用同名 AI 专用版本 [`integration-guide-for-ai.md`](./integration-guide-for-ai.md) — 指令式 + 决策树 + 检测/验证步骤,AI 不容易在模糊地带走偏。

## 0. 先决定:你需要集成哪些部分(按需)

集成是**按方法分摊**的,不必一次接全。先看你要用哪些能力:

> `screenshot`(adb) 不需要 SDK;下表列出所有需要集成 SDK 的能力。

| 你想用 | 需要做的 | 对应章节 |
|---|---|---|
| adb 截图(导航靠人工) | **无需集成 SDK** —— 你自己 `flutter run` 起 app,需热重载就在控制台按 `r` | — |
| `snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor`(交互闭环) | `await FlutterWright.start(enabled: kDebugMode);` 即可 —— **无需** navigatorKey | §1 §2 |
| `goto` / `reset`(命名路由) | `await FlutterWright.start(enabled: kDebugMode);` 并把 `FlutterWright.navigatorKey` 注入 `MaterialApp(navigatorKey:)` | §1 §2 §3 |
| `goto`(GoRouter / GetX 等) | `await FlutterWright.start(enabled: kDebugMode);` 并给 `start()` 传 `CallbackNavigationAdapter` | §1 §2 §5 |
| `GET /routes` 让 AI 发现页面 | 传 `routes:`(路由名列表,**纯可选**,不影响 `goto`) | §4 |
| 纯渲染树截图(不含状态栏) | 用 `FlutterWrightRoot` 包根 | §2 |

> **`FlutterWright.start(enabled: kDebugMode)` 解锁全套交互(snapshot/tap/type/scroll/longPress/waitFor)**;只有要用 goto/reset 才需要额外传 navigatorKey 或 navigationAdapter。下面各节按这个顺序展开;只接你需要的。

## 1. 添加依赖(推荐放 `dev_dependencies`)

这个库只在 debug 自动化时用,**理论上只应进 `dev_dependencies`**:release 构建不会编译它,生产包零残留。前提只有一条:**你的 `lib/` 不要直接 `import` 它**(否则既触发 `depend_on_referenced_packages` lint,语义上也不对)。落地办法见第 2 节的「dev 入口」范式。

```yaml
# your_app/pubspec.yaml
dev_dependencies:
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
    # 本地拷贝同理:path: ../flutter-wright/packages/flutter_wright_sdk
```

> **图省事**也可以放进 `dependencies`、直接在 `lib/main.dart` 里 import:传 `enabled: kDebugMode` 时 release 下为 false → no-op。代价是 SDK 代码仍被编进生产包(大部分会被 tree-shake,但非零残留)。要"生产零残留",用 `dev_dependencies` + dev 入口(下一节)。`packages/example` 就是按 dev_dependencies 范式组织的:`lib/` 对 SDK **零引用**,只有 `dev/` 和 `test/` 引用它。

## 2. 连接入口

### 推荐:独立 debug 入口(配合 `dev_dependencies`)

生产 `lib/main.dart` **完全不碰 SDK**;另起一个 `dev/main_dev.dart` 作为 debug 入口,只有它 import SDK。`dev/` 在 `lib/` 之外,引用 dev_dependency 合法、lint 干净。用 `flutter run -t dev/main_dev.dart` 启动它。

```dart
// dev/main_dev.dart
import 'package:flutter/material.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';
import 'package:your_app/app.dart'; // 你的根 widget,接受注入

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(enabled: kDebugMode, routes: appRoutes.keys); // debug 为 true;release 为 false → no-op
  // FlutterWrightRoot 包根让 /screenshot 可靠(见下)
  runApp(FlutterWrightRoot(
    child: MyApp(navigatorKey: FlutterWright.navigatorKey),
  ));
}
```

根 widget 接受**可注入**的 navigatorKey —— 生产 `main()` 传 null,debug 入口传 SDK 的 key:

```dart
// lib/app.dart —— 注意这里没有任何 SDK import
class MyApp extends StatelessWidget {
  const MyApp({this.navigatorKey, super.key});
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        onGenerateRoute: appRouter,
      );
}

// lib/main.dart —— 生产入口,零 SDK 引用
void main() => runApp(const MyApp());
```

完整可运行示例见 `packages/example`。

> 不方便用 `FlutterWrightRoot`(比如有自定义 binding)就忽略 `/screenshot`,让 skill 一直走 `adb screencap` —— Android 上这反而更优,能截完整设备帧。

### 图省事:单入口(SDK 在 `dependencies`)

```dart
// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(enabled: kDebugMode, routes: AppRouter.names); // debug 为 true;release 为 false → no-op
  runApp(FlutterWrightRoot(child: const MyApp()));
}
```

## 3. 把导航接进来(仅 goto/reset 需要)

> 只需 snapshot/tap/type/scroll/longPress/waitFor?这一节可以跳过。

`/navigate` 和 `/reset` **不绑定任何具体路由栈** —— 经 `NavigationAdapter` 适配。`start()` 不传 `navigationAdapter` 时默认走 **Navigator 1.0 命名路由**(`NavigatorKeyAdapter`):把 `FlutterWright.navigatorKey` 注入到 `MaterialApp(navigatorKey:)` 即可(见第 2 节)。

> 为什么共享 `navigatorKey`?`Navigator.of(context)` 需要 context,而 SDK 的 HTTP handler 没有 context;`GlobalKey<NavigatorState>` 绕开这个限制。

GoRouter / GetX / auto_route 等**不用命名路由**的架构,改传你自己的 adapter —— 见第 6 节。SDK 对路由 API **零假设**。

## 4. 提供可发现路由(纯可选 —— 仅为 `GET /routes`)

**`goto` 不需要任何注册**:`/navigate` 直接把路由名交给你的路由器,能否跳成功只取决于路由器认不认。`GET /routes` 返回当前 `NavigationAdapter.discoverableRoutes`;不可枚举的栈返回 `[]`。这一步唯一的作用是让 `GET /routes` 能列出"有哪些页面"给 AI 自动发现用。

**Navigator 1.0 + `MaterialApp(routes: map)`:**
```dart
// 引用同一个 map 的 keys
await FlutterWright.start(enabled: kDebugMode, routes: appRoutes.keys);
```

**Navigator 1.0 + onGenerateRoute:**
```dart
// 暴露一次路由名常量
await FlutterWright.start(enabled: kDebugMode, routes: AppRouter.names);
```

**宿主已有自己的 navigatorKey:**
```dart
await FlutterWright.start(enabled: kDebugMode, navigatorKey: myKey, routes: AppRouter.names);
```

**GoRouter / GetX 等:**  在 `CallbackNavigationAdapter` 里提供 `routesProvider`(见 §5 示例)。

可发现性≠"准入控制"——未在 `routes` 里出现的路由照样能被 `goto` 跳到。

## 5. 不同路由架构(GoRouter / GetX / 自定义)

不用 Navigator 1.0 命名路由的 app,给 `start()` 传一个 `CallbackNavigationAdapter`:你提供两个闭包(怎么跳页、怎么回根),SDK 只管回调,对路由 API 零假设。

**GoRouter:**
```dart
final router = GoRouter(routes: [...]);

Iterable<String> goRouterPaths(List<RouteBase> routes, [String prefix = '']) sync* {
  for (final r in routes) {
    if (r is GoRoute) {
      final full = r.path.startsWith('/') ? r.path : '$prefix/${r.path}';
      yield full;
      yield* goRouterPaths(r.routes, full);
    } else {
      yield* goRouterPaths(r.routes, prefix);
    }
  }
}

await FlutterWright.start(
  enabled: kDebugMode, // debug 为 true;release 为 false → no-op
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (r, args, _) => router.go(r, extra: args),
    onReset: () => router.go('/'),
    routesProvider: () => goRouterPaths(router.configuration.routes),
  ),
);
runApp(MaterialApp.router(routerConfig: router));
```
此时 `POST /navigate {"route":"/order/123"}` 触发 `router.go('/order/123')`,GoRouter 按 URL 解析。**无需**共享 navigatorKey。

**GetX:**
```dart
await FlutterWright.start(
  enabled: kDebugMode, // debug 为 true;release 为 false → no-op
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (r, args, _) => Get.toNamed(r, arguments: args),
    onReset: () => Get.until((route) => route.isFirst),
    routesProvider: () => getPages.map((p) => p.name),
  ),
);
runApp(GetMaterialApp(getPages: [...]));
```
`Get.toNamed` 是全局静态调用,连 key 都不用注入,GetX 反而最省事。

**auto_route / Beamer / 自定义栈:** 任何"按名字跳页"的栈都行,把跳转塞进 `onNavigate`、回根塞进 `onReset`。可选 `readiness: () => ...` 让 `/navigate` 在路由未就绪时返回 503。

> 默认的 Navigator 1.0 路径(第 3 节)等价于 `navigationAdapter: NavigatorKeyAdapter(FlutterWright.navigatorKey)` —— 不传 adapter 时 SDK 自动用它。

## 6. 控制 SDK 启用(profile/release)

`enabled` 默认 `false`,`start()` 直接 no-op、不绑端口。用你自己的「测试包?」判断接线:

```dart
await FlutterWright.start(
  enabled: AppEnv.isTestBuild,   // 或 kDebugMode
);
```

`AppEnv.isTestBuild` 是示意,替换成你 app 里判断「是否调试/QA 包」的表达式;最简单直接用 `kDebugMode`(来自 `package:flutter/foundation.dart`)。正式包让该判断为 `false`(即 `enabled` 默认值)即彻底关闭、零运行时攻击面;profile/QA 包想开就让它为真。

### 加 token 鉴权(profile/QA 包多一层防护)

profile/QA 包(非 loopback)想再多一层防护,给 `start()` 传 `token`:

```dart
await FlutterWright.start(
  enabled: kDebugMode,
  token: const String.fromEnvironment("FW_TOKEN"),
);
```

`token` 非空时,除 `GET /health` 外所有端点都要带匹配的 `X-FW-Token` 头,缺失/错误返 `401`(`unauthorized: missing or invalid X-FW-Token`);`token` 为空/`null` 则不鉴权,仅靠 `127.0.0.1` loopback 隔离。`token` 从 env / 本地配置读取,**绝不进仓库**。

## 7. 跟 CI / golden test 共存

这个 SDK 是给交互式循环用的,不是 unit/golden test。如果你两个都有:

- `flutter test` 跑在隔离进程里;SDK 的 `dart:io HttpServer` 能跑但跑了也没用。
- 用 `Platform.environment.containsKey('FLUTTER_TEST')` 跳过 bind:

```dart
import 'dart:io';

if (!Platform.environment.containsKey('FLUTTER_TEST')) {
  await FlutterWright.start(enabled: kDebugMode); // debug 为 true;release 为 false → no-op
}
```

## 8. 多 flavor app

不同 flavor(dev/staging/prod)需要不同 setup。配合 dev_dependencies 范式,最干净的做法是每个 flavor 各有自己的 debug 入口(`dev/main_dev.dart`、`dev/main_staging.dart`),prod 用零 SDK 的 `lib/main.dart`:

```dart
// dev/main_dev.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(
    enabled: kDebugMode, // debug 为 true;release 为 false → no-op
    config: const FlutterWrightConfig(port: 9123),
    routes: AppRouter.names,
  );
  runApp(FlutterWrightRoot(child: createApp(navigatorKey: FlutterWright.navigatorKey)));
}

// lib/main.dart —— prod,零 SDK 引用
void main() => runApp(createApp());
```
