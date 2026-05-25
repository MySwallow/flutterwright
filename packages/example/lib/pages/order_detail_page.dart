import 'package:flutter/material.dart';

import '../demo_data.dart';

class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({required this.args, super.key});

  final Map<String, Object?>? args;

  @override
  Widget build(BuildContext context) {
    const order = demoOrder;
    final items = (order['items'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<String, Object?>>();
    return Scaffold(
      appBar: AppBar(title: Text('订单 ${order['id']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('状态: ${order['status']}'),
          const SizedBox(height: 8),
          Text('金额: ¥ ${order['amount']}'),
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
