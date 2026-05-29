# Visual Loop 演示 app

用来端到端验证 SDK + Skill 的 Flutter app。

## 结构(dev_dependencies 范式)

`flutter_wright_sdk` 在 `dev_dependencies` 里,`lib/` 对它**零引用**:

- `lib/main.dart` —— 生产入口,`runApp(createApp())`,无 SDK。
- `dev/main_dev.dart` —— **debug 入口**,唯一 import SDK:`FlutterWright.start()` + 注入 navigatorKey,复用 `lib/app.dart` 的 `createApp()` 工厂。

## 启动

```bash
cd example
flutter create . --platforms=android,ios --org com.example.visualloop  # 第一次需要生成 android/ ios/
flutter pub get
flutter run -d <device-id> -t dev/main_dev.dart   # ← 必须指向 dev 入口,否则 SDK 不启动
```

启动后你应该看到:

```
[flutter_wright_sdk] listening on http://127.0.0.1:9123
```

## 从电脑端控制

```bash
adb forward tcp:9123 tcp:9123

curl http://localhost:9123/health
# → {"ok":true,"service":"flutter_wright_sdk","version":"0.8.0","name":null,"package":null}

curl http://localhost:9123/routes
# → {"ok":true,"routes":["/","/login","/product/detail","/order/detail"]}

curl -X POST http://localhost:9123/navigate \
  -H 'content-type: application/json' \
  -d '{"route":"/order/detail","args":{"id":"ORD-001"}}'
# → {"ok":true,"route":"/order/detail"}
# 设备应该跳转到订单页

curl -X POST http://localhost:9123/reset \
  -H 'content-type: application/json' -d '{}'
# → {"ok":true}  navigator pop 回根
```

交互层(0.7.0 新增):先 GET /snapshot 拿到元素的 `ref`,再带 `element`+`ref` 派发动作:

```bash
curl http://localhost:9123/snapshot
# → YAML 纯文本(text/plain),仅可操作节点末尾带 [ref=sN],纯文本节点无 ref。如:
#     - button "登录" [ref=s12]

curl -X POST http://localhost:9123/tap \
  -H 'content-type: application/json' \
  -d '{"element":"登录按钮","ref":"s12"}'
# → {"ok":true, ...}  动作成功后自动回吐最新 snapshot
```

> 若启用了 token,除 `GET /health` 外所有请求都要带 `-H "X-FW-Token: <token>"`,否则 401。
> 完整端点清单(11 个)与方法说明见 `skills/flutter-wright/SKILL.md` 和 `skills/flutter-wright/references/methods.md`。

## 从 Claude Code 触发

```
/flutter-visual-loop example/design/order_detail.md /order/detail
```
