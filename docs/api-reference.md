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
{ "ok": true, "version": "0.7.0", "service": "flutter_wright_sdk" }
```

## GET /snapshot

返回当前语义树的 Playwright 风格 YAML 快照。每个可操作节点附带 `[ref=sN]` 标识符,后续交互端点(`/tap` `/type` 等)用此 ref 定位元素。`FlutterWright.start()` 已持有常开语义句柄(`ensureSemantics`),无需额外配置。

**Response 200**
```
Content-Type: text/plain; charset=utf-8
- generic [ref=s1]
  - button "确认" [ref=s2]
  - textfield "请输入姓名" [ref=s3]
  - text "Hello" [ref=s4]
```

> 若语义树为空(未调 `FlutterWright.start()` 或 release 构建),返回 `# (no semantics data available)`。

---

## POST /tap

点击指定元素。

**Request body**
```json
{ "element": "确认", "ref": "s2" }
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `element` | string | 元素描述(可读标签),用于日志 |
| `ref` | string | 来自 `/snapshot` 的 `sN` 标识符 |

**Response 200**
```json
{ "ok": true, "snapshot": "<最新快照 YAML>" }
```

**错误**
- `404` — ref 在最新快照里不存在(ref 已过期,需重新 `/snapshot` 获取最新 ref)
- `422` — 该节点没有对应的 tap action

---

## POST /long_press

长按指定元素。请求体与 `/tap` 相同(`{element, ref}`)。

**Response 200**
```json
{ "ok": true, "snapshot": "<最新快照 YAML>" }
```

**错误**
- `404` — ref 过期
- `422` — 该节点没有对应的 long press action

---

## POST /scroll

在指定元素上执行滚动。

**Request body**
```json
{ "element": "列表", "ref": "s5", "dir": "down" }
```

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `element` | string | — | 元素描述,用于日志 |
| `ref` | string | — | 来自 `/snapshot` 的 `sN` 标识符 |
| `dir` | string | `"down"` | 滚动方向:`up` / `down` / `left` / `right` |

**Response 200**
```json
{ "ok": true, "snapshot": "<最新快照 YAML>" }
```

**错误**
- `404` — ref 过期
- `422` — 该节点没有对应的 scroll action

---

## POST /type

向可编辑输入框写入文字。

**Request body**
```json
{ "element": "姓名输入框", "ref": "s3", "text": "张三" }
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `element` | string | 元素描述,用于日志 |
| `ref` | string | 来自 `/snapshot` 的 `sN` 标识符 |
| `text` | string | 要写入的文字 |

**Response 200**
```json
{ "ok": true, "snapshot": "<最新快照 YAML>" }
```

**错误**
- `404` — ref 过期
- `422` — 目标节点不是可编辑输入框(`not an editable text field`)

---

## GET /wait_for

等待语义树满足条件后返回。

**Query 参数**(三选一):

| 参数 | 说明 |
|---|---|
| `text=<str>` | 等待语义树中出现指定文本 |
| `ref=<sN>` | 等待指定 ref 节点出现 |
| `gone=<str>` | 等待指定文本**消失** |

**可选参数**:
- `timeout=<ms>` — 超时毫秒数,默认 5000

**Response 200** — 条件满足:
```json
{ "ok": true, "snapshot": "<最新快照 YAML>" }
```

**Response 408** — 超时未满足:
```json
{ "ok": false, "error": "timeout waiting for condition" }
```

