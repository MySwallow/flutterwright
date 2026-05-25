# 路由自动发现重设计 Implementation Plan (v0.5.0)

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删掉手填的 `testRoutes` 与 `RouteRegistry`，让 `GET /routes` 的路由发现完全由 `NavigationAdapter.discoverableRoutes` 提供；`start()` 接收可选 `navigatorKey` 与 `routes` 路由名列表。

**Architecture:** 路由发现的唯一来源是当前 `NavigationAdapter`。`NavigatorKeyAdapter` 与 `CallbackNavigationAdapter` 各带一个路由来源（静态列表 / 闭包）。`RoutesHandler` 改为问 adapter 要列表。核心 SDK 包不引入任何第三方路由库依赖；GetX / GoRouter / FlutterBoost 通过文档片段经 `CallbackNavigationAdapter` 接入。

**Tech Stack:** Dart 3.5 / Flutter；纯 JSON over `127.0.0.1` 的 in-app HTTP server；E2E 测试用真实 `curl` + `flutter_test`。

**Spec:** `docs/superpowers/specs/2026-05-25-route-discovery-redesign-design.md`

---

### Task 1: NavigationAdapter 加发现能力

**Files:**
- Modify: `packages/flutter_wright_sdk/lib/src/navigation_adapter.dart`

- [ ] **Step 1: 给抽象类加默认 `discoverableRoutes` getter**

在 `abstract class NavigationAdapter` 的 `reset()` 声明之后、类结束 `}` 之前，加入：

```dart
  /// Routes this adapter can enumerate for `GET /routes`. Null = not
  /// enumerable (e.g. `onGenerateRoute` / FlutterBoost `routeFactory`); the
  /// handler then returns an empty list. Concrete default benefits subclasses
  /// that `extends` this type; adapters that `implements` NavigationAdapter
  /// (incl. the built-ins below) must declare it themselves.
  Iterable<String>? get discoverableRoutes => null;
```

- [ ] **Step 2: `NavigatorKeyAdapter` 收一个可选 routes 列表**

把构造函数与字段：

```dart
class NavigatorKeyAdapter implements NavigationAdapter {
  NavigatorKeyAdapter(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;
```

改为：

```dart
class NavigatorKeyAdapter implements NavigationAdapter {
  NavigatorKeyAdapter(
    this.navigatorKey, {
    Iterable<String> routes = const <String>[],
  }) : _routes = routes;

  final GlobalKey<NavigatorState> navigatorKey;
  final Iterable<String> _routes;

  @override
  Iterable<String>? get discoverableRoutes =>
      _routes.isEmpty ? null : _routes;
```

- [ ] **Step 3: `CallbackNavigationAdapter` 加 routesProvider 闭包**

把构造函数：

```dart
  CallbackNavigationAdapter({
    required this.onNavigate,
    required this.onReset,
    bool Function()? readiness,
  }) : _readiness = readiness;
```

改为：

```dart
  CallbackNavigationAdapter({
    required this.onNavigate,
    required this.onReset,
    bool Function()? readiness,
    Iterable<String> Function()? routesProvider,
  })  : _readiness = readiness,
        _routesProvider = routesProvider;
```

并在 `final bool Function()? _readiness;` 这一行下面加：

```dart
  /// Called for `GET /routes`. Return the routes this stack can enumerate
  /// (e.g. GetX `getPages.map((p) => p.name)`), or omit for non-enumerable
  /// stacks. Invoked per request so dynamic route tables stay fresh.
  final Iterable<String> Function()? _routesProvider;

  @override
  Iterable<String>? get discoverableRoutes => _routesProvider?.call();
```

- [ ] **Step 4: Run project's static checks**

Run: `cd packages/flutter_wright_sdk && dart analyze`
Expected: 通过，无新错误

- [ ] **Step 5: Stage changes for user review**

```bash
git add packages/flutter_wright_sdk/lib/src/navigation_adapter.dart
```

**不要 commit**——由用户审阅后自行 commit。

---

### Task 2: RoutesHandler 从 adapter 读路由

**Files:**
- Modify: `packages/flutter_wright_sdk/lib/src/handlers/routes_handler.dart`（整文件替换）

- [ ] **Step 1: 整文件替换为**

```dart
import '../navigation_adapter.dart';
import 'handler.dart';

class RoutesHandler extends Handler {
  RoutesHandler(this.adapter);

  final NavigationAdapter adapter;

  @override
  String get path => '/routes';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final routes = adapter.discoverableRoutes?.toList() ?? const <String>[];
    await ctx.request.writeJson(200, <String, Object?>{
      'ok': true,
      'routes': routes,
    });
  }
}
```

