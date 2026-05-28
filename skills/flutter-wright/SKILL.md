---
name: flutter-wright
description: 远程驱动一个【已经运行在已连接 Android 设备/模拟器上的 Flutter app】——Playwright 风格的运行时控制器。ONLY use when 你要对一个【正在运行的 app】做:截图 / 锁视口(只需 adb),或 snapshot 语义树、tap·type·scroll·longPress、waitFor、程序化 goto/reset(需 app 集成 flutter_wright_sdk,服务地址经目标注册表配置)。【不要】为以下触发:编写或讨论 Flutter 代码、改 SDK 源码、设计架构、跑单元/widget 测试,或当前没有已连接设备 + 运行中的 app——这些都不属于本 skill。Snapshot-first:先 snapshot 拿 ref 再 tap/type,对齐 Playwright MCP。仅 Android。16 个方法:health/targets/snapshot/tap/type/scroll/longPress/waitFor/pressKey/back/logs/goto/reset/screenshot/setViewport/resetViewport。
---

# FlutterWright — Flutter on Android 的 Playwright

远程驱动一个**已运行在已连接 Android 设备(真机/模拟器)上的 Flutter app**:截图、视口锁定开箱即用;**snapshot-first 交互**(snapshot/tap/type/scroll/longPress/waitFor)与**程序化导航**(`goto`/`reset`)在 app 集成 `flutter_wright_sdk` 后解锁。仅 Android。

入口声明:**"Using flutter-wright to <method> <target>."**

## 前提(按方法,失败即以对应退出码退出)

没有「首次必过 `/health`」的全局闸门——每个方法只查自己需要的:

- **只需 adb**:`screenshot` / `setViewport` / `resetViewport` / `pressKey` / `back` / `logs`。要 `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。`logs` 默认 `adb logcat -s flutter`;设了 `FW_TARGETS` 时按注册表 `package` 精确过滤(注册表不可用则退 14/15)。
- **需 SDK**(app 集成 `flutter_wright_sdk`,服务地址经目标注册表):`snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor` / `goto` / `reset` / `health`。在上面基础上再要 `curl`(13)+ 目标注册表可解析(14/15)+ `GET <base>/health` 通(SDK 不可达 12)。`goto`/`reset` 还要宿主在 `FlutterWright.start()` 传了 `navigatorKey` 或 `navigationAdapter`,否则回 501(脚本退 41)。
- **目标管理 `targets`**:列举需 `curl`(13)+ 注册表可解析(14);`targets forward` 需 `adb`(10/11)+ 注册表(14/15)。

集成 SDK 是宿主 app 的一次性步骤(`FlutterWright.start()` 解锁交互;再传 navigatorKey 解锁 goto),不在本 skill 操作范围内。

## 典型用法 / 不要使用

适用:

- **交互闭环**(对齐 Playwright):你自己 `flutter run` 起集成 SDK 的 dev 入口 → `snapshot` 拿 ref → `tap`/`type`/`scroll` 派发 → 动作自动回吐新 snapshot。
- **人工导航 + AI 改码迭代**(最常见,**不需要 SDK**):你自己 `flutter run` → 人工点到目标页 → 改 Dart → 控制台按 `r` 热重载 → `screenshot`。
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
| 看有哪些目标 app / 哪个连得上 / 建端口转发 | `targets` / `targets forward target=<name>` | 列举需 curl,forward 需 adb |
| 看 app 运行日志 | `logs [since=] [grep=]` | 仅 adb |
| 按系统返回 / 回车等硬件键 | `back` / `pressKey <key>` | 仅 adb |
| 锁定 / 恢复设计分辨率 | `setViewport` / `resetViewport` | 仅 adb |

定位歧义(同一 label 多个节点、ref 失效)时:重新 `snapshot`,用最新 ref;`screenshot` 只看效果、不拿来定位。

## 目标(target)

SDK 方法(snapshot/tap/type/scroll/longPress/waitFor/goto/reset/health)不再硬编码 `127.0.0.1:9123`,而是经**目标注册表**解析出 `base`(本地可达地址)、可选 `token`、可选 `package`。注册表由集成方/operator 维护在 **git 外**(环境变量 `FW_TARGETS` 指向的文件),**token 绝不进仓库**。单条目即默认;多条目时用 `target=<name>` 选择,未选则报错提示。base 配错只是连不上(快速失败),不引入安全风险。

**注册表格式**:每行一条 `name|base|token|package|deviceport`,`#` 开头或空行忽略;`token`/`package`/`deviceport` 可留空(用 `|` 占位)。`deviceport` 留空时默认 = `base` 端口,仅在「同机多 app 各占不同本地端口、转发到各自设备端口」时才需显式填。

**注册一个目标 = 写一条 + 建可达性**(可达性不再每次自动建):① 在 `$FW_TARGETS` 写一行;② 需要时 `targets forward target=<name>` 跑一次 `adb forward tcp:<本地> tcp:<设备>`(emulator 直连 / 已有 forward / 隧道场景免此步)。`targets`(无参)列举所有条目并逐条探活(免 token 的 `/health`),用于发现「有哪些目标、哪个连得上」。

## 工作法(snapshot-first)

像 Playwright 一样:**先 `snapshot` 拿 `ref`,再用 `ref` 去操作。**

- `ref`(`sN`,N 为 `SemanticsNode.id`)**临时**:只有最近一次 `snapshot` 发出过的能用,页面一变(导航/热重载/动作)就重新 `snapshot`,旧 ref 失效(端点回 404、脚本退 51)。
- `tap`/`type`/`scroll`/`longPress` 成功后**自动回吐**最新 snapshot 到 stdout,通常无需手动再 `snapshot`。
- 调用形式 **element + ref 双参**:`tap "<element 描述>" ref=<ref>` —— `<element>` 仅作日志/可读性用,定位以 `ref` 为准。
- 导航类动作(`goto`/`reset`)界面若下一帧才重建,用 `waitFor` 做确定性同步。
- 路由**无需预先注册**:`goto` 直接把路由名交给宿主路由器,能否跳成功取决于它认不认。