---

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
{ "ok": true, "route": "/order/detail", "snapshot": "<最新快照 YAML>" }
```

> `snapshot` 字段为跳转后的最新语义快照,与 `GET /snapshot` 内容一致。

**错误**
- `400` — 缺少 `route`
- `501` — 未配置导航(见下方「未配置导航」)
- `503` — adapter 未就绪(`NavigatorKeyAdapter`:`navigatorKey.currentState` 为 null,app 还没挂载;`CallbackNavigationAdapter`:`readiness` 返回 false)
- `500` — 跳转抛了异常(路由未注册、args 类型转换失败等)

## POST /reset

把 navigator pop 到 root(经 `NavigationAdapter.reset()`)。无请求参数。

**Request body:** 无(或空 `{}`)。

**Response 200**
```json
{ "ok": true, "snapshot": "<最新快照 YAML>" }
```

> `snapshot` 字段为 reset 后的最新语义快照。

**错误**
- `501` — 未配置导航(见下方「未配置导航」)
- `500` — adapter 的 reset 抛了异常

## 未配置导航

`FlutterWright.start()` 在未传 `navigatorKey` 或 `navigationAdapter` 时,不注册 `/navigate`、`/reset`、`/routes` 端点。调用这三个端点将返回:

**Response 501**
```json
{ "ok": false, "error": "navigation not configured — pass navigatorKey or navigationAdapter to FlutterWright.start()" }
```

> 若只需要 snapshot/tap/type/scroll/longPress/waitFor 等交互能力,只调 `FlutterWright.start()` 无需任何 navigatorKey 即可;需要 goto/reset 才传 navigatorKey 或 adapter。

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
| `navigationAdapter` | `NavigationAdapter?` | 可选自定义 adapter;传了则注册 `/navigate` `/reset` `/routes`;不传且也没有 `navigatorKey` 时这三个端点返回 501 |
| `navigatorKey` | `GlobalKey<NavigatorState>?` | 宿主已有自己的 navigatorKey 时传入,仅 Navigator 1.0 路径用;传了则注册导航端点 |
| `routes` | `Iterable<String>?` | 路由名列表,喂给 `GET /routes`;不传则由 adapter 的 `discoverableRoutes` 决定(可能为 `[]`) |
| `config` | `FlutterWrightConfig?` | host/port/enableInDebugOnly 等配置 |

> **交互闭环(snapshot/tap/type/scroll/longPress/waitFor)只需 `FlutterWright.start()`,无需 navigatorKey。** `start()` 自动持有常开语义句柄(`ensureSemantics`),`stop()` 时释放。

## curl 实用集合

```bash
# 1. 健康检查
curl -sf http://localhost:9123/health

# 2. 获取语义树快照(snapshot-first 交互起点)
curl -sf http://localhost:9123/snapshot

# 3. 点击元素(ref 来自 /snapshot 返回的 [ref=sN])
curl -sf -X POST http://localhost:9123/tap \
  -H 'content-type: application/json' \
  -d '{"element":"确认按钮","ref":"s2"}'

# 4. 向输入框写入文字
curl -sf -X POST http://localhost:9123/type \
  -H 'content-type: application/json' \
  -d '{"element":"姓名输入框","ref":"s3","text":"张三"}'

# 5. 滚动
curl -sf -X POST http://localhost:9123/scroll \
  -H 'content-type: application/json' \
  -d '{"element":"列表","ref":"s5","dir":"down"}'

# 6. 等待某文字出现(最多 5s)
curl -sf "http://localhost:9123/wait_for?text=加载完成&timeout=5000"

# 7. 列已注册路由
curl -sf http://localhost:9123/routes

# 8. 带参数跳转(需 navigatorKey 或 adapter)
curl -sf -X POST http://localhost:9123/navigate \
  -H 'content-type: application/json' \
  -d '{"route":"/order/detail","args":{"id":"ORD-001"}}'

# 9. 重置(pop 回根,需 navigatorKey 或 adapter)
curl -sf -X POST http://localhost:9123/reset \
  -H 'content-type: application/json' -d '{}'

# 10. 通过 SDK 截图(仅 Flutter 渲染树)
curl -sf http://localhost:9123/screenshot -o cur.png

# 11. 通过 adb 截图(完整设备,做视觉对齐时推荐)
adb exec-out screencap -p > cur.png
```
