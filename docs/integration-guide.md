# 集成指南

把 `flutter_wright_sdk` 接入到真实 Flutter app 的详细模式 — 包括 dev_dependencies 范式、不同路由架构(Navigator 1.0 / GoRouter / GetX)、多 flavor。

> **让 AI 助手做集成?** 用同名 AI 专用版本 [`integration-guide-for-ai.md`](./integration-guide-for-ai.md) — 指令式 + 决策树 + 检测/验证步骤,AI 不容易在模糊地带走偏。

## 0. 先决定:你需要集成哪些部分(按需)

集成是**按方法分摊**的,不必一次接全。先看你要用哪些能力:

| 你想用 | 需要做的 | 对应章节 |
|---|---|---|
| `reload` + adb 截图(导航靠人工) | **仅** `await FlutterWright.start();` | §1 §2 |
| `goto` / `reset`(命名路由) | 再把 `FlutterWright.navigatorKey` 注入 `MaterialApp(navigatorKey:)` | §3 |
| `goto`(GoRouter / GetX 等) | 给 `start()` 传 `CallbackNavigationAdapter` | §5 |
| `GET /routes` 让 AI 发现页面 | 传 `testRoutes`(**纯可选**,不影响 `goto`) | §4 |
| 纯渲染树截图(不含状态栏) | 用 `FlutterWrightRoot` 包根 | §2 |

> 最小集成就是 `FlutterWright.start()` 一行。下面各节按这个顺序展开;只接你需要的。

## 1. 添加依赖(推荐放 `dev_dependencies`)

这个库只在 debug 自动化时用,**理论上只应进 `dev_dependencies`** —— release 构建根本不会编译它,生产包零残留。前提只有一条:**你的 `lib/` 不要直接 `import` 它**(否则既触发 `depend_on_referenced_packages` lint,语义上也不对)。落地办法见第 2 节的「dev 入口」范式。

```yaml
# your_app/pubspec.yaml
dev_dependencies:
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
    # 本地拷贝同理:path: ../flutter-wright/packages/flutter_wright_sdk
```

> **图省事**也可以放进 `dependencies`、直接在 `lib/main.dart` 里 import —— `kDebugMode` 保证 release 运行期是 no-op。代价是 SDK 代码仍被编进生产包(大部分会被 tree-shake,但非零残留)。要"生产零残留",用 `dev_dependencies` + dev 入口(下一节)。`packages/example` 就是按 dev_dependencies 范式组织的:`lib/` 对 SDK **零引用**,只有 `dev/` 和 `test/` 引用它。

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
  await FlutterWright.start(
    testRoutes: const ['/home', '/login', '/order/detail'],
  );
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
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(testRoutes: const ['/home', '/login']);
  runApp(FlutterWrightRoot(child: const MyApp()));
}
```

## 3. 把导航接进来(路由架构无关)

`/navigate` 和 `/reset` **不绑定任何具体路由栈** —— 经 `NavigationAdapter` 适配。`start()` 不传 `navigationAdapter` 时默认走 **Navigator 1.0 命名路由**(`NavigatorKeyAdapter`):把 `FlutterWright.navigatorKey` 注入到 `MaterialApp(navigatorKey:)` 即可(见第 2 节)。

> 为什么共享 `navigatorKey`?`Navigator.of(context)` 需要 context,而 SDK 的 HTTP handler 没有 context;`GlobalKey<NavigatorState>` 绕开这个限制。

GoRouter / GetX / auto_route 等**不用命名路由**的架构,改传你自己的 adapter —— 见第 6 节。SDK 对路由 API **零假设**。

## 4. 注册路由(纯可选 —— 仅为可发现性)

**`goto` 不需要任何注册**:`/navigate` 直接把路由名交给你的路由器,能否跳成功只取决于路由器认不认。注册唯一的作用,是让 `GET /routes` 能列出"有哪些页面"——给 AI 自动发现用;你用 curl、自己知道路由名,那就完全不用注册。

```dart
// 想要可发现性时,启动时一次性传入:
await FlutterWright.start(
  testRoutes: const ['/home', '/order/detail', '/login'],
);

// 或之后任何时候:
FlutterWright.routes.register('/cart');
```

注册关乎"可发现性",不是"准入控制"——未注册的路由照样能被 `goto` 跳到。

## 5. 不同路由架构(GoRouter / GetX / 自定义)

不用 Navigator 1.0 命名路由的 app,给 `start()` 传一个 `CallbackNavigationAdapter` —— 你提供两个闭包(怎么跳页、怎么回根),SDK 只管回调,对路由 API 零假设。

**GoRouter:**
```dart
final router = GoRouter(routes: [...]);

await FlutterWright.start(
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (route, args, _) => router.go(route, extra: args),
    onReset: () => router.go('/'),
  ),
);
runApp(MaterialApp.router(routerConfig: router));
```
此时 `POST /navigate {"route":"/order/123"}` 触发 `router.go('/order/123')`,GoRouter 按 URL 解析。**无需**共享 navigatorKey。

**GetX:**
```dart
await FlutterWright.start(
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (route, args, _) => Get.toNamed(route, arguments: args),
    onReset: () => Get.until((r) => r.isFirst),
  ),
);
runApp(GetMaterialApp(getPages: [...]));
```
`Get.toNamed` 是全局静态调用,连 key 都不用注入 —— GetX 反而是最省事的。

**auto_route / Beamer / 自定义栈:** 任何"按名字跳页"的栈都行,把跳转塞进 `onNavigate`、回根塞进 `onReset`。可选 `readiness: () => ...` 让 `/navigate` 在路由未就绪时返回 503。

> 默认的 Navigator 1.0 路径(第 3 节)等价于 `navigationAdapter: NavigatorKeyAdapter(FlutterWright.navigatorKey)` —— 不传 adapter 时 SDK 自动用它。

## 6. 在 profile/release 里禁用 SDK

默认 `enableInDebugOnly: true` 已经做了。如果你想在 profile 构建里也开(给 QA 用):

```dart
await FlutterWright.start(
  config: const FlutterWrightConfig(enableInDebugOnly: false),
);
```

小心 — release+enabled 意味着生产包里 HTTP 端口是开着的。

## 7. 跟 CI / golden test 共存

这个 SDK 是给交互式循环用的,不是 unit/golden test。如果你两个都有:

- `flutter test` 跑在隔离进程里;SDK 的 `dart:io HttpServer` 能跑但跑了也没用。
- 用 `Platform.environment.containsKey('FLUTTER_TEST')` 跳过 bind:

```dart
import 'dart:io';

if (!Platform.environment.containsKey('FLUTTER_TEST')) {
  await FlutterWright.start();
}
```

## 8. 多 flavor app

不同 flavor(dev/staging/prod)需要不同 setup。配合 dev_dependencies 范式,最干净的做法是每个 flavor 各有自己的 debug 入口(`dev/main_dev.dart`、`dev/main_staging.dart`),prod 用零 SDK 的 `lib/main.dart`:

```dart
// dev/main_dev.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(
    config: const FlutterWrightConfig(port: 9123),
    testRoutes: const ['/', '/login', '/order/detail'],
  );
  runApp(FlutterWrightRoot(child: createApp(navigatorKey: FlutterWright.navigatorKey)));
}

// lib/main.dart —— prod,零 SDK 引用
void main() => runApp(createApp());
```
