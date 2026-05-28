# flutter_wright_sdk SDK 接入指引(AI 专用)

> **受众**:Claude / Cursor / Copilot 等 AI 编码助手。
> **任务**:把 `flutter_wright_sdk` SDK 集成到一个**已存在**的 Flutter app,使得它可被 `flutter-wright` skill 远程驱动。
>
> 给人类看的版本在 [`integration-guide.md`](./integration-guide.md)。

## 0. 阅读须知(给 AI)

执行规则:

1. **按顺序执行每个 Step**;每个 Step 都给出了"检测"(决定走哪条路径)和"验证"(做完后应该看到的产物)。
2. **不要发明额外抽象**。SDK 已经管理了 server / handler / 导航适配,你只负责接线。
3. **不要加 try/catch 包 `FlutterWright.start(...)`**。它在 release 模式下是 no-op,debug 模式下失败应该让 app crash(暴露问题,而不是悄悄静默)。
4. **默认把 SDK 放 `dev_dependencies` + 用独立 debug 入口**(Step 1/2 推荐路径),让生产 `lib/` 零 SDK 引用。只有当人类明确要求"图省事/单入口"时才放 `dependencies`。
5. **如果检测发现与本指引矛盾的既有代码**(例:已有 `navigatorKey` 用于别的用途),**停下**,把发现报告给人类后再继续。

### 决策路径(先看这里)

```
你需要什么能力?
│
├── 只需要 snapshot / tap / type / scroll / longPress / waitFor
│   └── 只调 FlutterWright.start()  ← 无需 navigatorKey,交互闭环开箱可用
│
└── 需要 goto / reset(程序化跳页)
    ├── Navigator 1.0 命名路由
    │   └── start() + 把 FlutterWright.navigatorKey 注入 MaterialApp
    ├── GoRouter / 其他 URL 路由
    │   └── start(navigationAdapter: CallbackNavigationAdapter(onNavigate: router.go ...))
    └── GetX
        └── start(navigationAdapter: CallbackNavigationAdapter(onNavigate: Get.toNamed ...))
```

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
| ⑦ 端口 9123 是否被占 | 检查 host app 的网络配置,确保没有别的服务用 9123 | 冲突 → 改 SDK 配置 |

**报告格式**(集成开始前先输出给人类):

```
Pre-check 报告:
  ① 已接入 SDK: <yes/no>
  ② 入口文件: <path>
  ③ Flutter 版本: <version>
  ④ App 形态: <MaterialApp / MaterialApp.router / CupertinoApp / GetMaterialApp / 其他>
  ⑤ 路由方案: <Navigator-1 / Navigator-2 / GoRouter / 其他>
  ⑥ navigatorKey 占用: <文件:行号 或 无>
  ⑦ 端口 9123: <空闲 / 占用>
```

