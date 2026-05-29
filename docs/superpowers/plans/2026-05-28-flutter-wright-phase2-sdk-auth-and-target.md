# flutter-wright Phase 2(适配性 + 安全)Implementation Plan

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 SDK 在 release 提测包里也能受控启用并可选鉴权(`enabled`/`token`/`/health` 身份),并把控制面端点从脚本里硬编码的 `127.0.0.1:9123` 外置为「目标注册表」,脚本带 token 头、去掉 adb 依赖——落地即满足「release 可用 + 鉴权」。

**Architecture:** 两层协同。**Part A(SDK,Dart)**:`FlutterWright.start()` 顶层加 `enabled`(默认 false,fail-safe)、`token`(可选,X-FW-Token 常量时间比对,`/health` 豁免)、`appName`/`package`(`/health` 身份);移除 `FlutterWrightConfig.enableInDebugOnly`;升 0.8.0。**Part B(脚本,bash)**:`_lib.sh` 加 `fw_resolve_target`(读 `FW_TARGETS` 注册表 → 导出 `FW_BASE`/`FW_TOKEN`/`FW_PACKAGE` + `FW_AUTH` curl 头数组)、重做 `fw_need_sdk`(探 `$FW_BASE/health`,**去掉 adb forward**);9 个 SDK 脚本改用 `$FW_BASE` + token 头。token 契约把两层耦合在一起,故 Part A 先行。

**Tech Stack:** Dart(`dart:io` HttpServer,flutter_test + 真实 curl 子进程);bash 3.2 / BSD coreutils;Python `http.server` mock(测试)。

> **范围与边界:** 覆盖 spec 的 **Phase 2 = 设计 3、9、5 + 设计 4「单目标子集」**。**不做**(留待后续):多目标 `target=` 的注册工具与 `adb forward` 注册时建立(设计 6,Phase 3)、`logs` 改 logcat、移除 run/reload/stop、SKILL.md/方法面全面收敛(设计 7/8/10,Phase 4)。Part A 单独完成即产出可交付的 SDK 0.8.0(`flutter test` 全绿),是一个自然的暂停点。
>
> **bash 3.2 已验证约束**(实机 3.2.57,落地务必照用):
> - 空数组直接展开 `"${a[@]}"` 在 `set -u` 下报 unbound;**curl 头数组一律用 `"${FW_AUTH[@]+"${FW_AUTH[@]}"}"`**。
> - `${#a[@]}`(计数)在空数组安全;`${a[*]}` 在空数组报错——错误信息别用 `[*]`。
> - 注册表用 **`|` 分隔**(非空白,`read` 不折叠空中间字段;URL/token/package 不含 `|`);**不要用 Tab**(IFS 空白会折叠空 token)。

**新增退出码(Part B)**:`14` = 目标注册表缺失/无可用条目;`15` = `target=` 指定的目标不存在,或多条目却未带 `target=`(歧义)。

---

## Part A — SDK 0.8.0:enable + token + health 身份(设计 3、9)

### Task A1: `enabled` 开关 + 移除 `enableInDebugOnly` + 迁移所有调用点(设计 3,TDD)

把启用从「debug-only」改为宿主显式 `enabled`(默认 false = 安全)。这是破坏性 API 变更:默认不再绑定,所有现有 `start()` 调用点都要显式传 `enabled`,否则控制面不起、相关测试全红。

**Files:**
- Create: `packages/flutter_wright_sdk/test/enabled_token_test.dart`(本任务先放 gating 用例,A2/A3 续填)
- Modify: `packages/flutter_wright_sdk/lib/src/config.dart`(移除 `enableInDebugOnly`)
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`(`start()` 加 `enabled`、换门控、`version` → 0.8.0)
- Modify: `packages/flutter_wright_sdk/pubspec.yaml`(version → 0.8.0)
- Modify 调用点(加 `enabled: true`,dev 入口用 `enabled: kDebugMode`):
  - `packages/flutter_wright_sdk/test/start_navigation_test.dart:25,36`
  - `packages/example/test/e2e_control_plane_test.dart:96`
  - `packages/example/test/e2e_navigation_adapter_test.dart:103`
  - `packages/example/test/e2e_interaction_test.dart:58`
  - `packages/example/test/getx_integration_test.dart:119,204`
  - `packages/example/test/e2e_route_discovery_test.dart:73,97`
  - `packages/example/dev/main_dev.dart:21`

- [ ] **Step 1: 写失败的测试**

创建 `packages/flutter_wright_sdk/test/enabled_token_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

const String _base = 'http://127.0.0.1:9123';

/// 真实 curl(flutter_test 会 fake 进程内 HttpClient,故走子进程)。
/// 返回 HTTP 状态码;可选 token 注入 X-FW-Token 头。
Future<int> _code(String path, {String? token, String method = 'GET'}) async {
  final args = <String>['-s', '-o', '/dev/null', '-w', '%{http_code}'];
  if (method == 'POST') {
    args.addAll(<String>['-X', 'POST', '-H', 'content-type: application/json', '-d', '{}']);
  }
  if (token != null) args.addAll(<String>['-H', 'X-FW-Token: $token']);
  args.add('$_base$path');
  final res = await Process.run('curl', args);
  return int.tryParse(res.stdout.toString().trim()) ?? 0;
}

