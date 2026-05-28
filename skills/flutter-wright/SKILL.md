---
name: flutter-wright
description: Playwright 风格的 Flutter 应用驱动器，针对在 Android 设备/模拟器上运行、并集成了 flutter_wright_sdk SDK 的 Flutter app。Use when you need to programmatically navigate routes, snapshot the semantics tree, tap/type/scroll on elements, wait for conditions, screenshot, hot-reload, or lock viewport. Snapshot-first:先 `snapshot` 拿 `ref` 再 `tap`/`type`,对齐 Playwright MCP。Skill 提供 18 个方法(run/stop/health/snapshot/tap/type/scroll/longPress/waitFor/pressKey/back/logs/goto/screenshot/reload/setViewport/resetViewport/reset),是一个 Claude Code skill。
---

# FlutterWright — Flutter on Android 的 Playwright

给定一个运行在已连接 Android 设备(真机或模拟器)上的 Flutter app,本 skill 暴露一套 Playwright 风格的 API,让 Claude(或更上层的编排 skill)远程驱动它 —— 截图、热重载、视口锁定开箱即用;**snapshot-first 交互**(snapshot/tap/type/scroll/longPress/waitFor)与**程序化导航**(`goto`/`reset`)在 app 集成了 `flutter_wright_sdk` 后解锁。仅支持 Android —— iOS 不在范围内。

入口声明:**"Using flutter-wright to <method> <target>."**

> ## ⚠️ 前提:按能力分,SDK 是交互/导航前提
>
> 各方法依赖不同:
>
> - **截图 / setViewport / run / reload** —— 只需 `adb`(reload 还需本 skill `run` 持有的 daemon)。**不需要 SDK**。
> - **snapshot / tap / type / scroll / longPress / waitFor / goto / reset / health** —— 需要目标 app 集成了 `flutter_wright_sdk` 且 SDK 服务在 `127.0.0.1:9123` 可达。交互闭环只需 `FlutterWright.start()`;`goto`/`reset` 额外要求宿主传了 `navigatorKey` 或 `navigationAdapter`,否则这俩端点回「导航未配置」(退出码 41)。
> - **pressKey / back** —— 走 `adb shell input keyevent`,**不需要 SDK**。
> - **logs** —— 读本 skill `run` 持有的 daemon `app.log`,**不需要 SDK**。
>
> 集成 SDK 是宿主 app 的一次性步骤(`FlutterWright.start()` 即可解锁交互;再传 navigatorKey 解锁 goto),不在本 skill 操作范围内。

## 何时使用

这个 skill 把 Flutter app 的「运行 / 导航 / 交互 / 观察」交给 AI 远程驱动。18 个方法分四类:

- **进程**:`run`(AI 后台起 `flutter run`)、`stop`、`reload`、`logs`。持有进程后才能 `reload`/`logs`。
- **观察**(SDK):`snapshot`(语义树 YAML,带 ref)、`screenshot`(设备整帧 PNG)、`health`(SDK 探针)。
- **交互**(SDK,snapshot-first):`tap`/`type`/`scroll`/`longPress`(经 `ref` 在节点上派发)、`waitFor`(轮询条件)、`pressKey`/`back`(adb 系统键)。
- **导航**(SDK,需宿主传 navigatorKey/adapter):`goto`(程序化跳任意路由)、`reset`(回根)。
- **环境**:`setViewport`/`resetViewport`(adb 改分辨率)。

适用:

- **snapshot-first 交互闭环**(对齐 Playwright):AI `run` 起 app(集成 SDK 的 dev 入口)→ `snapshot` 拿可操作节点的 ref → `tap`/`type`/`scroll` 派发 → 动作响应自动回吐新 snapshot。
- **人工导航 + AI 改码迭代**(最常见):AI `run` 起 app → 人工点到目标页 → AI 改 Dart → `reload` → `screenshot`。**不需要集成 SDK**。
- **编排构件**:上层 skill 把这些方法当原子操作调用。

不要使用:目标 app 没集成 SDK 而你需要 snapshot/tap/type/goto;或全程人工 —— `adb screencap` + 控制台按 `r` 更省事。

## 工作法(snapshot-first)

像 Playwright 一样:**先 `snapshot` 拿 `ref`,再用 `ref` 去 `tap`/`type`/`scroll`/`longPress`。**

- `snapshot` 返回带 `[ref=sN]` 的语义树 YAML;`ref` **临时** —— 页面一变(导航/reload/动作)就重新 `snapshot`,旧 ref 失效(对应端点回 404、脚本退 51)。
- `tap`/`type`/`scroll`/`longPress` 成功后**自动回吐**最新 snapshot 到 stdout,通常无需手动再 `snapshot`。导航类动作(`goto`/`reset`)若界面下一帧才重建,用 `waitFor` 做确定性同步。
- 调用形式:**element + ref 双参**——`tap "<element 描述>" ref=<ref>`。`<element>` 仅作日志/可读性用,定位以 `ref` 为准。
- `screenshot` 只用于**看效果**,**不用于定位元素** —— 定位靠 `snapshot`。
- 方法分三类:**observe**(`snapshot`/`screenshot`/`logs`)、**act**(`tap`/`type`/`scroll`/`longPress`/`pressKey`/`back`)、**navigate**(`goto`/`reset`)。

## 环境前提(按方法)

不再有「首次调用必过 `/health`」的全局闸门。每个方法只检查自己需要的前提,失败时以对应退出码退出:

