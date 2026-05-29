---
name: flutter-wright
description: 远程驱动一个【已经运行在已连接 Android 设备/模拟器上的 Flutter app】——Playwright 风格的运行时控制器。ONLY use when 你要对一个【正在运行的 app】做:截图 / 锁视口(只需 adb),或 snapshot 语义树、tap·type·scroll·longPress、waitFor、程序化 goto/reset(需 app 集成 flutter_wright_sdk,服务地址经目标注册表 $FW_TARGETS 配置)。【不要】为以下触发:编写或讨论 Flutter 代码、改 SDK 源码、设计架构、跑单元/widget 测试,或当前没有已连接设备 + 运行中的 app——这些都不属于本 skill。Snapshot-first:先 snapshot 拿 ref 再 tap/type,对齐 Playwright MCP。仅 Android。
---

# FlutterWright — Flutter on Android 的 Playwright

远程驱动一个**已运行在已连接 Android 设备(真机/模拟器)上的 Flutter app**:截图、视口锁定开箱即用;**snapshot-first 交互**(snapshot/tap/type/scroll/longPress/waitFor)与**程序化导航**(`goto`/`reset`)在 app 集成 `flutter_wright_sdk` 后解锁。仅 Android。

入口声明:**"Using flutter-wright to <method> <target>."**

## 前提(按方法,失败即以对应退出码退出)

没有「首次必过 `/health`」的全局闸门——每个方法只查自己需要的。两类前提**彼此独立**:

- **只需 adb + 设备**(完全不碰 SDK):`screenshot` / `setViewport` / `resetViewport` / `pressKey` / `back` / `logs`。要 `adb` 在 PATH(退出码 10)+ 至少一台设备(11)。`logs` 默认 `adb logcat -s flutter`;设了 `FW_TARGETS` 时按注册表 `package` 精确过滤(注册表不可用则退 14/15)。
- **只需 SDK 可达**(**不需要 adb / 设备**):`snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor` / `goto` / `reset` / `health`。要 `curl`(13)+ 目标注册表可解析出 base(14 缺失 / 15 歧义)+ `GET <base>/health` 通(**SDK 不可达统一退 12**——每个 SDK 方法都先跑这道预检)。base 的可达性经 `targets forward` 一次性建立,之后调用纯走 HTTP(emulator 直连 / 隧道场景连 forward 都免)。
  - **例外**:`type submit=true` 要借 adb 发 ENTER,因此**额外**需要设备(无设备退 10/11)。
  - `goto`/`reset` 还要宿主在 `FlutterWright.start(enabled: true)` 时传了 `navigatorKey` 或 `navigationAdapter`,否则端点回 501:**`goto` 退 41,`reset` 退 71**(两者退出码体系不同,别混)。
- **目标管理 `targets`**:`targets`(列举 + 探活)需 `curl`(13)+ 注册表(14);`targets forward` 需 `adb`(10/11)+ 注册表(14/15);`targets add`(录入一条)只写本地文件,需 `FW_TARGETS` 指向可写路径(未设退 14,参数非法/重名退 18)。

集成 SDK 是宿主 app 的一次性步骤(`FlutterWright.start(enabled: true)` 解锁交互;再传 `navigatorKey`/`navigationAdapter` 解锁 goto/reset),不在本 skill 操作范围内。

## 典型用法 / 不要使用

适用:

- **交互闭环**(对齐 Playwright):你自己 `flutter run` 起集成 SDK 的 dev 入口 → `snapshot` 拿 ref → `tap`/`type`/`scroll` 派发 → 动作自动回吐新 snapshot。见下方「端到端示例」。
- **人工导航 + AI 改码迭代**(最常见,**不需要 SDK**):你自己 `flutter run` → 人工点到目标页 → 改 Dart → 控制台按 `r` 热重载 → `screenshot`。
- **编排构件**:上层 skill 把这些方法当原子操作调用。

不要使用(这些都**不该触发**本 skill):

- **写或讨论 Flutter 代码、改 SDK 源码、设计架构** —— 普通编码/讨论,与「驱动一个运行中的 app」无关。
- **跑单元 / widget 测试** —— 那是 `flutter test`,不经本 skill。
- **没有已连接设备、或没有正在运行的 app** —— 没有可驱动的对象。
- **目标 app 没集成 SDK 而你需要 snapshot/tap/type/goto** —— 缺前提;只想看一眼用 `screenshot`(仅 adb)。
- **全程人工操作** —— `adb screencap` + 控制台按 `r` 更省事。