Future<Map<String, Object?>> _json(String path, {String? token}) async {
  final tmp = await Directory.systemTemp.createTemp('fw_h_');
  final out = File('${tmp.path}/b');
  try {
    final args = <String>['-s', '-o', out.path, '-w', '%{http_code}'];
    if (token != null) args.addAll(<String>['-H', 'X-FW-Token: $token']);
    args.add('$_base$path');
    await Process.run('curl', args);
    return jsonDecode(await out.readAsString()) as Map<String, Object?>;
  } finally {
    await tmp.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async => FlutterWright.stop());

  testWidgets('enabled:false → 不绑定', (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(enabled: false));
    expect(FlutterWright.isRunning, isFalse);
  });

  testWidgets('enabled:true → 绑定', (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(enabled: true));
    try {
      expect(FlutterWright.isRunning, isTrue);
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test test/enabled_token_test.dart`
Expected: FAIL — 编译错误 `The named parameter 'enabled' isn't defined`(`start()` 尚无 `enabled`)。**确认是这个错误再继续。**

- [ ] **Step 3: 实现——config 移除 `enableInDebugOnly`**

在 `packages/flutter_wright_sdk/lib/src/config.dart` 删除构造参数与字段。把构造器中的:

```dart
    this.enableInDebugOnly = true,
    this.autoStart = true,
```
改为:
```dart
    this.autoStart = true,
```
并删除字段定义(连同其 doc 注释):
```dart
  /// If true (default), `start()` returns without binding when not in debug.
  final bool enableInDebugOnly;

```

- [ ] **Step 4: 实现——`start()` 加 `enabled` + 换门控 + 升版本**

在 `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`:

把 `static const String version = '0.7.0';` 改为 `static const String version = '0.8.0';`。

把方法签名与开头门控:
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
```
替换为(顶层新增 `enabled`,默认 false;`appName`/`package`/`token` 留给 A2/A3,本步先加 `enabled`):
```dart
  static Future<void> start({
    bool enabled = false,
    FlutterWrightConfig config = const FlutterWrightConfig(),
    NavigationAdapter? navigationAdapter,
    GlobalKey<NavigatorState>? navigatorKey,
    Iterable<String> routes = const <String>[],
  }) async {
    if (!enabled) {
      vlLog('FlutterWright disabled (enabled: false)');
      return;
    }
```
并把方法上方 doc 注释里这一句:
```dart
  /// In release builds (or when `config.enableInDebugOnly == true` and
  /// `kDebugMode` is false), returns without binding.
```
替换为:
```dart
  /// Returns without binding unless `enabled` is true. The host controls this
  /// (e.g. `enabled: AppEnv.isTestBuild`); production builds pass false → the
  /// control plane never binds (fail-safe).
```

> `kDebugMode` 此前由这段门控引用;移除后 `flutter_wright.dart` 顶部 `import 'package:flutter/foundation.dart';` 可能变为未用。若 `flutter analyze` 报未用 import,删除该行;若其它地方仍用到(如无),保留。

- [ ] **Step 5: 迁移所有 `start()` 调用点**

逐个把下列调用点加上 `enabled`(测试用 `true`,dev 入口用 `kDebugMode`)。规则:在 `FlutterWright.start(` 之后插入 `enabled: true,`(或对无参的 `start()` 写成 `start(enabled: true)`)。

`packages/flutter_wright_sdk/test/start_navigation_test.dart`:
- 第 25 行 `await tester.runAsync(() => FlutterWright.start());` → `await tester.runAsync(() => FlutterWright.start(enabled: true));`
- 第 36 行 `() => FlutterWright.start(navigatorKey: FlutterWright.navigatorKey));` → `() => FlutterWright.start(enabled: true, navigatorKey: FlutterWright.navigatorKey));`

`packages/example/test/e2e_control_plane_test.dart:96` 起:
```dart
    await tester.runAsync(() => FlutterWright.start(
          navigatorKey: FlutterWright.navigatorKey,
          routes: AppRouter.names,
        ));
```
→ 在 `start(` 后加一行 `enabled: true,`:
```dart
    await tester.runAsync(() => FlutterWright.start(
          enabled: true,
          navigatorKey: FlutterWright.navigatorKey,
          routes: AppRouter.names,
        ));
```

其余按同规则在各 `FlutterWright.start(` 之后插入 `enabled: true,`:
- `packages/example/test/e2e_navigation_adapter_test.dart:103`
- `packages/example/test/e2e_interaction_test.dart:58`
- `packages/example/test/getx_integration_test.dart:119` 和 `:204`
- `packages/example/test/e2e_route_discovery_test.dart:73` 和 `:97`

`packages/example/dev/main_dev.dart:21` 起的 `await FlutterWright.start(` 后插入 `enabled: kDebugMode,`(这是宿主开关的范例:测试包开、正式包关)。若 `kDebugMode` 未导入,在该文件顶部加 `import 'package:flutter/foundation.dart';`。

- [ ] **Step 6: 运行 gating 测试 + 全量套件确认通过**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test test/enabled_token_test.dart`
Expected: PASS(2 用例)。

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test` 然后 `cd packages/example && /Users/mini/development/flutter/bin/flutter test`
Expected: 两包全绿(迁移后 `enabled: true` 让控制面照常绑定)。

- [ ] **Step 7: pubspec 升版本**

`packages/flutter_wright_sdk/pubspec.yaml`:`version: 0.7.0` → `version: 0.8.0`。

- [ ] **Step 8: 暂存变更,等用户审阅**

```bash
git add packages/flutter_wright_sdk/test/enabled_token_test.dart \
        packages/flutter_wright_sdk/lib/src/config.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart \
        packages/flutter_wright_sdk/pubspec.yaml \
        packages/flutter_wright_sdk/test/start_navigation_test.dart \
        packages/example/test/e2e_control_plane_test.dart \
        packages/example/test/e2e_navigation_adapter_test.dart \
        packages/example/test/e2e_interaction_test.dart \
        packages/example/test/getx_integration_test.dart \
        packages/example/test/e2e_route_discovery_test.dart \
        packages/example/dev/main_dev.dart
```
**不要 commit**——由用户审阅后自行 commit。

---

### Task A2: token 鉴权中间件(设计 3,TDD)

宿主可传非空 `token`;之后除 `/health` 外所有请求须带匹配的 `X-FW-Token`,否则 401。常量时间比对避免计时侧信道。token 为空 = 不鉴权(仅靠 loopback + enabled)。

**Files:**
- Modify: `packages/flutter_wright_sdk/lib/src/http_server.dart`(server 持 token + `_dispatch` 校验 + 常量时间比对)
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`(`start()` 加 `token`,传入 server)
- Modify: `packages/flutter_wright_sdk/test/enabled_token_test.dart`(加 token 用例)

- [ ] **Step 1: 写失败的测试**

在 `enabled_token_test.dart` 的 `main()` 末尾(`}` 之前)追加:

```dart
  testWidgets('token: 缺/错 → 401,对 → 非401;/health 豁免',
      (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(enabled: true, token: 'secret'));
    try {
      expect((await tester.runAsync(() => _code('/snapshot')))!, 401,
          reason: '缺 token 应 401');
      expect((await tester.runAsync(() => _code('/snapshot', token: 'wrong')))!, 401,
          reason: '错 token 应 401');
      final ok = (await tester.runAsync(() => _code('/snapshot', token: 'secret')))!;
      expect(ok, isNot(401), reason: '对 token 应通过鉴权');
      expect((await tester.runAsync(() => _code('/health')))!, 200,
          reason: '/health 不需 token');
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });

  testWidgets('token:null → 不鉴权,/snapshot 无 token 也非401',
      (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(enabled: true));
    try {
      expect((await tester.runAsync(() => _code('/snapshot')))!, isNot(401));
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });

  testWidgets("token:'' 等同 null:不鉴权,/snapshot 非401",
      (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(enabled: true, token: ''));
    try {
      expect((await tester.runAsync(() => _code('/snapshot')))!, isNot(401));
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });

  testWidgets('401 响应体为 {ok:false} JSON 信封', (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(enabled: true, token: 'secret'));
    try {
      final body = (await tester.runAsync(() => _json('/snapshot')))!;
      expect(body['ok'], false, reason: '401 body 应是 {ok:false, error:...}');
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test test/enabled_token_test.dart`
Expected: FAIL — 编译错误 `The named parameter 'token' isn't defined`。**确认再继续。**

- [ ] **Step 3: 实现——http_server 持 token + 校验 + 常量时间比对**

`packages/flutter_wright_sdk/lib/src/http_server.dart`:

把构造器与字段:
```dart
  FlutterWrightHttpServer({required this.config, required this.handlers});

  final FlutterWrightConfig config;
  final List<Handler> handlers;
```
改为:
```dart
  FlutterWrightHttpServer({
    required this.config,
    required this.handlers,
    this.token,
  });

  final FlutterWrightConfig config;
  final List<Handler> handlers;

  /// When non-empty, every request except `/health` must carry a matching
  /// `X-FW-Token` header. Null/empty = no auth (loopback-only protection).
  final String? token;
```

在 `_dispatch` 里,把:
```dart
      final method = req.method.toUpperCase();
      final path = req.uri.path;
      final handler = handlers.firstWhere(
```
改为(在查 handler 前插入 token 闸门):
```dart
      final method = req.method.toUpperCase();
      final path = req.uri.path;
      final t = token;
      // '/health' exact match: '/health/' is NOT exempt (→ 401, then 404), by design.
      if (t != null && t.isNotEmpty && path != '/health') {
        final provided = req.headers.value('x-fw-token') ?? '';
        if (!_constantTimeEquals(provided, t)) {
          await req.writeError(401, 'unauthorized: missing or invalid X-FW-Token');
          return;
        }
      }
      final handler = handlers.firstWhere(
```

在文件末尾(`class _NotFound` 之后)加入常量时间比对工具:
```dart
/// Constant-time string compare (avoids leaking match progress via timing).
/// The length check can leak length, which is acceptable for a bearer token.
bool _constantTimeEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  if (ab.length != bb.length) return false;
  var diff = 0;
  for (var i = 0; i < ab.length; i++) {
    diff |= ab[i] ^ bb[i];
  }
  return diff == 0;
}
```
> `utf8` 来自 `dart:convert`(http_server.dart 顶部已 `import 'dart:convert';`);`req.writeError` 来自 `handlers/handler.dart` 的扩展(已 import)。

- [ ] **Step 4: 实现——`start()` 加 `token` 并传入 server**

`packages/flutter_wright_sdk/lib/src/flutter_wright.dart`:

在签名里 `bool enabled = false,` 之后加一行 `String? token,`:
```dart
  static Future<void> start({
    bool enabled = false,
    String? token,
    FlutterWrightConfig config = const FlutterWrightConfig(),
```

把:
```dart
    _server = FlutterWrightHttpServer(config: config, handlers: handlers);
```
改为:
```dart
    _server = FlutterWrightHttpServer(
      config: config,
      handlers: handlers,
      token: token,
    );
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test test/enabled_token_test.dart`
Expected: PASS(4 用例)。

- [ ] **Step 6: 暂存变更,等用户审阅**

```bash
git add packages/flutter_wright_sdk/lib/src/http_server.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart \
        packages/flutter_wright_sdk/test/enabled_token_test.dart
```
**不要 commit。**

---

### Task A3: `/health` 应用身份(设计 9,TDD)

`/health`(免 token)除存活外回应用身份 `name`/`package`,供发现/探活确认「打的是哪个 app」。身份由宿主在 `start()` 提供(SDK 不自探,符合非目标);未提供则为 null。

**Files:**
- Modify: `packages/flutter_wright_sdk/lib/src/handlers/health_handler.dart`(加 `appName`/`package` 字段与输出)
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`(`start()` 加 `appName`/`package`,传给 HealthHandler)
- Modify: `packages/flutter_wright_sdk/test/enabled_token_test.dart`(加身份用例)

- [ ] **Step 1: 写失败的测试**

在 `enabled_token_test.dart` 的 `main()` 末尾追加:

```dart
  testWidgets('/health 携带宿主身份 name/package + 存活字段',
      (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(
          enabled: true,
          appName: 'Demo',
          package: 'com.acme.demo',
        ));
    try {
      final h = (await tester.runAsync(() => _json('/health')))!;
      expect(h['ok'], true);
      expect(h['service'], 'flutter_wright_sdk');
      expect(h['version'], FlutterWright.version);
      expect(h['name'], 'Demo');
      expect(h['package'], 'com.acme.demo');
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test test/enabled_token_test.dart`
Expected: FAIL — 编译错误 `The named parameter 'appName' isn't defined`。**确认再继续。**

- [ ] **Step 3: 实现——HealthHandler 加身份**

把 `packages/flutter_wright_sdk/lib/src/handlers/health_handler.dart` 整体替换为:

```dart
import 'handler.dart';

class HealthHandler extends Handler {
  HealthHandler(this.version, {this.appName, this.package});

  final String version;
  final String? appName;
  final String? package;

  @override
  String get path => '/health';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    await ctx.request.writeJson(200, <String, Object?>{
      'ok': true,
      'service': 'flutter_wright_sdk',
      'version': version,
      'name': appName,
      'package': package,
    });
  }
}
```

- [ ] **Step 4: 实现——`start()` 加 `appName`/`package` 并传入**

`packages/flutter_wright_sdk/lib/src/flutter_wright.dart`:

签名里 `String? token,` 之后加两行:
```dart
    bool enabled = false,
    String? token,
    String? appName,
    String? package,
    FlutterWrightConfig config = const FlutterWrightConfig(),
```

把 handlers 列表里:
```dart
      HealthHandler(version),
```
改为:
```dart
      HealthHandler(version, appName: appName, package: package),
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd packages/flutter_wright_sdk && /Users/mini/development/flutter/bin/flutter test test/enabled_token_test.dart`
Expected: PASS(5 用例)。

并跑一次 example 包确认 `/health` 旧断言未破:
Run: `cd packages/example && /Users/mini/development/flutter/bin/flutter test test/e2e_control_plane_test.dart`
Expected: PASS(e2e_control_plane 的 `/health` 仍断言 `ok/service/version`,新增 name/package 不影响)。

- [ ] **Step 6: 暂存变更,等用户审阅**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/health_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart \
        packages/flutter_wright_sdk/test/enabled_token_test.dart
```
**不要 commit。**

---

### Task A4: CHANGELOG 0.8.0(迁移说明)

记录破坏性变更与迁移路径,供集成方升级。

**Files:**
- Modify: `packages/flutter_wright_sdk/CHANGELOG.md`(在顶部 `# 更新日志` 之后插入 0.8.0 段)

- [ ] **Step 1: 写 0.8.0 条目**

在 `CHANGELOG.md` 的标题行 `# 更新日志` 与 `## 0.7.0 - 2026-05-27` 之间插入:

```markdown

## 0.8.0 - 2026-05-28

### 破坏性变更
- **启用改为宿主显式控制**:`FlutterWright.start({bool enabled = false})`。默认 **false → 不绑定控制面**(fail-safe,正式包零运行时攻击面)。移除 `FlutterWrightConfig.enableInDebugOnly`。
  - 迁移:旧 `enableInDebugOnly: true`(仅 debug 启用)≈ `FlutterWright.start(enabled: kDebugMode)`;提测的 release 包按自有「测试包?」判断接线,如 `FlutterWright.start(enabled: AppEnv.isTestBuild)`。

### 新增
- **可选 token 鉴权**:`start({String? token})`。非空时除 `GET /health` 外所有请求须带匹配 `X-FW-Token`,否则 401(常量时间比对)。为空 = 不鉴权(仅 loopback)。token 由集成方自定,只从 env/本地配置读,**绝不进仓库**。
- **`/health` 应用身份**:`start({String? appName, String? package})`,`/health`(免 token)回 `{ok, service, version, name, package}`,供发现/探活确认目标 app。`name`/`package` 未设时为 JSON `null`(键始终存在,便于强类型反序列化)。

```

- [ ] **Step 2: 暂存变更,等用户审阅**

```bash
git add packages/flutter_wright_sdk/CHANGELOG.md
```
**不要 commit。**

---

## Part B — 脚本目标外置 + 鉴权(设计 5、4 单目标)

> **Part B 前提**:Part A 已落地(SDK 支持 `enabled`/`token`/`/health` 身份)。Part B 让脚本从硬编码 `127.0.0.1:9123` 改为读「目标注册表」拿 `base`/`token`/`package`,并携带 token 头;`fw_need_sdk` 不再依赖 adb。

### Task B1: `_lib.sh` 目标解析 + 鉴权头 + 重做 `fw_need_sdk`(设计 5,TDD)

**Files:**
- Create: `skills/flutter-wright/test/resolve_target_test.sh`
- Modify: `skills/flutter-wright/scripts/_lib.sh`(新增 `fw_resolve_target`;重写 `fw_need_sdk`)

- [ ] **Step 1: 写失败的测试**

创建 `skills/flutter-wright/test/resolve_target_test.sh`:

```bash
#!/usr/bin/env bash
# resolve_target_test.sh — fw_resolve_target reads the FW_TARGETS registry (pipe-delimited
# name|base|token|package), exports FW_BASE/FW_TOKEN/FW_PACKAGE and builds the FW_AUTH
# curl-header array. Exits 14 (no usable registry) / 15 (ambiguous or unknown target).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../scripts/_lib.sh"

reg="$(mktemp -t fw-reg.XXXXXX)"
trap 'rm -f "$reg"' EXIT
fail=0

# --- single entry, no token: FW_AUTH empty ---
printf 'shop|http://127.0.0.1:9123||com.acme.shop\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_BASE" = "http://127.0.0.1:9123" ] || { echo "FAIL: base=$FW_BASE" >&2; fail=1; }
[ -z "$FW_TOKEN" ] || { echo "FAIL: token should be empty, got '$FW_TOKEN'" >&2; fail=1; }
[ "$FW_PACKAGE" = "com.acme.shop" ] || { echo "FAIL: package=$FW_PACKAGE" >&2; fail=1; }
[ "${#FW_AUTH[@]}" -eq 0 ] || { echo "FAIL: FW_AUTH should be empty (len ${#FW_AUTH[@]})" >&2; fail=1; }

# --- single entry, with token: FW_AUTH = (-H "X-FW-Token: sec") ---
printf 'qa|http://127.0.0.1:9200|sec|com.acme.qa\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target
[ "$FW_TOKEN" = "sec" ] || { echo "FAIL: token=$FW_TOKEN" >&2; fail=1; }
if [ "${#FW_AUTH[@]}" -eq 2 ] && [ "${FW_AUTH[0]}" = "-H" ] && [ "${FW_AUTH[1]}" = "X-FW-Token: sec" ]; then :; else
  echo "FAIL: FW_AUTH wrong (len ${#FW_AUTH[@]})" >&2; fail=1
fi

# --- two entries, target= selects ---
printf 'a|http://127.0.0.1:1|t1|p1\nb|http://127.0.0.1:2|t2|p2\n' > "$reg"
FW_TARGETS="$reg" fw_resolve_target target=b
{ [ "$FW_BASE" = "http://127.0.0.1:2" ] && [ "$FW_TOKEN" = "t2" ]; } || { echo "FAIL: target= base=$FW_BASE token=$FW_TOKEN" >&2; fail=1; }

# --- error paths (function calls exit → run in subshell) ---
( unset FW_TARGETS; fw_resolve_target ) 2>/dev/null; rc=$?
[ "$rc" -eq 14 ] || { echo "FAIL: missing registry expected 14, got $rc" >&2; fail=1; }
( FW_TARGETS="$reg" fw_resolve_target ) 2>/dev/null; rc=$?
[ "$rc" -eq 15 ] || { echo "FAIL: ambiguous expected 15, got $rc" >&2; fail=1; }
( FW_TARGETS="$reg" fw_resolve_target target=zzz ) 2>/dev/null; rc=$?
[ "$rc" -eq 15 ] || { echo "FAIL: unknown target expected 15, got $rc" >&2; fail=1; }

# --- set -e compatibility: empty token must NOT abort the caller (callers run set -euo
#     pipefail; an empty-token registry is the common no-auth path). Regression guard. ---
printf 'shop|http://127.0.0.1:9123||com.acme.shop\n' > "$reg"
FW_TARGETS="$reg" FW_LIB="$DIR/../scripts/_lib.sh" bash -c '
  set -euo pipefail
  source "$FW_LIB"
  fw_resolve_target
  [ -n "$FW_BASE" ]
'
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: empty token aborts fw_resolve_target under set -e (got $rc)" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: fw_resolve_target registry resolution"
exit "$fail"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash skills/flutter-wright/test/resolve_target_test.sh`
Expected: FAIL — `fw_resolve_target: command not found`(或非零退出),因为 `_lib.sh` 尚无该函数。**确认再继续。**

- [ ] **Step 3: 实现——`_lib.sh` 加 `fw_resolve_target`**

在 `skills/flutter-wright/scripts/_lib.sh` 末尾(`fw_locate_flutter` 之后)追加:

```bash
# fw_resolve_target — resolve the SDK target from the registry at $FW_TARGETS.
#   Registry: pipe-delimited lines `name|base|token|package` (# comments / blanks skipped;
#   pipe is non-whitespace so empty middle fields like an empty token survive).
#   Reads an optional `target=<name>` from "$@" (does NOT touch positional args — each
#   SDK script also ignores target= in its own arg loop). Single entry => default;
#   multiple entries require target=. Sets+exports FW_BASE/FW_TOKEN/FW_PACKAGE and the
#   FW_AUTH array (curl -H args; empty when no token). Exits 14 (no usable registry) /
#   15 (target not found or ambiguous).
fw_resolve_target() {
  local want="" a
  for a in "$@"; do case "$a" in target=*) want="${a#target=}";; esac; done

  local reg="${FW_TARGETS:-}"
  if [ -z "$reg" ] || [ ! -f "$reg" ]; then
    echo "ERR: target registry not found. Set FW_TARGETS to a registry file (see «目标» in SKILL.md)." >&2
    exit 14
  fi
  local lines
  lines="$(grep -vE '^[[:space:]]*(#|$)' "$reg" || true)"
  [ -n "$lines" ] || { echo "ERR: target registry '$reg' has no entries." >&2; exit 14; }

  local line
  if [ -n "$want" ]; then
    line="$(printf '%s\n' "$lines" | awk -F'|' -v n="$want" '$1==n{print; exit}')"
    [ -n "$line" ] || { echo "ERR: target '$want' not found in '$reg'." >&2; exit 15; }
  else
    local count
    count="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
    [ "$count" = "1" ] || { echo "ERR: registry has $count targets; pass target=<name> to choose one." >&2; exit 15; }
    line="$lines"
  fi

  local _n
  IFS='|' read -r _n FW_BASE FW_TOKEN FW_PACKAGE <<< "$line"
  [ -n "${FW_BASE:-}" ] || { echo "ERR: registry entry '${_n:-?}' has empty base." >&2; exit 14; }
  export FW_BASE FW_TOKEN FW_PACKAGE
  # if/then (not `[ ] && ...`): under the callers' `set -e`, a false `[ -n "" ]` as the
  # function's LAST statement would make fw_resolve_target return 1 and abort the script
  # on the common no-token path. `if` with no else returns 0 when the token is empty.
  FW_AUTH=()
  if [ -n "${FW_TOKEN:-}" ]; then
    FW_AUTH=(-H "X-FW-Token: $FW_TOKEN")
  fi
}
```

- [ ] **Step 4: 实现——重写 `fw_need_sdk`(去 adb forward,探 `$FW_BASE/health`)**

把 `skills/flutter-wright/scripts/_lib.sh` 中**整个** `fw_need_sdk` 函数(从 `# fw_need_sdk —` 注释块到其闭合 `}`)替换为:

```bash
# fw_need_sdk — the in-app SDK is reachable. Requires FW_BASE (set by fw_resolve_target).
#   Probes GET $FW_BASE/health (unauthenticated, design 9). No adb/device dependency.
#   Exits 13 (no curl) / 14 (no target resolved) / 12 (SDK unreachable).
fw_need_sdk() {
  command -v curl >/dev/null 2>&1 || { echo "ERR: curl not installed." >&2; exit 13; }
  [ -n "${FW_BASE:-}" ] || { echo "ERR: no target resolved — call fw_resolve_target first." >&2; exit 14; }
  if ! curl -sf "$FW_BASE/health" >/dev/null; then
    echo "ERR: SDK not reachable at $FW_BASE/health. Is the app running with FlutterWright.start(enabled: true)?" >&2
    exit 12
  fi
}
```

> 保留 `fw_need_adb`(adb-only 方法 screenshot/press_key/back/set_viewport/reset_viewport/run 仍用)与 `fw_locate_flutter` 不变。删除了原 `fw_need_sdk` 的 marker fast-path 与 `adb forward`。

- [ ] **Step 5: 运行测试确认通过**

Run: `bash skills/flutter-wright/test/resolve_target_test.sh`
Expected: PASS — `PASS: fw_resolve_target registry resolution`,退出码 0。

Run: `bash -n skills/flutter-wright/scripts/_lib.sh && echo "syntax ok"`
Expected: `syntax ok`。

- [ ] **Step 6: 暂存变更,等用户审阅**

```bash
git add skills/flutter-wright/test/resolve_target_test.sh skills/flutter-wright/scripts/_lib.sh
```
**不要 commit。**

---

### Task B2: 迁移测试 harness + 扩展 mock(支撑 B3/B4)

`fw_need_sdk` 已改为探 `$FW_BASE/health`,旧的 marker 路径作废。给 harness 加 `fw_test_setup_target`(起 mock 后写一条注册表、导出 `FW_TARGETS`);扩展 mock 支持 `GET /snapshot`、`GET /wait_for`(供 B4 冒烟)。

**Files:**
- Modify: `skills/flutter-wright/test/_helpers.sh`(删 `fw_test_setup_marker`,加 `fw_test_setup_target`)
- Modify: `skills/flutter-wright/test/mock_sdk.py`(GET `/snapshot`、`/wait_for` → 200)

- [ ] **Step 1: 实现——`_helpers.sh` 加 `fw_test_setup_target`,删 marker**

把 `skills/flutter-wright/test/_helpers.sh` 中**整个** `fw_test_setup_marker` 函数(从其 `# fw_test_setup_marker —` 注释到闭合 `}`)替换为:

```bash
# fw_test_setup_target [token] — write a one-entry registry pointing at the running mock
# and export FW_TARGETS. Call AFTER fw_mock_start (needs FW_MOCK_PORT). The trap should
# also `rm -f "${FW_TARGETS:-}"`.
fw_test_setup_target() {
  local token="${1:-}"
  [ -n "${FW_MOCK_PORT:-}" ] || { echo "ERR: FW_MOCK_PORT not set — call fw_mock_start first." >&2; return 1; }
  FW_TARGETS="$(mktemp -t fw-reg.XXXXXX)"
  export FW_TARGETS
  printf 'local-mock|http://127.0.0.1:%s|%s|com.test.app\n' "$FW_MOCK_PORT" "$token" > "$FW_TARGETS"
}
```

- [ ] **Step 2: 实现——mock 支持 GET /snapshot 与 /wait_for**

`skills/flutter-wright/test/mock_sdk.py`:把 `do_GET` 方法:
```python
    def do_GET(self):
        if self.path == "/health":
            return self._send(200, "ok")
        return self._send(404, "not found")
```
替换为(`/wait_for` 带查询串,故按前缀判断):
```python
    def do_GET(self):
        if self.path == "/health":
            return self._send(200, "ok")
        if self.path == "/snapshot" or self.path == "/wait_for" or self.path.startswith("/wait_for?"):
            return self._send(200, '- text "mock" [ref=s1]\n')
        return self._send(404, "not found")
```

并把 `do_POST` 的端点集合补全为所有交互 POST 端点(使 tap/type/scroll/long_press 也能被冒烟驱动,如 type.sh 的 `submit=true` 路径需要 /type 先回 200):
```python
    def do_POST(self):
        if self.path in ("/navigate", "/reset", "/tap", "/type", "/scroll", "/long_press"):
            return self._send(STATUS, NAV_BODY)
        return self._send(404, "not found")
```

- [ ] **Step 3: 静态检查 + 冒烟**

Run:
```bash
bash -n skills/flutter-wright/test/_helpers.sh && python3 -m py_compile skills/flutter-wright/test/mock_sdk.py && \
bash -c 'set -uo pipefail; source skills/flutter-wright/test/_helpers.sh
fw_mock_start && fw_test_setup_target tok123
echo "registry:"; cat "$FW_TARGETS"
source skills/flutter-wright/scripts/_lib.sh; fw_resolve_target
echo "FW_BASE=$FW_BASE FW_TOKEN=$FW_TOKEN auth_len=${#FW_AUTH[@]}"
curl -s -o /dev/null -w "snapshot=%{http_code}\n" "$FW_BASE/snapshot"
fw_mock_stop; rm -f "$FW_TARGETS"'
```
Expected: 打印 registry 行(`local-mock|http://127.0.0.1:<port>|tok123|com.test.app`)、`FW_BASE=...:<port> FW_TOKEN=tok123 auth_len=2`、`snapshot=200`。

- [ ] **Step 4: 暂存变更,等用户审阅**

```bash
git add skills/flutter-wright/test/_helpers.sh skills/flutter-wright/test/mock_sdk.py
```
**不要 commit。**

---

### Task B3: 迁移 POST 脚本 + Phase 1 退出码测试(设计 5,TDD)

把 6 个 POST 脚本(tap/type/scroll/long_press/goto/reset)从 `VL_PORT`+硬编码改为 `$FW_BASE` + token 头;同步把 Phase 1 的 `goto_exit_code_test.sh`/`reset_exit_code_test.sh` 迁到注册表 harness。

**Files:**
- Modify: `skills/flutter-wright/scripts/{tap,type,scroll,long_press,goto,reset}.sh`
- Modify: `skills/flutter-wright/test/{goto_exit_code_test,reset_exit_code_test}.sh`

每个脚本的统一改法(four edits per file):①`fw_need_sdk` 前插入 `fw_resolve_target "$@"`;②删 `PORT="${VL_PORT:-9123}"` 行;③在其参数解析 `case` 里加 `target=*) ;;`(已被 fw_resolve_target 消费);④curl 的 URL `"http://127.0.0.1:$PORT/<ep>"` → `"$FW_BASE/<ep>"` 并加鉴权头 `"${FW_AUTH[@]+"${FW_AUTH[@]}"}"`,`000)` 提示里 `127.0.0.1:$PORT` → `$FW_BASE`。

- [ ] **Step 1: 先迁移测试(RED)——goto/reset 退出码测试改用注册表**

`skills/flutter-wright/test/goto_exit_code_test.sh`:把
```bash
fw_test_setup_marker
fw_mock_start 501 || exit 1
trap 'fw_mock_stop; rm -rf "${CLAUDE_JOB_DIR:-}"' EXIT
```
替换为:
```bash
fw_mock_start 501 || exit 1
fw_test_setup_target
trap 'fw_mock_stop; rm -f "${FW_TARGETS:-}"' EXIT
```
并把运行行
```bash
err="$(VL_PORT="$FW_MOCK_PORT" bash "$FW_SCRIPTS_DIR/goto.sh" /order/detail 2>&1 >/dev/null)"
```
替换为(FW_TARGETS 已 export,脚本自行解析):
```bash
err="$(bash "$FW_SCRIPTS_DIR/goto.sh" /order/detail 2>&1 >/dev/null)"
```

`skills/flutter-wright/test/reset_exit_code_test.sh`:同样把 `fw_test_setup_marker` + `fw_mock_start 501 || exit 1` + 旧 trap 三行替换为:
```bash
fw_mock_start 501 || exit 1
fw_test_setup_target
trap 'fw_mock_stop; rm -f "${FW_TARGETS:-}"' EXIT
```
并把运行行
```bash
err="$(VL_PORT="$FW_MOCK_PORT" bash "$FW_SCRIPTS_DIR/reset.sh" 2>&1 >/dev/null)"
```
替换为:
```bash
err="$(bash "$FW_SCRIPTS_DIR/reset.sh" 2>&1 >/dev/null)"
```

- [ ] **Step 2: 运行确认失败**

Run: `bash skills/flutter-wright/test/goto_exit_code_test.sh`
Expected: FAIL —— `goto.sh` 尚未迁移,仍用旧 `fw_need_sdk`(现在要求 `FW_BASE` 却没人设)或仍 curl `127.0.0.1:$PORT`。具体失败信息可能是退 14 / stderr 不含预期短语。**确认非 PASS 再继续。**

- [ ] **Step 3: 实现——迁移 goto.sh**

`skills/flutter-wright/scripts/goto.sh`:
- 把 `fw_need_sdk` 这一行替换为两行:
  ```bash
  fw_resolve_target "$@"
  fw_need_sdk
  ```
- 删除 `PORT="${VL_PORT:-9123}"` 这一行。
- 在参数解析 `case "$arg" in` 里,`popUntilRoot=*) ...;;` 之后加一行:
  ```bash
    target=*) ;;
  ```
- 把 curl 块
  ```bash
  HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
    "http://127.0.0.1:$PORT/navigate" \
    -H 'content-type: application/json' \
    -d "$PAYLOAD") || HTTP_CODE="000"
  ```
  替换为:
  ```bash
  HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
    "$FW_BASE/navigate" \
    -H 'content-type: application/json' \
    "${FW_AUTH[@]+"${FW_AUTH[@]}"}" \
    -d "$PAYLOAD") || HTTP_CODE="000"
  ```
- 把 `000)` 行 `echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 43;;` 改为 `echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 43;;`。

- [ ] **Step 4: 实现——迁移 reset.sh**

`skills/flutter-wright/scripts/reset.sh`:
- 把 `fw_need_sdk` 替换为:
  ```bash
  fw_resolve_target "$@"
  fw_need_sdk
  ```
- 删除 `PORT="${VL_PORT:-9123}"`。
- reset 此前拒绝任何参数;改为允许 `target=`。把:
  ```bash
  if [ "$#" -gt 0 ]; then
    echo "ERR: reset.sh takes no arguments (got '$*')" >&2
    exit 70
  fi
  ```
  替换为:
  ```bash
  for arg in "$@"; do
    case "$arg" in
      target=*) ;;  # consumed by fw_resolve_target
      *) echo "ERR: reset.sh takes no arguments (got '$arg')" >&2; exit 70;;
    esac
  done
  ```
- curl 块
  ```bash
  HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
    "http://127.0.0.1:$PORT/reset" \
    -H 'content-type: application/json' \
    -d '{}') || HTTP_CODE="000"
  ```
  替换为:
  ```bash
  HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
    "$FW_BASE/reset" \
    -H 'content-type: application/json' \
    "${FW_AUTH[@]+"${FW_AUTH[@]}"}" \
    -d '{}') || HTTP_CODE="000"
  ```
- `000)` 行 `echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 70;;` → `echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 70;;`。

- [ ] **Step 5: 实现——迁移 tap.sh / long_press.sh / scroll.sh / type.sh**

四者结构同 tap(POST,positional `element` + `ref=` 等)。对**每个**文件做四处改:

(a) 把 `fw_need_sdk` 替换为:
```bash
fw_resolve_target "$@"
fw_need_sdk
```
(b) 删除 `PORT="${VL_PORT:-9123}"`。
(c) 在各自参数 `case` 的 `*)` 兜底行**之前**加一行 `target=*) ;;`。
(d) curl 行改 URL + 加头 + 改 000 提示,逐文件如下:

`tap.sh`:
```bash
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "$FW_BASE/tap" -H 'content-type: application/json' "${FW_AUTH[@]+"${FW_AUTH[@]}"}" -d "$PAYLOAD") || HTTP_CODE="000"
```
`000)` 行 → `echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 12;;`

`long_press.sh`(端点 `/long_press`):
```bash
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "$FW_BASE/long_press" -H 'content-type: application/json' "${FW_AUTH[@]+"${FW_AUTH[@]}"}" -d "$PAYLOAD") || HTTP_CODE="000"
```
`000)` 行 → `echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 12;;`

`scroll.sh`(端点 `/scroll`):
```bash
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "$FW_BASE/scroll" -H 'content-type: application/json' "${FW_AUTH[@]+"${FW_AUTH[@]}"}" -d "$PAYLOAD") || HTTP_CODE="000"
```
`000)` 行 → `echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 12;;`

`type.sh`(端点 `/type`):
```bash
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "$FW_BASE/type" -H 'content-type: application/json' "${FW_AUTH[@]+"${FW_AUTH[@]}"}" -d "$PAYLOAD") || HTTP_CODE="000"
```
`000)` 行 → `echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 12;;`

**type.sh 额外(`submit=true` 路径)**:旧 `fw_need_sdk` 经 `fw_need_adb` 设了 `FW_DEVICE_ID`;新 `fw_need_sdk` 不再碰 adb,故 `submit=true` 分支里 `adb -s "$FW_DEVICE_ID" ...` 会因 `FW_DEVICE_ID` 未设而在 `set -u` 下崩。删掉 `fw_need_sdk` 行尾「also sets FW_DEVICE_ID」的过时注释,并在 `submit=true` 分支内、`adb` 调用之前补 `fw_need_adb`(懒解析设备,无 adb/设备时干净退 10/11):
```bash
if [ "$SUBMIT" = "true" ]; then
  # ENTER needs adb + a device. fw_need_sdk no longer implies adb (it only probes
  # $FW_BASE/health), so resolve the device here — sets FW_DEVICE_ID, exits 10/11 if absent.
  fw_need_adb
  adb -s "$FW_DEVICE_ID" shell input keyevent 66 >/dev/null   # KEYCODE_ENTER
fi
```

> 各文件原 curl 行形如 `... "http://127.0.0.1:$PORT/<ep>" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"`(可能跨行)。以上是替换后的目标形态;保留各自原有的 `case` 状态码分支(404/422/55/57 等)不动,只改 URL/头/000 提示。

- [ ] **Step 6: 运行 goto/reset 测试确认通过**

Run:
```bash
bash skills/flutter-wright/test/goto_exit_code_test.sh
bash skills/flutter-wright/test/reset_exit_code_test.sh
```
Expected: 两条 `PASS:`(goto 退 41 + 「One-time host setup」;reset 退 71 + 同句),输出无 `Terminated` 噪声。

并对 tap/type/scroll/long_press 做语法检查:
Run: `for f in tap type scroll long_press goto reset; do bash -n skills/flutter-wright/scripts/$f.sh || echo "FAIL $f"; done; echo done`
Expected: 仅 `done`。

- [ ] **Step 7: 暂存变更,等用户审阅**

```bash
git add skills/flutter-wright/scripts/tap.sh skills/flutter-wright/scripts/type.sh \
        skills/flutter-wright/scripts/scroll.sh skills/flutter-wright/scripts/long_press.sh \
        skills/flutter-wright/scripts/goto.sh skills/flutter-wright/scripts/reset.sh \
        skills/flutter-wright/test/goto_exit_code_test.sh skills/flutter-wright/test/reset_exit_code_test.sh
```
**不要 commit。**

---

### Task B4: 迁移 GET / health 脚本(设计 5,TDD)

`snapshot.sh` / `wait_for.sh` 同样改用 `$FW_BASE` + token 头;`health.sh` 改为解析 target、探 `$FW_BASE/health`、打印 base。

**Files:**
- Modify: `skills/flutter-wright/scripts/{snapshot,wait_for,health}.sh`
- Create: `skills/flutter-wright/test/snapshot_smoke_test.sh`

- [ ] **Step 1: 写失败的测试**

创建 `skills/flutter-wright/test/snapshot_smoke_test.sh`(对迁移后的 GET 脚本做端到端冒烟:无 token + 有 token 都应 200 拿到 mock 快照):

```bash
#!/usr/bin/env bash
# snapshot_smoke_test.sh — GET-script migration smoke (Phase 2): snapshot.sh and
# wait_for.sh resolve the target, hit $FW_BASE with the auth header, and return the
# mock's YAML. The registry carries a token, so the scripts must send X-FW-Token.
set -uo pipefail  # no -e: out=$(...) captures a non-zero script exit; we inspect $code manually
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_helpers.sh"

fw_mock_start 200 || exit 1            # GET /snapshot & /wait_for → mock returns 200
fw_test_setup_target tok123 || exit 1  # registry carries a token → scripts send X-FW-Token
trap 'fw_mock_stop; rm -f "${FW_TARGETS:-}"' EXIT

fail=0

out="$(bash "$FW_SCRIPTS_DIR/snapshot.sh" 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: snapshot.sh exit $code" >&2; fail=1; }
case "$out" in
  *"[ref=s1]"*) ;;
  *) echo "FAIL: snapshot stdout missing mock ref: $out" >&2; fail=1;;
esac

out="$(bash "$FW_SCRIPTS_DIR/wait_for.sh" text=mock 2>/dev/null)"; code=$?
[ "$code" -eq 0 ] || { echo "FAIL: wait_for.sh exit $code" >&2; fail=1; }
case "$out" in
  *"[ref=s1]"*) ;;
  *) echo "FAIL: wait_for stdout missing mock ref: $out" >&2; fail=1;;
esac

[ "$fail" -eq 0 ] && echo "PASS: snapshot.sh + wait_for.sh resolve target + fetch via GET"
exit "$fail"
```

- [ ] **Step 2: 运行确认失败**

Run: `bash skills/flutter-wright/test/snapshot_smoke_test.sh`
Expected: FAIL —— `snapshot.sh` 未迁移,仍 `fw_need_sdk` 要 `FW_BASE` 却没人设(退 14)或 curl `127.0.0.1:$PORT`(mock 不在该端口)。**确认非 PASS 再继续。**

- [ ] **Step 3: 实现——迁移 snapshot.sh**

`skills/flutter-wright/scripts/snapshot.sh`:
- `fw_need_sdk` → 两行:
  ```bash
  fw_resolve_target "$@"
  fw_need_sdk
  ```
- 删 `PORT="${VL_PORT:-9123}"`。
- `case "$arg" in` 里 `out=*) ...;;` 之后加 `target=*) ;;`。
- curl 行
  ```bash
  HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" "http://127.0.0.1:$PORT/snapshot") || HTTP_CODE="000"
  ```
  →
  ```bash
  HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" "${FW_AUTH[@]+"${FW_AUTH[@]}"}" "$FW_BASE/snapshot") || HTTP_CODE="000"
  ```
- `000)` 行 `... at 127.0.0.1:$PORT ... exit 12;;` → `echo "ERR: SDK unreachable at $FW_BASE" >&2; exit 12;;`。

- [ ] **Step 4: 实现——迁移 wait_for.sh**

`skills/flutter-wright/scripts/wait_for.sh`:
- `fw_need_sdk` → 两行 `fw_resolve_target "$@"` + `fw_need_sdk`。
- 删 `PORT="${VL_PORT:-9123}"`。
- `case "$arg" in` 里 `timeout=*) ...;;` 之后加 `target=*) ;;`。
- curl 行
  ```bash
  HTTP_CODE=$(curl -s -G -o "$TMP" -w "%{http_code}" \
    "http://127.0.0.1:$PORT/wait_for" "${Q[@]}") || HTTP_CODE="000"
  ```
  →
  ```bash
  HTTP_CODE=$(curl -s -G -o "$TMP" -w "%{http_code}" "${FW_AUTH[@]+"${FW_AUTH[@]}"}" \
    "$FW_BASE/wait_for" "${Q[@]}") || HTTP_CODE="000"
  ```
- `000)` 行 `... at 127.0.0.1:$PORT ... exit 12;;` → `... at $FW_BASE ... exit 12;;`。

- [ ] **Step 5: 实现——迁移 health.sh**

把 `skills/flutter-wright/scripts/health.sh` 末尾两段:
```bash
# Always run the full chain + refresh marker, regardless of any prior marker.
FW_HEALTH_FORCE=1 fw_need_sdk

echo "ok: device=${FW_DEVICE_ID:-?} port=${VL_PORT:-9123}"
```
替换为:
```bash
fw_resolve_target "$@"
fw_need_sdk

echo "ok: base=$FW_BASE${FW_PACKAGE:+ package=$FW_PACKAGE}"
```

并把 health.sh 顶部陈旧的头注释(提到 `adb 10/11` / `refresh the session marker`)更新为反映新职责:
```bash
# health.sh — explicit SDK probe.
#
# Resolves the target (fw_resolve_target) and checks the in-app SDK is reachable
# (GET $base/health, unauthenticated). No adb/device dependency. Callers rarely need
# this explicitly — the SDK-talking methods run the same check implicitly.
#
# Exits non-zero with a single "ERR: <reason>" line on failure
# (12 SDK unreachable / 13 no curl / 14 no/invalid target registry / 15 ambiguous target).
```

- [ ] **Step 6: 运行测试确认通过**

Run: `bash skills/flutter-wright/test/snapshot_smoke_test.sh`
Expected: `PASS: snapshot.sh + wait_for.sh resolve target + fetch via GET`,退出码 0。

Run: `for f in snapshot wait_for health; do bash -n skills/flutter-wright/scripts/$f.sh || echo "FAIL $f"; done; echo done`
Expected: 仅 `done`。

- [ ] **Step 7: 暂存变更,等用户审阅**

```bash
git add skills/flutter-wright/scripts/snapshot.sh skills/flutter-wright/scripts/wait_for.sh \
        skills/flutter-wright/scripts/health.sh skills/flutter-wright/test/snapshot_smoke_test.sh
```
**不要 commit。**

---

### Task B5: 迁移 Dart e2e 的 `runScript` 到注册表

两个 e2e 测试通过 `runScript` 真实驱动脚本(`e2e_control_plane_test.dart` 的 goto/reset/reload;`e2e_interaction_test.dart` 的 snapshot/type/tap),旧法靠 marker + `VL_PORT`;脚本已改用 `FW_TARGETS`,故两处同步迁移。两处 SDK 启动均未带 token(注册表 token 留空)。

**Files:**
- Modify: `packages/example/test/e2e_control_plane_test.dart`(`group('skill bash 脚本...')` 的 setUp / runScript)
- Modify: `packages/example/test/e2e_interaction_test.dart`(`group('验收:skill 脚本真实驱动 SDK')` 的 setUp / runScript)

- [ ] **Step 1: 实现——e2e_control_plane setUp 写注册表,runScript 传 FW_TARGETS**

把该 group 内的 `setUp` 块:
```dart
    setUp(() async {
      jobDir = await Directory.systemTemp.createTemp('fw_job_');
      File('${jobDir.path}/fw_health_done')
          .writeAsStringSync('device=desktop-test\nport=9123\nts=0\n');
      scriptsDir =
          Directory('${Directory.current.path}/../../skills/flutter-wright/scripts')
              .absolute
              .path;
    });
```
替换为(写一条指向本机 9123、无 token 的注册表):
```dart
    setUp(() async {
      jobDir = await Directory.systemTemp.createTemp('fw_job_');
      File('${jobDir.path}/targets')
          .writeAsStringSync('local|http://127.0.0.1:9123||com.test.app\n');
      scriptsDir =
          Directory('${Directory.current.path}/../../skills/flutter-wright/scripts')
              .absolute
              .path;
    });
```
把 `runScript` 的 environment:
```dart
        environment: <String, String>{
          'CLAUDE_JOB_DIR': jobDir.path,
          'VL_PORT': '9123',
        },
```
替换为:
```dart
        environment: <String, String>{
          'FW_TARGETS': '${jobDir.path}/targets',
        },
```

- [ ] **Step 2: 实现——e2e_interaction setUp 写注册表,runScript 传 FW_TARGETS**

`packages/example/test/e2e_interaction_test.dart` 的 `group('验收:skill 脚本真实驱动 SDK')` 里,把 `setUp` 的 marker 写入:
```dart
      // 写 fw_health_done marker 走 fast-path,跳过 adb 检查;脚本直接 curl 9123。
      jobDir = await Directory.systemTemp.createTemp('fw_job_');
      File('${jobDir.path}/fw_health_done')
          .writeAsStringSync('device=desktop-test\nport=9123\nts=0\n');
```
替换为(写一条指向本机 9123、无 token 的注册表):
```dart
      // 写一条目标注册表,指向本机 9123(无 token);脚本经 fw_resolve_target 解析。
      jobDir = await Directory.systemTemp.createTemp('fw_job_');
      File('${jobDir.path}/targets')
          .writeAsStringSync('local|http://127.0.0.1:9123||com.test.app\n');
```
并把 `runScript` 的 environment:
```dart
          environment: <String, String>{
            'CLAUDE_JOB_DIR': jobDir.path,
            'VL_PORT': '9123',
          },
```
替换为:
```dart
          environment: <String, String>{
            'FW_TARGETS': '${jobDir.path}/targets',
          },
```

- [ ] **Step 3: 运行两个 e2e 确认通过**

Run:
```bash
cd packages/example && /Users/mini/development/flutter/bin/flutter test test/e2e_control_plane_test.dart test/e2e_interaction_test.dart
```
Expected: 两文件全绿(control_plane 的 `goto.sh`/`reset.sh` 真实驱动 + `reload.sh` 退 33;interaction 的 `snapshot.sh`→`type.sh`→`tap.sh` 闭环;`enabled: true` 已在 A1 加好,脚本经注册表打到 9123)。

- [ ] **Step 4: 暂存变更,等用户审阅**

```bash
git add packages/example/test/e2e_control_plane_test.dart packages/example/test/e2e_interaction_test.dart
```
**不要 commit。**

---

### Task B6: SKILL.md / methods.md 加「目标(target)」(设计 5 文档面)

让使用 skill 的 AI 知道:SDK 方法需经注册表解析 target,可选 `target=` 选择,token 由 base 注册表携带。

**Files:**
- Modify: `skills/flutter-wright/SKILL.md`(派发约定加 `target=`;新增「目标」简述)
- Modify: `skills/flutter-wright/references/methods.md`(9 个 SDK 方法签名加可选 `target=`)

- [ ] **Step 1: SKILL.md 加「目标」段 + 派发约定 target=**

在 `skills/flutter-wright/SKILL.md` 的「## 工作法」段**之前**插入一节:

```markdown
## 目标(target)

SDK 方法(snapshot/tap/type/scroll/longPress/waitFor/goto/reset/health)不再硬编码 `127.0.0.1:9123`,而是经**目标注册表**解析出 `base`(本地可达地址)、可选 `token`、可选 `package`。注册表由集成方/operator 维护在 **git 外**(环境变量 `FW_TARGETS` 指向的文件),**token 绝不进仓库**。单条目即默认;多条目时用 `target=<name>` 选择,未选则报错提示。base 配错只是连不上(快速失败),不引入安全风险。
```

在「## 派发约定」第 2 步的 `key=value` 列表里把现有键集合补上 `target`(在 `submit`/`device`/`project` 同处加入 `target`)。注意:位置参数列表里**已有**一个 `target`(那是 `run [target]` 的 dart 入口位置参数),与新加的 `key=value` 形 `target=<name>`(注册表条目名)同词不同义,易混淆——在该步追加一句澄清:位置参数 `target` 是 run 的 dart 入口文件;`key=value` 的 `target=<name>` 是目标注册表条目名,作为 key=value 排在位置参数之后(`goto /route target=shop`,**不要** `goto target=shop /route`)。

- [ ] **Step 2: methods.md 9 个 SDK 方法签名加 target=**

`skills/flutter-wright/references/methods.md`:对 `snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`/`goto`/`reset`/`health` 九节,在各自代码块签名里追加可选 `[target=<name>]`(放末尾),例如把 `Skill flutter-wright "snapshot [out=<path>]"` 改为 `Skill flutter-wright "snapshot [out=<path>] [target=<name>]"`;`health` 段把「`adb` + 设备 + ...」前提描述改为「解析 target → 探 `$base/health`(免 token),不再依赖 adb」,**删掉已不存在的「强制刷新 marker」那句**,退出码去 10/11 补 `14 无目标/15 目标歧义`,输出行须与 health.sh 实际一致 `ok: base=<base>`(带 package 时追加 ` package=<pkg>`)——**不要编造 `target=<name>` 字段**(health.sh 不输出它)。

> 本任务只做 target= 的最小文档接入;退出码对照表、方法数收敛(移除 run/reload/stop)等留待 Phase 4。

- [ ] **Step 3: 暂存变更,等用户审阅**

```bash
git add skills/flutter-wright/SKILL.md skills/flutter-wright/references/methods.md
```
**不要 commit。**

---

## Part C — 回归

### Task C1: 全量回归校验

**Files:** 无改动(只运行)。

- [ ] **Step 1: bash 全脚本 + 全测试语法 + 全 bash 测试**

Run:
```bash
cd /Users/mini/Documents/dev/github/flutterwright
for f in skills/flutter-wright/scripts/*.sh skills/flutter-wright/test/*.sh; do bash -n "$f" || echo "SYNTAX FAIL: $f"; done; echo "syntax done"
python3 -m py_compile skills/flutter-wright/test/mock_sdk.py && echo "py ok"
bash skills/flutter-wright/test/dispatch_naming_test.sh
bash skills/flutter-wright/test/resolve_target_test.sh
bash skills/flutter-wright/test/goto_exit_code_test.sh
bash skills/flutter-wright/test/reset_exit_code_test.sh
bash skills/flutter-wright/test/snapshot_smoke_test.sh
```
Expected: `syntax done`(无 SYNTAX FAIL)、`py ok`、五条 `PASS:`,无 `Terminated` 噪声。

- [ ] **Step 2: 两包 flutter test 全绿(串行)**

**必须 `--concurrency=1`**:多个测试文件都绑定同一控制面端口 9123(SDK 包的 `enabled_token_test` + `start_navigation_test`;example 包的多个 e2e),默认并发会跨文件抢端口导致 bind 失败。串行可完全规避。

Run:
```bash
FLUTTER=/Users/mini/development/flutter/bin/flutter
cd /Users/mini/Documents/dev/github/flutterwright/packages/flutter_wright_sdk && "$FLUTTER" test --concurrency=1
cd /Users/mini/Documents/dev/github/flutterwright/packages/example && "$FLUTTER" test --concurrency=1
```
Expected: 两包全部用例通过(含新 `enabled_token_test.dart` 与迁移后的 e2e)。

- [ ] **Step 3: 无需暂存**

本任务不产生文件变更;Part A/B 各任务已各自 `git add`。由用户统一审阅后 commit。
