# HTTP API 参考

`flutter_wright_sdk` 在 `127.0.0.1:9123`(可配置)上暴露一个小型的 JSON-over-HTTP API。Claude Code skill 用它,但任何能讲 HTTP 的客户端都能调。

## 通用约定

- **绑定地址**:默认 `127.0.0.1`。**不要**在共享网络里绑 `0.0.0.0` — 控制面没有认证。
- **Content-Type**:带 body 的请求必须用 `application/json`。JSON 解析失败会被静默当作 `{}`。
- **响应信封**:
  - 成功:`{"ok": true, ...}` (各 endpoint 额外字段不同)
  - 失败:`{"ok": false, "error": "<原因>"}`,HTTP 4xx/5xx
- **Body 上限**:默认 1 MiB,通过 `FlutterWrightConfig.maxBodyBytes` 配置。超过返回 HTTP 413。

## GET /health

存活 + 版本检查。

**Response 200**
```json
{ "ok": true, "version": "0.6.0", "service": "flutter_wright_sdk" }
```

## GET /routes

列出当前 `NavigationAdapter.discoverableRoutes`。宿主通过 `start(routes: ...)` 或 `CallbackNavigationAdapter(routesProvider: ...)` 提供路由列表;未配置时返回空数组(不是错误)。

**Response 200**
```json
{ "ok": true, "routes": ["/", "/login", "/order/detail"] }
```

> `GET /routes` 返回什么取决于 adapter 的 `discoverableRoutes`。**`POST /navigate`(goto)从不查此列表**,能否跳成功只取决于 app 路由器认不认路由名。

## POST /navigate

跳转到一个路由。具体怎么跳由宿主配置的 `NavigationAdapter` 决定 —— 默认
`NavigatorKeyAdapter` 走 `Navigator.pushNamed`(命名路由);GoRouter / GetX 等
经 `CallbackNavigationAdapter` 走 `router.go` / `Get.toNamed`(见集成指南第 6 节)。

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
| `route`        | string   | —       | 必填。路由名 / URL,交给 adapter。            |
| `args`         | 任意 JSON | `null`  | 作为路由参数 / `extra` / `arguments` 传入。   |
| `popUntilRoot` | bool     | `true`  | 跳转前先回到 root。防止循环之间状态污染。     |

**Response 200**
```json
{ "ok": true, "route": "/order/detail" }
```

**错误**
- `400` — 缺少 `route`
- `503` — adapter 未就绪(`NavigatorKeyAdapter`:`navigatorKey.currentState` 为 null,app 还没挂载;`CallbackNavigationAdapter`:`readiness` 返回 false)
- `500` — 跳转抛了异常(路由未注册、args 类型转换失败等)

## POST /reset

把 navigator pop 到 root(经 `NavigationAdapter.reset()`)。无请求参数。

**Request body:** 无(或空 `{}`)。

**Response 200**
```json
{ "ok": true }
```

**错误**
- `500` — adapter 的 reset 抛了异常

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

`start()` 主要参数:

| 参数 | 类型 | 说明 |
|---|---|---|
| `navigationAdapter` | `NavigationAdapter?` | 可选自定义 adapter;不传时默认 `NavigatorKeyAdapter` |
| `navigatorKey` | `GlobalKey<NavigatorState>?` | 宿主已有自己的 navigatorKey 时传入,仅 Navigator 1.0 路径用 |
| `routes` | `Iterable<String>?` | 路由名列表,喂给 `GET /routes`;不传则由 adapter 的 `discoverableRoutes` 决定(可能为 `[]`) |
| `config` | `FlutterWrightConfig?` | host/port/enableInDebugOnly 等配置 |

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

# 4. 重置(pop 回根)
curl -sf -X POST http://localhost:9123/reset \
  -H 'content-type: application/json' -d '{}'

# 5. 通过 SDK 截图(仅 Flutter 渲染树)
curl -sf http://localhost:9123/screenshot -o cur.png

# 6. 通过 adb 截图(完整设备,做视觉对齐时推荐)
adb exec-out screencap -p > cur.png
```