- [ ] **Step 2: Run project's static checks**

Run: `cd packages/flutter_wright_sdk && dart analyze`
Expected: 报 `flutter_wright.dart` 仍以旧签名 `RoutesHandler(routes)` 调用的错误（Task 3 修复）；本文件自身无错。

- [ ] **Step 3: Stage changes for user review**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/routes_handler.dart
```

**不要 commit**。

---

### Task 3: FlutterWright.start 改签名，删 RouteRegistry

**Files:**
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`
- Delete: `packages/flutter_wright_sdk/lib/src/route_registry.dart`
- Modify: `packages/flutter_wright_sdk/lib/flutter_wright_sdk.dart`

- [ ] **Step 1: 删掉 route_registry 的 import 与静态字段**

在 `flutter_wright.dart` 中删除这一行 import：

```dart
import 'route_registry.dart';
```

并删除类内的静态字段（连同其文档注释那一行）：

```dart
  static final RouteRegistry routes = RouteRegistry();
```

- [ ] **Step 2: 替换 `start()` 方法体**

把现有 `start({...})` 整个方法（从 `static Future<void> start({` 到对应的结束 `}`）替换为：

```dart
  static Future<void> start({
    FlutterWrightConfig config = const FlutterWrightConfig(),
    NavigationAdapter? navigationAdapter,
    GlobalKey<NavigatorState>? navigatorKey,
    Iterable<String> routes = const <String>[],
  }) async {
    if (config.enableInDebugOnly && !kDebugMode) {
      vlLog('release build: SDK disabled');
      return;
    }
    if (_server != null) {
      vlWarn('start() called twice; ignoring');
      return;
    }

    // Default to the Navigator 1.0 path (shared navigatorKey). Apps on
    // GoRouter / GetX / FlutterBoost pass their own adapter instead.
    final NavigationAdapter adapter = navigationAdapter ??
        NavigatorKeyAdapter(
          navigatorKey ?? FlutterWright.navigatorKey,
          routes: routes,
        );

    if (navigationAdapter != null && routes.isNotEmpty) {
      vlWarn('start(routes:) ignored because navigationAdapter was provided; '
          'put discoverable routes in the adapter (routesProvider)');
    }

    final handlers = <Handler>[
      HealthHandler(version),
      RoutesHandler(adapter),
      NavigateHandler(adapter),
      ResetHandler(adapter),
      ScreenshotHandler(config.screenshotMode),
      ReloadHandler(),
    ];

    _server = FlutterWrightHttpServer(config: config, handlers: handlers);
    if (config.autoStart) {
      await _server!.start();
    }
  }
```

- [ ] **Step 3: 从 `stop()` 删掉 `routes.clear()`**

把：

```dart
  static Future<void> stop() async {
    await _server?.stop();
    _server = null;
    routes.clear();
  }
```

改为：

```dart
  static Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
```

- [ ] **Step 4: 升版本常量**

把 `static const String version = '0.4.0';` 改为：

```dart
  static const String version = '0.5.0';
```

- [ ] **Step 5: 删除 route_registry.dart 文件**

```bash
git rm packages/flutter_wright_sdk/lib/src/route_registry.dart
```

- [ ] **Step 6: 从 barrel 移除 RouteRegistry export**

在 `packages/flutter_wright_sdk/lib/flutter_wright_sdk.dart` 删除这一行：

```dart
export 'src/route_registry.dart' show RouteRegistry;
```

- [ ] **Step 7: Run project's static checks**

Run: `cd packages/flutter_wright_sdk && dart analyze`
Expected: 通过，无新错误（`route_registry.dart` 已无引用）

- [ ] **Step 8: Stage changes for user review**

```bash
git add packages/flutter_wright_sdk/lib/src/flutter_wright.dart packages/flutter_wright_sdk/lib/flutter_wright_sdk.dart
```

（`git rm` 已暂存删除）**不要 commit**。

---

### Task 4: 暴露 AppRouter.names，更新 dev 入口

**Files:**
- Modify: `packages/example/lib/router/app_router.dart`
- Modify: `packages/example/dev/main_dev.dart`

- [ ] **Step 1: 在 AppRouter 暴露一次路由名常量**

在 `class AppRouter {` 之后、`static Route<dynamic>? generate(...)` 之前插入：

