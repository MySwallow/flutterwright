# Visual Loop 演示 app

一个用来端到端验证 SDK + Skill 的简单 Flutter app。

## 启动

```bash
cd example
flutter create . --platforms=android,ios --org com.example.visualloop  # 第一次需要生成 android/ ios/
flutter pub get
flutter run -d <device-id>
```

启动后你应该看到:

```
[flutter_wright_sdk] registered route: /
[flutter_wright_sdk] registered route: /login
[flutter_wright_sdk] registered route: /product/detail
[flutter_wright_sdk] registered route: /order/detail
[flutter_wright_sdk] listening on http://127.0.0.1:9123
```

## 从电脑端控制

```bash
adb forward tcp:9123 tcp:9123

curl http://localhost:9123/health
# → {"ok":true,"version":"0.1.0","service":"flutter_wright_sdk"}

curl http://localhost:9123/routes
# → {"ok":true,"routes":["/","/login","/product/detail","/order/detail"]}

curl -X POST http://localhost:9123/navigate \
  -H 'content-type: application/json' \
  -d '{"route":"/order/detail","args":{"id":"ORD-001"}}'
# → {"ok":true,"route":"/order/detail"}
# 设备应该跳转到订单页

curl -X POST http://localhost:9123/mock \
  -H 'content-type: application/json' \
  -d '{"action":"set","key":"order","value":{"id":"ORD-007","amount":42.0,"status":"待发货","items":[]}}'
# 下次跳转到 /order/detail 会看到新的 mock 数据

curl -X POST http://localhost:9123/reset \
  -H 'content-type: application/json' \
  -d '{"clearMock":true}'
```

## 从 Claude Code 触发

```
/flutter-visual-loop example/design/order_detail.md /order/detail
```