若 ① yes → 直接跳到 [Step 7 验证](#step-7-验证)。否则继续 Step 2。

## 2. Step 1:加依赖(决定放哪)

**决策**:
- **推荐(生产零残留)**:放 `dev_dependencies`,配合 Step 2 的独立 debug 入口 —— 生产 `lib/` 不 import SDK,release 构建根本不编译它。
- **图省事(仅当人类要求)**:放 `dependencies`,在 `lib/main.dart` 直接 import;`kDebugMode` 保证 release 运行期 no-op,但 SDK 代码仍进生产包。

**编辑** `pubspec.yaml`(推荐路径):

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  # ... 既有 dev 依赖 ...
  flutter_wright_sdk:
    git:
      url: https://github.com/MySwallow/flutterwright
      path: packages/flutter_wright_sdk
      ref: main
```

(图省事路径:把同样的块放到 `dependencies:` 下。)

**运行**:`flutter pub get`
**验证**:命令退出 0,`pubspec.lock` 出现 `flutter_wright_sdk` 条目。

⚠️ **如果项目用 monorepo 或 melos**:把 SDK 路径声明也加到 `melos.yaml` / 父级 `pubspec.yaml` 的 `packages:` 列表里(若适用)。否则跳过。

## 3. Step 2:启动 SDK

### 推荐:独立 debug 入口(配合 dev_dependencies)

**新建** `dev/main_dev.dart` —— 唯一 import SDK 的文件。生产 `lib/main.dart` 不动、零 SDK 引用。用 `flutter run -t dev/main_dev.dart` 启动。

```dart
// dev/main_dev.dart
import 'package:flutter/material.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';
import 'package:<your_app>/app.dart'; // 你的根 widget

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // start() 无需任何参数即可解锁 snapshot/tap/type/scroll/longPress/waitFor
  // 若还需要 goto/reset,额外传 navigatorKey 或 navigationAdapter(见 Step 3)
  await FlutterWright.start(
    routes: AppRouter.names, // 可选:喂 GET /routes,不影响 goto
  );
  runApp(FlutterWrightRoot(
    child: MyApp(navigatorKey: FlutterWright.navigatorKey), // navigatorKey 仅 goto/reset 路径需要
  ));
}
```

`FlutterWrightRoot` 包根让 `/screenshot` 可靠;Android 上 skill 默认走 adb screencap,可省。若根 widget 不接受注入且你只需要交互(不需要 goto),可以直接 `runApp(FlutterWrightRoot(child: const MyApp()))`,无需注入 key。

### 图省事:单入口(SDK 在 dependencies)

**编辑** `lib/main.dart`,改造 `main()`:

```dart
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // start() 即解锁交互(snapshot/tap/type/scroll/longPress/waitFor)
  // 若需要 goto/reset,在 runApp 中注入 FlutterWright.navigatorKey 并按 Step 3 接线
  await FlutterWright.start(
    routes: AppRouter.names, // 可选:喂 GET /routes,不影响 goto
  );
  runApp(const MyApp()); // 保留原有 runApp
}
```

**规则**(两条路径通用):
- 同步 `void main()` 改为 `Future<void> main() async`。
- 已有异步 init(Firebase、DI)时,`FlutterWright.start` 放它们之后、`runApp` 之前。
- 不要把 `start` 包进 `if (kDebugMode)` —— SDK 内部已判断。

**验证**:
1. `flutter analyze` 退出 0。
2. `grep -rc FlutterWright.start dev/ lib/` 合计为 `1`(不能调用两次)。

## 4. Step 3:把导航接进来(仅 goto/reset 需要,可跳过)

> **如果只需要 snapshot/tap/type/scroll/longPress/waitFor**,Step 2 完成后即可跳过本节直接到 Step 4 验证。`FlutterWright.start()` 无需 navigatorKey 就已开启全套交互。

`/navigate`、`/reset` 经 `NavigationAdapter` 适配,**对路由 API 零假设**。基于 pre-check ④/⑤ 选模板:**命名路由用 A/C(默认 NavigatorKeyAdapter);GoRouter/GetX/auto_route 用 B/D(CallbackNavigationAdapter)。**

### 模板 A — `MaterialApp(...)` + onGenerateRoute(命名路由)

根 widget 接受**可注入**的 navigatorKey;debug 入口传 `FlutterWright.navigatorKey`,生产 `main()` 传 null。

```dart
// lib/app.dart —— 注意:无 SDK import
class MyApp extends StatelessWidget {
  const MyApp({this.navigatorKey, super.key});
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey, // ← 注入
        onGenerateRoute: appRouter, // 既有
      );
}
```

> 单入口(dependencies)路径可直接写 `navigatorKey: FlutterWright.navigatorKey`,不必注入。

### 模板 B — GoRouter / `MaterialApp.router`

GoRouter 不用命名路由,给 `start()` 传 `CallbackNavigationAdapter`,SDK 回调 `router.go`。**不要**把 SDK 的 navigatorKey 塞给 GoRouter。

```dart
// dev/main_dev.dart
final router = GoRouter(routes: [...]); // 你既有的 router
await FlutterWright.start(
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (r, args, _) => router.go(r, extra: args),
    onReset: () => router.go('/'),
    routesProvider: () => goRouterPaths(router.configuration.routes),
  ),
);
runApp(FlutterWrightRoot(child: MyApp(router: router)));
```
`POST /navigate {"route":"/order/123"}` → `router.go('/order/123')`,GoRouter 按 URL 解析。

### 模板 C — `CupertinoApp(...)`

同模板 A,把可注入的 `navigatorKey` 传给 `CupertinoApp(...)`。

### 模板 D — `GetMaterialApp`(GetX)

`Get.toNamed` 是全局静态调用,连 key 都不用注入:

```dart
// dev/main_dev.dart
await FlutterWright.start(
  navigationAdapter: CallbackNavigationAdapter(
    onNavigate: (r, args, _) => Get.toNamed(r, arguments: args),
    onReset: () => Get.until((route) => route.isFirst),
    routesProvider: () => getPages.map((p) => p.name),
  ),
);
runApp(const MyApp()); // 你的 GetMaterialApp 根
```

### 冲突处理(仅命名路由路径)

如 pre-check ⑥ 发现已有顶层 `final navigatorKey = GlobalKey<NavigatorState>();`,**不要**直接覆盖。让 debug 入口把**那个**已有 key 传给 `start(navigationAdapter: NavigatorKeyAdapter(existingKey))`,而不是用 `FlutterWright.navigatorKey`。

**验证**:
1. 命名路由:根 widget 的 `MaterialApp(navigatorKey:)` 接到了注入的 key;GoRouter/GetX:`start(navigationAdapter: ...)` 有匹配。
2. `flutter analyze` 退出 0。

## 5. Step 4:提供可发现路由(可选)

`GET /routes` 返回当前 `NavigationAdapter.discoverableRoutes`;不可枚举的栈返回 `[]`——这不是错误。**`goto` 完全不依赖此列表**,能否跳成功只取决于 app 路由器认不认。

只有当 skill 或 AI 需要"自动发现有哪些页面"时才需要做这一步。

**Navigator 1.0** — 在 `start()` 传 `routes:`：
```dart
// Navigator 1.0 + MaterialApp(routes: map)
await FlutterWright.start(routes: appRoutes.keys);

