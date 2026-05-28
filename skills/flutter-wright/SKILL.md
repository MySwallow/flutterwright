---
name: flutter-wright
description: 远程驱动一个【已经运行在已连接 Android 设备/模拟器上的 Flutter app】——Playwright 风格的运行时控制器。ONLY use when 你要对一个【正在运行的 app】做:截图 / 热重载 / 锁视口(只需 adb),或 snapshot 语义树、tap·type·scroll·longPress、waitFor、程序化 goto/reset(需 app 集成 flutter_wright_sdk,服务在 127.0.0.1:9123)。【不要】为以下触发:编写或讨论 Flutter 代码、改 SDK 源码、设计架构、跑单元/widget 测试,或当前没有已连接设备 + 运行中的 app——这些都不属于本 skill。Snapshot-first:先 snapshot 拿 ref 再 tap/type,对齐 Playwright MCP。仅 Android。18 个方法:run/stop/health/snapshot/tap/type/scroll/longPress/waitFor/pressKey/back/logs/goto/reset/screenshot/reload/setViewport/resetViewport。
---

# FlutterWright — Flutter on Android 的 Playwright

远程驱动一个**已运行在已连接 Android 设备(真机/模拟器)上的 Flutter app**:截图、热重载、视口锁定开箱即用;**snapshot-first 交互**(snapshot/tap/type/scroll/longPress/waitFor)与**程序化导航**(`goto`/`reset`)在 app 集成 `flutter_wright_sdk` 后解锁。仅 Android。

入口声明:**"Using flutter-wright to <method> <target>."**

## 前提(按方法,失败即以对应退出码退出)

没有「首次必过 `/health`」的全局闸门——每个方法只查自己需要的:

- **只需 adb**:`screenshot` / `setViewport` / `resetViewport` / `run` / `pressKey` / `back`。要 `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。
- **需 SDK**(app 集成 `flutter_wright_sdk`,服务在 `127.0.0.1:9123`):`snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor` / `goto` / `reset` / `health`。在上面基础上再要 `curl`(13)+ `adb forward tcp:9123` + `GET /health` 通(SDK 不可达 12)。本 job 首次通过后写 `$CLAUDE_JOB_DIR/fw_health_done`,后续走 fast-path。`goto`/`reset` 还要宿主在 `FlutterWright.start()` 传了 `navigatorKey` 或 `navigationAdapter`,否则回 501(脚本退 41)。
- **需先 `run`**:`reload` / `logs` 读本 skill 持有的 daemon,不查 adb/SDK(无 daemon 退 33/92)。

集成 SDK 是宿主 app 的一次性步骤(`FlutterWright.start()` 解锁交互;再传 navigatorKey 解锁 goto),不在本 skill 操作范围内。

## 典型用法 / 不要使用

适用:

- **交互闭环**(对齐 Playwright):`run` 起集成 SDK 的 dev 入口 → `snapshot` 拿 ref → `tap`/`type`/`scroll` 派发 → 动作自动回吐新 snapshot。
- **人工导航 + AI 改码迭代**(最常见,**不需要 SDK**):`run` → 人工点到目标页 → 改 Dart → `reload` → `screenshot`。
- **编排构件**:上层 skill 把这些方法当原子操作调用。

不要使用(这些都**不该触发**本 skill):

- **写或讨论 Flutter 代码、改 SDK 源码、设计架构** —— 普通编码/讨论,与「驱动一个运行中的 app」无关。
- **跑单元 / widget 测试** —— 那是 `flutter test`,不经本 skill。
- **没有已连接设备、或没有正在运行的 app** —— 没有可驱动的对象。
- **目标 app 没集成 SDK 而你需要 snapshot/tap/type/goto** —— 缺前提;只想看一眼用 `screenshot`(仅 adb)。
- **全程人工操作** —— `adb screencap` + 控制台按 `r` 更省事。

## 按意图选方法(自动路由)

被触发后,把用户的自然语言诉求映射到方法——**不需要用户报方法名**。snapshot-first:凡是要在元素上操作(tap/type/scroll/longPress),先 `snapshot` 拿 `ref`。

| 用户想做什么 | 走哪个方法 | 前提 |
|---|---|---|
| 看当前页有哪些可操作元素 | `snapshot` | SDK |
| 点 / 长按某个东西 | `snapshot` 拿 ref → `tap` / `longPress` | SDK |
| 在输入框里打字(可顺带提交) | `snapshot` → `type`(`submit=true` 发 ENTER) | SDK |
| 滚动列表 / 翻到底 | `snapshot` → `scroll dir=...` | SDK |
| 等某段文字或元素出现 / 消失 | `waitFor text=… \| ref=… \| gone=…` | SDK |
| 跳到某个路由页 / 回根 | `goto <route>` / `reset` | SDK + navigatorKey/adapter |
| 截图看效果(不用于定位) | `screenshot <out>` | 仅 adb |
| 起 app / 停 app | `run [target]` / `stop` | adb |
| 改了 Dart 代码要生效 | `reload` | 已 `run` |
| 看 app 运行日志 | `logs [since=] [grep=]` | 已 `run` |
| 按系统返回 / 回车等硬件键 | `back` / `pressKey <key>` | 仅 adb |
| 锁定 / 恢复设计分辨率 | `setViewport` / `resetViewport` | 仅 adb |

定位歧义(同一 label 多个节点、ref 失效)时:重新 `snapshot`,用最新 ref;`screenshot` 只看效果、不拿来定位。

## 工作法(snapshot-first)

像 Playwright 一样:**先 `snapshot` 拿 `ref`,再用 `ref` 去操作。**

- `ref`(`sN`,N 为 `SemanticsNode.id`)**临时**:只有最近一次 `snapshot` 发出过的能用,页面一变(导航/reload/动作)就重新 `snapshot`,旧 ref 失效(端点回 404、脚本退 51)。
- `tap`/`type`/`scroll`/`longPress` 成功后**自动回吐**最新 snapshot 到 stdout,通常无需手动再 `snapshot`。
- 调用形式 **element + ref 双参**:`tap "<element 描述>" ref=<ref>` —— `<element>` 仅作日志/可读性用,定位以 `ref` 为准。
- 导航类动作(`goto`/`reset`)界面若下一帧才重建,用 `waitFor` 做确定性同步。
- 路由**无需预先注册**:`goto` 直接把路由名交给宿主路由器,能否跳成功取决于它认不认。

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

**每个方法的完整签名、参数约束、示例与逐条退出码见 [`references/methods.md`](references/methods.md)。**

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
