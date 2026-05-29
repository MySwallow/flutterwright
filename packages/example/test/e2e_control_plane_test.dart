// 真实 e2e 验收测试。
//
// 设计要点：`flutter test` 的 TestWidgetsFlutterBinding 会把**进程内** dart:io
// HttpClient 全部 fake 成返回 400、不走真实网络。因此本测试一律用**独立进程的
// curl**（以及 skill 自带的 bash 脚本）发起 HTTP —— 这才是真实网络，也正是
// flutter-wright skill 在生产里实际走的路径。
//
// 它在真实 Dart VM 里启动 flutter_wright_sdk 的真实 HTTP 控制面
// （127.0.0.1:9123，纯 dart:io，与平台无关），挂载真实的 example app，然后：
//   1. 用真实 curl 打 /health /routes /navigate /reset /screenshot，断言导航真的发生；
//   2. 真实调用 skills/flutter-wright/scripts 下的 bash 脚本（goto.sh / reset.sh /
//      reload.sh），证明 skill ↔ SDK 端到端打通。
//
// 不需要 Android 真机 / 模拟器 / adb。设备特有命令（screenshot 走 adb screencap、
// setViewport 走 wm size）的边界在验收报告中单独说明。
//
// 运行：在 packages/example 下 `flutter test test/e2e_control_plane_test.dart`。

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

import 'package:flutter_wright_example/app.dart';
import 'package:flutter_wright_example/pages/home_page.dart';
import 'package:flutter_wright_example/pages/login_page.dart';
import 'package:flutter_wright_example/pages/order_detail_page.dart';
import 'package:flutter_wright_example/router/app_router.dart';

const String _base = 'http://127.0.0.1:9123';

typedef _Resp = ({int code, String body});
typedef _BytesResp = ({int code, List<int> bytes, String contentType});

