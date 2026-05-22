import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

class DemoMockProvider extends InMemoryMockDataProvider {
  DemoMockProvider() {
    set('order', <String, Object?>{
      'id': 'ORD-001',
      'amount': 199.0,
      'status': '已支付',
      'items': <Map<String, Object?>>[
        <String, Object?>{'name': '示例商品 A', 'qty': 2, 'price': 49.0},
        <String, Object?>{'name': '示例商品 B', 'qty': 1, 'price': 101.0},
      ],
    });
    set('product', <String, Object?>{
      'id': 'P-100',
      'name': '示例产品',
      'price': 99.0,
      'desc': '这是一个用于视觉对齐演示的占位商品。',
    });
  }
}
