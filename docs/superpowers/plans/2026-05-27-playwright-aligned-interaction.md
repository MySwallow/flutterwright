# Playwright-aligned Interaction Layer Implementation Plan (TDD)

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 FlutterWright 加一层 snapshot-first 交互:`snapshot`(读 Semantics 树→带 ref 的 YAML)+ `tap`/`type`/`scroll`/`longPress`/`waitFor`(SDK)+ `pressKey`/`back`/`logs`(免 SDK),并把 navigatorKey 降级为可选。

**Architecture:** 扩展现有 `flutter_wright_sdk` HTTP 控制面(adb forward + curl:9123)。两个纯逻辑单元 `semantics_snapshot.dart`(序列化+ref 解析)与 `semantics_action.dart`(经 `SemanticsOwner.performAction` 驱动)+ 6 个 HTTP handler + 9 个 bash 脚本。动作成功响应附最新 snapshot。导航(goto/reset)handler 改为仅在传 navigatorKey/adapter 时注册。

**Tech Stack:** Dart / Flutter 3.24(下限)~3.44、`dart:io HttpServer`、bash + curl + adb、`flutter_test`。

**TDD 模式(本计划核心):**
- **可单测的 Dart 逻辑**(`SemanticsSnapshot` / `SemanticsActions`):严格红绿 —— 先写失败测试 → 跑确认红 → 最小实现 → 跑转绿 → stage。
- **HTTP handler**:验收驱动(ATDD)—— 先写真实 curl e2e 期望(红:端点未注册返 404)→ 实现 + 注册(绿)。e2e 沿用 `e2e_control_plane_test.dart` 范式:`flutter_test` 内挂真实 app + 启真实 SDK,**真实 curl 子进程**打 9123(`flutter_test` 不 fake 子进程)。
- **bash 脚本 / 文档**:不做单测;由 **Phase 6 验收**(真实脚本驱动真实 app + 真机手测清单)端到端覆盖。

**已对 Flutter 3.24.0(支持下限)+ 3.44.0(本机)双版本源码核实的 API(签名一致):** `SemanticsBinding.instance.ensureSemantics()→SemanticsHandle`;`RendererBinding.instance.renderViews`;`view.owner?.semanticsOwner?.rootSemanticsNode`;`SemanticsNode.{id,owner,visitChildren,getSemanticsData}`;`SemanticsData.{label,value,hasFlag(SemanticsFlag),hasAction(SemanticsAction)}`;`SemanticsOwner.performAction(int,SemanticsAction,[Object?])`;6 个 `SemanticsFlag` 值(isTextField/isButton/isHeader/isImage/isLink/hasCheckedState)。

**计划级范围决定(YAGNI):** spec 第 2 节的「合成 pointer 兜底」**本期不做**。v1 一律走 `performAction`;节点未暴露对应 action 时返回明确错误(标准 Material/Cupertino 控件都暴露 tap/setText)。

---

## Phase 1 — `SemanticsSnapshot`(TDD 单元)

### Task 1: 序列化 + ref 解析 + 文本搜索(红绿)

**Files:**
- Create: `packages/flutter_wright_sdk/test/semantics_snapshot_test.dart`
- Create: `packages/flutter_wright_sdk/lib/src/semantics_snapshot.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/src/semantics_snapshot.dart';

void main() {
  group('serialize', () {
    testWidgets('列出 header/textfield/button,只给可操作节点 ref',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: <Widget>[
            const Semantics(header: true, child: Text('登录')),
            const TextField(decoration: InputDecoration(labelText: '手机号')),
            ElevatedButton(onPressed: () {}, child: const Text('提交')),
            const Text('纯文本'), // 无 action → 无 ref
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      final String yaml = SemanticsSnapshot.serialize();
      expect(yaml, contains('header'));
      expect(yaml, contains('textfield'));
      expect(yaml, contains('button'));
      expect(yaml, contains('提交'));
      expect(yaml, contains('[ref=s'));
      handle.dispose();
    });

    testWidgets('转义 label 里的引号', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
              onPressed: () {}, child: const Text('说"好"')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(SemanticsSnapshot.serialize(), contains(r'\"好\"'));
      handle.dispose();
    });
  });

  group('resolve', () {
    testWidgets('已知 ref 命中,未知 ref → null', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ElevatedButton(onPressed: () {}, child: const Text('OK'))),
      ));
      await tester.pumpAndSettle();
      SemanticsSnapshot.serialize();
      final SemanticsNode node = tester.getSemantics(find.text('OK'));
      expect(SemanticsSnapshot.resolve('s${node.id}'), isNotNull);
      expect(SemanticsSnapshot.resolve('s999999'), isNull);
      handle.dispose();
    });

    testWidgets('下次 snapshot 后旧 ref 失效', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ElevatedButton(onPressed: () {}, child: const Text('A'))),
      ));
      await tester.pumpAndSettle();
      SemanticsSnapshot.serialize();
      final String oldRef = 's${tester.getSemantics(find.text('A')).id}';
      expect(SemanticsSnapshot.resolve(oldRef), isNotNull);

      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pumpAndSettle();
      SemanticsSnapshot.serialize(); // 新快照无可操作节点
      expect(SemanticsSnapshot.resolve(oldRef), isNull);
      handle.dispose();
    });
  });

  group('containsText', () {
    testWidgets('命中 label / 缺失 false', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: Text('订单详情')))));
      await tester.pumpAndSettle();
      expect(SemanticsSnapshot.containsText('订单详情'), isTrue);
      expect(SemanticsSnapshot.containsText('不存在'), isFalse);
      handle.dispose();
    });
  });
}
```

- [ ] **Step 2: 跑测试确认红**

Run: `cd packages/flutter_wright_sdk && flutter test test/semantics_snapshot_test.dart`
Expected: 编译失败 / FAIL —— `SemanticsSnapshot` 未定义。

> 若红的原因是「`renderViews` 在测试里为空 → serialize 输出空」而非「未定义」,说明测试 binding 的语义树要从别处取;在 Step 3 实现里加注释处理(见该步备注)。

- [ ] **Step 3: 最小实现 `SemanticsSnapshot`**