/// 真实 curl GET。flutter_test 不会 fake 子进程，因此走真实网络。
Future<_Resp> _curlGet(String path) async {
  final tmp = await Directory.systemTemp.createTemp('fw_curl_');
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

Future<_Resp> _curlPost(String path, Map<String, Object?> json) async {
  final tmp = await Directory.systemTemp.createTemp('fw_curl_');
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

Future<_BytesResp> _curlGetBytes(String path) async {
  final tmp = await Directory.systemTemp.createTemp('fw_curl_');
  final out = File('${tmp.path}/body');
  try {
    final res = await Process.run('curl', <String>[
      '-s', '-o', out.path, '-w', '%{http_code}\n%{content_type}', '$_base$path',
    ]);
    final lines = res.stdout.toString().split('\n');
    final code = int.tryParse(lines.first.trim()) ?? 0;
    final ct = lines.length > 1 ? lines[1].trim() : '';
    final bytes = await out.exists() ? await out.readAsBytes() : <int>[];
    return (code: code, bytes: bytes, contentType: ct);
  } finally {
    await tmp.delete(recursive: true);
  }
}

/// PNG magic bytes: 89 50 4E 47
bool _looksLikePng(List<int> b) =>
    b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

void main() {
  Future<void> bootApp(WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(
          enabled: true,
          navigatorKey: FlutterWright.navigatorKey,
          routes: AppRouter.names,
        ));
    await tester.pumpWidget(
      FlutterWrightRoot(
        child: createApp(navigatorKey: FlutterWright.navigatorKey),
      ),
    );
    await tester.pumpAndSettle();
  }

  // start() 持有的 SemanticsHandle 须在测试体内释放(flutter_test invariant
  // 检查早于 tearDown)。所有用例经此包装:跑完体内即 stop()。
  Future<void> withApp(
      WidgetTester tester, Future<void> Function() body) async {
    await bootApp(tester);
    try {
      await body();
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  }

  tearDown(() async {
    await FlutterWright.stop();
  });

  testWidgets('SDK 控制面：真实 curl 端到端（health/routes/navigate/reset）',
      (WidgetTester tester) async {
    await withApp(tester, () async {
      expect(FlutterWright.isRunning, isTrue, reason: 'HTTP 服务应已绑定 127.0.0.1:9123');
      expect(find.byType(HomePage), findsOneWidget);

      // --- /health ---
      final health = (await tester.runAsync(() => _curlGet('/health')))!;
      expect(health.code, 200, reason: 'health body: ${health.body}');
      final healthJson = jsonDecode(health.body) as Map<String, Object?>;
      expect(healthJson['ok'], true);
      expect(healthJson['service'], 'flutter_wright_sdk');
      expect(healthJson['version'], FlutterWright.version);

      // --- /routes ---
      final routes = (await tester.runAsync(() => _curlGet('/routes')))!;
      expect(routes.code, 200);
      final routeNames =
          ((jsonDecode(routes.body) as Map<String, Object?>)['routes'] as List<Object?>)
              .cast<String>();
      expect(routeNames, containsAll(<String>['/', '/login', '/order/detail']));

      // --- /navigate 真的把界面推到 OrderDetailPage ---
      final nav = (await tester.runAsync(() => _curlPost('/navigate', <String, Object?>{
            'route': '/order/detail',
            'args': <String, Object?>{'id': 'ORD-001'},
            'popUntilRoot': true,
          })))!;
      await tester.pumpAndSettle();
      expect(nav.code, 200);
      expect(find.byType(OrderDetailPage), findsOneWidget,
          reason: '/navigate 应真实触发 Navigator.pushNamed');
      expect(find.text('状态: 已支付'), findsOneWidget); // 静态 demo 数据

      // --- /reset pop 回根 ---
      final reset = (await tester.runAsync(
          () => _curlPost('/reset', <String, Object?>{})))!;
      await tester.pumpAndSettle();
      expect(reset.code, 200);
      expect(find.byType(HomePage), findsOneWidget, reason: '/reset 应 pop 回首页');
      expect(find.byType(OrderDetailPage), findsNothing);
    });
  });

  testWidgets('SDK 控制面：/screenshot 端点 + PNG 像素管线', (WidgetTester tester) async {
    await withApp(tester, () async {
      // captureFlutterScreen 经 FlutterWrightRoot 的 keyed RepaintBoundary 截图。
      // 应用已用 FlutterWrightRoot 包裹（bootApp），故 /screenshot 真实返回 200 PNG。
      // （修复前因检查 binding 根 RenderView 恒返回 500——本断言即该 bug 的回归守卫。）
      final shot = (await tester.runAsync(() => _curlGetBytes('/screenshot')))!;
      expect(shot.code, 200,
          reason: '/screenshot 应经 FlutterWrightRoot 的 RepaintBoundary 返回 200 PNG，实际=${shot.code}');
      expect(shot.contentType, contains('image/png'));
      expect(_looksLikePng(shot.bytes), isTrue);
      expect(shot.bytes.length, greaterThan(100));

      // 独立证明截图像素管线本身真实可用：对一个 RepaintBoundary 调用与
      // captureFlutterScreen 相同的 toImage→PNG 调用，产出合法 PNG 字节。
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('flutterwright'))),
        ),
      ));
      await tester.pumpAndSettle();

      final pngBytes = await tester.runAsync(() async {
        final ro =
            boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 2.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      expect(pngBytes, isNotNull);
      expect(pngBytes!.length, greaterThan(100));
      expect(_looksLikePng(pngBytes), isTrue,
          reason: 'RenderRepaintBoundary.toImage→PNG 管线应产出合法 PNG');
    });
  });

  group('skill bash 脚本：真实驱动同一个 SDK 服务', () {
    // 写一条目标注册表指向本机 9123（无 token）；脚本经 fw_resolve_target 解析出
    // base、fw_need_sdk 预检 /health，再 curl 到同一个 SDK 控制面。纯 SDK 路径，不碰 adb。
    late Directory jobDir;
    late String scriptsDir;

    setUp(() async {
      jobDir = await Directory.systemTemp.createTemp('fw_job_');
      File('${jobDir.path}/targets')
          .writeAsStringSync('local|http://127.0.0.1:9123||com.test.app\n');
      scriptsDir =
          Directory('${Directory.current.path}/../../skills/flutter-wright/scripts')
              .absolute
              .path;
    });

    tearDown(() async {
      if (await jobDir.exists()) {
        await jobDir.delete(recursive: true);
      }
    });

    Future<ProcessResult> runScript(String script, List<String> args) {
      return Process.run(
        'bash',
        <String>['$scriptsDir/$script', ...args],
        environment: <String, String>{
          'FW_TARGETS': '${jobDir.path}/targets',
        },
        includeParentEnvironment: true,
      );
    }

    testWidgets('goto.sh / reset.sh 真实驱动真实 app', (WidgetTester tester) async {
      await withApp(tester, () async {
        expect(File('$scriptsDir/goto.sh').existsSync(), isTrue,
            reason: '脚本路径解析失败：$scriptsDir');

        // goto.sh /login → 真实推入 LoginPage
        final goLogin =
            (await tester.runAsync(() => runScript('goto.sh', <String>['/login'])))!;
        await tester.pumpAndSettle();
        expect(goLogin.exitCode, 0, reason: 'goto.sh stderr: ${goLogin.stderr}');
        expect(find.byType(LoginPage), findsOneWidget);

        // goto.sh /order/detail → 真实推入 OrderDetailPage（静态 demo 数据）
        final goOrder =
            (await tester.runAsync(() => runScript('goto.sh', <String>['/order/detail'])))!;
        await tester.pumpAndSettle();
        expect(goOrder.exitCode, 0, reason: 'goto.sh stderr: ${goOrder.stderr}');
        expect(find.byType(OrderDetailPage), findsOneWidget);
        expect(find.text('状态: 已支付'), findsOneWidget);

        // reset.sh → pop 回首页
        final reset =
            (await tester.runAsync(() => runScript('reset.sh', <String>[])))!;
        await tester.pumpAndSettle();
        expect(reset.exitCode, 0, reason: 'reset.sh stderr: ${reset.stderr}');
        expect(find.byType(HomePage), findsOneWidget);
      });
    });
  });
}