## 目标(target):集成方必须维护 `$FW_TARGETS`

SDK 方法不硬编码地址,而是经**目标注册表**解析出 `base`(本地可达地址)、可选 `token`、可选 `package`。**注册表是 SDK 方法的硬前提——集成方/operator 必须在环境变量 `FW_TARGETS` 指向的文件里维护它**(该文件应在 **git 外**,`token` 绝不进仓库)。没有它,所有 SDK 方法退 14。

**注册表格式**:每行一条 `name|base|token|package|deviceport`,`#` 开头或空行忽略;`token`/`package`/`deviceport` 可留空(用 `|` 占位)。`base` 必须带端口。`deviceport` 留空时默认 = `base` 端口,仅在「同机多 app 各占不同本地端口、转发到各自设备端口」时才显式填。单条目即默认;多条目时 SDK 方法用 `target=<name>` 选择,未选则退 15。完整带注释的样例见 [`references/targets.example`](references/targets.example)。

一行示例(无 token):

```
shop-qa|http://127.0.0.1:9123||com.acme.shop|9123
```

**录入一个目标(skill 引导)**:用 `targets add` 写入——token 字段会**故意留空**,因为 token 是机密、绝不能经本会话传递:

```
Skill flutter-wright "targets add name=shop-qa base=http://127.0.0.1:9123 package=com.acme.shop"
```

若服务端开启了鉴权,**手动**编辑 `$FW_TARGETS`、在该行第 3 字段(两个 `|` 之间)补上 token。

**鉴权**:除 `/health` 与 `targets` 探活(免 token)外,所有 SDK 端点在注册表条目配了 `token` 时自动带 `X-FW-Token`。若服务端要求 token 而注册表缺/错,端点回 **401/403**,脚本归入该方法的「其它非 200」码(`tap` 57 / `type` 55 / `snapshot` 80 等)——拿到这些码先排查 token。

**建立可达性 = 写一条 + 按需 forward**:① `targets add`(或手写)一行;② 需要时 `targets forward target=<name>` 跑一次 `adb forward tcp:<本地> tcp:<设备>`(emulator 直连 / 已有 forward / 隧道场景免此步)。`targets`(无参)列举所有条目并逐条探活,用于发现「有哪些目标、哪个连得上」。

## 工作法(snapshot-first)

像 Playwright 一样:**先 `snapshot` 拿 `ref`,再用 `ref` 去操作。**

- `ref`(`sN`,N 为 `SemanticsNode.id`)**临时**:只有最近一次 `snapshot` 发出过的能用,页面一变(导航/热重载/动作)就重新 `snapshot`,旧 ref 失效(端点回 404、脚本退 51)。
- `tap`/`type`/`scroll`/`longPress` 成功后**自动回吐** snapshot 到 stdout——但**导航类动作(`goto`/`reset`,或会触发跳转的 `tap`)回吐的是重建前的旧帧**(界面下一帧才重建),别拿它当导航结果;导航后改用 `waitFor` 或重新 `snapshot` 确认(刚导航时单跑 `snapshot` 可能短暂返回旧帧甚至空语义)。非导航动作的回吐通常可直接用。
- 调用形式 **element + ref 双参**:`tap "<element 描述>" ref=<ref>` —— `<element>` 仅作日志/可读性,定位以 `ref` 为准。
- 导航类动作(`goto`/`reset`)界面若下一帧才重建,用 `waitFor` 做确定性同步,而不是猜延时。
- 路由**无需预先注册**:`goto` 直接把路由名交给宿主路由器,能否跳成功取决于它认不认。
- `screenshot` 只用来**看效果**,不拿来定位(定位永远靠 `snapshot` 的 ref);同一 label 多个节点 / ref 失效时,重新 `snapshot` 用最新 ref。
- **缺必填信息别硬来**:用户没给的关键值(账号/密码/搜索词等)先向用户确认,或显式用占位符并说明,**不要编造**;也**不要据弱信号断言成功**(如"离开了登录页"≠"登录成功"——可能只是 pop 返回)。

## 端到端示例(交互闭环)