```dart
  /// The named routes this app's [generate] switch handles. Exposed once so
  /// the debug harness can feed `FlutterWright.start(routes:)` without a
  /// duplicated hand-typed list. `onGenerateRoute` apps have no enumerable
  /// route map, so this const is the single source.
  static const List<String> names = <String>[
    '/',
    '/login',
    '/product/detail',
    '/order/detail',
  ];
```

- [ ] **Step 2: 更新 dev/main_dev.dart 用新 API**

把：

```dart
  await FlutterWright.start(
    testRoutes: const <String>[
      '/',
      '/login',
      '/product/detail',
      '/order/detail',
    ],
  );
```

改为：

```dart
  await FlutterWright.start(routes: AppRouter.names);
```

并在文件顶部 import 区加入（紧跟现有 import）：

```dart
import 'package:flutter_wright_example/router/app_router.dart';
```

- [ ] **Step 3: Run project's static checks**

Run: `cd packages/example && dart analyze`
Expected: 通过，无新错误

- [ ] **Step 4: Stage changes for user review**

```bash
git add packages/example/lib/router/app_router.dart packages/example/dev/main_dev.dart
```

**不要 commit**。

---

### Task 5: 更新 e2e_control_plane_test.dart

**Files:**
- Modify: `packages/example/test/e2e_control_plane_test.dart`

- [ ] **Step 1: 用新 API 启动，引用 AppRouter.names**

把 `bootApp` 里的：

```dart
    await tester.runAsync(() => FlutterWright.start(
          testRoutes: const <String>['/', '/login', '/product/detail', '/order/detail'],
        ));
```

改为：

```dart
    await tester.runAsync(() => FlutterWright.start(
          routes: AppRouter.names,
        ));
```

并确认文件顶部已 import（若无则添加）：

```dart
import 'package:flutter_wright_example/router/app_router.dart';
```

> `/routes` 现有断言 `containsAll(['/', '/login', '/order/detail'])` 保持不变——它现在验证经 `NavigatorKeyAdapter.discoverableRoutes` 的新发现路径。

- [ ] **Step 2: 运行该测试**

Run: `cd packages/example && flutter test test/e2e_control_plane_test.dart`
Expected: PASS（health/routes/navigate/reset/screenshot 全绿）

- [ ] **Step 3: Stage changes for user review**

```bash
git add packages/example/test/e2e_control_plane_test.dart
```

**不要 commit**。

---

### Task 6: 更新并扩展 e2e_navigation_adapter_test.dart

**Files:**
- Modify: `packages/example/test/e2e_navigation_adapter_test.dart`

- [ ] **Step 1: 把 testRoutes 改成 adapter 的 routesProvider**

把 `FlutterWright.start(...)` 调用：

```dart
    await tester.runAsync(() => FlutterWright.start(
          config: const FlutterWrightConfig(port: _port),
          navigationAdapter: CallbackNavigationAdapter(
            onNavigate: (r, args, _) => route.value = r,
            onReset: () {
              route.value = '/';
              lastReset = '/';
            },
          ),
          testRoutes: const <String>['/', '/cart', '/profile'],
        ));
```

改为（routesProvider 进 adapter，删 testRoutes）：

```dart
    await tester.runAsync(() => FlutterWright.start(
          config: const FlutterWrightConfig(port: _port),
          navigationAdapter: CallbackNavigationAdapter(
            onNavigate: (r, args, _) => route.value = r,
            onReset: () {
              route.value = '/';
              lastReset = '/';
            },
            routesProvider: () => const <String>['/', '/cart', '/profile'],
          ),
        ));
```

- [ ] **Step 2: 加一个 GET 辅助函数**

在文件里 `_curlPost` 函数之后插入：

```dart
Future<({int code, String body})> _curlGet(String path) async {
  final tmp = await Directory.systemTemp.createTemp('fw_navget_');
  final out = File('${tmp.path}/body');
  try {
    final res = await Process.run('curl', <String>[
      '-s', '-o', out.path, '-w', '%{http_code}', '$_base$path',
    ]);
    final code = int.tryParse(res.stdout.toString().trim()) ?? 0;
    final body = await out.exists() ? await out.readAsString() : '';
    return (code: code, body: body);
  } finally {
    await tmp.delete(recursive: true);
  }
}
```

- [ ] **Step 3: 断言 routesProvider 喂到了 GET /routes，且未列出的路由仍能导航**

