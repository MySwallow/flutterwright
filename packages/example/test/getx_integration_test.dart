// GetX 架构集成验收:证明 SDK 经 CallbackNavigationAdapter 真正驱动 GetX。
//
// 与 e2e_navigation_adapter_test.dart(手搓 ValueNotifier 声明式路由)不同,
// 这个用**真实 `get` 包**:GetMaterialApp + getPages + Get.toNamed / Get.until。
// 通过 CallbackNavigationAdapter 把 SDK 的 /navigate、/reset、/routes 接到 GetX 上,
// 再用**真实 curl** 打这些端点,断言 GetX 真的切页、args 透传、reset 回根。
//
// 用独立端口 9126,避免与其它 e2e 测试(9123/9124/9125)并发冲突。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';
import 'package:get/get.dart';

const int _port = 9126;
const String _base = 'http://127.0.0.1:$_port';

Future<({int code, String body})> _curlPost(
    String path, Map<String, Object?> json) async {
  final tmp = await Directory.systemTemp.createTemp('fw_getx_');
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

Future<({int code, String body})> _curlGet(String path) async {
  final tmp = await Directory.systemTemp.createTemp('fw_getxget_');
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

// GetX 命名路由表 —— routesProvider 的来源,也是真实导航的目标。
final List<GetPage<dynamic>> _pages = <GetPage<dynamic>>[
  GetPage<dynamic>(
      name: '/',
      page: () =>
          const Scaffold(body: Center(child: Text('GETX HOME')))),
  GetPage<dynamic>(
      name: '/cart',
      page: () =>
          const Scaffold(body: Center(child: Text('GETX CART')))),
  GetPage<dynamic>(
      name: '/profile',
      page: () =>
          const Scaffold(body: Center(child: Text('GETX PROFILE')))),
];

class _GetXApp extends StatelessWidget {
  const _GetXApp();

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      initialRoute: '/',
      getPages: _pages,
    );
  }
}

void main() {
  tearDown(() async {
    await FlutterWright.stop();
    Get.reset(); // 清掉 GetX 全局状态,避免测试间串扰
  });

  testWidgets(
      'GetX 架构集成验收:真实 GetMaterialApp + Get.toNamed 经 SDK 端到端',
      (WidgetTester tester) async {
    Object? lastArgs;

    await tester.runAsync(() => FlutterWright.start(
          config: const FlutterWrightConfig(port: _port),
          navigationAdapter: CallbackNavigationAdapter(
            onNavigate: (String route, Object? args, bool _) {
              lastArgs = args;
              Get.toNamed<dynamic>(route, arguments: args);
            },
            onReset: () => Get.until((Route<dynamic> r) => r.isFirst),
            readiness: () => Get.key.currentState != null,
            routesProvider: () => _pages.map((GetPage<dynamic> p) => p.name),
          ),
        ));
    await tester.pumpWidget(const _GetXApp());
    await tester.pumpAndSettle();

    expect(FlutterWright.isRunning, isTrue);
    expect(find.text('GETX HOME'), findsOneWidget);

    // GET /routes 应来自 getPages.map((p) => p.name)
    final routesResp = (await tester.runAsync(() => _curlGet('/routes')))!;
    expect(routesResp.code, 200);
    final discovered =
        ((jsonDecode(routesResp.body) as Map<String, Object?>)['routes']
                as List<Object?>)
            .cast<String>();
    expect(discovered, containsAll(<String>['/', '/cart', '/profile']),
        reason: 'GET /routes 应来自 GetX 的 getPages');

    // POST /navigate → Get.toNamed → GetX 真实切页 + args 透传
    final toCart =
        (await tester.runAsync(() => _curlPost('/navigate', <String, Object?>{
              'route': '/cart',
              'args': <String, Object?>{'id': 'X1'},
            })))!;
    await tester.pumpAndSettle();
    expect(toCart.code, 200, reason: 'body: ${toCart.body}');
    expect(find.text('GETX CART'), findsOneWidget,
        reason: 'SDK 应经 CallbackNavigationAdapter 调 Get.toNamed 切到 /cart');
    expect(find.text('GETX HOME'), findsNothing);
    expect(lastArgs, <String, Object?>{'id': 'X1'},
        reason: 'GetX arguments 应从 /navigate 的 args 透传');

    // 再跳 /profile,栈变为 [/ , /cart , /profile]
    await tester.runAsync(() =>
        _curlPost('/navigate', <String, Object?>{'route': '/profile'}));
    await tester.pumpAndSettle();
    expect(find.text('GETX PROFILE'), findsOneWidget);

    // /reset → Get.until(isFirst) → 回到 home
    final reset =
        (await tester.runAsync(() => _curlPost('/reset', <String, Object?>{})))!;
    await tester.pumpAndSettle();
    expect(reset.code, 200);
    expect(find.text('GETX HOME'), findsOneWidget,
        reason: '/reset 应触发 Get.until 回根');
    expect(find.text('GETX PROFILE'), findsNothing);
  });
}
