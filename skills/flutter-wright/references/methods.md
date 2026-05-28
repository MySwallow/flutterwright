# flutter-wright 方法参考

每个方法的完整签名、行为、示例与逐条退出码。SKILL.md 的「方法」表是速查;需要细节(参数约束、退出码语义)时读这里。

## 目录

- 进程:[`run`](#run) · [`stop`](#stop)
- 观察:[`health`](#health) · [`snapshot`](#snapshot) · [`screenshot`](#screenshot) · [`logs`](#logs)
- 交互:[`tap`](#tap) · [`type`](#type) · [`scroll`](#scroll) · [`longPress`](#longpress) · [`waitFor`](#waitfor) · [`pressKey`](#presskey) · [`back`](#back)
- 导航:[`goto`](#goto) · [`reset`](#reset)
- 环境/进程:[`reload`](#reload) · [`setViewport` / `resetViewport`](#setviewport--resetviewport)

---

### `run`

```
Skill flutter-wright "run [target] [device=<id>] [project=<dir>]"
```

后台启动 `flutter run --machine`(Flutter 官方 daemon 协议),持有进程供后续 `reload` 驱动。`target` 默认 `lib/main.dart`;要用 snapshot/tap/type/goto 时传集成了 SDK 的 dev 入口(如 `dev/main_dev.dart`)。`device` 默认第一台已连接设备;`project` 默认当前工作目录。状态存于 `$CLAUDE_JOB_DIR/fw_daemon.{in,log,env}`。

等到 app 首帧(`app.started`)才返回,超时 180s。

示例:`Skill flutter-wright "run dev/main_dev.dart"`

退出码:0 成功 / 10 adb 缺失 / 11 无设备 / 36 找不到 flutter(设 `FLUTTER_BIN`)/ 37 已在运行(先 `stop`)/ 38 app 未在 180s 内启动(看 `$CLAUDE_JOB_DIR/fw_daemon.log`)。

### `stop`

```
Skill flutter-wright "stop"
```

向 owned daemon 发 `app.stop`,再终止进程、清理状态文件。**总是退出 0**,可安全用于清理钩子。没有 owned daemon 时打印提示并退出 0。

### `health`

```
Skill flutter-wright "health"
```

显式跑一遍 **SDK** 探针(交互/导航的前提):`adb` + 至少一台设备 + `curl` + `adb forward tcp:9123`(幂等)+ `GET /health`,并**强制刷新**标记 `$CLAUDE_JOB_DIR/fw_health_done`。

通常不需要手动调 —— 交互/导航首次调用时会自动跑同一套检查。需要显式调用的场景:手工 debug、SDK job 中途重启想重做检查。

退出码:0 成功 / 10 adb 缺失 / 11 没有设备 / 12 SDK 不可达 / 13 curl 缺失。

输出:`ok: device=<id> port=9123`。

### `snapshot`

```
Skill flutter-wright "snapshot [out=<path>]"
```

`GET /snapshot`,返回当前页 Semantics 树的 Playwright 风格 YAML。每个可操作节点(有 tap/longPress/scroll/setText action 之一)末尾带 `[ref=sN]`,N 为 `SemanticsNode.id`。

**Ref 临时性**:只有这一次返回的 ref 才能在后续 `tap`/`type` 里用 —— 页面一变(导航/reload/动作)就重新 `snapshot`,旧 ref 在 SDK 侧标记失效(对应 HTTP 404、脚本退 51)。

`out=<path>` 可选,把 YAML 落盘到指定路径(也仍打到 stdout)。

示例:`Skill flutter-wright "snapshot"`

退出码:0 / 12 SDK 不可达 / 80 服务返回非 200。

### `tap`

```
Skill flutter-wright "tap \"<element>\" ref=<ref>"
```

`POST /tap`,在 `ref` 解析到的 SemanticsNode 上派发 tap action。`<element>` 是给人/日志看的描述,**定位以 ref 为准**。成功响应回吐最新 snapshot。

示例:`Skill flutter-wright "tap \"登录\" ref=s12"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期(重 snapshot)/ 52 节点无 tap action / 57 其它非 200。

### `type`

```
Skill flutter-wright "type \"<element>\" ref=<ref> text=<text> [submit=<bool>]"
```

`POST /type`,把 `text` 写入 ref 对应的输入框(经 `EditableTextState.userUpdateTextEditingValue`,Unicode/中文安全)。`submit=true` 时额外发 `adb keyevent 66`(ENTER)提交表单。成功响应回吐 snapshot。

`<element>`、`<ref>`、`<text>` **不支持** 包含 `"` / `\` / 换行(脚本侧会拒绝并退 53)。

示例:`Skill flutter-wright "type \"手机号\" ref=s8 text=13800000000 submit=true"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期 / 53 参数错(含非法字符)/ 54 节点不是输入框 / 55 其它非 200。

### `scroll`

```
Skill flutter-wright "scroll \"<element>\" ref=<ref> dir=<up|down|left|right>"
```

`POST /scroll`,在 ref 对应的可滚动节点上派发指定方向滚动。成功响应回吐 snapshot(滚动后新出现的节点带新 ref)。

示例:`Skill flutter-wright "scroll \"订单列表\" ref=s4 dir=down"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期 / 52 节点无该方向滚动 / 56 参数错(dir/element 等)/ 57 其它非 200。

### `longPress`

```
Skill flutter-wright "longPress \"<element>\" ref=<ref>"
```

`POST /long_press`,长按。成功响应回吐 snapshot。

示例:`Skill flutter-wright "longPress \"订单项\" ref=s7"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期 / 52 节点无 longPress / 57 其它非 200。

### `waitFor`

```
Skill flutter-wright "waitFor (text=<s>|ref=<s>|gone=<s>) [timeout=<ms>]"
```

`GET /wait_for`,SDK 端轮询条件(默认 5000ms),满足返回 200 + snapshot;到期未满足回 408,脚本退 85。`text=` 匹配语义节点 label/value 的子串;`ref=` 等待该 ref 出现;`gone=` 等待某 text 消失。`text`/`ref`/`gone` 三选一。

示例:`Skill flutter-wright "waitFor text=订单详情 timeout=3000"`

退出码:0 / 12 SDK 不可达 / 84 参数错 / 85 超时或非 200。

### `pressKey`

```
Skill flutter-wright "pressKey <enter|back|home|tab|del|search|menu>"
```

`adb shell input keyevent <code>` 发硬件/IME 键。**不需要 SDK**。

示例:`Skill flutter-wright "pressKey enter"`

退出码:0 / 10 adb 缺失 / 11 无设备 / 90 未知 key / 91 adb keyevent 失败。

### `back`

```
Skill flutter-wright "back"
```

系统返回(`adb keyevent 4`)。**不需要 SDK**;`pressKey back` 的简写。

退出码:0 / 10/11/91 同 pressKey。

### `logs`

```
Skill flutter-wright "logs [since=<n>] [grep=<pat>]"
```

读本 skill `run` 持有的 daemon `app.log` 行(对应 `print`/`debugPrint`)。`since=<n>` 取最后 N 行;`grep=<pat>` 用 ERE 过滤。**不需要 SDK**;未 `run` 时退 92。

示例:`Skill flutter-wright "logs since=50 grep=ERROR"`

退出码:0 / 92 未 run(无 daemon log)或参数错。

### `goto`

```
Skill flutter-wright "goto <route> [args=<json>] [popUntilRoot=<bool>]"
```

跳转到 `<route>`。`args` 是任意 JSON 值,作为路由参数传入。`popUntilRoot` 默认 `true`(先回到根)。

**路由无需预先注册**;能否跳成功取决于宿主路由器认不认。**需要宿主在 `FlutterWright.start()` 时传 `navigatorKey` 或 `navigationAdapter`**;0.7.0 起未配置时这端点回 501、脚本退 41。

示例:`Skill flutter-wright "goto /order/detail args={\"id\":\"ORD-001\"}"`

退出码:0 / 40 缺 route 或未知参数 / 41 navigator 未配置或未就绪(501/503)/ 42 跳转失败(500) / 43 SDK 不可达。

### `reset`

```
Skill flutter-wright "reset"
```

`POST /reset`,把 navigator pop 回根。同 `goto` 一样需要 navigatorKey/adapter 已配置(未配置回 501)。

退出码:0 / 70 SDK 不可达或多余参数 / 71 `/reset` 返回非 200(含 501)。

### `screenshot`

```
Skill flutter-wright "screenshot <out_path>"
```

`adb exec-out screencap -p > <out>`,随后做 PNG magic-byte 检查。捕获**整帧设备画面,含状态栏**,且**与页面是怎么打开的无关**。若只想要 Flutter 渲染树(不含状态栏),直接调 SDK `GET /screenshot`(需宿主用 `FlutterWrightRoot` 包根)。

示例:`Skill flutter-wright "screenshot /tmp/order_detail.png"`

退出码:0 / 20 空文件 / 21 文件 < 1KB / 22 不是 PNG(设备锁屏?)。

### `reload`

```
Skill flutter-wright "reload"
```

向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart {fullRestart:false}`(热重载)。源文件改动由调用方在调用前完成。**前提是先 `run` 过** —— 没有 owned daemon 时退 33。

退出码:0 / 33 没有 owned daemon(先 `run`,或自己按 `r`)/ 34 daemon 已死 / 35 重载失败或超时。

### `setViewport` / `resetViewport`

```
Skill flutter-wright "setViewport <width> <height> <dpi>"
Skill flutter-wright "resetViewport"
```

`setViewport` 先把原始 `wm size`/`wm density` 记录到 `$CLAUDE_JOB_DIR/fw_original.env`,再应用覆盖并回读校验。`resetViewport` 从该文件恢复;**总是退出 0**,可安全用于 cleanup hook。

示例:`Skill flutter-wright "setViewport 1080 2400 480"`

退出码:setViewport 0 / 60 缺参 / 61 覆盖被拒(回读不一致);resetViewport 恒 0。
