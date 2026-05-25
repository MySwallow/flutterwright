# 路由自动发现重设计 Design (v0.5.0)

**日期：** 2026-05-25
**状态：** 已认可，待转实施计划

## Goal

删掉手填的 `testRoutes` 字符串列表，让 `GET /routes` 的路由发现完全由当前的 `NavigationAdapter` 提供。能枚举的路由栈（Navigator 1.0 / GoRouter / GetX）自动给出路由列表；不能枚举的（FlutterBoost）由宿主 app 传一次已知列表。核心 SDK 包保持**零第三方依赖**。

## 背景与动机

### 问题 1：`testRoutes` 是冗余的

`POST /navigate`（`goto`）从不查路由表——它直接把 curl 传入的路由名交给 app 的路由器（`navigate_handler.dart`：取 `ctx.json['route']` → `adapter.navigate(route)`）。能否跳成功只取决于 app 自己的路由器认不认这个名字。

`testRoutes` 的唯一作用是喂给 `RouteRegistry`，再由 `GET /routes` 读出来做"页面可发现性"。但它要求开发者**手敲一份路由字符串列表**，与 app 路由器里已有的声明重复、且会漂移。

### 问题 2：要让 GetX / FlutterBoost 开箱即用

各路由栈的"可枚举性"不同：

| 栈 | 导航入口 | 路由能否枚举 |
|---|---|---|
| Navigator 1.0 | `pushNamed`（需 navigatorKey） | ✅ `MaterialApp(routes:)` 的 map 取 `.keys` |
| GoRouter | `router.go()` | ✅ 递归 `router.configuration.routes` 取 `.path` |
| GetX | `Get.toNamed()` | ✅ `getPages` 取 `.name` |
| FlutterBoost | `BoostNavigator.instance.push()` | ❌ `routeFactory` 是函数，枚举不出 → app 传一次列表 |

导航本身对所有栈早已可用（`CallbackNavigationAdapter`）。本次只补"发现"和接入人体工学。

### 依赖约束

`GetXAdapter` / `FlutterBoostAdapter` 若内置进核心包，会强制所有用户依赖 `get` / `flutter_boost`。因此核心包**不内置**这些适配器，各栈通过 `CallbackNavigationAdapter` + 文档片段接入。

### navigatorKey 的角色（澄清）

SDK 的 HTTP handler 跑在 widget 树之外，收到 `/navigate` 时没有 `BuildContext`，无法 `Navigator.of(context)`。`navigatorKey`（`GlobalKey<NavigatorState>`）是树外 handler 伸进 app Navigator 的桥：同一个 key 既给 `MaterialApp(navigatorKey:)` 又给 `NavigatorKeyAdapter`，SDK 通过 `navigatorKey.currentState.pushNamed(...)` 驱动导航。**仅 Navigator 1.0 路径需要它**；GoRouter/GetX/FlutterBoost 有自带的全局导航入口，不需要。

很多 app 已有自己的全局 navigatorKey，而 `MaterialApp` 只能挂一个。本次让 `start()` 直接接收 navigatorKey，避免冲突时还要手建 adapter。

## 设计

### 单一来源原则

路由发现的唯一来源 = `NavigationAdapter.discoverableRoutes`。删掉独立的 `RouteRegistry` 和 `start(testRoutes:)`，`GET /routes` 直接问当前 adapter 要列表。

### 1. `NavigationAdapter` 接口加可选 getter

`packages/flutter_wright_sdk/lib/src/navigation_adapter.dart`

```dart
abstract class NavigationAdapter {
  bool get isReady;
  FutureOr<void> navigate(String route, {Object? args, bool popUntilRoot = true});
  FutureOr<void> reset();

  /// 可枚举给 GET /routes 的路由。null = 不可枚举
  /// (onGenerateRoute / FlutterBoost routeFactory)，handler 返回空数组。
  Iterable<String>? get discoverableRoutes => null; // 默认 null，旧自定义 adapter 不破
}
```

