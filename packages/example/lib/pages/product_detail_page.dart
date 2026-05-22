import 'package:flutter/material.dart';

import '../mock/demo_mock_provider.dart';

class ProductDetailPage extends StatelessWidget {
  const ProductDetailPage({required this.args, required this.mock, super.key});

  final Map<String, Object?>? args;
  final DemoMockProvider mock;

  @override
  Widget build(BuildContext context) {
    final data = mock.enabled
        ? mock.get('product') as Map<String, Object?>?
        : <String, Object?>{'name': '真实接口结果(未接)', 'price': 0.0};
    return Scaffold(
      appBar: AppBar(title: Text('${data?['name']}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 200,
              color: Colors.grey.shade300,
              alignment: Alignment.center,
              child: const Text('商品图片占位'),
            ),
            const SizedBox(height: 16),
            Text(
              '${data?['name']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('¥ ${data?['price']}'),
            const SizedBox(height: 16),
            Text('${data?['desc'] ?? ''}'),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.pushNamed(
                context,
                '/order/detail',
                arguments: <String, Object?>{'id': 'ORD-001'},
              ),
              child: const Text('立即下单'),
            ),
          ],
        ),
      ),
    );
  }
}