// Navigator 1.0 + onGenerateRoute
await FlutterWright.start(routes: AppRouter.names);

// 宿主已有自己的 navigatorKey
await FlutterWright.start(navigatorKey: myKey, routes: AppRouter.names);
```

**GoRouter / GetX** — 在 `CallbackNavigationAdapter` 传 `routesProvider:`(已在 Step 3 模板 B/D 中给出)。

**收集路由的查找命令**（辅助用,不是必做步骤）:

```bash
# GoRouter
grep -oE "GoRoute\(\s*path:\s*'[^']+" lib/ -r | grep -oE "'[^']+$" | tr -d "'" | sort -u

# Navigator-1 onGenerateRoute case
grep -oE "case\s*'[^']+'" lib/ -r | grep -oE "'[^']+'" | tr -d "'" | sort -u
```

## 6. Step 5:Android 平台要求

flutter-wright v1 是 **Android-only**。检查 `android/app/build.gradle` 的 `minSdkVersion` ≥ 21(已是 Flutter 默认)。

**不需要**改 `AndroidManifest.xml`:HTTP server 绑在 `127.0.0.1`(loopback),不需要 `INTERNET` permission(虽然多数 app 已有)。

**iOS**:SDK 代码能编但 flutter-wright v1 不驱动 iOS。若 host app 同时跑 iOS,不影响。

## 7. Step 6:验证

按顺序跑下面 4 个检查,任何一条不过都停下来报错。

### 6.1 编译通过

```bash
flutter analyze
# 期望:0 issues
```

### 6.2 启动 app 看 banner

```bash
# dev 入口路径(推荐):
flutter run -d <android_device_or_emulator> -t dev/main_dev.dart
# 单入口路径:flutter run -d <device>
# 期望日志:
#   [flutter_wright_sdk] listening on http://127.0.0.1:9123
```

如未看到该 banner,说明 SDK 没启动 — 检查:
- dev 入口路径:是否带了 `-t dev/main_dev.dart`
- Step 2 的 `await FlutterWright.start(...)` 是否真在 `main` 里、`runApp` 之前
- 是不是 release/profile 构建(SDK 自动 no-op)
- `kDebugMode` 是否为 true

### 6.3 端口转发 + 健康检查

```bash
adb forward tcp:9123 tcp:9123
curl -s http://127.0.0.1:9123/health
# 期望:{"ok":true,"version":"0.4.0"}
```

### 6.4 路由可发现

```bash
curl -s http://127.0.0.1:9123/routes
# 若传了 routes: 或 routesProvider:,期望:{"ok":true,"routes":["/","/order/detail", ...]}
# 若未传,返回 {"ok":true,"routes":[]} 属正常,不是错误
```

## 8. 必须避免的常见错误

| 错误 | 为什么是错的 | 正确做法 |
|---|---|---|
| ❌ 把 `FlutterWright` 调用包进 `try/catch` | 隐藏问题,debug 模式下应崩溃以暴露集成 bug | 不要包,让 app 直接 crash |
| ❌ 在 `start()` 之前调 `bind()` | 抛 `StateError` | 必须先 `start()` |
| ❌ 命名路由路径重复声明 `GlobalKey<NavigatorState>` | 多个 key 会让一个 navigator 失效 | 复用同一个 key(注入或 `FlutterWright.navigatorKey`) |
| ❌ 把 `enableInDebugOnly: false` 设到 release | 生产包开 HTTP 端口 = 安全风险 | 默认值就是对的,**不要**改 |
| ❌ GoRouter 还去设 SDK 的 navigatorKey | GoRouter 用 URL 路由,push 命名路由不触发它 | 用 `CallbackNavigationAdapter(onNavigate: router.go ...)` |
| ❌ dev_dependencies 路径里 `lib/` 直接 import SDK | 触发 `depend_on_referenced_packages`,且破坏"生产零残留" | SDK 只在 `dev/` + `test/` import;`lib/` 用注入 + 本地接口 |
| ❌ 改 SDK package 名 / 用 path 但忘了写 `pubspec_overrides.yaml` | Dart pub 解析失败 | 按 Step 1 的 git 依赖写法 |
| ❌ 在 `flutter_test` 里调 `start()` 不跳过 | 测试进程绑 9123 端口跟主 app 冲突 | 用 `Platform.environment.containsKey('FLUTTER_TEST')` 守卫(参考人类版指引 §9) |
| ❌ skill 调用前忘了 `adb forward tcp:9123 tcp:9123` | curl 全部 connection refused | flutter-wright skill 自动做了,但手动 curl 调试时记得 |

## 9. 失败排查 recipe

| 现象 | grep / 命令 | 含义 |
|---|---|---|
| `flutter analyze` 报 `FlutterWright is not defined` | `grep flutter_wright_sdk pubspec.yaml` 无输出 | Step 1 没做或 `pub get` 失败 |
| 启动后看不到 listening banner | `grep -rc FlutterWright.start dev/ lib/` 应为 1;确认用 `-t dev/main_dev.dart` 启动 | Step 2 漏了 |
| `curl /navigate` 永远 503 "navigator not ready" | 命名路由:`MaterialApp(navigatorKey:)` 是否接到注入的 key;GoRouter/GetX:`start(navigationAdapter:)` 是否传了 | Step 3 漏了 |
| `curl /navigate` 200 但页面不动(GoRouter/GetX) | 用了默认 NavigatorKeyAdapter 但 app 不是命名路由 | 改传 `CallbackNavigationAdapter`(Step 3 模板 B/D) |
| `flutter run` 时 `bind: address already in use` | `lsof -i :9123` 在主机侧 / `netstat` 在设备侧 | 改 SDK config 的 `port` 或杀冲突进程 |

## 10. 完成报告模板

接入完成后,把下面这段给人类(填实际值):

```
✅ flutter_wright_sdk 已接入 <app-name>

变更文件:
  - pubspec.yaml(加 flutter_wright_sdk 依赖,dev_dependencies 优先)
  - dev/main_dev.dart(新建 debug 入口:FlutterWright.start + 注入/adapter)  # 单入口路径则是 lib/main.dart
  - lib/app.dart(根 widget 接受可注入 navigatorKey)  # 命名路由路径

可发现路由(若传了 routes: 或 routesProvider:,否则留空):
  - /home
  - /order/detail
  ...

验证结果:
  [✓] flutter analyze 0 issues
  [✓] 看到 banner: [flutter_wright_sdk] listening on http://127.0.0.1:9123
  [✓] GET /health → 200 {"ok":true,"version":"0.4.0"}
  [✓] GET /routes → 包含 N 条路由

下一步:
  - 在 Claude Code 里运行 `Skill flutter-wright "health"` 验证 skill 端
  - 跑业务流: `Skill flutter-wright "goto /home"` 等
```

---

**版本对照**:本指引基于 `flutter_wright_sdk 0.7.0`(snapshot-first 交互层 + navigatorKey 可选 + dev_dependencies 范式)。SDK 升级后 API 不兼容时,Step 2-4 的代码片段会跟着改。