- `screenshot` / `setViewport` / `run` / `pressKey` / `back` → `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。
- `snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor` / `goto` / `reset` / `health` → 上述 + `curl`(13)+ `adb forward tcp:9123` + `GET /health`(SDK 不可达 12)。这些方法在本 job 首次通过后写 `$CLAUDE_JOB_DIR/fw_health_done`,后续走 fast-path。
- `reload` / `logs` → 不查 adb/SDK,只校验本 skill 已 `run` 且 daemon 存活(33/92)。

## 概念

- **Page** = 当前运行在已连接 Android 设备上的 Flutter app。
- **Snapshot** = SDK 把活的 Semantics(无障碍)树序列化成 Playwright 风格 YAML;每个可操作节点带 `[ref=sN]`。
- **Ref** = `sN`,`N` 为 `SemanticsNode.id`。**临时**:只有最近一次 `snapshot` 发出过的 ref 才能用,页面一变即失效。
- **Route** = 一个应用路由名(如 `/order/detail`)。**无需预先注册** —— `goto` 直接把路由名交给 app 的路由器,能否跳成功取决于路由器认不认。
- **Viewport** = 通过 `wm size` + `wm density` 覆盖,把设备锁定到设计分辨率。
- **Reload** = 向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart`(`fullRestart:false`),即热重载。不经 SDK。

## 方法

| 方法 | 用途 | 脚本 |
|---|---|---|
| `run [target] [device=<id>] [project=<dir>]` | 后台启 `flutter run --machine` 并持有(reload/logs 的前提) | `run.sh` |
| `stop` | 停止 owned daemon + 清理 | `stop.sh` |
| `health` | 显式 SDK 探针(交互/导航相关) | `health.sh` |
| `snapshot [out=<path>]` | 取当前页语义树 YAML(带 ref) | `snapshot.sh` |
| `tap "<element>" ref=<ref>` | 在 ref 节点上派发 tap(响应回吐 snapshot) | `tap.sh` |
| `type "<element>" ref=<ref> text=<text> [submit=<bool>]` | 写入文本(submit 发 ENTER);响应回吐 snapshot | `type.sh` |
| `scroll "<element>" ref=<ref> dir=<up\|down\|left\|right>` | 在 ref 节点上派发滚动 | `scroll.sh` |
| `longPress "<element>" ref=<ref>` | 在 ref 节点上派发长按 | `long_press.sh` |
| `waitFor (text=<s>\|ref=<s>\|gone=<s>) [timeout=<ms>]` | 轮询条件,满足返回 200 + snapshot;超时 85 | `wait_for.sh` |
| `pressKey <enter\|back\|home\|tab\|del\|search\|menu>` | adb 系统/IME 键(免 SDK) | `press_key.sh` |
| `back` | 系统返回(adb keyevent 4,免 SDK) | `back.sh` |
| `logs [since=<n>] [grep=<pat>]` | 读 owned daemon `app.log`(免 SDK) | `logs.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 程序化跳转到一个路由(需 SDK + navigatorKey/adapter) | `goto.sh` |
| `reset` | 把 navigator pop 到根(需 SDK + navigatorKey/adapter) | `reset.sh` |
| `screenshot <out_path>` | 设备整帧截图(含状态栏)输出 PNG | `screenshot.sh` |
| `reload` | 热重载 owned daemon(`app.restart`) | `reload.sh` |
| `setViewport <w> <h> <dpi>` | 锁定 `wm size` + `wm density` | `set_viewport.sh` |
| `resetViewport` | 恢复 `wm size` + `wm density` 默认值 | `reset_viewport.sh` |

## 方法参考

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

## 派发约定

当以 `Skill flutter-wright "<method> <args...>"` 形式调用时:

1. 把第一个由空白分隔的 token 解析为**方法名**。
2. 把剩余 token 解析为位置参数(`element` / `route` / `out_path` / `target` / 宽高 / key 名),随后是 `key=value` 对(`ref`/`text`/`dir`/`args`/`popUntilRoot`/`out`/`since`/`grep`/`timeout`/`submit`/`device`/`project`)。`<element>` 用引号位置参数(`tap "登录" ref=s12`)。
3. 调用 `bash skills/flutter-wright/scripts/<method>.sh <args>`。

**含 `"` / `\` / 换行的值不支持** —— 交互方法的 element/ref/text 会被脚本侧拒绝。

`key=value` 中的 JSON 值必须把内部的 `"` 转义为 `\"`(穿过 shell + curl)。示例:

- Skill 调用:`goto /order/detail args={\"id\":\"X\"}`
- Bash 执行:`bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## 退出码对照

| 区间 | 类别 | 备注 |
|---|---|---|
| 0 | 成功 | — |
| 10-13 | 环境 / 设备 | 10 adb / 11 设备 / 12 SDK 不可达 / 13 curl |
| 20-22 | 截图 | screenshot.sh |
| 33-36 | reload / run | 33 未 run / 34 daemon 已死 / 35 重载失败或超时 / 36 找不到 flutter |
| 37-38 | run | 37 已在运行 / 38 app 未启动 |
| 40-43 | 导航 | goto.sh(需 SDK + navigatorKey/adapter,未配置 → 41/501) |
| 50-57 | 交互 | tap/long_press/scroll(50 缺参 / 51 ref 过期 / 52 节点无对应 action / 53-55 type / 56 scroll 参数 / 57 其它) |
| 60-61 | Viewport | set_viewport.sh |
| 70-71 | 重置 | reset.sh(需 SDK + navigatorKey/adapter) |
| 80-81 | snapshot | snapshot.sh |
| 84-85 | waitFor | wait_for.sh(85 超时) |
| 90-92 | 按键 / 日志 | press_key/back(90/91)/ logs(92) |
