# flutter-wright 方法参考

每个方法的完整签名、行为、示例与逐条退出码。SKILL.md 的「方法」表是速查;需要细节(参数约束、退出码语义)时读这里。

## 目录

- 观察:[`health`](#health) · [`snapshot`](#snapshot) · [`screenshot`](#screenshot) · [`logs`](#logs)
- 交互:[`tap`](#tap) · [`type`](#type) · [`scroll`](#scroll) · [`longPress`](#longpress) · [`waitFor`](#waitfor) · [`pressKey`](#presskey) · [`back`](#back)
- 导航:[`goto`](#goto) · [`reset`](#reset)
- 环境:[`setViewport` / `resetViewport`](#setviewport--resetviewport)
- 目标:[`targets`](#targets)

---

### `health`

```
Skill flutter-wright "health [target=<name>]"
```

显式跑一遍 **SDK** 探针(交互/导航的前提):解析 target(`fw_resolve_target`)→ 探 `$base/health`(免 token),**不再依赖 adb**。

通常不需要手动调 —— 交互/导航首次调用时会自动跑同一套检查。需要显式调用的场景:手工 debug、SDK job 中途重启想重做检查。

退出码:0 成功 / 12 SDK 不可达 / 13 curl 缺失 / 14 无/非法目标注册表 / 15 目标歧义(多条目未指定 `target=`)。

输出:`ok: base=<base>`(若注册表条目带 package,追加 ` package=<pkg>`)。

### `targets`

```
Skill flutter-wright "targets"
Skill flutter-wright "targets forward target=<name>"
```

无参时**列举**目标注册表(`$FW_TARGETS`)所有条目,并对每条 `GET <base>/health`(免 token)**探活**,打印 `NAME / BASE / PACKAGE / HEALTH(ok|unreachable)`,用于发现「有哪些目标、哪个连得上」。列举需 `curl`;`forward` 子命令不需要 `curl`,但需要 `adb` + 设备。注册表行格式:`name|base|token|package|deviceport`(后三者可留空,用 `|` 占位)。

`forward target=<name>` 为指定目标建立可达性:`adb -s <device> forward tcp:<本地端口> tcp:<deviceport>`。本地端口 = `base` 里的端口部分;`deviceport` 取自注册表第 5 字段,**留空则默认同本地端口**(仅同机多 app 各占不同本地端口时才需显式填)。emulator 直连 / 已有 forward / 隧道场景不需要此步——可达性改为「注册 target 时一次性建立」,SDK 方法不再每次自动 `adb forward`。

示例:`Skill flutter-wright "targets forward target=shop-qa"`

退出码:0 / 10 adb 缺失 / 11 无设备 / 13 curl 缺失 / 14 注册表缺失或空 / 15 目标歧义或未找到 / 16 adb forward 失败 / 17 未知子命令。

### `snapshot`

```
Skill flutter-wright "snapshot [out=<path>] [target=<name>]"
```

`GET /snapshot`,返回当前页 Semantics 树的 Playwright 风格 YAML。每个可操作节点(有 tap/longPress/scroll/setText action 之一)末尾带 `[ref=sN]`,N 为 `SemanticsNode.id`。

**Ref 临时性**:只有这一次返回的 ref 才能在后续 `tap`/`type` 里用 —— 页面一变(导航/reload/动作)就重新 `snapshot`,旧 ref 在 SDK 侧标记失效(对应 HTTP 404、脚本退 51)。

`out=<path>` 可选,把 YAML 落盘到指定路径(也仍打到 stdout)。

示例:`Skill flutter-wright "snapshot"`

退出码:0 / 12 SDK 不可达 / 80 服务返回非 200。

### `tap`

```
Skill flutter-wright "tap \"<element>\" ref=<ref> [target=<name>]"
```

`POST /tap`,在 `ref` 解析到的 SemanticsNode 上派发 tap action。`<element>` 是给人/日志看的描述,**定位以 ref 为准**。成功响应回吐最新 snapshot。

示例:`Skill flutter-wright "tap \"登录\" ref=s12"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期(重 snapshot)/ 52 节点无 tap action / 57 其它非 200。

### `type`

```
Skill flutter-wright "type \"<element>\" ref=<ref> text=<text> [submit=<bool>] [target=<name>]"
```

`POST /type`,把 `text` 写入 ref 对应的输入框(经 `EditableTextState.userUpdateTextEditingValue`,Unicode/中文安全)。`submit=true` 时额外发 `adb keyevent 66`(ENTER)提交表单。成功响应回吐 snapshot。

`<element>`、`<ref>`、`<text>` **不支持** 包含 `"` / `\` / 换行(脚本侧会拒绝并退 53)。

示例:`Skill flutter-wright "type \"手机号\" ref=s8 text=13800000000 submit=true"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期 / 53 参数错(含非法字符)/ 54 节点不是输入框 / 55 其它非 200。

### `scroll`

```
Skill flutter-wright "scroll \"<element>\" ref=<ref> dir=<up|down|left|right> [target=<name>]"
```

`POST /scroll`,在 ref 对应的可滚动节点上派发指定方向滚动。成功响应回吐 snapshot(滚动后新出现的节点带新 ref)。

示例:`Skill flutter-wright "scroll \"订单列表\" ref=s4 dir=down"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期 / 52 节点无该方向滚动 / 56 参数错(dir/element 等)/ 57 其它非 200。

### `longPress`

```
Skill flutter-wright "longPress \"<element>\" ref=<ref> [target=<name>]"
```

`POST /long_press`,长按。成功响应回吐 snapshot。

示例:`Skill flutter-wright "longPress \"订单项\" ref=s7"`

退出码:0 / 12 SDK 不可达 / 50 缺 ref / 51 ref 过期 / 52 节点无 longPress / 57 其它非 200。

### `waitFor`

```
Skill flutter-wright "waitFor (text=<s>|ref=<s>|gone=<s>) [timeout=<ms>] [target=<name>]"
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
Skill flutter-wright "logs [since=<n>] [grep=<pat>] [target=<name>]"
```

`adb logcat -d` 读设备日志,**不托管 flutter 进程、不走 SDK**(进程由调用方自行 `flutter run`)。若目标注册表(`$FW_TARGETS`)可解析出 `package`,按 `adb shell pidof -s <package>` 取 pid 后 `logcat --pid` 精确过滤;否则回退 `logcat -d -s flutter`(多 app 会混)。`since=<n>` → `logcat -t <n>`(最后 N 行);`grep=<pat>` → ERE 管道过滤;`target=<name>` 选注册表条目(决定用哪个 app 的 package)。未设 `FW_TARGETS` 时直接走 `-s flutter`。

示例:`Skill flutter-wright "logs since=50 grep=ERROR"`

退出码:0 / 10 adb 缺失 / 11 无设备 / 14 已设 `FW_TARGETS` 但注册表缺失或空 / 15 目标歧义或未找到 / 92 参数错 / 93 指定 `package` 未在设备上运行。

### `goto`

```
Skill flutter-wright "goto <route> [args=<json>] [popUntilRoot=<bool>] [target=<name>]"
```

跳转到 `<route>`。`args` 是任意 JSON 值,作为路由参数传入。`popUntilRoot` 默认 `true`(先回到根)。

**路由无需预先注册**;能否跳成功取决于宿主路由器认不认。**需要宿主在 `FlutterWright.start()` 时传 `navigatorKey` 或 `navigationAdapter`**;0.7.0 起未配置时这端点回 501、脚本退 41。

示例:`Skill flutter-wright "goto /order/detail args={\"id\":\"ORD-001\"}"`

退出码:0 / 40 缺 route 或未知参数 / 41 navigator 未配置或未就绪(501/503)/ 42 跳转失败(500) / 43 SDK 不可达。

### `reset`

```
Skill flutter-wright "reset [target=<name>]"
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

### `setViewport` / `resetViewport`

```
Skill flutter-wright "setViewport <width> <height> <dpi>"
Skill flutter-wright "resetViewport"
```

`setViewport` 先把原始 `wm size`/`wm density` 记录到 `$CLAUDE_JOB_DIR/fw_original.env`,再应用覆盖并回读校验。`resetViewport` 从该文件恢复;**总是退出 0**,可安全用于 cleanup hook。

示例:`Skill flutter-wright "setViewport 1080 2400 480"`

退出码:setViewport 0 / 60 缺参 / 61 覆盖被拒(回读不一致);resetViewport 恒 0。