```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

/// 把活的 Flutter Semantics(无障碍)树序列化成 Playwright 风格 YAML,并把
/// `ref` 解析回节点。`ref` = `s<SemanticsNode.id>`;**临时**:只有最近一次
/// [serialize] 发出过的 ref 才能 [resolve](与 Playwright 行为一致)。
class SemanticsSnapshot {
  SemanticsSnapshot._();

  static final Set<int> _liveRefs = <int>{};

  static String serialize() {
    _liveRefs.clear();
    final StringBuffer buffer = StringBuffer();
    for (final RenderView view in RendererBinding.instance.renderViews) {
      final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root == null) continue;
      _writeNode(root, buffer, 0);
    }
    final String out = buffer.toString();
    return out.isEmpty ? '# (no semantics — is the app mounted?)' : out;
  }

  static SemanticsNode? resolve(String ref) {
    final int? id = _parseRef(ref);
    if (id == null || !_liveRefs.contains(id)) return null;
    for (final RenderView view in RendererBinding.instance.renderViews) {
      final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root == null) continue;
      final SemanticsNode? found = _findById(root, id);
      if (found != null) return found;
    }
    return null;
  }

  static bool containsText(String needle) {
    for (final RenderView view in RendererBinding.instance.renderViews) {
      final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null && _containsText(root, needle)) return true;
    }
    return false;
  }

  static int? _parseRef(String ref) =>
      int.tryParse(ref.startsWith('s') ? ref.substring(1) : ref);

  static void _writeNode(SemanticsNode node, StringBuffer buffer, int depth) {
    final SemanticsData data = node.getSemanticsData();
    final String? role = _roleOf(data);
    final String label = _escape(data.label);
    final String value = _escape(data.value);
    final bool actionable = _isActionable(data);

    int childDepth = depth;
    if (role != null || label.isNotEmpty || actionable) {
      final StringBuffer line =
          StringBuffer('${'  ' * depth}- ${role ?? 'node'}');
      if (label.isNotEmpty) line.write(' "$label"');
      if (value.isNotEmpty) line.write(' value="$value"');
      if (actionable) {
        _liveRefs.add(node.id);
        line.write(' [ref=s${node.id}]');
      }
      buffer.writeln(line.toString());
      childDepth = depth + 1;
    }
    node.visitChildren((SemanticsNode child) {
      _writeNode(child, buffer, childDepth);
      return true;
    });
  }

  static String? _roleOf(SemanticsData d) {
    if (d.hasFlag(SemanticsFlag.isTextField)) return 'textfield';
    if (d.hasFlag(SemanticsFlag.isButton)) return 'button';
    if (d.hasFlag(SemanticsFlag.isHeader)) return 'header';
    if (d.hasFlag(SemanticsFlag.isImage)) return 'image';
    if (d.hasFlag(SemanticsFlag.isLink)) return 'link';
    if (d.hasFlag(SemanticsFlag.hasCheckedState)) return 'checkbox';
    return null;
  }

  static bool _isActionable(SemanticsData d) =>
      d.hasAction(SemanticsAction.tap) ||
      d.hasAction(SemanticsAction.longPress) ||
      d.hasAction(SemanticsAction.scrollUp) ||
      d.hasAction(SemanticsAction.scrollDown) ||
      d.hasAction(SemanticsAction.scrollLeft) ||
      d.hasAction(SemanticsAction.scrollRight) ||
      d.hasAction(SemanticsAction.setText);

  static String _escape(String s) =>
      s.replaceAll('\n', ' ').replaceAll('"', r'\"').trim();

  static SemanticsNode? _findById(SemanticsNode node, int id) {
    if (node.id == id) return node;
    SemanticsNode? result;
    node.visitChildren((SemanticsNode child) {
      result ??= _findById(child, id);
      return result == null;
    });
    return result;
  }

  static bool _containsText(SemanticsNode node, String needle) {
    final SemanticsData d = node.getSemanticsData();
    if (d.label.contains(needle) || d.value.contains(needle)) return true;
    bool found = false;
    node.visitChildren((SemanticsNode child) {
      if (_containsText(child, needle)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}
```

> 备注(若 Step 2 红因「renderViews 空」):测试 binding 下若 `renderViews` 不含语义树,改为同时遍历 `RendererBinding.instance.rootPipelineOwner` 的子 owner 树取 `semanticsOwner`。先按上面 `renderViews` 实现跑;真为空再调整,这正是 TDD 早暴露的点。

- [ ] **Step 4: 跑测试转绿**

Run: `cd packages/flutter_wright_sdk && flutter test test/semantics_snapshot_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 静态检查 + Stage**

Run: `cd packages/flutter_wright_sdk && flutter analyze`(Expected: `No issues found!`)

```bash
git add packages/flutter_wright_sdk/test/semantics_snapshot_test.dart \
        packages/flutter_wright_sdk/lib/src/semantics_snapshot.dart
```
**不要 commit。**

---

## Phase 2 — `SemanticsActions`(TDD 单元,含 spec 风险 #1 验证)

### Task 2: tap / setText / scroll / longPress(红绿)

**Files:**
- Create: `packages/flutter_wright_sdk/test/semantics_action_test.dart`
- Create: `packages/flutter_wright_sdk/lib/src/semantics_action.dart`

> 这条测试就是 spec 风险 #1/#2 的早期验证点:`setText` 若在测试 binding 里不奏效,这里立刻红,据此决定 `type` 是否退回 `adb input text`。

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/src/semantics_action.dart';

void main() {
  testWidgets('tap 触发 onPressed,无 tap action 节点返回 false',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    bool tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: <Widget>[
          ElevatedButton(onPressed: () => tapped = true, child: const Text('按我')),
          const Text('纯文本'),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(SemanticsActions.tap(tester.getSemantics(find.text('按我'))), isTrue);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(SemanticsActions.tap(tester.getSemantics(find.text('纯文本'))), isFalse);
    handle.dispose();
  });

  testWidgets('setText 写入输入框,非输入框返回 false',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: <Widget>[
          TextField(controller: controller),
          ElevatedButton(onPressed: () {}, child: const Text('btn')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        SemanticsActions.setText(
            tester.getSemantics(find.byType(TextField)), '北京'),
        isTrue);
    await tester.pumpAndSettle();
    expect(controller.text, '北京');
    expect(
        SemanticsActions.setText(tester.getSemantics(find.text('btn')), 'x'),
        isFalse);
    handle.dispose();
  });

  testWidgets('scroll 非法方向返回 false', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: <Widget>[
          for (int i = 0; i < 40; i++) ListTile(title: Text('item $i')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        SemanticsActions.scroll(
            tester.getSemantics(find.byType(Scrollable)), 'sideways'),
        isFalse);
    handle.dispose();
  });
}
```

- [ ] **Step 2: 跑测试确认红**

Run: `cd packages/flutter_wright_sdk && flutter test test/semantics_action_test.dart`
Expected: 编译失败 —— `SemanticsActions` 未定义。

- [ ] **Step 3: 最小实现 `SemanticsActions`**

```dart
import 'package:flutter/semantics.dart';

/// 经 [SemanticsAction] 在已解析节点上驱动交互 —— 与 OS 无障碍系统同一条路径。
/// v1 不含合成 pointer 兜底:节点未暴露对应 action 时返回 false。
class SemanticsActions {
  SemanticsActions._();

  static bool tap(SemanticsNode node) => _perform(node, SemanticsAction.tap);

  static bool longPress(SemanticsNode node) =>
      _perform(node, SemanticsAction.longPress);

  static bool scroll(SemanticsNode node, String dir) {
    final SemanticsAction? action = switch (dir) {
      'up' => SemanticsAction.scrollUp,
      'down' => SemanticsAction.scrollDown,
      'left' => SemanticsAction.scrollLeft,
      'right' => SemanticsAction.scrollRight,
      _ => null,
    };
    if (action == null) return false;
    return _perform(node, action);
  }

  /// 先 tap 取焦点(若支持),再 setText。节点不可输入时返回 false。
  static bool setText(SemanticsNode node, String text) {
    final SemanticsData data = node.getSemanticsData();
    final SemanticsOwner? owner = node.owner;
    if (owner == null || !data.hasAction(SemanticsAction.setText)) return false;
    if (data.hasAction(SemanticsAction.tap)) {
      owner.performAction(node.id, SemanticsAction.tap);
    }
    owner.performAction(node.id, SemanticsAction.setText, text);
    return true;
  }

  static bool _perform(SemanticsNode node, SemanticsAction action) {
    final SemanticsOwner? owner = node.owner;
    if (owner == null) return false;
    if (!node.getSemanticsData().hasAction(action)) return false;
    owner.performAction(node.id, action);
    return true;
  }
}
```

- [ ] **Step 4: 跑测试转绿**

Run: `cd packages/flutter_wright_sdk && flutter test test/semantics_action_test.dart`
Expected: `All tests passed!`

> 若 `setText` 用例红:记录失败信息,这是 spec 风险 #1 的决策依据 —— 改 `setText` 退回 skill 侧 `adb shell input text`(并相应调整 Task 10 type.sh)。

- [ ] **Step 5: 静态检查 + Stage**

Run: `cd packages/flutter_wright_sdk && flutter analyze`(Expected: `No issues found!`)

```bash
git add packages/flutter_wright_sdk/test/semantics_action_test.dart \
        packages/flutter_wright_sdk/lib/src/semantics_action.dart
```
**不要 commit。**