```
# 0. 一次性:录入目标 + 建可达性(集成方维护 $FW_TARGETS)
Skill flutter-wright "targets add name=dev base=http://127.0.0.1:9123 package=com.acme.app"
Skill flutter-wright "targets forward target=dev"
Skill flutter-wright "targets"                       # 确认 dev 行 HEALTH=ok

# 1. 拿语义树,从中读出 ref(actionable 节点才带 [ref=sN])
Skill flutter-wright "snapshot"
#   - textfield "手机号" [ref=s8]
#   - button "登录" [ref=s12]

# 2. 在 ref 上操作(动作成功会自动回吐新 snapshot)
Skill flutter-wright "type \"手机号\" ref=s8 text=13800000000"
Skill flutter-wright "tap \"登录\" ref=s12"

# 3. 确定性同步,而不是猜延时
Skill flutter-wright "waitFor text=订单列表"
```

## 按意图选方法(自动路由)

被触发后,把用户的自然语言诉求映射到方法——**不需要用户报方法名**。snapshot-first:凡是要在元素上操作(tap/type/scroll/longPress),先 `snapshot` 拿 `ref`。

| 用户想做什么 | 走哪个方法 | 前提 |
|---|---|---|
| 看当前页有哪些可操作元素 | `snapshot` | SDK |
| 点 / 长按某个东西 | `snapshot` 拿 ref → `tap` / `longPress` | SDK |
| 在输入框里打字(可顺带提交) | `snapshot` → `type`(`submit=true` 发 ENTER,需 adb) | SDK(+adb) |
| 滚动列表 / 翻到底 | `snapshot` → `scroll dir=...` | SDK |
| 等某段文字或元素出现 / 消失 | `waitFor text=… \| ref=… \| gone=…` | SDK |
| 跳到某个路由页 / 回根 | `goto <route>` / `reset` | SDK + navigatorKey/adapter |
| 截图看效果(不用于定位) | `screenshot <out>` | 仅 adb |
| 看有哪些目标 app / 哪个连得上 / 建端口转发 | `targets` / `targets forward target=<name>` | 列举需 curl,forward 需 adb |
| 录入一个目标 app | `targets add name= base= [package=]`(token 留空,手动补) | 写本地文件 |
| 看 app 运行日志 | `logs [since=] [grep=]` | 仅 adb |
| 按系统返回 / 回车等硬件键 | `back` / `pressKey <key>` | 仅 adb |
| 锁定 / 恢复设计分辨率 | `setViewport` / `resetViewport` | 仅 adb |

## 方法