`=> null` 默认实现保证任何已有的自定义 adapter 不需要改动即可编译。

### 2. 两个内置 adapter 各加路由来源

```dart
class NavigatorKeyAdapter implements NavigationAdapter {
  NavigatorKeyAdapter(this.navigatorKey, {Iterable<String> routes = const <String>[]})
      : _routes = routes;
  final GlobalKey<NavigatorState> navigatorKey;
  final Iterable<String> _routes;

  @override
  Iterable<String>? get discoverableRoutes => _routes.isEmpty ? null : _routes;
  // navigate / reset / isReady 不变
}

class CallbackNavigationAdapter implements NavigationAdapter {
  CallbackNavigationAdapter({
    required this.onNavigate,
    required this.onReset,
    bool Function()? readiness,
    Iterable<String> Function()? routesProvider, // 新增
  })  : _readiness = readiness,
        _routesProvider = routesProvider;
  final Iterable<String> Function()? _routesProvider;

  @override
  Iterable<String>? get discoverableRoutes => _routesProvider?.call();
  // 其余不变
}
```

`CallbackNavigationAdapter` 用闭包而非静态列表，让动态路由栈（如 GetX 运行期增删 `getPages`）每次 `GET /routes` 都拿到最新值。

### 3. `start()` 改签名，删 `RouteRegistry`

`packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

```dart
static Future<void> start({
  FlutterWrightConfig config = const FlutterWrightConfig(),
  NavigationAdapter? navigationAdapter,
  GlobalKey<NavigatorState>? navigatorKey,          // 新增：默认走内置 key
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{}, // Navigator 1.0 便捷糖
}) async {
  // ... debug/重复 start 守卫不变 ...

  final NavigationAdapter adapter = navigationAdapter ??
      NavigatorKeyAdapter(navigatorKey ?? FlutterWright.navigatorKey, routes: routes.keys);

  if (navigationAdapter != null && routes.isNotEmpty) {
    vlWarn('start(routes:) ignored because navigationAdapter was provided; '
        'put discoverable routes in the adapter');
  }

  final handlers = <Handler>[
    HealthHandler(version),
    RoutesHandler(adapter),   // 改：接 adapter，不再接 RouteRegistry
    NavigateHandler(adapter),
    ResetHandler(adapter),
    ScreenshotHandler(config.screenshotMode),
    ReloadHandler(),
  ];
  // ... 其余不变 ...
}
```

删除：`static final RouteRegistry routes` 字段；`stop()` 里的 `routes.clear()`；`testRoutes` 参数；整个 `route_registry.dart` 文件。

`routes:` 仅对默认 Navigator 1.0 路径生效；传了 `navigationAdapter` 时以 adapter 为准并 warn（两者都给属误用）。

### 4. `RoutesHandler` 从 adapter 读

`packages/flutter_wright_sdk/lib/src/handlers/routes_handler.dart`

```dart
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
    await ctx.request.writeJson(200, <String, Object?>{'ok': true, 'routes': routes});
  }
}
```

**HTTP 契约不变**：仍返回 `{"ok": true, "routes": [...]}`，不可枚举时 `routes` 为 `[]`。因此 skill 脚本无需改动。

### 5. 各栈接入片段（写入文档，核心包不引依赖）

```dart
// Navigator 1.0 —— 同一个 map 同时给 MaterialApp 和 SDK，零重复零漂移
await FlutterWright.start(routes: appRoutes);          // appRoutes 也喂给 MaterialApp(routes:)
// 已有自己的 navigatorKey 时：
await FlutterWright.start(navigatorKey: myKey, routes: appRoutes);

// GoRouter —— 递归展开 configuration.routes（:id 动态段原样保留）
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
CallbackNavigationAdapter(
  onNavigate: (r, args, _) => router.go(r, extra: args),
  onReset: () => router.go('/'),
  routesProvider: () => goRouterPaths(router.configuration.routes),
);

