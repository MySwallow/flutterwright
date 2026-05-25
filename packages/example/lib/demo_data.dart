/// Static demo content for the example app. No `flutter_wright_sdk` reference —
/// the SDK only drives navigation/screenshot/etc., it does not feed data.
const Map<String, Object?> demoOrder = <String, Object?>{
  'id': 'ORD-001',
  'amount': 199.0,
  'status': '已支付',
  'items': <Map<String, Object?>>[
    <String, Object?>{'name': '示例商品 A', 'qty': 2, 'price': 49.0},
    <String, Object?>{'name': '示例商品 B', 'qty': 1, 'price': 101.0},
  ],
};

const Map<String, Object?> demoProduct = <String, Object?>{
  'id': 'P-100',
  'name': '示例产品',
  'price': 99.0,
  'desc': '这是一个用于视觉对齐演示的占位商品。',
};
