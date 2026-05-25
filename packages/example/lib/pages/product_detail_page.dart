import 'package:flutter/material.dart';

import '../demo_data.dart';

class ProductDetailPage extends StatelessWidget {
  const ProductDetailPage({required this.args, super.key});

  final Map<String, Object?>? args;

  @override
  Widget build(BuildContext context) {
    const product = demoProduct;
    return Scaffold(
      appBar: AppBar(title: Text('${product['name']}')),
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
              '${product['name']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('¥ ${product['price']}'),
            const SizedBox(height: 16),
            Text('${product['desc'] ?? ''}'),
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
