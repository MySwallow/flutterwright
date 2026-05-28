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

/// 启动控制平面(由 `start()` 强制常开语义树)并导航到登录页。
Future<void> bootLogin(WidgetTester tester) async {
  await tester.runAsync(() => FlutterWright.start(
        enabled: true,
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

/// 在登录页上跑 [body],结束时**在测试体内** `stop()`。
///
/// `start()` 持有的 [SemanticsHandle] 必须在测试体内释放:flutter_test 的
/// invariant 检查(_endOfTestVerifications)早于用户 `tearDown` 执行,若只在
/// tearDown 里 stop() 会被判为「SemanticsHandle 泄漏」。`stop()` 幂等,tearDown
/// 里再调一次是无害兜底。后续交互用例都应经此包装器。
Future<void> withLoginApp(
    WidgetTester tester, Future<void> Function() body) async {
  await bootLogin(tester);
  try {
    await body();
  } finally {
    await tester.runAsync(() => FlutterWright.stop());
  }
}

void main() {
  tearDown(() async {
    await FlutterWright.stop();
  });

  testWidgets('snapshot 列出登录页元素(textfield/button + ref)',
      (WidgetTester tester) async {
    await withLoginApp(tester, () async {
      final snap = (await tester.runAsync(() => _curlGet('/snapshot')))!;
      expect(snap.code, 200, reason: 'body: ${snap.body}');
      expect(snap.body, contains('textfield'));
      expect(snap.body, contains('登录'));
      expect(refFor(snap.body, '手机号'), isNotNull, reason: snap.body);
      expect(refFor(snap.body, '登录'), isNotNull, reason: snap.body);
    });
  });

  testWidgets('type 写手机号(响应含 snapshot)→ tap 登录',
      (WidgetTester tester) async {
    await withLoginApp(tester, () async {
      final snap = (await tester.runAsync(() => _curlGet('/snapshot')))!;
      final String? phoneRef = refFor(snap.body, '手机号');
      final String? loginRef = refFor(snap.body, '登录');
      expect(phoneRef, isNotNull);
      expect(loginRef, isNotNull);

      final typed = (await tester.runAsync(() => _curlPost('/type',
          <String, Object?>{
            'element': '手机号',
            'ref': phoneRef,
            'text': '13800000000'
          })))!;
      await tester.pumpAndSettle();
      expect(typed.code, 200, reason: typed.body);
      expect(
          (jsonDecode(typed.body) as Map<String, Object?>)
              .containsKey('snapshot'),
          isTrue,
          reason: '动作响应应自动回吐 snapshot');
      expect(find.text('13800000000'), findsOneWidget);

      final tapped = (await tester.runAsync(() => _curlPost(
          '/tap', <String, Object?>{'element': '登录', 'ref': loginRef})))!;
      await tester.pumpAndSettle();
      expect(tapped.code, 200, reason: tapped.body);
    });
  });

  testWidgets('wait_for:登录页已有「登录」文本 → 立即命中',
      (WidgetTester tester) async {
    await withLoginApp(tester, () async {
      final r = (await tester.runAsync(
          () => _curlGet('/wait_for?text=%E7%99%BB%E5%BD%95&timeout=2000')))!;
      expect(r.code, 200, reason: r.body); // %E7%99%BB%E5%BD%95 = 登录
    });
  });

  testWidgets('navigate 响应自动回吐 snapshot',
      (WidgetTester tester) async {
    await withLoginApp(tester, () async {
      final nav = (await tester.runAsync(() => _curlPost(
          '/navigate', <String, Object?>{'route': '/order/detail', 'args': <String, Object?>{'id': 'ORD-001'}, 'popUntilRoot': true})))!;
      await tester.pumpAndSettle();
      expect(nav.code, 200, reason: nav.body);
      expect(
          (jsonDecode(nav.body) as Map<String, Object?>)
              .containsKey('snapshot'),
          isTrue);
    });
  });

  group('验收:skill 脚本真实驱动 SDK', () {
    late Directory jobDir;
    late String scriptsDir;

    setUp(() async {
      // 写一条目标注册表,指向本机 9123(无 token);脚本经 fw_resolve_target 解析。
      jobDir = await Directory.systemTemp.createTemp('fw_job_');
      File('${jobDir.path}/targets')
          .writeAsStringSync('local|http://127.0.0.1:9123||com.test.app\n');
      scriptsDir = Directory(
              '${Directory.current.path}/../../skills/flutter-wright/scripts')
          .absolute
          .path;
    });

    tearDown(() async {
      if (await jobDir.exists()) await jobDir.delete(recursive: true);
    });

    Future<ProcessResult> runScript(String script, List<String> args) {
      return Process.run('bash', <String>['$scriptsDir/$script', ...args],
          environment: <String, String>{
            'FW_TARGETS': '${jobDir.path}/targets',
          },
          includeParentEnvironment: true);
    }

    testWidgets('snapshot.sh → type.sh → tap.sh 闭环',
        (WidgetTester tester) async {
      await withLoginApp(tester, () async {
        final ProcessResult snap = (await tester
            .runAsync(() => runScript('snapshot.sh', <String>[])))!;
        expect(snap.exitCode, 0, reason: 'snapshot.sh stderr: ${snap.stderr}');
        final String yaml = snap.stdout.toString();
        final String? phoneRef = refFor(yaml, '手机号');
        final String? loginRef = refFor(yaml, '登录');
        expect(phoneRef, isNotNull, reason: yaml);
        expect(loginRef, isNotNull, reason: yaml);

        final ProcessResult typed = (await tester.runAsync(() => runScript(
            'type.sh',
            <String>['手机号', 'ref=$phoneRef', 'text=13800000000'])))!;
        await tester.pumpAndSettle();
        expect(typed.exitCode, 0, reason: 'type.sh stderr: ${typed.stderr}');
        expect(find.text('13800000000'), findsOneWidget);

        final ProcessResult tapped = (await tester.runAsync(
            () => runScript('tap.sh', <String>['登录', 'ref=$loginRef'])))!;
        await tester.pumpAndSettle();
        expect(tapped.exitCode, 0, reason: 'tap.sh stderr: ${tapped.stderr}');
      });
    });
  });
}