## 方法

| 方法 | 用途 | 脚本 |
|---|---|---|
| `health` | 显式 SDK 探针(交互/导航相关) | `health.sh` |
| `targets [forward target=<name>]` | 列举注册表目标 + 逐条探活;`forward` 建立 adb 端口转发 | `targets.sh` |
| `snapshot [out=<path>]` | 取当前页语义树 YAML(带 ref) | `snapshot.sh` |
| `tap "<element>" ref=<ref>` | 在 ref 节点上派发 tap(响应回吐 snapshot) | `tap.sh` |
| `type "<element>" ref=<ref> text=<text> [submit=<bool>]` | 写入文本(submit 发 ENTER);响应回吐 snapshot | `type.sh` |
| `scroll "<element>" ref=<ref> dir=<up\|down\|left\|right>` | 在 ref 节点上派发滚动 | `scroll.sh` |
| `longPress "<element>" ref=<ref>` | 在 ref 节点上派发长按 | `long_press.sh` |
| `waitFor (text=<s>\|ref=<s>\|gone=<s>) [timeout=<ms>]` | 轮询条件,满足返回 200 + snapshot;超时 85 | `wait_for.sh` |
| `pressKey <enter\|back\|home\|tab\|del\|search\|menu>` | adb 系统/IME 键(免 SDK) | `press_key.sh` |
| `back` | 系统返回(adb keyevent 4,免 SDK) | `back.sh` |
| `logs [since=<n>] [grep=<pat>] [target=<name>]` | `adb logcat`(按注册表 package 或 `-s flutter`),免 SDK | `logs.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 程序化跳转到一个路由(需 SDK + navigatorKey/adapter) | `goto.sh` |
| `reset` | 把 navigator pop 到根(需 SDK + navigatorKey/adapter) | `reset.sh` |
| `screenshot <out_path>` | 设备整帧截图(含状态栏)输出 PNG | `screenshot.sh` |
| `setViewport <w> <h> <dpi>` | 锁定 `wm size` + `wm density` | `set_viewport.sh` |
| `resetViewport` | 恢复 `wm size` + `wm density` 默认值 | `reset_viewport.sh` |

**每个方法的完整签名、参数约束、示例与逐条退出码见 [`references/methods.md`](references/methods.md)。**

> **迁移**:`run` / `reload` / `stop` 已移除——本 skill 不再托管 flutter 进程。你自己 `flutter run`(集成 SDK 时跑 dev 入口),需热重载就在它的控制台按 `r`;`logs` 改用 `adb logcat`(按注册表 `package` 或 `-s flutter`),不再依赖 `run`。

## 派发约定

当以 `Skill flutter-wright "<method> <args...>"` 形式调用时:

1. 把第一个由空白分隔的 token 解析为**方法名**。
2. 把剩余 token 解析为位置参数(`element` / `route` / `out_path` / 宽高 dpi / key 名),随后是 `key=value` 对(`ref`/`text`/`dir`/`args`/`popUntilRoot`/`out`/`since`/`grep`/`timeout`/`submit`/`target`)。`<element>` 用引号位置参数(`tap "登录" ref=s12`)。`target=<name>` 是「目标注册表」条目名(选驱动哪个 app),作为 `key=value` 排在位置参数之后(写 `goto /route target=shop`)。
3. 调用对应脚本 `bash skills/flutter-wright/scripts/<script>.sh <args>`。**脚本文件名是方法名的 snake_case**——驼峰里每个大写字母转 `_<小写>`:`waitFor`→`wait_for.sh`、`longPress`→`long_press.sh`、`pressKey`→`press_key.sh`、`setViewport`→`set_viewport.sh`、`resetViewport`→`reset_viewport.sh`;其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`health`/`logs`/`back`/`screenshot`/`targets`)名一致。**以「方法」表脚本列为准。**

**含 `"` / `\` / 换行的值不支持** —— 交互方法的 element/ref/text 会被脚本侧拒绝。

`key=value` 中的 JSON 值必须把内部的 `"` 转义为 `\"`(穿过 shell + curl)。示例:

- Skill 调用:`goto /order/detail args={\"id\":\"X\"}`
- Bash 执行:`bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## 退出码对照

| 区间 | 类别 | 备注 |
|---|---|---|
| 0 | 成功 | — |
| 10-13 | 环境 / 设备 | 10 adb / 11 设备 / 12 SDK 不可达 / 13 curl |
| 14-17 | 目标 / 注册表 | 14 注册表缺失或空 / 15 目标歧义或未找到 / 16 adb forward 失败 / 17 targets 未知子命令 |
| 20-22 | 截图 | screenshot.sh |
| 40-43 | 导航 | goto.sh(需 SDK + navigatorKey/adapter,未配置 → 41/501) |
| 50-57 | 交互 | tap/long_press/scroll(50 缺参 / 51 ref 过期 / 52 节点无对应 action / 53-55 type / 56 scroll 参数 / 57 其它) |
| 60-61 | Viewport | set_viewport.sh |
| 70-71 | 重置 | reset.sh(需 SDK + navigatorKey/adapter) |
| 80-81 | snapshot | snapshot.sh |
| 84-85 | waitFor | wait_for.sh(85 超时) |
| 90-93 | 按键 / 日志 | press_key/back(90 未知 key / 91 失败)/ logs(92 参数错 / 93 指定 package 未运行;另用 adb 10/11、注册表 14/15) |