// GetX —— getPages 是 List<GetPage>，取 .name
CallbackNavigationAdapter(
  onNavigate: (r, args, _) => Get.toNamed(r, arguments: args),
  onReset: () => Get.until((route) => route.isFirst),
  routesProvider: () => getPages.map((p) => p.name),
);

// FlutterBoost —— routeFactory 枚举不出，app 传一次已知列表
CallbackNavigationAdapter(
  onNavigate: (r, args, _) => BoostNavigator.instance.push(r, arguments: args as Map<String, dynamic>?),
  onReset: () => BoostNavigator.instance.popUntil(route: rootRouteName),
  routesProvider: () => myKnownBoostRoutes, // app 自己维护的 const 列表
);
```

## 影响的文件

**核心代码：**
- 改：`packages/flutter_wright_sdk/lib/src/navigation_adapter.dart`
- 改：`packages/flutter_wright_sdk/lib/src/flutter_wright.dart`
- 改：`packages/flutter_wright_sdk/lib/src/handlers/routes_handler.dart`
- 删：`packages/flutter_wright_sdk/lib/src/route_registry.dart`
- 改：`packages/flutter_wright_sdk/lib/flutter_wright_sdk.dart`（移除第 9 行 `export 'src/route_registry.dart' show RouteRegistry;`）

**版本对齐（现有 drift）：** `pubspec.yaml` 当前 `0.3.0`，但 `flutter_wright.dart` 的 `version` 常量是 `0.4.0`。本次两者统一为 **`0.5.0`**，并更新 `CHANGELOG.md`。

**示例与测试：**
- 改：`packages/example/dev/main_dev.dart`（`testRoutes:` → `routes:`）
- 改：`packages/example/test/e2e_control_plane_test.dart`
- 改：`packages/example/test/e2e_navigation_adapter_test.dart`
- 改：`packages/example/README.md`

**文档（重写路由发现章节 + 加各栈片段）：**
- `README.md`
- `packages/flutter_wright_sdk/README.md`
- `docs/integration-guide.md`
- `docs/integration-guide-for-ai.md`
- `docs/api-reference.md`
- `docs/architecture.md`
- `docs/troubleshooting.md`

## 不在范围内

- **skill 脚本**（`skills/flutter-wright/scripts/*`）：`GET /routes` 的 HTTP 契约未变，不动。
- **独立胶水包**（`flutter_wright_getx` 等）：本阶段不做，靠文档片段接入。
- **历史 superpowers 文档**（`docs/superpowers/specs/2026-05-22-*`、`plans/2026-05-22-*`）：作为历史设计记录保留，不回填。

## 测试

沿用项目既有的 `packages/example/test/` E2E 测试（本项目有 E2E 测试，遵循其约定补充覆盖）：
- `GET /routes` 在 `NavigatorKeyAdapter(routes: ['/a','/b'])` 下返回 `['/a','/b']`。
- `GET /routes` 在无路由来源（默认 adapter、空 routes）下返回 `[]` 且 `ok:true`。
- `GET /routes` 在 `CallbackNavigationAdapter(routesProvider: ...)` 下返回闭包结果。
- `POST /navigate` 对未在任何列表中的路由名仍正常驱动 adapter（证明发现与导航解耦）。
- `start(navigatorKey: customKey)` 时导航走该 key 对应的 NavigatorState。

验证命令：`dart analyze`（零新错误）+ `flutter test`（`packages/example/`）。

## 破坏性变更

- 移除 `FlutterWright.start(testRoutes:)` 参数。
- 移除 `FlutterWright.routes`（`RouteRegistry`）静态字段及 `route_registry.dart`。

迁移：`start(testRoutes: ['/a','/b'])` → Navigator 1.0 用 `start(routes: appRoutesMap)`；其他栈把路由放进 adapter 的 `routesProvider`。属 0.4→0.5 的破坏性变更，记入 CHANGELOG。