在测试体内 `expect(find.text('HOME PAGE'), findsOneWidget);`（首次断言）之后插入：

```dart
    // routesProvider 的结果应原样出现在 GET /routes
    final routesResp =
        (await tester.runAsync(() => _curlGet('/routes')))!;
    expect(routesResp.code, 200);
    final discovered =
        ((jsonDecode(routesResp.body) as Map<String, Object?>)['routes']
                as List<Object?>)
            .cast<String>();
    expect(discovered, containsAll(<String>['/', '/cart', '/profile']),
        reason: 'GET /routes 应来自 CallbackNavigationAdapter.routesProvider');

    // 发现与导航解耦:跳一个不在 routesProvider 里的路由仍应 200
    final unlisted = (await tester
        .runAsync(() => _curlPost('/navigate', <String, Object?>{'route': '/zzz'})))!;
    await tester.pumpAndSettle();
    expect(unlisted.code, 200,
        reason: '导航直接交给 adapter,不查发现列表');
    expect(find.text('HOME PAGE'), findsOneWidget,
        reason: '_DeclarativeApp 对未知路由回落到 HOME');
```

> `_DeclarativeApp` 的 `switch` 对 `/zzz` 命中 `default` → HOME PAGE，证明导航不依赖发现列表。

- [ ] **Step 4: 运行该测试**

Run: `cd packages/example && flutter test test/e2e_navigation_adapter_test.dart`
Expected: PASS

- [ ] **Step 5: Stage changes for user review**

```bash
git add packages/example/test/e2e_navigation_adapter_test.dart
```

**不要 commit**。

---

### Task 7: 新增 e2e_route_discovery_test.dart（空发现 + 自定义 navigatorKey）

**Files:**
- Create: `packages/example/test/e2e_route_discovery_test.dart`

- [ ] **Step 1: 创建测试文件**

```dart
// 验收:① 无路由来源时 GET /routes 返回空数组;② start(navigatorKey:) 用
// 自定义 key 驱动 Navigator 1.0 导航。独立端口 9125,避免与其他 e2e 并发冲突。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_example/app.dart';
import 'package:flutter_wright_example/pages/login_page.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

const int _port = 9125;
const String _base = 'http://127.0.0.1:$_port';

Future<({int code, String body})> _curlGet(String path) async {
  final tmp = await Directory.systemTemp.createTemp('fw_disc_get_');
  final out = File('${tmp.path}/body');
  try {
    final res = await Process.run('curl', <String>[
      '-s', '-o', out.path, '-w', '%{http_code}', '$_base$path',
    ]);
    final code = int.tryParse(res.stdout.toString().trim()) ?? 0;
    final body = await out.exists() ? await out.readAsString() : '';
    return (code: code, body: body);
  } finally {
    await tmp.delete(recursive: true);
  }
}

Future<({int code, String body})> _curlPost(
    String path, Map<String, Object?> json) async {
  final tmp = await Directory.systemTemp.createTemp('fw_disc_post_');
  final out = File('${tmp.path}/body');
  try {
    final res = await Process.run('curl', <String>[
      '-s', '-o', out.path, '-w', '%{http_code}',
      '-X', 'POST', '$_base$path',
      '-H', 'content-type: application/json',
      '-d', jsonEncode(json),
    ]);
    final code = int.tryParse(res.stdout.toString().trim()) ?? 0;
    final body = await out.exists() ? await out.readAsString() : '';
    return (code: code, body: body);
  } finally {
    await tmp.delete(recursive: true);
  }
}

void main() {
  tearDown(() async {
    await FlutterWright.stop();
  });

  testWidgets('无路由来源时 GET /routes 返回空数组', (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(
          config: const FlutterWrightConfig(port: _port),
        ));
    await tester.pumpWidget(
      FlutterWrightRoot(
        child: createApp(navigatorKey: FlutterWright.navigatorKey),
      ),
    );
    await tester.pumpAndSettle();

    final resp = (await tester.runAsync(() => _curlGet('/routes')))!;
    expect(resp.code, 200);
    final json = jsonDecode(resp.body) as Map<String, Object?>;
    expect(json['ok'], true);
    expect(json['routes'], isEmpty,
        reason: '没传 routes、默认 adapter → discoverableRoutes 为 null → []');
  });

  testWidgets('start(navigatorKey:) 用自定义 key 驱动导航',
      (WidgetTester tester) async {
    final customKey = GlobalKey<NavigatorState>();
    await tester.runAsync(() => FlutterWright.start(
          config: const FlutterWrightConfig(port: _port),
          navigatorKey: customKey,
          routes: const <String>['/', '/login'],
        ));
    await tester.pumpWidget(
      FlutterWrightRoot(child: createApp(navigatorKey: customKey)),
    );
    await tester.pumpAndSettle();

    final nav = (await tester.runAsync(
        () => _curlPost('/navigate', <String, Object?>{'route': '/login'})))!;
    await tester.pumpAndSettle();
    expect(nav.code, 200, reason: 'body: ${nav.body}');
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'SDK 应经自定义 navigatorKey 驱动 pushNamed');
  });
}
```

