# Playwright-aligned Interaction Layer Implementation Plan

> **For agentic workers:** Use the subagent-driven-development skill (recommended) or executing-plans skill to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 FlutterWright 加一层 snapshot-first 交互:`snapshot`(读 Semantics 树→带 ref 的 YAML)+ `tap`/`type`/`scroll`/`longPress`/`waitFor`(SDK)+ `pressKey`/`back`/`logs`(免 SDK),并把 navigatorKey 降级为可选。

**Architecture:** 扩展现有 `flutter_wright_sdk` HTTP 控制面(adb forward + curl:9123)。新增两个纯逻辑单元 `semantics_snapshot.dart`(序列化+ref 解析)与 `semantics_action.dart`(经 `SemanticsOwner.performAction` 驱动动作),6 个 HTTP handler,9 个 bash 脚本。动作成功响应附最新 snapshot。交互闭环只需 `FlutterWright.start()`;导航(goto/reset)handler 改为仅在传了 navigatorKey/adapter 时注册。

**Tech Stack:** Dart / Flutter 3.44(`SemanticsBinding.ensureSemantics`、`RendererBinding.renderViews`、`SemanticsOwner.performAction`)、`dart:io HttpServer`、bash + curl + adb、`flutter_test`。

**已对 Flutter 3.24.0(支持下限)+ 3.44.0(本机)双版本源码核实的 API(签名一致):** `SemanticsBinding.instance.ensureSemantics()→SemanticsHandle`;`RendererBinding.instance.renderViews`;`view.owner?.semanticsOwner?.rootSemanticsNode`;`SemanticsNode.{id,owner,visitChildren,getSemanticsData}`;`SemanticsData.{label,value,hasFlag(SemanticsFlag),hasAction(SemanticsAction)}`;`SemanticsOwner.performAction(int,SemanticsAction,[Object?])`;6 个 `SemanticsFlag` 值(isTextField/isButton/isHeader/isImage/isLink/hasCheckedState)。

