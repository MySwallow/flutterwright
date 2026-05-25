// 通用性验收:证明 SDK 路由架构无关。
//
// 这个 app 故意**不用** Navigator 1.0 命名路由 —— 导航是一个 ValueNotifier<String>,
// 变了就重建 body。这正是 GoRouter / GetX 那种"调一个函数、widget 树重建"的声明式
// 模型。通过 CallbackNavigationAdapter 把 SDK 的 /navigate、/reset 接到这个 notifier
// 上,然后用**真实 curl** 打 /navigate,断言页面真的换了 —— 全程不碰 pushNamed。
//
// 用独立端口 9124,避免与 e2e_control_plane_test.dart(9123)并发冲突。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

const int _port = 9124;
const String _base = 'http://127.0.0.1:$_port';

Future<({int code, String body})> _curlPost(
    String path, Map<String, Object?> json) async {
  final tmp = await Directory.systemTemp.createTemp('fw_nav_');
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

/// 声明式路由 app:导航 = 改 [route] 的值,树重建。无 Navigator.pushNamed。
class _DeclarativeApp extends StatelessWidget {
  const _DeclarativeApp(this.route);

  final ValueListenable<String> route;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ValueListenableBuilder<String>(
        valueListenable: route,
        builder: (_, r, __) {
          switch (r) {
            case '/cart':
              return const Scaffold(body: Center(child: Text('CART PAGE')));
            case '/profile':
              return const Scaffold(body: Center(child: Text('PROFILE PAGE')));
            default:
              return const Scaffold(body: Center(child: Text('HOME PAGE')));
          }
        },
      ),
    );
  }
}

void main() {
  tearDown(() async {
    await FlutterWright.stop();
  });

  testWidgets('CallbackNavigationAdapter 驱动非 Navigator-1.0 路由(真实 curl 端到端)',
      (WidgetTester tester) async {
    final route = ValueNotifier<String>('/');
    String? lastReset;

    await tester.runAsync(() => FlutterWright.start(
          config: const FlutterWrightConfig(port: _port),
          navigationAdapter: CallbackNavigationAdapter(
            onNavigate: (r, args, _) => route.value = r,
            onReset: () {
              route.value = '/';
              lastReset = '/';
            },
          ),
          testRoutes: const <String>['/', '/cart', '/profile'],
        ));
    await tester.pumpWidget(_DeclarativeApp(route));
    await tester.pumpAndSettle();
    expect(FlutterWright.isRunning, isTrue);
    expect(find.text('HOME PAGE'), findsOneWidget);

    // 真实 curl POST /navigate → adapter 把 notifier 设成 /cart → 树重建
    final toCart =
        (await tester.runAsync(() => _curlPost('/navigate', <String, Object?>{
              'route': '/cart',
            })))!;
    await tester.pumpAndSettle();
    expect(toCart.code, 200, reason: 'body: ${toCart.body}');
    expect(find.text('CART PAGE'), findsOneWidget,
        reason: 'SDK 应经 CallbackNavigationAdapter 驱动声明式路由,而非 pushNamed');
    expect(find.text('HOME PAGE'), findsNothing);

    // 再跳 /profile
    await tester.runAsync(
        () => _curlPost('/navigate', <String, Object?>{'route': '/profile'}));
    await tester.pumpAndSettle();
    expect(find.text('PROFILE PAGE'), findsOneWidget);

    // /reset → onReset 闭包 → 回 home
    final reset =
        (await tester.runAsync(() => _curlPost('/reset', <String, Object?>{})))!;
    await tester.pumpAndSettle();
    expect(reset.code, 200);
    expect(lastReset, '/', reason: '/reset 应触发 adapter.onReset');
    expect(find.text('HOME PAGE'), findsOneWidget);
  });
}