- [ ] **Step 2: 运行该测试**

Run: `cd packages/example && flutter test test/e2e_route_discovery_test.dart`
Expected: PASS（两条用例全绿）

- [ ] **Step 3: Stage changes for user review**

```bash
git add packages/example/test/e2e_route_discovery_test.dart
```

**不要 commit**。

---

### Task 8: 版本对齐 + CHANGELOG

**Files:**
- Modify: `packages/flutter_wright_sdk/pubspec.yaml:3`
- Modify: `packages/flutter_wright_sdk/CHANGELOG.md`

- [ ] **Step 1: pubspec 升到 0.5.0**

把 `version: 0.3.0` 改为：

```yaml
version: 0.5.0
```

- [ ] **Step 2: CHANGELOG 顶部加 0.5.0 条目**

在 `# 更新日志` 标题之后、`## 0.4.0 - 2026-05-25` 之前插入：

```markdown
## 0.5.0 - 2026-05-25

> **破坏性变更。**

### 移除
- `FlutterWright.start(testRoutes:)` 参数；`FlutterWright.routes`(`RouteRegistry`)
  静态字段；`src/route_registry.dart` 整个文件及其 barrel export。路由发现改由
  `NavigationAdapter.discoverableRoutes` 提供。

### 新增
- `NavigationAdapter.discoverableRoutes`(可选,默认 `null`):`GET /routes` 的唯一来源。
- `NavigatorKeyAdapter(.., {routes})` 与 `CallbackNavigationAdapter(.., {routesProvider})`
  用于喂路由发现。
- `FlutterWright.start({navigatorKey, routes})`:可传宿主自有 navigatorKey;`routes`
  路由名列表喂 `GET /routes`(取代 `testRoutes`)。

### 修复
- 统一版本号:`pubspec.yaml`(此前 0.3.0)与代码 `version` 常量(此前 0.4.0)对齐为 0.5.0。

### 迁移
- `start(testRoutes: [...])` → Navigator 1.0(map)用 `start(routes: map.keys)`;
  Navigator 1.0(onGenerateRoute)暴露一次路由名常量 `start(routes: AppRouter.names)`;
  其他栈把路由放进 adapter 的 `routesProvider`。
- 自定义 `implements NavigationAdapter` 的 adapter 需补一行
  `Iterable<String>? get discoverableRoutes => null;`(不可枚举时)。
```

- [ ] **Step 3: Stage changes for user review**

```bash
git add packages/flutter_wright_sdk/pubspec.yaml packages/flutter_wright_sdk/CHANGELOG.md
```

**不要 commit**。

---

### Task 9: 文档更新

**Files:**
- Modify: `README.md`
- Modify: `packages/flutter_wright_sdk/README.md`
- Modify: `packages/example/README.md`
- Modify: `docs/integration-guide.md`
- Modify: `docs/integration-guide-for-ai.md`
- Modify: `docs/api-reference.md`
- Modify: `docs/architecture.md`
- Modify: `docs/troubleshooting.md`

**共用替换规则**（对每个文件逐处应用）：

1. 所有 `FlutterWright.start(testRoutes: [...])` → 按栈改成下方"各栈接入片段"对应写法。
2. 所有把 `testRoutes` 描述成"必填 / 必做步骤 / 校验门"的措辞 → 删除或降级为"可选，只影响 `GET /routes` 发现，不影响 `goto`"。
3. 所有提到 `FlutterWright.routes.register(...)` / `RouteRegistry` 的句子 → 删除（该 API 已移除）。
4. 凡介绍 `start()` 参数处，补上 `navigatorKey`（宿主已有自己的 key 时传入）与 `routes`（路由名列表）。

**各栈接入片段**（作为文档中的标准代码块，按文件语境插入）：