**计划级范围决定(YAGNI):** spec 第 2 节的「合成 pointer 兜底」**本期不做**。v1 一律走 `performAction`;节点未暴露对应 action 时返回明确错误(标准 Material/Cupertino 控件都暴露 tap/setText,登录页 E2E 不依赖兜底)。兜底连同其全局 rect 变换数学(spec 风险 #2)留作后续,届时配真机验证。

---

## Phase 1 — SDK 读路径(snapshot)

### Task 1: `SemanticsSnapshot` 单元(序列化 + ref 解析 + 文本搜索)

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/semantics_snapshot.dart`

- [ ] **Step 1: 实现 `SemanticsSnapshot`**

```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

/// 把活的 Flutter Semantics(无障碍)树序列化成 Playwright 风格的 YAML 快照,
/// 并把 `ref` 解析回节点。
///
/// `ref` = `s<SemanticsNode.id>`。ref 是**临时的**:只有最近一次 [serialize]
/// 发出过的 ref 才能 [resolve](与 Playwright 的 snapshot ref 行为一致)。
class SemanticsSnapshot {
  SemanticsSnapshot._();

  /// 最近一次 [serialize] 中带过 ref 的节点 id 集合。
  static final Set<int> _liveRefs = <int>{};

  /// 遍历每个 render view 的语义树 → YAML,并刷新 ref 集合。
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

  /// 把最近一次 [serialize] 的 `ref` 解析为活节点;未知/过期/节点已消失则 null。
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

  /// 任一节点的 label 或 value 是否包含 [needle](供 waitFor)。
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

- [ ] **Step 2: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/semantics_snapshot.dart
```
**不要 commit。**

---

### Task 2: `SemanticsSnapshot` 单元测试

**Files:**
- Create: `packages/flutter_wright_sdk/test/semantics_snapshot_test.dart`

- [ ] **Step 1: 写测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/src/semantics_snapshot.dart';

void main() {
  testWidgets('serialize 列出 textfield/button 并只给可操作节点 ref',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: <Widget>[
          const TextField(
              decoration: InputDecoration(labelText: '手机号')),
          ElevatedButton(onPressed: () {}, child: const Text('登录')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final String yaml = SemanticsSnapshot.serialize();
    expect(yaml, contains('textfield'));
    expect(yaml, contains('button'));
    expect(yaml, contains('登录'));
    expect(yaml, contains('[ref=s')); // 可操作节点带 ref
    handle.dispose();
  });

  testWidgets('resolve:已知 ref 命中,未知 ref 返回 null',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ElevatedButton(onPressed: () {}, child: const Text('OK'))),
    ));
    await tester.pumpAndSettle();
    SemanticsSnapshot.serialize(); // 填充 ref 集合

    final SemanticsNode node = tester.getSemantics(find.text('OK'));
    expect(SemanticsSnapshot.resolve('s${node.id}'), isNotNull);
    expect(SemanticsSnapshot.resolve('s999999'), isNull); // 不在快照
    handle.dispose();
  });
}
```

- [ ] **Step 2: Run 测试**

Run: `cd packages/flutter_wright_sdk && flutter test test/semantics_snapshot_test.dart`
Expected: `All tests passed!`

- [ ] **Step 3: Stage**

```bash
git add packages/flutter_wright_sdk/test/semantics_snapshot_test.dart
```
**不要 commit。**

---

### Task 3: `SnapshotHandler` + `start()` 接 ensureSemantics

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/handlers/snapshot_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: 实现 `SnapshotHandler`(GET /snapshot,返回 text/plain YAML)**

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

- [ ] **Step 2: 在 `flutter_wright.dart` 接入 ensureSemantics + 注册 SnapshotHandler**

在文件顶部 import 区加(与既有 import 并列):

```dart
import 'package:flutter/semantics.dart';
import 'handlers/snapshot_handler.dart';
```

在 `class FlutterWright` 内 `_server` 字段旁加一个持有句柄的静态字段:

```dart
  static SemanticsHandle? _semanticsHandle;
```

在 `start()` 内、`if (_server != null) {...}` 守卫之后,**插入** ensureSemantics:

```dart
    // 常开语义树,/snapshot 与全套交互才有树可读(仅 debug 生效)。
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
```

在 `final handlers = <Handler>[ ... ];` 列表里把 `SnapshotHandler()` 加进去(放在 `ScreenshotHandler(...)` 之后):

```dart
      ScreenshotHandler(config.screenshotMode),
      SnapshotHandler(),
```

在 `stop()` 内、`await _server?.stop();` 之后释放句柄:

```dart
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
```

- [ ] **Step 3: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/snapshot_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

## Phase 2 — SDK 动作(act)

### Task 4: `SemanticsActions` 单元(performAction 驱动)

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/semantics_action.dart`

- [ ] **Step 1: 实现 `SemanticsActions`**

```dart
import 'package:flutter/semantics.dart';

/// 经 [SemanticsAction] 在已解析节点上驱动交互 —— 与 OS 无障碍系统同一条路径。
/// v1 不含合成 pointer 兜底:节点未暴露对应 action 时返回 false(见计划范围说明)。
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

  /// 先 tap 取焦点(若节点支持),再 setText。节点不可输入时返回 false。
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

- [ ] **Step 2: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/semantics_action.dart
```
**不要 commit。**

---

### Task 5: `SemanticsActions` 单元测试(同时验证 spec 风险 #1 setText)

**Files:**
- Create: `packages/flutter_wright_sdk/test/semantics_action_test.dart`

> 这条测试就是 spec 风险 #1/#2 的早期验证点:若 `performAction(tap/setText)` 在测试 binding 里不奏效,这里立刻暴露,据此决定 `type` 是否退回 `adb input text`。

- [ ] **Step 1: 写测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/src/semantics_action.dart';

void main() {
  testWidgets('tap 触发按钮 onPressed', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    bool tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
              onPressed: () => tapped = true, child: const Text('按我')),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final SemanticsNode node = tester.getSemantics(find.text('按我'));
    expect(SemanticsActions.tap(node), isTrue);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    handle.dispose();
  });

  testWidgets('setText 写入输入框', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));
    await tester.pumpAndSettle();

    final SemanticsNode node = tester.getSemantics(find.byType(TextField));
    expect(SemanticsActions.setText(node, '北京'), isTrue);
    await tester.pumpAndSettle();
    expect(controller.text, '北京');
    handle.dispose();
  });
}
```

- [ ] **Step 2: Run 测试**

Run: `cd packages/flutter_wright_sdk && flutter test test/semantics_action_test.dart`
Expected: `All tests passed!`

> 若 `setText` 用例失败:在 `SemanticsActions.setText` 退回方案(skill 侧 `adb shell input text`)前,先记录失败信息,这是 spec 风险 #1 的决策依据。

- [ ] **Step 3: Stage**

```bash
git add packages/flutter_wright_sdk/test/semantics_action_test.dart
```
**不要 commit。**

---

### Task 6: `TapHandler` + `LongPressHandler` + 注册 + 自动回吐 snapshot

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/handlers/tap_handler.dart`
- Create: `packages/flutter_wright_sdk/lib/src/handlers/long_press_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: 实现 `TapHandler`**

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

- [ ] **Step 2: 实现 `LongPressHandler`**

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

> 这两个 handler 不显式命名 `SemanticsNode` 类型(用推断 `final node`),因此**无需** import `package:flutter/semantics.dart`。

- [ ] **Step 3: 在 `flutter_wright.dart` 注册**

import 区加:

```dart
import 'handlers/tap_handler.dart';
import 'handlers/long_press_handler.dart';
```

`handlers` 列表加(`SnapshotHandler()` 之后):

```dart
      TapHandler(),
      LongPressHandler(),
```

- [ ] **Step 4: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/tap_handler.dart \
        packages/flutter_wright_sdk/lib/src/handlers/long_press_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

### Task 7: `TypeHandler` + 注册

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/handlers/type_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: 实现 `TypeHandler`(submit 由 skill 侧发 ENTER,见 Task 14)**

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

- [ ] **Step 2: 注册**

`flutter_wright.dart` import 区 + handlers 列表加 `TypeHandler()`:

```dart
import 'handlers/type_handler.dart';
```
```dart
      TypeHandler(),
```

- [ ] **Step 3: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/type_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

### Task 8: `ScrollHandler` + 注册

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/handlers/scroll_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: 实现 `ScrollHandler`**

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

- [ ] **Step 2: 注册**

```dart
import 'handlers/scroll_handler.dart';
```
```dart
      ScrollHandler(),
```

- [ ] **Step 3: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/scroll_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

### Task 9: `WaitForHandler` + 注册

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/handlers/wait_for_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`

- [ ] **Step 1: 实现 `WaitForHandler`(GET,读 query;命中 200+snapshot,超时 408)**

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
      await ctx.request
          .writeError(400, 'need one of text= / ref= / gone=');
      return;
    }

    bool met() {
      if (text != null) return SemanticsSnapshot.containsText(text);
      if (ref != null) return SemanticsSnapshot.resolve(ref) != null;
      return !SemanticsSnapshot.containsText(gone!); // gone
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

- [ ] **Step 2: 注册**

```dart
import 'handlers/wait_for_handler.dart';
```
```dart
      WaitForHandler(),
```

- [ ] **Step 3: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/wait_for_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart
```
**不要 commit。**

---

### Task 10: navigate / reset handler 也回吐 snapshot

**Files:**
- Modify: `packages/flutter_wright_sdk/lib/src/handlers/navigate_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/handlers/reset_handler.dart`

- [ ] **Step 1: `navigate_handler.dart` 成功响应附 snapshot**

顶部加 import:

```dart
import '../semantics_snapshot.dart';
```

把成功分支(现为 `await ctx.request.writeOk(<String, Object?>{'route': route});`)改为:

```dart
      await ctx.request.writeOk(<String, Object?>{
        'route': route,
        'snapshot': SemanticsSnapshot.serialize(),
      });
```

- [ ] **Step 2: `reset_handler.dart` 成功响应附 snapshot**

顶部加 import:

```dart
import '../semantics_snapshot.dart';
```

把成功分支 `await ctx.request.writeOk();`(`reset_handler.dart:22`)改为:

```dart
      await ctx.request.writeOk(<String, Object?>{
        'snapshot': SemanticsSnapshot.serialize(),
      });
```

- [ ] **Step 3: Run 静态检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/navigate_handler.dart \
        packages/flutter_wright_sdk/lib/src/handlers/reset_handler.dart
```
**不要 commit。**

---

## Phase 3 — navigatorKey 降级为可选(决策 B)

### Task 11: 导航 handler 条件注册 + 「未配置」明确报错 + 更新 example/测试

**Files:**
- Create: `packages/flutter_wright_sdk/lib/src/handlers/nav_not_configured_handler.dart`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`
- Modify: `packages/example/dev/main_dev.dart`
- Modify: `packages/example/test/e2e_control_plane_test.dart`
- Create: `packages/flutter_wright_sdk/test/start_navigation_test.dart`

- [ ] **Step 1: 实现 `NavNotConfiguredHandler`(一个类,按 path/method 复用)**

```dart
import 'handler.dart';

/// 当 host 未传 navigatorKey/navigationAdapter 时,占位回应导航端点,
/// 返回明确的「导航未配置」(501),而不是默默 503 或 404。
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

- [ ] **Step 2: 改写 `flutter_wright.dart` 的 `start()` 为条件注册**

import 区加:

```dart
import 'handlers/nav_not_configured_handler.dart';
```

把现有「构造 adapter + 无条件加入 Routes/Navigate/Reset」那段(当前 `flutter_wright.dart:53-70` 的 `final NavigationAdapter adapter = ...` 到 `handlers` 列表)替换为:**先建只含非导航 handler 的列表,再按是否配置导航追加**:

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

    // 导航(goto/reset)是可选 opt-in:仅当 host 传了 navigatorKey 或自定义
    // adapter 才注册;否则占位 handler 明确回「导航未配置」。
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

> 注意:Task 3/6/7/8/9 已分别把 SnapshotHandler/TapHandler/... 加进旧的 `handlers` 列表;本步用上面这段**整体替换**那个列表定义,确保两套逻辑不重复。替换后确认 import 区含全部 handler。

- [ ] **Step 3: 更新 `packages/example/dev/main_dev.dart` 显式传 navigatorKey**

把 `await FlutterWright.start(routes: AppRouter.names);` 改为:

```dart
  await FlutterWright.start(
    navigatorKey: FlutterWright.navigatorKey,
    routes: AppRouter.names,
  );
```

- [ ] **Step 4: 更新 `e2e_control_plane_test.dart` 的 `bootApp` 同样显式传**

把 `bootApp` 内:

```dart
    await tester.runAsync(() => FlutterWright.start(
          routes: AppRouter.names,
        ));
```

改为:

```dart
    await tester.runAsync(() => FlutterWright.start(
          navigatorKey: FlutterWright.navigatorKey,
          routes: AppRouter.names,
        ));
```

- [ ] **Step 5: 写条件注册单元测试**

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
    final res = await Process.run('curl', <String>[
      '-s', '-o', '/dev/null', '-w', '%{http_code}',
      '-X', 'POST', 'http://127.0.0.1:9123/navigate',
      '-H', 'content-type: application/json',
      '-d', jsonEncode(<String, Object?>{'route': '/x'}),
    ]);
    return int.tryParse(res.stdout.toString().trim()) ?? 0;
  }

  testWidgets('未传 navigatorKey/adapter:/navigate 回 501 导航未配置',
      (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start());
    final int code = (await tester.runAsync(postNavigate))!;
    expect(code, 501);
  });

  testWidgets('传了 navigatorKey:/navigate 被注册(非 501)',
      (WidgetTester tester) async {
    await tester.runAsync(() =>
        FlutterWright.start(navigatorKey: FlutterWright.navigatorKey));
    final int code = (await tester.runAsync(postNavigate))!;
    expect(code, isNot(501)); // 已注册;navigator 未挂载时为 503
  });
}
```

- [ ] **Step 6: Run 静态检查 + 全部测试**

Run: `cd packages/flutter_wright_sdk && flutter analyze && flutter test`
Expected: `No issues found!` 且 `All tests passed!`

Run: `cd packages/example && flutter test test/e2e_control_plane_test.dart`
Expected: `All tests passed!`(确认 bootApp 改动后既有导航/截图 e2e 仍绿)

- [ ] **Step 7: Stage**

```bash
git add packages/flutter_wright_sdk/lib/src/handlers/nav_not_configured_handler.dart \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart \
        packages/flutter_wright_sdk/test/start_navigation_test.dart \
        packages/example/dev/main_dev.dart \
        packages/example/test/e2e_control_plane_test.dart
```
**不要 commit。**

---

## Phase 4 — skill bash 脚本

> 所有脚本:`set -euo pipefail`、`source _lib.sh`、`VL_PORT` 默认 9123。SDK 类先 `fw_need_sdk`;免-SDK 类不调。curl 用 `-o $TMP -w "%{http_code}"` + `case` 分流退出码。`element`/`ref`/`text` 等含 `"`/`\`/换行的拒绝(避免 bash 手搓 JSON 转义),与 `goto.sh` 一致。

### Task 12: `snapshot.sh`

**Files:**
- Create: `skills/flutter-wright/scripts/snapshot.sh`

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
    if [ -n "$OUT" ]; then
      mkdir -p "$(dirname "$OUT")"
      cp "$TMP" "$OUT"
      echo "snapshot -> $OUT" >&2
    fi
    cat "$TMP"; echo
    ;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /snapshot returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 80;;
esac
```

- [ ] **Step 2: 语法检查**

Run: `bash -n skills/flutter-wright/scripts/snapshot.sh && chmod +x skills/flutter-wright/scripts/snapshot.sh`
Expected: 无输出(语法 OK)

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/snapshot.sh
```
**不要 commit。**

---

### Task 13: `tap.sh` + `long_press.sh`

**Files:**
- Create: `skills/flutter-wright/scripts/tap.sh`
- Create: `skills/flutter-wright/scripts/long_press.sh`

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
    echo "ERR: value contains unsupported characters (quotes/backslash/newline)." >&2
    exit 50
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s"}' "$ELEMENT" "$REF")
TMP=$(mktemp -t fw-tap.XXXXXX)
trap 'rm -f "$TMP"' EXIT

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

- [ ] **Step 2: 写 `long_press.sh`(同结构,改端点/动作名)**

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
    echo "ERR: value contains unsupported characters (quotes/backslash/newline)." >&2
    exit 50
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s"}' "$ELEMENT" "$REF")
TMP=$(mktemp -t fw-lp.XXXXXX)
trap 'rm -f "$TMP"' EXIT

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

- [ ] **Step 3: 语法检查 + 可执行**

Run: `for s in tap long_press; do bash -n skills/flutter-wright/scripts/$s.sh && chmod +x skills/flutter-wright/scripts/$s.sh; done`
Expected: 无输出

- [ ] **Step 4: Stage**

```bash
git add skills/flutter-wright/scripts/tap.sh skills/flutter-wright/scripts/long_press.sh
```
**不要 commit。**

---

### Task 14: `type.sh`(含 submit 发 ENTER)

**Files:**
- Create: `skills/flutter-wright/scripts/type.sh`

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
    echo "ERR: value contains unsupported characters (quotes/backslash/newline)." >&2
    exit 53
  fi
done

PAYLOAD=$(printf '{"element":"%s","ref":"%s","text":"%s"}' "$ELEMENT" "$REF" "$TEXT")
TMP=$(mktemp -t fw-type.XXXXXX)
trap 'rm -f "$TMP"' EXIT

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

- [ ] **Step 2: 语法检查 + 可执行**

Run: `bash -n skills/flutter-wright/scripts/type.sh && chmod +x skills/flutter-wright/scripts/type.sh`
Expected: 无输出

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/type.sh
```
**不要 commit。**

---

### Task 15: `scroll.sh`

**Files:**
- Create: `skills/flutter-wright/scripts/scroll.sh`

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
TMP=$(mktemp -t fw-scroll.XXXXXX)
trap 'rm -f "$TMP"' EXIT

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

- [ ] **Step 2: 语法检查 + 可执行**

Run: `bash -n skills/flutter-wright/scripts/scroll.sh && chmod +x skills/flutter-wright/scripts/scroll.sh`
Expected: 无输出

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/scroll.sh
```
**不要 commit。**

---

### Task 16: `wait_for.sh`(GET + curl 自动 URL 编码)

**Files:**
- Create: `skills/flutter-wright/scripts/wait_for.sh`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# wait_for.sh — wait until a condition holds via SDK /wait_for.
# Usage: wait_for.sh (text=<s> | ref=<s> | gone=<s>) [timeout=<ms>]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"
fw_need_sdk

PORT="${VL_PORT:-9123}"
# 收集 query 参数;用 curl -G --data-urlencode 安全编码(支持空格/中文)。
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

TMP=$(mktemp -t fw-wait.XXXXXX)
trap 'rm -f "$TMP"' EXIT

HTTP_CODE=$(curl -s -G -o "$TMP" -w "%{http_code}" \
  "http://127.0.0.1:$PORT/wait_for" "${Q[@]}") || HTTP_CODE="000"
case "$HTTP_CODE" in
  200) cat "$TMP"; echo;;
  408) echo "ERR: condition not met before timeout." >&2; cat "$TMP" >&2; exit 85;;
  000) echo "ERR: SDK unreachable at 127.0.0.1:$PORT" >&2; exit 12;;
  *)   echo "ERR: /wait_for returned $HTTP_CODE" >&2; cat "$TMP" >&2; exit 85;;
esac
```

- [ ] **Step 2: 语法检查 + 可执行**

Run: `bash -n skills/flutter-wright/scripts/wait_for.sh && chmod +x skills/flutter-wright/scripts/wait_for.sh`
Expected: 无输出

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/wait_for.sh
```
**不要 commit。**

---

### Task 17: `press_key.sh` + `back.sh`(adb,免 SDK)

**Files:**
- Create: `skills/flutter-wright/scripts/press_key.sh`
- Create: `skills/flutter-wright/scripts/back.sh`

- [ ] **Step 1: 写 `press_key.sh`(友好名→keycode)**

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

- [ ] **Step 2: 写 `back.sh`(≈ browser_navigate_back = 系统返回)**

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

- [ ] **Step 3: 语法检查 + 可执行**

Run: `for s in press_key back; do bash -n skills/flutter-wright/scripts/$s.sh && chmod +x skills/flutter-wright/scripts/$s.sh; done`
Expected: 无输出

- [ ] **Step 4: Stage**

```bash
git add skills/flutter-wright/scripts/press_key.sh skills/flutter-wright/scripts/back.sh
```
**不要 commit。**

---

### Task 18: `logs.sh`(读 daemon app.log,免 SDK)

**Files:**
- Create: `skills/flutter-wright/scripts/logs.sh`

- [ ] **Step 1: 写脚本(打印原始 app.log 行,稳健、不脆弱解析)**

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

# daemon stdout 里 app 日志走 "event":"app.log" 行;直接打印整行(结构化、可读)。
LINES=$(grep '"app.log"' "$LOG" || true)
[ -n "$PAT" ]   && LINES=$(printf '%s\n' "$LINES" | grep -E "$PAT" || true)
[ -n "$SINCE" ] && LINES=$(printf '%s\n' "$LINES" | tail -n "$SINCE")
printf '%s\n' "$LINES"
```

- [ ] **Step 2: 语法检查 + 可执行**

Run: `bash -n skills/flutter-wright/scripts/logs.sh && chmod +x skills/flutter-wright/scripts/logs.sh`
Expected: 无输出

- [ ] **Step 3: Stage**

```bash
git add skills/flutter-wright/scripts/logs.sh
```
**不要 commit。**

---

## Phase 5 — E2E + 版本 + 文档

### Task 19: 交互 E2E(snapshot → type → tap,真实 curl)

**Files:**
- Create: `packages/example/test/e2e_interaction_test.dart`

> 沿用 `e2e_control_plane_test.dart` 的范式:flutter_test 内挂真实 app + 启真实 SDK,**真实 curl 子进程**打 9123。语义树需 `tester.ensureSemantics()`。

- [ ] **Step 1: 写测试**

```dart
// 交互层 e2e:真实 curl 打 /snapshot /type /tap,断言 UI 真的变化。
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
    final ProcessResult res = await Process.run('curl', <String>[
      '-s', '-o', out.path, '-w', '%{http_code}', '$_base$path',
    ]);
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
      '-s', '-o', out.path, '-w', '%{http_code}',
      '-X', 'POST', '$_base$path',
      '-H', 'content-type: application/json', '-d', jsonEncode(json),
    ]);
    final int code = int.tryParse(res.stdout.toString().trim()) ?? 0;
    final String body = await out.exists() ? await out.readAsString() : '';
    return (code: code, body: body);
  } finally {
    await tmp.delete(recursive: true);
  }
}

/// 从 snapshot YAML 里抓某 label 行的 ref(形如 `... "登录" [ref=s12]`)。
String? _refFor(String yaml, String label) {
  for (final String line in yaml.split('\n')) {
    if (line.contains('"$label"')) {
      final RegExp re = RegExp(r'\[ref=(s\d+)\]');
      final Match? m = re.firstMatch(line);
      if (m != null) return m.group(1);
    }
  }
  return null;
}

void main() {
  late SemanticsHandle semantics;

  Future<void> bootLogin(WidgetTester tester) async {
    semantics = tester.ensureSemantics();
    await tester.runAsync(() => FlutterWright.start(
          navigatorKey: FlutterWright.navigatorKey,
          routes: AppRouter.names,
        ));
    await tester.pumpWidget(
      FlutterWrightRoot(child: createApp(navigatorKey: FlutterWright.navigatorKey)),
    );
    await tester.pumpAndSettle();
    // 跳到登录页(有手机号/密码 TextField + 登录按钮)。
    await tester.runAsync(() => _curlPost('/navigate', <String, Object?>{'route': '/login'}));
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    await FlutterWright.stop();
    semantics.dispose();
  });

  testWidgets('snapshot 列出登录页元素,type+tap 真实驱动',
      (WidgetTester tester) async {
    await bootLogin(tester);

    // --- /snapshot ---
    final snap = (await tester.runAsync(() => _curlGet('/snapshot')))!;
    expect(snap.code, 200, reason: snap.body);
    expect(snap.body, contains('textfield'));
    expect(snap.body, contains('登录'));
    final String? phoneRef = _refFor(snap.body, '手机号');
    final String? loginRef = _refFor(snap.body, '登录');
    expect(phoneRef, isNotNull, reason: 'snapshot:\n${snap.body}');
    expect(loginRef, isNotNull, reason: 'snapshot:\n${snap.body}');

    // --- /type 写手机号,响应应含 snapshot 字段(自动回吐)---
    final typed = (await tester.runAsync(() => _curlPost('/type', <String, Object?>{
          'element': '手机号输入框',
          'ref': phoneRef,
          'text': '13800000000',
        })))!;
    await tester.pumpAndSettle();
    expect(typed.code, 200, reason: typed.body);
    expect((jsonDecode(typed.body) as Map<String, Object?>).containsKey('snapshot'),
        isTrue, reason: '动作响应应自动回吐 snapshot');
    expect(find.text('13800000000'), findsOneWidget);

    // --- /tap 登录(本 demo 登录按钮 pop 回上一页)---
    final tapped = (await tester.runAsync(() => _curlPost('/tap', <String, Object?>{
          'element': '登录按钮',
          'ref': loginRef,
        })))!;
    await tester.pumpAndSettle();
    expect(tapped.code, 200, reason: tapped.body);
  });
}
```

- [ ] **Step 2: Run 测试**

Run: `cd packages/example && flutter test test/e2e_interaction_test.dart`
Expected: `All tests passed!`

> 若失败在 `find.text('13800000000')`:即 spec 风险 #1,`setText` 在该控件上未生效 —— 回到 Task 4/5 评估 `adb input text` 退路。

- [ ] **Step 3: Stage**

```bash
git add packages/example/test/e2e_interaction_test.dart
```
**不要 commit。**

---

### Task 20: 版本 0.6.0 → 0.7.0

**Files:**
- Modify: `packages/flutter_wright_sdk/pubspec.yaml:3`
- Modify: `packages/flutter_wright_sdk/lib/src/flutter_wright.dart`(`version` 常量)
- Modify: `packages/flutter_wright_sdk/CHANGELOG.md`

- [ ] **Step 1: bump pubspec 版本**

`pubspec.yaml` 把 `version: 0.6.0` 改为:

```yaml
version: 0.7.0
```

- [ ] **Step 2: bump 代码版本常量**

`flutter_wright.dart` 把 `static const String version = '0.6.0';` 改为:

```dart
  static const String version = '0.7.0';
```

- [ ] **Step 3: CHANGELOG 加条目(置于文件最上方 `# 更新日志` 标题之后)**

```markdown
## 0.7.0 - 2026-05-27

### 新增
- **snapshot-first 交互层**(对齐 Playwright MCP):
  - `GET /snapshot` —— 序列化 Semantics 树为带 `ref` 的 YAML(`ref=s<SemanticsNode.id>`,临时)。
  - `POST /tap` `/long_press` `/scroll` `/type` —— 经 `SemanticsOwner.performAction` 驱动;
    请求体带 `element`(描述)+ `ref`(定位);成功响应**自动回吐**最新 `snapshot`。
  - `GET /wait_for?text=|ref=|gone=&timeout=` —— 轮询语义树直到条件满足(408 超时)。
  - `start()` 启动时 `ensureSemantics()` 常开语义树(仅 debug)。
- (skill 侧)`snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`(SDK)+ `pressKey`/`back`/`logs`(免 SDK)。

### 变更
- **navigatorKey 降级为可选**:`start()` 仅当传了 `navigatorKey` 或 `navigationAdapter`
  才注册 `/navigate` `/reset` `/routes`;否则这三个端点回 501「navigation not configured」。
  交互闭环(snapshot/tap/type/...)只需 `start()`,不再需要 navigatorKey。
- `/navigate` `/reset` 成功响应也附 `snapshot` 字段。
- 示例 `dev/main_dev.dart` 显式传 `navigatorKey: FlutterWright.navigatorKey`。
```

- [ ] **Step 4: Run 静态检查 + 全测**

Run: `cd packages/flutter_wright_sdk && flutter analyze && flutter test`
Expected: `No issues found!` 且 `All tests passed!`

- [ ] **Step 5: Stage**

```bash
git add packages/flutter_wright_sdk/pubspec.yaml \
        packages/flutter_wright_sdk/lib/src/flutter_wright.dart \
        packages/flutter_wright_sdk/CHANGELOG.md
```
**不要 commit。**

---

### Task 21: 改写 `SKILL.md`(方法面 + doctrine + 退出码 + 派发)

**Files:**
- Modify: `skills/flutter-wright/SKILL.md`

> 保持中文/skill 本味,**不照搬 Playwright 英文措辞**。先通读现文件再改。

- [ ] **Step 1: frontmatter `description` 更新方法数与能力**

把 `description` 里「Skill 提供 9 个方法（run/stop/health/goto/screenshot/reload/setViewport/resetViewport/reset）」改为列出 18 个方法,并补一句「snapshot-first 交互:snapshot 拿 ref 再 tap/type」。

- [ ] **Step 2: 新增「snapshot-first 工作法」一节(放在「方法」表之前)**

```markdown
## 工作法(snapshot-first)

像 Playwright 一样:**先 `snapshot` 拿 `ref`,再用 `ref` 去 `tap`/`type`/`scroll`。**

- `snapshot` 返回带 `[ref=sN]` 的语义树;`ref` **临时** —— 页面一变(导航、reload、动作)就重新 `snapshot`,旧 `ref` 会失效(回 51)。
- `tap`/`type`/`scroll`/`longPress` 成功后**自动回吐**最新 snapshot,通常无需手动再 `snapshot`。
- `screenshot` 只用于**看效果**(给人看 / 视觉对比),**不用于定位元素** —— 定位一律靠 `snapshot`。
- 方法按用途分三类:**observe**(`snapshot`/`screenshot`/`logs`)、**act**(`tap`/`type`/`scroll`/`longPress`/`pressKey`/`back`)、**navigate**(`goto`/`reset`)。
```

- [ ] **Step 3: 方法表追加 9 行**

在现有方法表后追加:

```markdown
| `snapshot [out=<path>]` | 语义树快照(带 ref 的 YAML) | `snapshot.sh` |
| `tap "<element>" ref=<ref>` | 点击 ref 指向的节点 | `tap.sh` |
| `type "<element>" ref=<ref> text=<text> [submit=<bool>]` | 往输入框写文本 | `type.sh` |
| `scroll "<element>" ref=<ref> dir=<up\|down\|left\|right>` | 滚动可滚动节点 | `scroll.sh` |
| `longPress "<element>" ref=<ref>` | 长按 | `long_press.sh` |
| `waitFor (text=<s>\|ref=<s>\|gone=<s>) [timeout=<ms>]` | 等待条件满足 | `wait_for.sh` |
| `pressKey <key>` | 发系统/IME 键(enter/back/...) | `press_key.sh` |
| `back` | 系统返回(pop 一层) | `back.sh` |
| `logs [since=<n>] [grep=<pat>]` | app 日志(经 run daemon) | `logs.sh` |
```

- [ ] **Step 4: 前提段补「按能力分」+ 派发约定补 element**

在「前提」段补:交互(snapshot/tap/type/scroll/longPress/waitFor)需 SDK(同 goto);`pressKey`/`back` 走 adb、`logs` 走 daemon,**免 SDK**。

在「派发约定」补一条:`element` 是**引号包裹的位置参数**(第一个位置参数),`ref`/`text`/`dir`/`submit` 等为 `key=value`;含 `"`/`\` 的值不支持(同 `goto` 的路由约束)。示例:

```markdown
- Skill 调用：`tap \"登录按钮\" ref=s12`
- Bash 执行：`bash scripts/tap.sh '登录按钮' ref=s12`
```

- [ ] **Step 5: 退出码总表追加**

```markdown
| 50-57 | 交互 | 50 缺 ref/element / 51 ref 过期 / 52 无对应 action / 53 缺 text / 54 不可输入 / 55 输入失败 / 56 scroll 参数 / 57 动作失败 |
| 80-81 | snapshot | 80 失败 / 81 写文件失败 |
| 84-85 | waitFor | 84 缺条件 / 85 超时 |
| 90-92 | 按键/日志 | 90 key 非法 / 91 keyevent 失败 / 92 logs 无 daemon |
```

并在「⚠️ 前提」段同时说明:goto/reset 现在**仅当宿主 `start()` 传了 navigatorKey/adapter** 才可用,否则回「导航未配置」。

- [ ] **Step 6: Stage**

```bash
git add skills/flutter-wright/SKILL.md
```
**不要 commit。**

---

### Task 22: 更新其余文档

**Files:**
- Modify: `docs/api-reference.md`
- Modify: `docs/architecture.md`
- Modify: `docs/integration-guide.md`
- Modify: `docs/integration-guide-for-ai.md`
- Modify: `docs/troubleshooting.md`
- Modify: `README.md`

- [ ] **Step 1: `api-reference.md`** —— 新增端点协议:`GET /snapshot`(text/plain YAML)、`POST /tap` `/long_press` `/scroll`(`{element,ref[,dir]}` → `{ok,snapshot}`)、`POST /type`(`{element,ref,text}`)、`GET /wait_for`(query `text|ref|gone&timeout` → 200+`{ok,snapshot}` / 408)。注明 `/navigate` `/reset` 响应新增 `snapshot` 字段;未配置导航时 `/navigate` `/reset` `/routes` 回 501。版本 0.7.0。

- [ ] **Step 2: `architecture.md`** —— 「故意不做(v1)」删掉「UI 交互(tap/swipe/text input)」「Widget tree 检视 / locator」两条;组件图补 `semantics_snapshot` / `semantics_action` 与 6 个交互 handler;补「navigatorKey 降级 / 集成分层」小节(零集成 / `start()` 解锁交互 / +navigatorKey 解锁 goto / +FlutterWrightRoot 渲染树截图)。

- [ ] **Step 3: `integration-guide.md` + `integration-guide-for-ai.md`** —— 把「集成 SDK 才解锁 goto」更新为「`start()` 解锁全套交互(snapshot/tap/type/...),navigatorKey/adapter 再额外解锁 goto/reset」;AI 版补一条决策:只要交互不要 goto → 只 `start()`,不接 navigatorKey。

- [ ] **Step 4: `troubleshooting.md`** —— 新增症状:① `snapshot` 为空(语义未开 / 页面无 Semantics:确认 app 已挂载、用标准控件);② `tap`/`type` 回 51(ref 过期 → 重新 snapshot);③ `type` 回 54(目标非输入框);④ `goto` 回 501(未传 navigatorKey/adapter)。

- [ ] **Step 5: `README.md`** —— 「是什么」补一句:像 Playwright 一样 snapshot 拿 ref 再 tap/type;能力清单从「跳页 + 截图 + 热重载」扩到「看语义树 + 操作」;SDK 角色:`start()` 解锁交互,navigatorKey 仅 goto。

- [ ] **Step 6: 全局健全性检查**

Run: `cd packages/flutter_wright_sdk && flutter analyze && flutter test` 然后 `cd packages/example && flutter test`
Expected: 两包 `No issues found!` 且全部测试 `All tests passed!`

- [ ] **Step 7: Stage**

```bash
git add docs/api-reference.md docs/architecture.md docs/integration-guide.md \
        docs/integration-guide-for-ai.md docs/troubleshooting.md README.md
```
**不要 commit。**

---

## 实施排序与说明

- **Phase 1→2→3 是硬依赖**(读路径 → 动作 → 导航重构),Phase 4(脚本)依赖对应端点已存在,Phase 5 收尾。
- **风险 #1(setText)** 在 Task 5 单元测试即暴露;若红,先定退路(`adb input text`)再继续 Task 7/14。
- **自动回吐 snapshot 的新鲜度**:handler 内同步序列化,反映「动作派发后即刻」的树;导航类动作可能略滞后(下一帧才重建)。需要确定性同步时用 `waitFor`。这是 v1 的已知取舍(写进 SKILL.md 工作法)。
- 全程**只 stage 不 commit**,由你审阅后自行 commit。
- 仓库其余 untracked(`docs/ACCEPTANCE-REPORT.md`、`packages/example/android/` 等)与本计划无关,勿 `git add -A`。
