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
}
