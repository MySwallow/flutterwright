# HTTP API 参考

`flutter_wright_sdk` 在 `127.0.0.1:9123`(可配置)上暴露一个小型的 JSON-over-HTTP API。Claude Code skill 用它,但任何能讲 HTTP 的客户端都能调。

## 通用约定

- **绑定地址**:默认 `127.0.0.1`。**不要**在共享网络里绑 `0.0.0.0` — mock 控制没有认证。
- **Content-Type**:带 body 的请求必须用 `application/json`。JSON 解析失败会被静默当作 `{}`。
- **响应信封**:
  - 成功:`{"ok": true, ...}` (各 endpoint 额外字段不同)
  - 失败:`{"ok": false, "error": "<原因>"}`,HTTP 4xx/5xx
- **Body 上限**:默认 1 MiB,通过 `FlutterWrightConfig.maxBodyBytes` 配置。超过返回 HTTP 413。

## GET /health

存活 + 版本检查。

**Response 200**
```json
{ "ok": true, "version": "0.1.0", "service": "flutter_wright_sdk" }
```

## GET /routes

列出宿主注册为"可被 visual loop 发现"的路由。

**Response 200**
```json
{ "ok": true, "routes": ["/", "/login", "/order/detail"] }
```

> 只有调用过 `FlutterWright.routes.register('/x')` 或在 `start()` 的 `testRoutes:` 参数里传过的路由才会出现在这里。

## POST /navigate

往 navigator push 一个命名路由。

**Request body**
```json
{
  "route": "/order/detail",
  "args": { "id": "ORD-001" },
  "popUntilRoot": true
}
```

| 字段           | 类型     | 默认值  | 说明                                          |
|----------------|----------|---------|-----------------------------------------------|
| `route`        | string   | —       | 必填。传给 `Navigator.pushNamed`。            |
| `args`         | 任意 JSON | `null`  | 作为 `arguments` 传给路由。                   |
| `popUntilRoot` | bool     | `true`  | push 前先 pop 到 root。防止循环之间状态污染。 |

**Response 200**
```json
{ "ok": true, "route": "/order/detail" }
```

**错误**
- `400` — 缺少 `route`
- `503` — `navigatorKey.currentState` 为 null(app 还没挂载)
- `500` — push 抛了异常(路由不在 `onGenerateRoute`、args 类型转换失败等)

## POST /reset

把 navigator pop 到 root。可选清空 mock 状态。

**Request body**
```json
{ "clearMock": true }
```

| 字段        | 类型 | 默认值  | 说明                              |
|-------------|------|---------|-----------------------------------|
| `clearMock` | bool | `false` | 为 true 时调用 `mockProvider.reset()` |

**Response 200**
```json
{ "ok": true, "clearedMock": true }
```

## POST /reload

触发 Flutter hot reload(经 VM service `reloadSources`)。Source 改动由调用方完成(Claude/上层 skill 编辑 Dart 文件之后调本端点)。

**Request body:** 无(或空 `{}`)。

**Response 200**
```json
{ "ok": true }
```

**错误**
- `503` — VM service 未在本进程开启(release/profile 构建);或 SDK < 0.2.0(端点尚不存在,会落到 404)
- `500` — `reloadSources` 失败(常见:语法错误、`main()` 改了需 hot restart)

实现:`ReloadHandler` 用 `dart:developer Service.getInfo()` 拿本进程 VM service URI,再用 `package:vm_service` 连回自己,对 main isolate 调 `reloadSources`。

## POST /mock

控制 mock 数据。5 种 action:

### action: enable
```json
{ "action": "enable", "enabled": true }
```
全局开关 mock 模式。Response: `{ "ok": true, "enabled": true }`。

### action: set
```json
{ "action": "set", "key": "user", "value": { "name": "Alice" } }
```
写入一个 key。Response: `{ "ok": true, "key": "user" }`。

### action: get
```json
{ "action": "get", "key": "user" }
```
读一个 key。Response: `{ "ok": true, "key": "user", "value": ... }`。

### action: reset
```json
{ "action": "reset" }
```
清空所有 key,还原初始的 enabled 标志。Response: `{ "ok": true, "reset": true }`。

### action: list
```json
{ "action": "list" }
```
查看当前状态。Response:
```json
{ "ok": true, "enabled": true, "keys": ["user", "order"] }
```

**错误**
- `501` — `FlutterWright.start()` 时没配 `MockDataProvider`
- `400` — `key`/`enabled`/`action` 缺失或类型错

## GET /screenshot

把 Flutter 渲染树截成 PNG。**不包含** OS chrome(状态栏、导航栏)。要截完整设备帧,用 `adb exec-out screencap`。

**Response 200**
```
Content-Type: image/png
<PNG 二进制字节>
```

**错误**
- `500` — 截图失败;宿主没用 `FlutterWrightRoot` 包根
- `501` — `screenshotMode = ScreenshotMode.external`(让你用 adb)

## 生命周期 API(纯 Dart 端,不走 HTTP)

```dart
FlutterWright.start({...});   // 绑 server
FlutterWright.bind();         // autoStart 是 false 时延后 bind
FlutterWright.stop();         // 关 server
FlutterWright.isRunning;      // bool
```

## curl 实用集合

```bash
# 1. 健康检查
curl -sf http://localhost:9123/health

# 2. 列已注册路由
curl -sf http://localhost:9123/routes

# 3. 带参数跳转
curl -sf -X POST http://localhost:9123/navigate \
  -H 'content-type: application/json' \
  -d '{"route":"/order/detail","args":{"id":"ORD-001"}}'

# 4. 设 mock 后再跳转
curl -sf -X POST http://localhost:9123/mock \
  -H 'content-type: application/json' \
  -d '{"action":"set","key":"order","value":{"id":"X","amount":1.0}}'

curl -sf -X POST http://localhost:9123/navigate \
  -H 'content-type: application/json' \
  -d '{"route":"/order/detail"}'

# 5. 重置
curl -sf -X POST http://localhost:9123/reset \
  -H 'content-type: application/json' \
  -d '{"clearMock":true}'

# 6. 通过 SDK 截图(仅 Flutter 渲染树)
curl -sf http://localhost:9123/screenshot -o cur.png

# 7. 通过 adb 截图(完整设备,做视觉对齐时推荐)
adb exec-out screencap -p > cur.png
```