---

## Phase 3 — SDK handler + 接线(验收驱动,红绿)

### Task 3: `GET /snapshot` + `start()` 接 ensureSemantics(e2e 红绿)

**Files:**
- Create: `packages/example/test/e2e_interaction_test.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/snapshot_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: 写失败 e2e(curl /snapshot)+ 复用工具**

```dart
// 交互层 e2e:真实 curl 打 9123(flutter_test 不 fake 子进程)。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

import 'package:flutter_wright_example/app.dart';
import 'package:flutter_wright_example/router/app_router.dart';

const String _base = 'http://127.0.0.1:9123';

Future<({int code, String body})> _curlGet(String path) async {
  final Directory tmp = await Directory.systemTemp.createTemp('fw_curl_');
  final File out = File('${tmp.path}/body');
  try {
    final ProcessResult res = await Process.run('curl',
        <String>['-s', '-o', out.path, '-w', '%{http_code}', '$_base$path']);
    final int code = int.tryParse(res.stdout.toString().trim()) ?? 0;
    final String body = await out.exists() ? await out.readAsString() : '';
    return (code: code, body: body);
  } finally {
    await tmp.delete(recursive: true);
  }
}

Future<({int code, String body})> _curlPost(
    String path, Map<String, Object?> json) async {
  final Directory tmp = await Directory.systemTemp.createTemp('fw_curl_');
  final File out = File('${tmp.path}/body');
  try {
    final ProcessResult res = await Process.run('curl', <String>[
      '-s', '-o', out.path, '-w', '%{http_code}', '-X', 'POST', '$_base$path',
      '-H', 'content-type: application/json', '-d', jsonEncode(json),
    ]);
    final int code = int.tryParse(res.stdout.toString().trim()) ?? 0;
    final String body = await out.exists() ? await out.readAsString() : '';
    return (code: code, body: body);
  } finally {
    await tmp.delete(recursive: true);
  }
}

/// 从 snapshot YAML 抓某 label 行的 ref(`... "登录" [ref=s12]`)。
String? refFor(String yaml, String label) {
  for (final String line in yaml.split('\n')) {
    if (line.contains('"$label"')) {
      final Match? m = RegExp(r'\[ref=(s\d+)\]').firstMatch(line);
      if (m != null) return m.group(1);
    }
  }
  return null;
}

late SemanticsHandle _semantics;

Future<void> bootLogin(WidgetTester tester) async {
  _semantics = tester.ensureSemantics();
  await tester.runAsync(() => FlutterWright.start(
        navigatorKey: FlutterWright.navigatorKey,
        routes: AppRouter.names,
      ));
  await tester.pumpWidget(FlutterWrightRoot(
      child: createApp(navigatorKey: FlutterWright.navigatorKey)));
  await tester.pumpAndSettle();
  await tester.runAsync(
      () => _curlPost('/navigate', <String, Object?>{'route': '/login'}));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() async {
    await FlutterWright.stop();
    _semantics.dispose();
  });

  testWidgets('snapshot 列出登录页元素(textfield/button + ref)',
      (WidgetTester tester) async {
    await bootLogin(tester);
    final snap = (await tester.runAsync(() => _curlGet('/snapshot')))!;
    expect(snap.code, 200, reason: 'body: ${snap.body}');
    expect(snap.body, contains('textfield'));
    expect(snap.body, contains('登录'));
    expect(refFor(snap.body, '手机号'), isNotNull, reason: snap.body);
    expect(refFor(snap.body, '登录'), isNotNull, reason: snap.body);
  });
}
```

- [ ] **Step 2: 跑确认红**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`
Expected: FAIL —— `/snapshot` 未注册,curl 得 404,`snap.code != 200`。

- [ ] **Step 3: 实现 `SnapshotHandler`(GET,text/plain YAML)**

```dart
import 'dart:io';

import '../semantics_snapshot.dart';
import 'handler.dart';

class SnapshotHandler extends Handler {
  @override
  String get path => '/snapshot';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final String yaml = SemanticsSnapshot.serialize();
    ctx.request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8')
      ..write(yaml);
    await ctx.request.response.close();
  }
}
```

- [ ] **Step 4: `flutter_wright.dart` 接 ensureSemantics + 注册**

import 区加:

```dart
import 'package:flutter/semantics.dart';
import 'handlers/snapshot_handler.dart';
```

`_server` 字段旁加:

```dart
  static SemanticsHandle? _semanticsHandle;
```

`start()` 内 `if (_server != null) {...}` 之后插:

```dart
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
```

`handlers` 列表 `ScreenshotHandler(...)` 之后加 `SnapshotHandler()`。`stop()` 内 `await _server?.stop();` 之后加:

```dart
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
```

- [ ] **Step 5: 跑转绿 + analyze**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`(Expected: `All tests passed!`)
Run: `cd packages/flutter_wright_sdk && flutter analyze`(Expected: `No issues found!`)

- [ ] **Step 6: Stage**

```bash
git add packages/example/test/e2e_interaction_test.dart \
        packages/flutter_wright_sdk/lib/src/handlers/snapshot_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

### Task 4: `/tap` `/type` `/long_press` `/scroll` handler(e2e 红绿)

**Files:**
- Modify: `packages/example/test/e2e_interaction_test.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/tap_handler.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/type_handler.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/long_press_handler.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/scroll_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: 在 e2e 追加失败用例(type → tap,断言自动回吐 snapshot)**

在 `e2e_interaction_test.dart` 的 `main()` 里追加:

```dart
  testWidgets('type 写手机号(响应含 snapshot)→ tap 登录',
      (WidgetTester tester) async {
    await bootLogin(tester);
    final snap = (await tester.runAsync(() => _curlGet('/snapshot')))!;
    final String? phoneRef = refFor(snap.body, '手机号');
    final String? loginRef = refFor(snap.body, '登录');
    expect(phoneRef, isNotNull);
    expect(loginRef, isNotNull);

    final typed = (await tester.runAsync(() => _curlPost('/type',
        <String, Object?>{'element': '手机号', 'ref': phoneRef, 'text': '13800000000'})))!;
    await tester.pumpAndSettle();
    expect(typed.code, 200, reason: typed.body);
    expect((jsonDecode(typed.body) as Map<String, Object?>).containsKey('snapshot'),
        isTrue, reason: '动作响应应自动回吐 snapshot');
    expect(find.text('13800000000'), findsOneWidget);

    final tapped = (await tester.runAsync(() => _curlPost(
        '/tap', <String, Object?>{'element': '登录', 'ref': loginRef})))!;
    await tester.pumpAndSettle();
    expect(tapped.code, 200, reason: tapped.body);
  });
```

- [ ] **Step 2: 跑确认红**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`
Expected: 新用例 FAIL（`/type` `/tap` 未注册 → 404）。

- [ ] **Step 3: 实现 4 个 handler**

`tap_handler.dart`:

```dart
import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

class TapHandler extends Handler {
  @override
  String get path => '/tap';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Object? ref = ctx.json['ref'];
    if (ref is! String || ref.isEmpty) {
      await ctx.request.writeError(400, 'missing "ref"');
      return;
    }
    final node = SemanticsSnapshot.resolve(ref);
    if (node == null) {
      await ctx.request
          .writeError(404, 'ref "$ref" not in latest snapshot — re-snapshot');
      return;
    }
    if (!SemanticsActions.tap(node)) {
      await ctx.request.writeError(422, 'node has no tap action');
      return;
    }
    vlLog('tap ${ctx.json['element'] ?? ref}');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
```

`long_press_handler.dart`(同结构,`/long_press` + `SemanticsActions.longPress` + 文案 longPress):

