import 'dart:convert';
import 'dart:io';

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

  // start() 持有的 SemanticsHandle 必须在测试体内释放(invariant 检查早于
  // tearDown),故每个用例 finally 里 stop();tearDown 再调一次幂等兜底。
  testWidgets('未传 navigatorKey/adapter:/navigate 回 501',
      (WidgetTester tester) async {
    await tester.runAsync(() => FlutterWright.start(enabled: true));
    try {
      expect((await tester.runAsync(postNavigate))!, 501);
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });

  testWidgets('传 navigatorKey:/navigate 已注册(非 501)',
      (WidgetTester tester) async {
    await tester.runAsync(
        () => FlutterWright.start(enabled: true, navigatorKey: FlutterWright.navigatorKey));
    try {
      expect((await tester.runAsync(postNavigate))!, isNot(501));
    } finally {
      await tester.runAsync(() => FlutterWright.stop());
    }
  });
}
