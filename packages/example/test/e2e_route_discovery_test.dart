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