```dart
import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

class LongPressHandler extends Handler {
  @override
  String get path => '/long_press';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Object? ref = ctx.json['ref'];
    if (ref is! String || ref.isEmpty) {
      await ctx.request.writeError(400, 'missing "ref"');
      return;
    }
    final node = SemanticsSnapshot.resolve(ref);
    if (node == null) {
      await ctx.request
          .writeError(404, 'ref "$ref" not in latest snapshot — re-snapshot');
      return;
    }
    if (!SemanticsActions.longPress(node)) {
      await ctx.request.writeError(422, 'node has no longPress action');
      return;
    }
    vlLog('longPress ${ctx.json['element'] ?? ref}');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
```

`type_handler.dart`:

```dart
import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

class TypeHandler extends Handler {
  @override
  String get path => '/type';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Object? ref = ctx.json['ref'];
    final Object? text = ctx.json['text'];
    if (ref is! String || ref.isEmpty) {
      await ctx.request.writeError(400, 'missing "ref"');
      return;
    }
    if (text is! String) {
      await ctx.request.writeError(400, 'missing "text"');
      return;
    }
    final node = SemanticsSnapshot.resolve(ref);
    if (node == null) {
      await ctx.request
          .writeError(404, 'ref "$ref" not in latest snapshot — re-snapshot');
      return;
    }
    if (!SemanticsActions.setText(node, text)) {
      await ctx.request.writeError(422, 'node is not an editable text field');
      return;
    }
    vlLog('type ${ctx.json['element'] ?? ref} = "$text"');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
```

`scroll_handler.dart`:

```dart
import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

class ScrollHandler extends Handler {
  static const Set<String> _dirs = <String>{'up', 'down', 'left', 'right'};

  @override
  String get path => '/scroll';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Object? ref = ctx.json['ref'];
    final Object? dir = ctx.json['dir'];
    if (ref is! String || ref.isEmpty) {
      await ctx.request.writeError(400, 'missing "ref"');
      return;
    }
    if (dir is! String || !_dirs.contains(dir)) {
      await ctx.request.writeError(400, 'dir must be one of $_dirs');
      return;
    }
    final node = SemanticsSnapshot.resolve(ref);
    if (node == null) {
      await ctx.request
          .writeError(404, 'ref "$ref" not in latest snapshot — re-snapshot');
      return;
    }
    if (!SemanticsActions.scroll(node, dir)) {
      await ctx.request.writeError(422, 'node has no scroll$dir action');
      return;
    }
    vlLog('scroll ${ctx.json['element'] ?? ref} $dir');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
```

- [ ] **Step 4: `flutter_wright.dart` 注册 4 个**

import 区加四行;`handlers` 列表 `SnapshotHandler()` 之后加:

```dart
      TapHandler(),
      LongPressHandler(),
      TypeHandler(),
      ScrollHandler(),
```

- [ ] **Step 5: 跑转绿 + analyze**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`(Expected: `All tests passed!`)
Run: `cd packages/flutter_wright_sdk && flutter analyze`（Expected: `No issues found!`）

> 若 `find.text('13800000000')` 红 → spec 风险 #1(setText 真机/IME),回 Task 2 评估 `adb input text` 退路。

- [ ] **Step 6: Stage**

```bash
git add packages/example/test/e2e_interaction_test.dart \
        packages/flutter_wright_sdk/lib/src/handlers/tap_handler.dart \
        packages/flutter_wright_sdk/lib/src/handlers/long_press_handler.dart \
        packages/flutter_wright_sdk/lib/src/handlers/type_handler.dart \
        packages/flutter_wright_sdk/lib/src/handlers/scroll_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

### Task 5: `GET /wait_for` handler(e2e 红绿)

**Files:**
- Modify: `packages/example/test/e2e_interaction_test.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/wait_for_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: e2e 追加失败用例(条件已满足应立即 200)**

```dart
  testWidgets('wait_for:登录页已有「登录」文本 → 立即命中', (WidgetTester tester) async {
    await bootLogin(tester);
    final r = (await tester.runAsync(
        () => _curlGet('/wait_for?text=%E7%99%BB%E5%BD%95&timeout=2000')))!;
    expect(r.code, 200, reason: r.body); // %E7%99%BB%E5%BD%95 = 登录
  });
```

- [ ] **Step 2: 跑确认红**(404)

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`
Expected: 新用例 FAIL。

- [ ] **Step 3: 实现 `WaitForHandler`**

```dart
import 'dart:async';

import '../semantics_snapshot.dart';
import 'handler.dart';

class WaitForHandler extends Handler {
  @override
  String get path => '/wait_for';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Map<String, String> q = ctx.request.uri.queryParameters;
    final String? text = q['text'];
    final String? ref = q['ref'];
    final String? gone = q['gone'];
    final int timeoutMs = int.tryParse(q['timeout'] ?? '') ?? 5000;
    if (text == null && ref == null && gone == null) {
      await ctx.request.writeError(400, 'need one of text= / ref= / gone=');
      return;
    }
    bool met() {
      if (text != null) return SemanticsSnapshot.containsText(text);
      if (ref != null) return SemanticsSnapshot.resolve(ref) != null;
      return !SemanticsSnapshot.containsText(gone!);
    }

    final DateTime deadline =
        DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (met()) {
        await ctx.request.writeOk(
            <String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await ctx.request.writeError(408, 'condition not met within ${timeoutMs}ms');
  }
}
```

- [ ] **Step 4: 注册 `WaitForHandler()`(import + handlers 列表)**

- [ ] **Step 5: 跑转绿 + analyze**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`(Expected: `All tests passed!`)
Run: `cd packages/flutter_wright_sdk && flutter analyze`

- [ ] **Step 6: Stage**

```bash
git add packages/example/test/e2e_interaction_test.dart \
        packages/flutter_wright_sdk/lib/src/handlers/wait_for_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

### Task 6: navigate / reset 也回吐 snapshot(e2e 红绿)

**Files:**
- Modify: `packages/example/test/e2e_interaction_test.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/handlers/navigate_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/handlers/reset_handler.dart`

- [ ] **Step 1: e2e 追加失败用例(/navigate 响应应含 snapshot)**

```dart
  testWidgets('navigate 响应自动回吐 snapshot', (WidgetTester tester) async {
    await bootLogin(tester);
    final nav = (await tester.runAsync(() =>
        _curlPost('/navigate', <String, Object?>{'route': '/order/detail'})))!;
    await tester.pumpAndSettle();
    expect(nav.code, 200, reason: nav.body);
    expect((jsonDecode(nav.body) as Map<String, Object?>).containsKey('snapshot'),
        isTrue);
  });
```

- [ ] **Step 2: 跑确认红**（响应无 `snapshot` 字段）

- [ ] **Step 3: `navigate_handler.dart` 加 snapshot**

顶部加 `import '../semantics_snapshot.dart';`;成功分支 `await ctx.request.writeOk(<String, Object?>{'route': route});` 改为:

```dart
      await ctx.request.writeOk(<String, Object?>{
        'route': route,
        'snapshot': SemanticsSnapshot.serialize(),
      });
```

- [ ] **Step 4: `reset_handler.dart` 加 snapshot**

顶部加 `import '../semantics_snapshot.dart';`;把成功分支 `await ctx.request.writeOk();`(`reset_handler.dart:22`)改为:

```dart
      await ctx.request.writeOk(<String, Object?>{
        'snapshot': SemanticsSnapshot.serialize(),
      });
```

- [ ] **Step 5: 跑转绿 + analyze + Stage**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`(Expected: `All tests passed!`)

```bash
git add packages/example/test/e2e_interaction_test.dart \
        packages/flutter_wright_sdk/lib/src/handlers/navigate_handler.dart \
        packages/flutter_wright_sdk/lib/src/handlers/reset_handler.dart
