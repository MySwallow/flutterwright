// 验收:① 传 navigatorKey 但无 routes 时 GET /routes 返回空数组;② start(navigatorKey:)
// 用自定义 key 驱动 Navigator 1.0 导航。独立端口 9125,避免与其他 e2e 并发冲突。
//
// 注:0.7.0 起 navigatorKey/adapter 是导航(/routes /navigate /reset)的注册前提,
// 不再有「默认 adapter 兜底」;完全不传时这三个端点回 501,见
// flutter_wright_sdk/test/start_navigation_test.dart。

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
  // start() 持有的 SemanticsHandle 须在测试体内释放(flutter_test invariant
  // 检查早于 tearDown)。所有用例经此包装:跑完体内即 stop()。
  Future<void> withApp(
      WidgetTester tester, Future<void> Function() body) async {
    try {
      await body();
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  }

  tearDown(() async {
    await FlutterWright.stop();
  });

  testWidgets('传 navigatorKey 但无 routes 时 GET /routes 返回空数组',
      (WidgetTester tester) async {
    await withApp(tester, () async {
      await tester.runAsync(() => FlutterWright.start(
            config: const FlutterWrightConfig(port: _port),
            navigatorKey: FlutterWright.navigatorKey,
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
          reason: '传 navigatorKey 但没传 routes → discoverableRoutes 为 null → []');
    });
  });

  testWidgets('start(navigatorKey:) 用自定义 key 驱动导航',
      (WidgetTester tester) async {
    await withApp(tester, () async {
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
  });
}
