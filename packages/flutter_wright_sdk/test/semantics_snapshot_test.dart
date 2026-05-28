import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
            Semantics(header: true, child: const Text('登录')),
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