```
**不要 commit。**

---

### Task 7: navigatorKey 降级为可选(测试红绿 + 更新 example/既有 e2e)

**Files:**
- Create: `packages/flutter_wright_sdk/test/start_navigation_test.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/nav_not_configured_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`
- Modify: `packages/example/dev/main_dev.dart`
- Modify: `packages/example/test/e2e_control_plane_test.dart`

- [ ] **Step 1: 写失败测试(条件注册契约)**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async => FlutterWright.stop());

  Future<int> postNavigate() async {
    final ProcessResult res = await Process.run('curl', <String>[
      '-s', '-o', '/dev/null', '-w', '%{http_code}',
      '-X', 'POST', 'http://127.0.0.1:9123/navigate',
      '-H', 'content-type: application/json',
      '-d', jsonEncode(<String, Object?>{'route': '/x'}),
    ]);
    return int.tryParse(res.stdout.toString().trim()) ?? 0;
  }

  testWidgets('未传 navigatorKey/adapter:/navigate 回 501',
      (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start());
    expect((await tester.runAsync(postNavigate))!, 501);
  });

  testWidgets('传 navigatorKey:/navigate 已注册(非 501)',
      (WidgetTester tester) async {
    await tester.runAsync(
        () => FlutterWright.start(navigatorKey: FlutterWright.navigatorKey));
    expect((await tester.runAsync(postNavigate))!, isNot(501));
  });
}
```

- [ ] **Step 2: 跑确认红**（当前 `start()` 无条件注册 navigate → 未传 key 时回 503 而非 501）

Run: `cd packages/flutter_wright_sdk && flutter test test/start_navigation_test.dart`
Expected: 第一个用例 FAIL（得到 503,期望 501)。

- [ ] **Step 3: 实现 `NavNotConfiguredHandler`**

```dart
import 'handler.dart';

/// host 未传 navigatorKey/navigationAdapter 时,占位回应导航端点:明确「未配置」。
class NavNotConfiguredHandler extends Handler {
  NavNotConfiguredHandler(this.path, this.method);

  @override
  final String path;

  @override
  final String method;

  @override
  Future<void> handle(HandlerContext ctx) async {
    await ctx.request.writeError(
      501,
      'navigation not configured — pass navigatorKey or navigationAdapter '
      'to FlutterWright.start() to enable goto/reset',
    );
  }
}
```

- [ ] **Step 4: 改写 `start()` 为条件注册**

import 区加 `import 'handlers/nav_not_configured_handler.dart';`。把「构造 adapter + 无条件加 Routes/Navigate/Reset」整段(连同 `final adapter = ...`)替换为:

```dart
    final handlers = <Handler>[
      HealthHandler(version),
      ScreenshotHandler(config.screenshotMode),
      SnapshotHandler(),
      TapHandler(),
      LongPressHandler(),
      TypeHandler(),
      ScrollHandler(),
      WaitForHandler(),
    ];

    if (navigationAdapter != null || navigatorKey != null) {
      final NavigationAdapter adapter = navigationAdapter ??
          NavigatorKeyAdapter(navigatorKey!, routes: routes);
      if (navigationAdapter != null && routes.isNotEmpty) {
        vlWarn('start(routes:) ignored because navigationAdapter was provided; '
            'put discoverable routes in the adapter (routesProvider)');
      }
      handlers
        ..add(RoutesHandler(adapter))
        ..add(NavigateHandler(adapter))
        ..add(ResetHandler(adapter));
    } else {
      if (routes.isNotEmpty) {
        vlWarn('start(routes:) ignored: no navigatorKey/adapter — '
            'navigation (goto/reset) not registered');
      }
      handlers
        ..add(NavNotConfiguredHandler('/routes', 'GET'))
        ..add(NavNotConfiguredHandler('/navigate', 'POST'))
        ..add(NavNotConfiguredHandler('/reset', 'POST'));
    }
```

确认 import 区含全部 handler(Snapshot/Tap/LongPress/Type/Scroll/WaitFor/NavNotConfigured)。

- [ ] **Step 5: 更新 `dev/main_dev.dart` 显式传 navigatorKey**

`await FlutterWright.start(routes: AppRouter.names);` 改为:

```dart
  await FlutterWright.start(
    navigatorKey: FlutterWright.navigatorKey,
    routes: AppRouter.names,
  );
```

- [ ] **Step 6: 更新 `e2e_control_plane_test.dart` 的 `bootApp` 同样显式传**

把 `bootApp` 内 `FlutterWright.start(routes: AppRouter.names)` 改为带 `navigatorKey: FlutterWright.navigatorKey,`。

- [ ] **Step 7: 跑转绿 + 全量回归**

Run: `cd packages/flutter_wright_sdk && flutter analyze && flutter test`（Expected: `No issues found!` + `All tests passed!`）
Run: `cd packages/example && flutter test`（Expected: `All tests passed!` —— 含既有 control-plane e2e 在 bootApp 改动后仍绿）

- [ ] **Step 8: Stage**

```bash
git add packages/flutter_wright_sdk/test/start_navigation_test.dart \
        packages/flutter_wright_sdk/lib/src/handlers/nav_not_configured_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart \
        packages/example/dev/main_dev.dart \
        packages/example/test/e2e_control_plane_test.dart
```
**不要 commit。**

---

## Phase 4 — skill bash 脚本

> 不做单测,Phase 6 验收端到端覆盖。所有脚本:`set -euo pipefail`、`source _lib.sh`、`VL_PORT` 默认 9123;curl `-o $TMP -w "%{http_code}"` + `case` 分流;`element`/`ref`/`text` 含 `"`/`\`/换行的拒绝(同 `goto.sh`)。每步收尾:`bash -n` 语法检查 + `chmod +x` + `git add`(**不 commit**)。

### Task 8: `snapshot.sh`

**Files:** Create `skills/flutter-wright/scripts/snapshot.sh`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# snapshot.sh — fetch the Playwright-style semantics snapshot (YAML).
# Usage: snapshot.sh [out=<path>]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
OUT=""
for arg in "$@"; do
  case "$arg" in
    out=*) OUT="${arg#out=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 80;;
  esac
done

TMP=$(mktemp -t fw-snap.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" "http://127.0.0.1:$PORT/snapshot") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200)
    if [ -n "$OUT" ]; then mkdir -p "$(dirname "$OUT")"; cp "$TMP" "$OUT"; echo "snapshot -> $OUT" >&2; fi
    cat "$TMP"; echo
    ;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /snapshot returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 80;;
esac
```

- [ ] **Step 2: 检查 + Stage**

Run: `bash -n skills/flutter-wright/scripts/snapshot.sh && chmod +x skills/flutter-wright/scripts/snapshot.sh`(Expected: 无输出)

```bash
git add skills/flutter-wright/scripts/snapshot.sh
```

---

### Task 9: `tap.sh` + `long_press.sh`

**Files:** Create `skills/flutter-wright/scripts/tap.sh`、`long_press.sh`

- [ ] **Step 1: 写 `tap.sh`**

```bash
#!/usr/bin/env bash
# tap.sh — tap an element by ref (from a prior snapshot) via SDK /tap.
# Usage: tap.sh "<element>" ref=<ref>
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
ELEMENT="${1:?element description required (positional arg 1)}"
shift
REF=""
for arg in "$@"; do
  case "$arg" in
    ref=*) REF="${arg#ref=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 50;;
  esac
done
[ -n "$REF" ] || { echo "ERR: ref= required" >&2; exit 50; }
for v in "$ELEMENT" "$REF"; do
  if [[ "$v" == *'"'* || "$v" == *'\'* || "$v" == *$'\n'* ]]; then
    echo "ERR: value contains unsupported characters (quotes/backslash/newline)." >&2; exit 50
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s"}' "$ELEMENT" "$REF")
TMP=$(mktemp -t fw-tap.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/tap" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  404) echo "ERR: ref '$REF' not in latest snapshot — re-run snapshot." >&2; cat "$TMP" >&2; exit 51;;
  422) echo "ERR: '$ELEMENT' (ref $REF) has no tap action." >&2; cat "$TMP" >&2; exit 52;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /tap returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 57;;
esac
```