| 方法 | 用途 | 脚本 |
|---|---|---|
| `health` | 显式 SDK 探针(交互/导航相关) | `health.sh` |
| `targets [forward target=<name>] [add name= base= …]` | 列举注册表 + 探活;`forward` 建 adb 转发;`add` 录入一条(token 留空) | `targets.sh` |
| `snapshot [out=<path>]` | 取当前页语义树 YAML(actionable 节点带 ref) | `snapshot.sh` |
| `tap "<element>" ref=<ref>` | 在 ref 节点上派发 tap(响应回吐 snapshot) | `tap.sh` |
| `type "<element>" ref=<ref> text=<text> [submit=<bool>]` | 写入文本(submit 发 ENTER,需 adb);响应回吐 snapshot | `type.sh` |
| `scroll "<element>" ref=<ref> dir=<up\|down\|left\|right>` | 在 ref 节点上派发滚动 | `scroll.sh` |
| `longPress "<element>" ref=<ref>` | 在 ref 节点上派发长按 | `long_press.sh` |
| `waitFor (text=<s>\|ref=<s>\|gone=<s>) [timeout=<ms>]` | 轮询条件,满足返回 200 + snapshot;超时 85 | `wait_for.sh` |
| `pressKey <enter\|back\|home\|tab\|del\|search\|menu>` | adb 系统/IME 键(免 SDK) | `press_key.sh` |
| `back` | 系统返回(adb keyevent 4,免 SDK) | `back.sh` |
| `logs [since=<n>] [grep=<pat>] [target=<name>]` | `adb logcat`(按注册表 package 或 `-s flutter`),免 SDK | `logs.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 程序化跳转到一个路由(需 SDK + navigatorKey/adapter) | `goto.sh` |
| `reset` | 把 navigator pop 到根(需 SDK + navigatorKey/adapter) | `reset.sh` |
| `screenshot <out_path>` | 设备整帧截图(含状态栏)输出 PNG | `screenshot.sh` |
| `setViewport <w> <h> <dpi>` | 锁定 `wm size` + `wm density`(改了**务必**配对 resetViewport 复位) | `set_viewport.sh` |
| `resetViewport` | 恢复 `wm size` + `wm density` 默认值(恒退 0,可放 cleanup) | `reset_viewport.sh` |

**每个方法的完整签名、参数约束、示例与逐条退出码见 [`references/methods.md`](references/methods.md)。**

> **迁移**:`run` / `reload` / `stop` 已移除——本 skill 不再托管 flutter 进程。你自己 `flutter run`(集成 SDK 时跑 dev 入口),需热重载就在它的控制台按 `r`;`logs` 改用 `adb logcat`,不再依赖 `run`。

## 派发约定

当以 `Skill flutter-wright "<method> <args...>"` 形式调用时:

1. 第一个空白分隔 token = **方法名**;**位置参数必须紧跟其后**(`element` / `route` / `out_path` / 宽高 dpi / key 名),再之后才是 `key=value` 对。位置参数放错位会被当成 element——`tap ref=s8 "登录"` 会把 `ref=s8` 当成 element、`ref` 反而空,报 50。`<element>` 用引号包裹(`tap "登录" ref=s12`)。
2. `key=value` 键:`ref`/`text`/`dir`/`args`/`popUntilRoot`/`out`/`since`/`grep`/`timeout`/`submit`/`target`(以及 `targets add` 的 `name`/`base`/`package`/`deviceport`)。`target=<name>` 是目标注册表条目名(选驱动哪个 app),排在位置参数之后(`goto /route target=shop`)。
3. 调用 `bash skills/flutter-wright/scripts/<script>.sh <args>`。**脚本名 = 方法名的 snake_case**(驼峰里每个大写字母转 `_<小写>`:`waitFor`→`wait_for.sh`、`longPress`→`long_press.sh`);**以上面「方法」表的「脚本」列为准**。

**含 `"` / `\` / 换行的值不支持** —— 交互方法的 element/ref/text 会被脚本侧拒绝。`key=value` 中的 JSON 值必须把内部的 `"` 转义为 `\"`(穿过 shell + curl):

- Skill 调用:`goto /order/detail args={\"id\":\"X\"}`
- Bash 执行:`bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## 退出码对照

> **所有 SDK 方法**(snapshot/tap/type/scroll/longPress/waitFor/goto/reset/health)在各自的方法码之前,都可能先因**共享前提**退出:13(无 curl)/ 14(注册表缺失或空)/ 15(目标歧义)/ 12(SDK 不可达预检)。逐条细节见 `references/methods.md`。

| 区间 | 类别 | 备注 |
|---|---|---|
| 0 | 成功 | — |
| 10-13 | 环境 / 设备 | 10 adb 缺失 / 11 无设备 / 12 SDK 不可达(**SDK 方法统一预检码**)/ 13 curl 缺失 |
| 14-18 | 目标 / 注册表 | 14 注册表缺失或空 / 15 目标歧义或未找到 / 16 adb forward 失败 / 17 targets 未知子命令 / 18 targets add 参数非法或重名 |
| 20-22 | 截图 | screenshot.sh(20 空 / 21 <1KB / 22 非 PNG)|
| 40-43 | 导航 goto | goto.sh:40 缺 route/未知参数 / 41 navigator 未配置(501)或未就绪(503)/ 42 跳转失败(500)/ 43 非预期响应 |
| 50-57 | 交互 | tap/type/scroll/longPress:50 缺 ref / 51 ref 过期 / 52 节点无对应 action / 53-55 type(53 参数 / 54 非输入框 / 55 其它)/ 56 scroll 参数 / 57 其它非 200。**type submit=true 另可退 10/11**(借 adb 发 ENTER)|
| 60-61 | Viewport | set_viewport.sh(60 缺参 / 61 覆盖被拒);resetViewport 恒 0 |
| 70-71 | reset | reset.sh(需 navigatorKey/adapter;**501→71**,与 goto 的 41 不同)|
| 80-81 | snapshot | snapshot.sh(80 非 200)|
| 84-85 | waitFor | wait_for.sh(85 超时)|
| 90-93 | 按键 / 日志 | press_key/back(90 未知 key / 91 失败);logs(92 参数 / 93 指定 package 未运行)|
