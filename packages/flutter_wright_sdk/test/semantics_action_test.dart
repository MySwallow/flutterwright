import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/src/semantics_action.dart';

void main() {
  testWidgets('tap 触发 onPressed,无 tap action 节点返回 false',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    bool tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: <Widget>[
          ElevatedButton(onPressed: () => tapped = true, child: const Text('按我')),
          const Text('纯文本'),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(SemanticsActions.tap(tester.getSemantics(find.text('按我'))), isTrue);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(SemanticsActions.tap(tester.getSemantics(find.text('纯文本'))), isFalse);
    handle.dispose();
  });

  testWidgets('setText 写入输入框,非输入框返回 false',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: <Widget>[
          TextField(controller: controller),
          ElevatedButton(onPressed: () {}, child: const Text('btn')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        SemanticsActions.setText(
            tester.getSemantics(find.byType(TextField)), '北京'),
        isTrue);
    await tester.pumpAndSettle();
    expect(controller.text, '北京');
    expect(
        SemanticsActions.setText(tester.getSemantics(find.text('btn')), 'x'),
        isFalse);
    handle.dispose();
  });

  // 注:setText 的「物理↔逻辑像素归一(DPR)」回归无法在 flutter_test 单测复现 ——
  // 单测绑定的语义树是逻辑坐标(不随 view.devicePixelRatio 缩放),手动改 DPR 只会
  // 制造真机上不存在的不一致状态。该回归由 example 的双输入框(手机号/密码)e2e
  // `e2e_interaction_test.dart` 守卫(真实 app 语义树为物理坐标,DPR=3)。

  testWidgets('scroll 非法方向返回 false', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: <Widget>[
          for (int i = 0; i < 40; i++) ListTile(title: Text('item $i')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        SemanticsActions.scroll(
            tester.getSemantics(find.byType(Scrollable)), 'sideways'),
        isFalse);
    handle.dispose();
  });
}