- [ ] **Step 2: 写 `long_press.sh`**(同上,端点 `/long_press`、文案 longPress)

```bash
#!/usr/bin/env bash
# long_press.sh — long-press an element by ref via SDK /long_press.
# Usage: long_press.sh "<element>" ref=<ref>
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
ELEMENT="${1:?element description required (positional arg 1)}"
shift
REF=""
for arg in "$@"; do
  case "$arg" in
    ref=*) REF="${arg#ref=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 50;;
  esac
done
[ -n "$REF" ] || { echo "ERR: ref= required" >&2; exit 50; }
for v in "$ELEMENT" "$REF"; do
  if [[ "$v" == *'"'* || "$v" == *'\'* || "$v" == *$'\n'* ]]; then
    echo "ERR: value contains unsupported characters." >&2; exit 50
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s"}' "$ELEMENT" "$REF")
TMP=$(mktemp -t fw-lp.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/long_press" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  404) echo "ERR: ref '$REF' not in latest snapshot — re-run snapshot." >&2; cat "$TMP" >&2; exit 51;;
  422) echo "ERR: '$ELEMENT' (ref $REF) has no longPress action." >&2; cat "$TMP" >&2; exit 52;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /long_press returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 57;;
esac
```

- [ ] **Step 3: 检查 + Stage**

Run: `for s in tap long_press; do bash -n skills/flutter-wright/scripts/$s.sh && chmod +x skills/flutter-wright/scripts/$s.sh; done`

```bash
git add skills/flutter-wright/scripts/tap.sh skills/flutter-wright/scripts/long_press.sh
```

---

### Task 10: `type.sh`(含 submit 发 ENTER)

**Files:** Create `skills/flutter-wright/scripts/type.sh`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# type.sh — set text on a field by ref via SDK /type; optional submit (ENTER).
# Usage: type.sh "<element>" ref=<ref> text=<text> [submit=<bool>]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk   # also sets FW_DEVICE_ID for the optional ENTER keyevent

PORT="${VL_PORT:-9123}"
ELEMENT="${1:?element description required (positional arg 1)}"
shift
REF=""; TEXT=""; SUBMIT="false"
for arg in "$@"; do
  case "$arg" in
    ref=*) REF="${arg#ref=}";;
    text=*) TEXT="${arg#text=}";;
    submit=*) SUBMIT="${arg#submit=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 53;;
  esac