```dart
// Navigator 1.0 + MaterialApp(routes: map) —— 引用同一个 map 的 keys
await FlutterWright.start(routes: appRoutes.keys);

// Navigator 1.0 + onGenerateRoute —— 暴露一次路由名常量
await FlutterWright.start(routes: AppRouter.names);

// 宿主已有自己的 navigatorKey
await FlutterWright.start(navigatorKey: myKey, routes: AppRouter.names);

// GoRouter —— 递归展开 configuration.routes(:id 动态段原样保留)
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
FlutterWright.start(
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (r, args, _) => router.go(r, extra: args),
    onReset: () => router.go('/'),
    routesProvider: () => goRouterPaths(router.configuration.routes),
  ),
);

// GetX —— getPages 取 .name
FlutterWright.start(
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (r, args, _) => Get.toNamed(r, arguments: args),
    onReset: () => Get.until((route) => route.isFirst),
    routesProvider: () => getPages.map((p) => p.name),
  ),
);

// FlutterBoost —— routeFactory 枚举不出,宿主传一次已知列表
FlutterWright.start(
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (r, args, _) =>
        BoostNavigator.instance.push(r, arguments: args as Map<String, dynamic>?),
    onReset: () => BoostNavigator.instance.popUntil(route: rootRouteName),
    routesProvider: () => myKnownBoostRoutes,
  ),
);
```

- [ ] **Step 1: `docs/api-reference.md`** —— 更新 `start()` 参数表/`GET /routes` 章节：删掉"只有 register/testRoutes 过的路由才出现"的旧描述，改为"`GET /routes` 返回当前 `NavigationAdapter.discoverableRoutes`；不可枚举的栈返回 `[]`"。补 `navigatorKey` / `routes` 参数说明。

- [ ] **Step 2: `docs/integration-guide.md`** —— 替换所有 `testRoutes` 示例为各栈片段；把"传 `testRoutes`（纯可选）"行更新为新参数 `routes`。

- [ ] **Step 3: `docs/integration-guide-for-ai.md`** —— 删除"Step 4 填真实路由"的必做框架与"至少含 1 个真实路由不是 placeholder"校验门；改成"可选：用 `routes:` 或 adapter 的 `routesProvider` 喂 `GET /routes`"。

- [ ] **Step 4: `docs/architecture.md`** —— 把 `RouteRegistry` 相关描述替换为"发现经 `NavigationAdapter.discoverableRoutes`"。

- [ ] **Step 5: `docs/troubleshooting.md`** —— 若有 `testRoutes`/`/routes` 排查条目，更新为新机制（`GET /routes` 空 = adapter 无 `discoverableRoutes`，非错误）。

- [ ] **Step 6: `README.md` 与 `packages/flutter_wright_sdk/README.md`** —— 更新 `start()` 示例与"`GET /routes` 让 AI 发现页面"一行（去掉 `testRoutes`，指向 `routes` / `routesProvider`）。

- [ ] **Step 7: `packages/example/README.md`** —— 若示例命令用了 `testRoutes`，改为 `routes: AppRouter.names`。

- [ ] **Step 8: 校验文档无残留旧 API**

Run: `cd /Users/mini/Documents/dev/github/flutterwright && grep -rn "testRoutes\|RouteRegistry\|routes.register" README.md docs/ packages/flutter_wright_sdk/README.md packages/example/README.md`
Expected: 无输出（历史 `docs/superpowers/specs|plans/2026-05-22-*` 不在本次范围，可忽略；命令已不含该目录）

- [ ] **Step 9: Stage changes for user review**

```bash
git add README.md packages/flutter_wright_sdk/README.md packages/example/README.md docs/integration-guide.md docs/integration-guide-for-ai.md docs/api-reference.md docs/architecture.md docs/troubleshooting.md
```

**不要 commit**。

---

### Task 10: 全量验证

**Files:** （无改动，仅验证）

- [ ] **Step 1: 静态检查两个包**

Run: `cd packages/flutter_wright_sdk && dart analyze && cd ../example && dart analyze`
Expected: 两个包均通过，无新错误

- [ ] **Step 2: 跑全部 example E2E**

Run: `cd packages/example && flutter test`
Expected: 全绿（control_plane / navigation_adapter / route_discovery 等）

- [ ] **Step 3: 确认 skill 脚本未受影响**

Run: `cd /Users/mini/Documents/dev/github/flutterwright && grep -rn "testRoutes\|RouteRegistry" skills/`
Expected: 无输出（`GET /routes` HTTP 契约未变，脚本无需改）
