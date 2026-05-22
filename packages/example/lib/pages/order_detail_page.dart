import 'package:flutter/material.dart';

import '../mock/demo_mock_provider.dart';

class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({required this.args, required this.mock, super.key});

  final Map<String, Object?>? args;
  final DemoMockProvider mock;

  @override
  Widget build(BuildContext context) {
    final data = mock.enabled
        ? mock.get('order') as Map<String, Object?>?
        : <String, Object?>{
            'id': args?['id'],
            'status': '加载中…',
            'items': const <Object?>[],
          };
    final items = (data?['items'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<String, Object?>>();
    return Scaffold(
      appBar: AppBar(title: Text('订单 ${data?['id']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('状态: ${data?['status']}'),
          const SizedBox(height: 8),
          Text('金额: ¥ ${data?['amount']}'),
          const Divider(height: 32),
          for (final it in items)
            ListTile(
              title: Text('${it['name']}'),
              subtitle: Text('x${it['qty']}'),
              trailing: Text('¥ ${it['price']}'),
            ),
        ],
      ),
    );
  }
}