done
[ -n "$REF" ] || { echo "ERR: ref= required" >&2; exit 50; }
for v in "$ELEMENT" "$REF" "$TEXT"; do
  if [[ "$v" == *'"'* || "$v" == *'\'* || "$v" == *$'\n'* ]]; then
    echo "ERR: value contains unsupported characters (quotes/backslash/newline)." >&2; exit 53
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s","text":"%s"}' "$ELEMENT" "$REF" "$TEXT")
TMP=$(mktemp -t fw-type.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/type" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) ;;
  404) echo "ERR: ref '$REF' not in latest snapshot — re-run snapshot." >&2; cat "$TMP" >&2; exit 51;;
  422) echo "ERR: '$ELEMENT' (ref $REF) is not an editable text field." >&2; cat "$TMP" >&2; exit 54;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /type returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 55;;
esac
if [ "$SUBMIT" = "true" ]; then
  adb -s "$FW_DEVICE_ID" shell input keyevent 66 >/dev/null   # KEYCODE_ENTER
fi
cat "$TMP"; echo
```

- [ ] **Step 2: 检查 + Stage**

Run: `bash -n skills/flutter-wright/scripts/type.sh && chmod +x skills/flutter-wright/scripts/type.sh`

```bash
git add skills/flutter-wright/scripts/type.sh
```

---

### Task 11: `scroll.sh`

**Files:** Create `skills/flutter-wright/scripts/scroll.sh`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# scroll.sh — scroll a scrollable element by ref via SDK /scroll.
# Usage: scroll.sh "<element>" ref=<ref> dir=<up|down|left|right>
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
ELEMENT="${1:?element description required (positional arg 1)}"
shift
REF=""; DIR=""
for arg in "$@"; do
  case "$arg" in
    ref=*) REF="${arg#ref=}";;
    dir=*) DIR="${arg#dir=}";;
    amount=*) : ;;  # reserved; SDK v1 ignores amount
    *) echo "ERR: unknown arg '$arg'" >&2; exit 56;;
  esac
done
[ -n "$REF" ] || { echo "ERR: ref= required" >&2; exit 50; }
case "$DIR" in up|down|left|right) ;; *) echo "ERR: dir must be up|down|left|right" >&2; exit 56;; esac
for v in "$ELEMENT" "$REF"; do
  if [[ "$v" == *'"'* || "$v" == *'\'* || "$v" == *$'\n'* ]]; then
    echo "ERR: value contains unsupported characters." >&2; exit 56
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s","dir":"%s"}' "$ELEMENT" "$REF" "$DIR")
TMP=$(mktemp -t fw-scroll.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -o "$TMP" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/scroll" -H 'content-type: application/json' -d "$PAYLOAD") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  404) echo "ERR: ref '$REF' not in latest snapshot — re-run snapshot." >&2; cat "$TMP" >&2; exit 51;;
  422) echo "ERR: '$ELEMENT' (ref $REF) has no scroll$DIR action." >&2; cat "$TMP" >&2; exit 52;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /scroll returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 57;;
esac
```

- [ ] **Step 2: 检查 + Stage**

Run: `bash -n skills/flutter-wright/scripts/scroll.sh && chmod +x skills/flutter-wright/scripts/scroll.sh`

```bash
git add skills/flutter-wright/scripts/scroll.sh
```

---

### Task 12: `wait_for.sh`

**Files:** Create `skills/flutter-wright/scripts/wait_for.sh`

- [ ] **Step 1: 写脚本(curl -G --data-urlencode 安全编码)**

```bash
#!/usr/bin/env bash
# wait_for.sh — wait until a condition holds via SDK /wait_for.
# Usage: wait_for.sh (text=<s> | ref=<s> | gone=<s>) [timeout=<ms>]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
declare -a Q=()
HAS_COND=""
for arg in "$@"; do
  case "$arg" in
    text=*|ref=*|gone=*) Q+=(--data-urlencode "$arg"); HAS_COND="1";;
    timeout=*) Q+=(--data-urlencode "$arg");;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 84;;
  esac
done
[ -n "$HAS_COND" ] || { echo "ERR: need one of text= / ref= / gone=" >&2; exit 84; }

TMP=$(mktemp -t fw-wait.XXXXXX); trap 'rm -f "$TMP"' EXIT
HTTP_CODE=$(curl -s -G -o "$TMP" -w "%{http_code}" \
  "http://127.0.0.1:$PORT/wait_for" "${Q[@]}") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  408) echo "ERR: condition not met before timeout." >&2; cat "$TMP" >&2; exit 85;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /wait_for returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 85;;
esac
```

- [ ] **Step 2: 检查 + Stage**

Run: `bash -n skills/flutter-wright/scripts/wait_for.sh && chmod +x skills/flutter-wright/scripts/wait_for.sh`

```bash
git add skills/flutter-wright/scripts/wait_for.sh
```

---

### Task 13: `press_key.sh` + `back.sh`(adb,免 SDK)

**Files:** Create `skills/flutter-wright/scripts/press_key.sh`、`back.sh`

- [ ] **Step 1: 写 `press_key.sh`**

```bash
#!/usr/bin/env bash
# press_key.sh — send a hardware/IME key via adb. No SDK needed.
# Usage: press_key.sh <enter|back|home|tab|del|search|menu>
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_adb

KEY="${1:?key name required (enter|back|home|tab|del|search|menu)}"
case "$KEY" in
  enter)  CODE=66;;
  back)   CODE=4;;
  home)   CODE=3;;
  tab)    CODE=61;;
  del)    CODE=67;;
  search) CODE=84;;
  menu)   CODE=82;;
  *) echo "ERR: unknown key '$KEY'" >&2; exit 90;;
esac
if adb -s "$FW_DEVICE_ID" shell input keyevent "$CODE" >/dev/null; then
  echo "pressed: $KEY (keycode $CODE)"
else
  echo "ERR: adb keyevent $CODE failed" >&2; exit 91
fi
```

- [ ] **Step 2: 写 `back.sh`**

```bash
#!/usr/bin/env bash
# back.sh — system back (pop one route) via adb keyevent 4. No SDK needed.
# Usage: back.sh
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_adb

if adb -s "$FW_DEVICE_ID" shell input keyevent 4 >/dev/null; then
  echo "back"
else
  echo "ERR: adb keyevent 4 (BACK) failed" >&2; exit 91
fi
```

- [ ] **Step 3: 检查 + Stage**

Run: `for s in press_key back; do bash -n skills/flutter-wright/scripts/$s.sh && chmod +x skills/flutter-wright/scripts/$s.sh; done`

```bash
git add skills/flutter-wright/scripts/press_key.sh skills/flutter-wright/scripts/back.sh
```

---

### Task 14: `logs.sh`(读 daemon app.log,免 SDK)

**Files:** Create `skills/flutter-wright/scripts/logs.sh`

- [ ] **Step 1: 写脚本(打印原始 app.log 行,稳健)**

```bash
#!/usr/bin/env bash
# logs.sh — print app.log lines captured by the run-owned flutter daemon.
# Usage: logs.sh [since=<n>] [grep=<pat>]
set -euo pipefail

LOG="${CLAUDE_JOB_DIR:-/tmp}/fw_daemon.log"
[ -f "$LOG" ] || { echo "ERR: no daemon log at $LOG — start the app first (run)." >&2; exit 92; }

SINCE=""; PAT=""
for arg in "$@"; do
  case "$arg" in
    since=*) SINCE="${arg#since=}";;
    grep=*)  PAT="${arg#grep=}";;
    *) echo "ERR: unknown arg '$arg'" >&2; exit 92;;
  esac
done

LINES=$(grep '"app.log"' "$LOG" || true)
[ -n "$PAT" ]   && LINES=$(printf '%s\n' "$LINES" | grep -E "$PAT" || true)
[ -n "$SINCE" ] && LINES=$(printf '%s\n' "$LINES" | tail -n "$SINCE")
printf '%s\n' "$LINES"
```

- [ ] **Step 2: 检查 + Stage**

Run: `bash -n skills/flutter-wright/scripts/logs.sh && chmod +x skills/flutter-wright/scripts/logs.sh`

```bash
git add skills/flutter-wright/scripts/logs.sh
```

---

## Phase 5 — 版本 + 文档

### Task 15: 版本 0.6.0 → 0.7.0

**Files:** Modify `packages/flutter_wright_sdk/pubspec.yaml:3`、`lib/src/flutter_wright.dart`(version 常量)、`CHANGELOG.md`

- [ ] **Step 1**: `pubspec.yaml` `version: 0.6.0` → `version: 0.7.0`。
- [ ] **Step 2**: `flutter_wright.dart` `static const String version = '0.6.0';` → `'0.7.0'`。
- [ ] **Step 3**: `CHANGELOG.md` 在 `# 更新日志` 后插入:

```markdown
## 0.7.0 - 2026-05-27

### 新增
- **snapshot-first 交互层**(对齐 Playwright MCP):`GET /snapshot`(带 ref 的 YAML);
  `POST /tap` `/long_press` `/scroll` `/type`(经 `SemanticsOwner.performAction`,
  请求体 `element`+`ref`,成功响应**自动回吐** `snapshot`);`GET /wait_for`(408 超时)。
  `start()` 启动 `ensureSemantics()` 常开语义树。
- (skill 侧)`snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`(SDK)+ `pressKey`/`back`/`logs`(免 SDK)。

### 变更
- **navigatorKey 降级为可选**:`start()` 仅当传了 `navigatorKey`/`navigationAdapter` 才注册
  `/navigate` `/reset` `/routes`;否则回 501「navigation not configured」。交互闭环只需 `start()`。
- `/navigate` `/reset` 成功响应也附 `snapshot`。
- 示例 `dev/main_dev.dart` 显式传 `navigatorKey`。
```

- [ ] **Step 4**: Run `cd packages/flutter_wright_sdk && flutter analyze && flutter test`(Expected: 全绿)
- [ ] **Step 5**: Stage

```bash
git add packages/flutter_wright_sdk/pubspec.yaml \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart \
        packages/flutter_wright_sdk/CHANGELOG.md
```

---

### Task 16: 改写 `SKILL.md`

**Files:** Modify `skills/flutter-wright/SKILL.md`

> 保持中文/skill 本味,不照搬 Playwright 英文措辞。先通读现文件。

- [ ] **Step 1**: frontmatter `description` 把「9 个方法(...)」更新为 18 个方法,并补「snapshot-first:先 snapshot 拿 ref 再 tap/type」。
- [ ] **Step 2**: 「方法」表前新增「工作法(snapshot-first)」一节:

```markdown
## 工作法(snapshot-first)

像 Playwright 一样:**先 `snapshot` 拿 `ref`,再用 `ref` 去 `tap`/`type`/`scroll`。**

- `snapshot` 返回带 `[ref=sN]` 的语义树;`ref` **临时** —— 页面一变(导航/reload/动作)就重新 `snapshot`,旧 ref 失效(回 51)。
- `tap`/`type`/`scroll`/`longPress` 成功后**自动回吐**最新 snapshot,通常无需手动再 `snapshot`(导航类动作若界面下一帧才重建,用 `waitFor` 做确定性同步)。
- `screenshot` 只用于**看效果**,**不用于定位元素** —— 定位靠 `snapshot`。
- 方法分三类:**observe**(`snapshot`/`screenshot`/`logs`)、**act**(`tap`/`type`/`scroll`/`longPress`/`pressKey`/`back`)、**navigate**(`goto`/`reset`)。
```

- [ ] **Step 3**: 方法表追加 9 行(snapshot/tap/type/scroll/longPress/waitFor/pressKey/back/logs),签名见本计划「方法面」。
- [ ] **Step 4**: 「⚠️ 前提」段补:交互(snapshot/tap/...)需 SDK(同 goto);`pressKey`/`back` 走 adb、`logs` 走 daemon,免 SDK。**goto/reset 现仅当宿主 `start()` 传了 navigatorKey/adapter 才可用,否则回「导航未配置」。** 派发约定补:`element` 是引号位置参数 + `ref`/`text`/`dir` 等 key=value;含 `"`/`\` 不支持。
- [ ] **Step 5**: 退出码总表追加 `50-57 交互 / 80-81 snapshot / 84-85 waitFor / 90-92 按键·日志`(细分见本计划退出码)。
- [ ] **Step 6**: Stage `git add skills/flutter-wright/SKILL.md`

---

### Task 17: 更新其余文档

**Files:** Modify `docs/api-reference.md`、`architecture.md`、`integration-guide.md`、`integration-guide-for-ai.md`、`troubleshooting.md`、`README.md`

- [ ] **Step 1** `api-reference.md`:新增 `/snapshot`(text/plain YAML)、`/tap` `/long_press` `/scroll`(`{element,ref[,dir]}`→`{ok,snapshot}`)、`/type`(`{element,ref,text}`)、`/wait_for`(query→200+`{ok,snapshot}`/408);注明 `/navigate` `/reset` 响应新增 `snapshot`,未配置导航时这三端点回 501;版本 0.7.0。
- [ ] **Step 2** `architecture.md`:删「故意不做」里「UI 交互」「Widget tree 检视」两条;组件图补 `semantics_snapshot`/`semantics_action` + 6 handler;补 navigatorKey 降级 / 集成分层(零集成 / `start()` 解锁交互 / +navigatorKey 解锁 goto / +FlutterWrightRoot 渲染树截图)。
- [ ] **Step 3** `integration-guide.md` + `integration-guide-for-ai.md`:SDK 角色从「只解锁 goto」改为「`start()` 解锁全套交互,navigatorKey/adapter 再解锁 goto/reset」;AI 版补决策:只要交互不要 goto → 只 `start()`。
- [ ] **Step 4** `troubleshooting.md`:新增 snapshot 为空 / ref 过期(51)/ type 回 54 / goto 回 501 四个症状。
- [ ] **Step 5** `README.md`:「是什么」补 snapshot→act;能力清单扩到「看语义树 + 操作」;SDK 角色更新。
- [ ] **Step 6** Stage 全部 docs。

---

## Phase 6 — 验收(Acceptance)

### Task 18: 脚本级验收 e2e(真实 bash 脚本驱动真实 app)

**Files:** Modify `packages/example/test/e2e_interaction_test.dart`

> 仿 `e2e_control_plane_test.dart` 的 `skill bash 脚本` group:写 `fw_health_done` marker 走 fast-path 跳过 adb,真实跑 `snapshot.sh`/`tap.sh`/`type.sh` 打本机 9123。这是脚本↔SDK 端到端验收。`type.sh` 不带 `submit`(无真机 adb)。

- [ ] **Step 1: 追加脚本验收 group(先红:脚本路径/行为未就绪即失败)**

在 `e2e_interaction_test.dart` 追加:

```dart
  group('验收:skill 脚本真实驱动 SDK', () {
    late Directory jobDir;
    late String scriptsDir;

    setUp(() async {
      jobDir = await Directory.systemTemp.createTemp('fw_job_');
      File('${jobDir.path}/fw_health_done')
          .writeAsStringSync('device=desktop-test\nport=9123\nts=0\n');
      scriptsDir = Directory(
              '${Directory.current.path}/../../skills/flutter-wright/scripts')
          .absolute
          .path;
    });
    tearDown(() async {
      if (await jobDir.exists()) await jobDir.delete(recursive: true);
    });

    Future<ProcessResult> run(String script, List<String> args) {
      return Process.run('bash', <String>['$scriptsDir/$script', ...args],
          environment: <String, String>{
            'CLAUDE_JOB_DIR': jobDir.path,
            'VL_PORT': '9123',
          },
          includeParentEnvironment: true);
    }

    testWidgets('snapshot.sh → type.sh → tap.sh 闭环', (WidgetTester tester) async {
      await bootLogin(tester);

      final ProcessResult snap =
          (await tester.runAsync(() => run('snapshot.sh', <String>[])))!;
      expect(snap.exitCode, 0, reason: 'snapshot.sh stderr: ${snap.stderr}');
      final String yaml = snap.stdout.toString();
      final String? phoneRef = refFor(yaml, '手机号');
      final String? loginRef = refFor(yaml, '登录');
      expect(phoneRef, isNotNull, reason: yaml);
      expect(loginRef, isNotNull, reason: yaml);

      final ProcessResult typed = (await tester.runAsync(() => run('type.sh',
          <String>['手机号', 'ref=$phoneRef', 'text=13800000000'])))!;
      await tester.pumpAndSettle();
      expect(typed.exitCode, 0, reason: 'type.sh stderr: ${typed.stderr}');
      expect(find.text('13800000000'), findsOneWidget);

      final ProcessResult tapped = (await tester
          .runAsync(() => run('tap.sh', <String>['登录', 'ref=$loginRef'])))!;
      await tester.pumpAndSettle();
      expect(tapped.exitCode, 0, reason: 'tap.sh stderr: ${tapped.stderr}');
    });
  });
```

- [ ] **Step 2: 跑确认红 → 实现 Phase 4 脚本后转绿**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`
Expected:Phase 4 脚本就绪后 `All tests passed!`(若先于 Phase 4 跑,因脚本不存在而红 —— 符合验收驱动顺序)。

- [ ] **Step 3: Stage**

```bash
git add packages/example/test/e2e_interaction_test.dart
```

---

### Task 19: 验收标准 + 真机手测清单(ACCEPTANCE 报告)

**Files:** Create `docs/superpowers/acceptance/2026-05-27-interaction-acceptance.md`

> 自动 e2e 跑在桌面 flutter_test(无 adb/真机)。`pressKey`/`back`/`logs`(adb/daemon)、`type submit`(adb ENTER)、`setText` 在真实 IME 下的可靠性必须**真机手测**。本文件即验收依据。

- [ ] **Step 1: 写验收文档**

```markdown
# 交互层验收 — 2026-05-27

## A. 自动验收(`flutter test`,已在 CI 可跑)

- [ ] `flutter_wright_sdk`:`flutter test` 全绿(`semantics_snapshot_test` / `semantics_action_test` / `start_navigation_test`)。
- [ ] `example`:`flutter test` 全绿(`e2e_control_plane_test` 回归 + `e2e_interaction_test`:snapshot/type/tap/wait_for/navigate 回吐 + 脚本闭环)。
- [ ] 两包 `flutter analyze` 干净。

## B. 真机手测(连一台开了 USB 调试的 Android,`run` 起集成 SDK 的 `dev/main_dev.dart`)

- [ ] `snapshot` 返回当前页语义树,登录/列表页元素都带 ref。
- [ ] `tap "<x>" ref=<r>`:点中按钮,响应回吐的 snapshot 反映新页面。
- [ ] `type "<x>" ref=<r> text=... submit=true`:输入框出现文本,ENTER 提交生效。
- [ ] `scroll "<x>" ref=<r> dir=down`:长列表真的滚动(snapshot 出现新项)。
- [ ] `longPress`:触发长按菜单/回调。
- [ ] `waitFor text=... timeout=3000`:目标出现即返回 200,不出现超时 exit 85。
- [ ] `pressKey enter|back`、`back`:系统键/返回生效(免 SDK)。
- [ ] `logs since=50`:打印 app 近期 `app.log`(需先 `run`)。
- [ ] `goto` 在**未传 navigatorKey** 的 `start()` 下回「导航未配置」;传了则正常跳。

## C. 退出码抽查

- [ ] 过期 ref → `tap` exit 51;非输入框 → `type` exit 54;非法 scroll dir → exit 56;`wait_for` 超时 → exit 85;`logs` 未 run → exit 92。

## 结论

- 通过条件:A 全绿 + B/C 全勾。
- 未达项记录于此并附 issue 链接。
```

- [ ] **Step 2: Stage**

```bash
git add docs/superpowers/acceptance/2026-05-27-interaction-acceptance.md
```

---

## 实施排序与说明

- **Phase 1→2→3 硬依赖**(逻辑单元 → handler);**Phase 6 Task 18 依赖 Phase 4 脚本就绪**(验收驱动:可先写红,Phase 4 后转绿)。Phase 5(版本/文档)可在 3 之后任意时插。
- **TDD 红绿**贯穿 Phase 1-3、7;**风险 #1(setText)** 在 Task 2 红绿即定论。
- **自动回吐 snapshot 新鲜度**:handler 内同步序列化,反映「动作派发后即刻」;导航类动作下一帧才重建,确定性同步用 `waitFor`(已写进 SKILL.md 工作法)。
- 全程**只 stage 不 commit**;勿 `git add -A`(仓库另有无关 untracked)。
