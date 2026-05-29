# 对齐 Playwright MCP:snapshot-first 交互层 —— 设计 spec

**日期:** 2026-05-27
**状态:** 设计已认可,待写实施计划

## 目标

给 FlutterWright 补上 Playwright MCP 的灵魂能力 —— **「看语义树 → 操作」** 的 snapshot-first 闭环。`snapshot` 吐回一棵带 `ref` 的 Flutter Semantics(无障碍)树,AI 读树、再用 `ref` 去 `tap` / `type` / `scroll`,而不是靠像素猜坐标。顺带补上 `logs`(≈ `browser_console_messages`)。

一句话:**把 Playwright MCP 的 `browser_snapshot` + 交互工具,按触屏等价物落到 Flutter 上,交付形态仍是现在这个 Claude Code skill。**

## 设计决策(brainstorm 已认可)

| 决策点 | 结论 | 理由 |
|---|---|---|
| 对齐重点 | **功能优先**,交付形态仍是 Claude Code skill(不做 MCP server) | 没有 snapshot/交互,"对齐 usage"无从谈起;能力是前提 |
| 动作哲学 | **触屏等价映射**:补 tap/type/wait_for + scroll/longPress/back;砍 hover/file_upload/tabs/drag-drop | hover/file_upload 在触屏无意义;scroll/longPress/back 是移动端必需而 Playwright 没有 |
| 实现机制 | **扩展现有 HTTP SDK**(Path A):新 handler + adb forward + curl:9123,沿用现有传输与 release no-op 安全模型 | 架构一致、输出可做成 Playwright 形状、skill 不用学新传输 |
| 动作命名 | **tap / type / longPress / scroll**(Flutter 本味,贴 `tester.tap`/`driver.tap`);文档标注 ≈ Playwright | 对 Flutter 用户更自然,与官方测试 API 同词 |
| console 观察 | **带上 `logs`**(SDK-free,走 `run` 持有的 daemon 的 `app.log`) | daemon 已在收 log,导出近乎免费,补齐 Playwright 的 console 能力 |
| **navigatorKey** | **保留代码,降级为「可选」** —— 交互闭环只需 `FlutterWright.start()`;navigatorKey/adapter 仅为 `goto`/`reset` 的额外 opt-in | 交互层经 Semantics 树工作、根本不碰 navigatorKey;它从"驱动 app 的前提"降为"deep-link 导航的 opt-in" |
| **交互参数** | **element + ref 双参**(学 Playwright):`tap "<element>" ref=<ref>` | 人读描述进 transcript/权限提示、逼 Claude 说清意图、减少点错 ref;`element` 纯描述,定位以 `ref` 为准 |
| **动作后状态** | **自动回吐新 snapshot**(SDK 动作 tap/type/scroll/longPress/goto/reset) | Claude 永握新鲜 ref、省一次往返,闭环最顺(Playwright 同款) |
| **SKILL 提示词** | 借 Playwright 的 snapshot-first **doctrine**,**不**照搬其英文措辞;SKILL.md 保持中文/skill 本味 | 提示词的职责是让 Claude 养成对的操作习惯,不是长得像 MCP schema |

这次正是来兑现 `architecture.md` 里"UI 交互(tap/swipe/输入)、widget 树自省 —— 留 v2"那两条。

## 背景与动机

现状:FlutterWright 是 9 个方法的 skill(`run`/`stop`/`reload`/`screenshot`/`goto`/`reset`/`setViewport`/`resetViewport`/`health`),覆盖**进程 / 导航 / 观察(仅截图)/ 环境**,但**完全没有交互原语,也没有结构化的页面自省**。对照 Playwright MCP 的 ~23 个 `browser_*` 工具,最大缺口集中在两类:

- **观察**:缺 `browser_snapshot`(无障碍树)、`browser_console_messages`、network。
- **交互**:`click`/`type`/`hover`/`select_option`/`drag`/`drop`/`press_key`/... 全缺。

Playwright MCP 的工作方式不是截图猜坐标,而是 `browser_snapshot` 返回一棵带 `[ref=eN]` 的无障碍树,再 `browser_click(element, ref)`。Flutter 有一个**天然完美的对应物:Semantics 树** —— 同样是无障碍树语义,每个 `SemanticsNode` 带 label/value/role/actions/rect,且可以被无障碍系统**直接驱动执行动作**(`SemanticsOwner.performAction`)。本设计就把这条 snapshot→act 闭环建起来。

## 改造后的能力矩阵(= 集成分层)

| 能力 | 底层机制 | 集成要求 |
|---|---|---|
| run/reload/stop / screenshot(adb)/ setViewport / **pressKey / back / logs** | flutter daemon / `adb`(screencap、`input keyevent`、`wm`)/ daemon `app.log` | **零集成** |
| **snapshot**(语义树) | 遍历 `renderViews` 的 `SemanticsOwner` 树 → 带 ref 的 YAML | **`FlutterWright.start()`** |
| **tap / longPress / scroll** | `SemanticsOwner.performAction(id, action)`,兜底合成 pointer | `start()` |
| **type** | `SemanticsAction.setText`(+ 可选 focus / submit) | `start()` |
| **waitFor** | 轮询语义树直到条件满足/超时 | `start()` |
| goto / reset | SDK `/navigate` `/reset`(经 `NavigationAdapter`) | `start()` **+ navigatorKey 或 CallbackNavigationAdapter** |
| 渲染树 `/screenshot`(去状态栏) | `FlutterWrightRoot` 的 `RepaintBoundary` | `start()` + 包 `FlutterWrightRoot` |

**关键变化**:解锁完整 Playwright 式交互闭环(snapshot→tap→type→scroll→wait)现在只需 `FlutterWright.start()` —— **不必接 navigatorKey、不必改 `MaterialApp`**。navigatorKey 从"驱动 app 的前提"降为"仅 `goto`/`reset` 的可选 opt-in"。

## 组件设计

### 1. `snapshot` —— Semantics 树序列化 + ref 模型(对齐核心)

新 handler `GET /snapshot`:

1. **强制开启语义**:`FlutterWright.start()` 启动时调一次 `SemanticsBinding.instance.ensureSemantics()` 并持有返回的 `SemanticsHandle`(`stop()` 时释放),保证语义树始终被构建(否则只有无障碍服务激活时才有树)。
2. **拿到根节点(已对 Flutter 3.44 源码坐实)**:单数的 `RendererBinding.pipelineOwner` / `renderView` 自 v3.10 起 `@Deprecated`(多窗口支持),**不用**。稳妥路径是遍历 `RendererBinding.instance.renderViews`,每个 `view.owner?.semanticsOwner?.rootSemanticsNode`(`SemanticsOwner.rootSemanticsNode`,semantics.dart:4840)。普通单窗口 app 就一个 view = 一棵树。
3. 从每棵根起 DFS:`node.visitChildren(...)`(semantics.dart:3100)。
4. 每个节点读 `node.getSemanticsData()`(semantics.dart:3771)→ `SemanticsData`(label / value / hint / flags / actions / rect)。**role 推导**由 flag/action 映射 —— `isButton`→`button`、`isTextField`→`textfield`、`isHeader`→`header`、`isImage`→`image`,有 `tap` action 的→可点。
5. **ref 分配**:**可操作节点**(暴露了 tap/longPress/scroll/setText 任一 action)带 `[ref=sN]`,`N` = `SemanticsNode.id`(节点存活期内稳定的整型 id)。SDK 缓存**最近一次** snapshot 的 `Map<String ref, int nodeId>`;**ref 临时**,只在下次 `snapshot` 前有效(与 Playwright 的 ephemeral ref 一致)。

输出镜像 Playwright 的 YAML 无障碍树,到 stdout,可选 `out=<path>` 落文件:

```yaml
# flutterwright snapshot — route: /login
- Scaffold
  - AppBar
    - header "登录"
  - textfield "手机号" value="" [ref=s7]
  - textfield "密码" value="" [ref=s9]
  - button "登录" [ref=s12]
```

> 这套序列化逻辑(`semantics_snapshot.dart`)被**复用**于动作的「自动回吐 snapshot」(见节 3)。默认出结构树、只给可操作节点 ref;树过大时按需加 `interactive-only`(只列可操作节点,留作后续 flag)。

### 2. ref → 动作机制(Path A 最稳的做法)

**主路径:`SemanticsOwner.performAction(nodeId, SemanticsAction.xxx)`**(semantics.dart:5064)—— 这正是 Android 无障碍系统驱动 Flutter 的方式,**不算坐标、不合成 pointer、几乎不碰 `flutter_test`**:

| 动作 | SemanticsAction |
|---|---|
| `tap` | `SemanticsAction.tap` |
| `longPress` | `SemanticsAction.longPress` |
| `scroll <dir>` | `scrollUp` / `scrollDown` / `scrollLeft` / `scrollRight` |
| `type`(设值) | `SemanticsAction.setText`(args = 文本) |

动作执行步骤(以 `tap` 为例):读 `ref` → 从缓存查 `nodeId` → 在当前语义树按 id 找到存活的 `SemanticsNode`(找不到 = ref 过期/不在快照,退出码 51)→ `performAction`。`element`(人读描述)**不参与定位**,仅入日志 / transcript(与 Playwright 一致)。

**兜底**:某节点未暴露对应 action 时(如自绘控件没接 Semantics),回退到「取 `node.rect` 中心(经变换到全局)+ `GestureBinding.instance.handlePointerEvent` 合成 `PointerDown`+`PointerUp`」。仅在主路径不可用时走。

### 3. 各动作 handler(element + ref 双参 + 自动回吐 snapshot)

每端点一文件,继承 `Handler`,沿用 `ctx.json` / `writeOk` / `writeError` 约定(与 `NavigateHandler` 同构)。请求体均带 **`element`**(人读描述,仅入日志)+ **`ref`**(定位用):

- `POST /tap` `{element, ref}` → performAction tap。
- `POST /type` `{element, ref, text, submit?}` → (可选 tap 取焦点)+ `setText`;`submit:true` 时随后发一次 ENTER(skill 层 `adb keyevent 66`,或 TextInput action)。
- `POST /scroll` `{element, ref, dir, amount?}` → `scroll*` action;`dir` ∈ up/down/left/right。
- `POST /long_press` `{element, ref}` → performAction longPress。
- `GET /wait_for` `?text= | ?ref= | ?gone= &timeout=` → SDK 侧轮询语义树:`text`/`ref` 出现即返,`gone` 消失即返,超时(默认 5s)退出码 85。

**自动回吐 snapshot**:`tap` / `type` / `scroll` / `long_press` 以及 SDK 导航 `/navigate` `/reset` 的**成功响应里带一个 `snapshot` 字段**(复用节 1 的序列化),`/wait_for` **成功时**也带。这样 Claude 每次动作后都手握新鲜 ref,不必显式再 `snapshot`。**例外**:`back` / `pressKey` 走 adb、属免-SDK tier,**不自动回吐**(要看新状态时 Claude 显式 `snapshot`)。

### 4. `pressKey` / `back`(adb,免 SDK)

- `pressKey <key>`:`adb shell input keyevent <code>`;`key` 取友好名(`enter`/`back`/`home`/`tab`/`del`...)映射到 keycode,非法 key → 退出码 90。
- `back`:≈ `browser_navigate_back`,实为 `adb shell input keyevent 4`(系统返回 = pop 一层)。与现有 `reset`(pop 到根)分工互补。

> 这两个不进 SDK、也不自动回吐 snapshot:系统键 / 系统返回是 OS 层事件,adb 直接发更省事,也保住「不集成也能用一部分」。

### 5. `logs`(daemon,免 SDK)

`run` 持有的 `flutter run --machine` daemon 的 stdout(`fw_daemon.log`)里已含 `app.log` 等结构化事件,app 的 `print`/framework 日志走 `app.log`。`logs.sh`:从 `fw_daemon.log` 抽 `"event":"app.log"` 行的 `message`(grep/sed,**不引入 jq**),支持 `[since=<n>]`(尾部 N 行)/ `[grep=<pat>]` 过滤。无 `fw_daemon.env`(没 `run` 过)→ 退出码 92。

### 6. navigatorKey 降级为「可选」(决策 B)

**现状**(读代码核实):`start()` 永远兜底构造 `NavigatorKeyAdapter`(用静态 `FlutterWright.navigatorKey`)并注册 `Navigate/Reset/Routes` handler(`flutter_wright.dart:53-70`)。navigatorKey **仅**供 `/navigate` `/reset`,别处一概不碰 —— `screenshot` 用 `fwRepaintBoundaryKey` + `rootElement`(`screenshot.dart:33-35`),交互层走 Semantics 树。

**改造**:

- `navigatorKey` + `NavigatorKeyAdapter` + `CallbackNavigationAdapter` 代码**全部保留**(Nav 1.0 / GoRouter / GetX 的 `goto`/`reset` 仍靠它们)。
- `start()` 改为**仅当显式传了 `navigationAdapter` 或 `navigatorKey` 时**才构造 adapter 并注册 `NavigateHandler`/`ResetHandler`/`RoutesHandler`;否则不注册。这样 `goto`/`reset` 在未配置导航时返回**明确的「导航未配置」**,而不是现在那种「静态 key 没挂到 `MaterialApp` → `isReady` 恒 false → 默默 503」。
- 交互层 handler(snapshot/tap/type/scroll/long_press/wait_for)与导航无关,**无条件注册**。
- `FlutterWright.navigatorKey` 静态便利 key 原样保留。

集成分层见上方「能力矩阵」表。

### 7. SDK 侧改动

- 新 handler 文件:`snapshot_handler.dart` / `tap_handler.dart` / `type_handler.dart` / `scroll_handler.dart` / `long_press_handler.dart` / `wait_for_handler.dart`。
- 新单元(小文件、高内聚):
  - `semantics_snapshot.dart` —— 遍历语义树 → 节点模型 + YAML 序列化 + role 推导;**被 snapshot handler 与各动作 handler 的自动回吐共用**。
  - `semantics_action.dart` —— ref→nodeId→`SemanticsNode` 解析、`performAction`、pointer 合成兜底。
- `flutter_wright.dart` 门面:`start()` 内 `ensureSemantics()` 持有 `SemanticsHandle`(`stop()` 释放);**无条件**注册 6 个交互 handler;`Navigate/Reset/Routes` 改为**条件注册**(见节 6)。
- 版本:`0.6.0` → **`0.7.0`**(新增能力,非破坏),CHANGELOG 加条目。

### 8. skill 侧改动

- 新脚本:`snapshot.sh` / `tap.sh` / `type.sh` / `scroll.sh` / `long_press.sh` / `wait_for.sh` / `press_key.sh` / `back.sh` / `logs.sh`,复用 `_lib.sh`。SDK 类用 `fw_need_sdk`(沿用 12 SDK 不可达);`press_key`/`back`/`logs` 不调 SDK 检查。
- **派发约定**:`element` 作为**引号包裹的位置参数**(第一个位置参数),`ref`/`text`/`dir`/`submit`/`amount` 等为 `key=value`;引号转义同现有 `goto args` 的 JSON 转义惯例。例:
  - Skill 调用:`tap \"登录按钮\" ref=s12`
  - Bash 执行:`bash scripts/tap.sh '登录按钮' ref=s12`

## 方法面(改造后)

| 方法 | 状态 | ≈ Playwright | 集成 | 回吐 snapshot |
|---|---|---|---|---|
| `snapshot [out=<path>]` | **新增** | browser_snapshot | `start()` | — |
| `tap "<element>" ref=<ref>` | **新增** | browser_click | `start()` | ✓ |
| `type "<element>" ref=<ref> text=<text> [submit=<bool>]` | **新增** | browser_type | `start()` | ✓ |
| `scroll "<element>" ref=<ref> dir=<dir> [amount=<n>]` | **新增** | (PW 自动滚) | `start()` | ✓ |
| `longPress "<element>" ref=<ref>` | **新增** | (无对应) | `start()` | ✓ |
| `waitFor (text=<s>\|ref=<s>\|gone=<s>) [timeout=<ms>]` | **新增** | browser_wait_for | `start()` | 成功时 ✓ |
| `pressKey <key>` | **新增** | browser_press_key | 零集成(adb) | — |
| `back` | **新增** | browser_navigate_back | 零集成(adb) | — |
| `logs [since=<n>] [grep=<pat>]` | **新增** | browser_console_messages | 零集成(daemon) | — |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | 集成降级 | browser_navigate | `start()`+navigatorKey/adapter | ✓ |
| `reset` | 集成降级 | — | `start()`+navigatorKey/adapter | ✓ |
| `run`/`stop`/`reload`/`screenshot`/`setViewport`/`resetViewport`/`health` | 不变 | — | — | — |

## 退出码(新增区间)

沿用现有 0 / 10-13 / 20-22 / 33-38 / 40-43 / 60-61 / 70-71,新增:

| 区间 | 类别 |
|---|---|
| 50-57 | 交互:50 缺 ref 或 element / 51 ref 过期或不在快照 / 52 节点无对应 action 且无法合成 / 53 缺 text / 54 节点不可输入 / 55 输入失败 / 56 scroll 参数非法 / 57 动作执行失败 |
| 80-81 | snapshot:80 语义树不可用(为空/未构建)/ 81 写文件失败 |
| 84-85 | waitFor:84 缺条件参数 / 85 超时未满足 |
| 90-92 | 按键/日志:90 key 非法 / 91 keyevent 失败 / 92 logs 无 daemon |

> SDK 不可达统一沿用 `fw_need_sdk` 的 12。

## 安全 / SDK 角色

- 新端点同受现有约束:`kDebugMode==false` 拒启动、仅绑 `127.0.0.1`、release no-op、每端点输出一行汇总、超 `maxBodyBytes` 返 413。
- **SDK 角色重定位**:交互闭环(snapshot/tap/type/scroll/longPress/waitFor)只需 `FlutterWright.start()`,**不需要 navigatorKey、不改 `MaterialApp`**;navigatorKey/adapter 进一步降为 `goto`/`reset` 专属的可选项。"免集成只截图+热重载+按键+日志"对**零集成** tier 依旧成立。
- `start()` 会调 `ensureSemantics()` 常开语义树 —— 仅 debug 生效,release no-op。
- `setText` 会写入宿主应用的输入框 —— 仅 debug、仅本机回环,风险面与现有 `/navigate` 同级。

## 测试策略

- **单元**(`flutter test`,SDK 包内):
  - `semantics_snapshot`:给定一棵构造的 Semantics 树 → 断言 YAML 输出、role 推导、ref 只分配给可操作节点。
  - `semantics_action`:ref→nodeId 解析、ref 过期返回 null(→ 51)。
  - **navigatorKey 条件注册**:`start()` 不传 adapter/navigatorKey → `goto`/`reset` 命中返回「导航未配置」而非 503;显式传则正常注册。
- **E2E**(example app + 控制面 bash):login 页已有「手机号 / 密码」两个 `TextField` + 「登录」`FilledButton`,直接拿来跑闭环 —— `snapshot`(断言出现 `textfield "手机号"`、`button "登录"` 且带 ref)→ `type "手机号" ref=<r> text=13800000000` → `tap "登录" ref=<r>` → 断言行为,并校验**动作响应里含 `snapshot` 字段**。沿用现有 `e2e_*_test.dart` 结构,新增 `e2e_interaction_test.dart`。
- 两包 `dart analyze` 干净;`flutter test` 全绿。

## 需要更新的文档

- `skills/flutter-wright/SKILL.md` —— 方法表 9 → ~18;**写入 snapshot-first doctrine**(先 `snapshot` 拿 ref 再操作、ref 临时、`screenshot` 只看效果不定位)、方法按 **observe→act→navigate** 重排、`element+ref` 双参与「动作自动回吐 snapshot」说明、navigatorKey 降级;dispatch 约定补 `element` 位置参数。**保持中文/skill 本味,不照搬 Playwright 英文措辞。**
- `docs/api-reference.md` —— 新增 `/snapshot` `/tap` `/type` `/scroll` `/long_press` `/wait_for` 端点协议(含 `element` 字段、响应 `snapshot` 字段);版本 0.7.0。
- `docs/architecture.md` —— 「故意不做(v1)」里删掉「UI 交互」「widget 树自省」两条;组件图补交互层 + `semantics_snapshot`/`semantics_action`;补 navigatorKey 降级 / 集成分层。
- `docs/integration-guide.md` / `integration-guide-for-ai.md` —— 讲清「交互闭环只需 `start()`,navigatorKey 仅为 `goto`/`reset`」;SDK 角色从「只解锁 goto」扩为「`start()` 解锁全套交互,navigatorKey 再加 goto」。
- `docs/troubleshooting.md` —— 新增「snapshot 为空(语义未开/页面无 Semantics)」「ref 过期」「setText 不生效」「goto 报『导航未配置』(没接 navigatorKey/adapter)」。
- `README.md` —— 「是什么」补 snapshot→act;能力清单从「跳页」扩到「看树 + 操作」;SDK 角色更新。
- `packages/flutter_wright_sdk/CHANGELOG.md` —— 0.7.0 条目。

## 待 plan 阶段验证的风险

1. **`SemanticsAction.setText` 文字输入**:对焦点 / IME / 是否需先 tap 取焦点有细节差异 —— 实施前做一个真机小实验,确定 `type` 的最终实现(纯 setText / tap+setText / 退回 `adb input text`)。
2. **合成 pointer 兜底**:在**活的(非 test)**binding 里用 `GestureBinding.handlePointerEvent` 合成点击的可靠性,需在真机确认坐标变换(`node.rect` → 全局)正确。
3. **语义树覆盖度**:自绘 / 第三方控件可能不暴露 Semantics —— 这类节点拿不到 ref,文档需说明「snapshot 反映的是无障碍树,不是 widget 树」。
4. **自动回吐 snapshot 的体积**:语义树大时,每次动作响应都附整棵树会膨胀 token —— 若实测过大,用后续的 `interactive-only` flag 收窄回吐内容。

> 已坐实(brainstorm 阶段):语义树的获取入口已对 Flutter 3.44 源码核实(`ensureSemantics` + `renderViews` 路径,见节 1),原「入口跨版本」的风险已消除。

## 范围外(YAGNI)

- `evaluate` / `run_code`(无安全的 Dart-eval;SDK 是固定 handler 集)。
- network 观察(Flutter 侧无干净的统一钩子)。
- `hover` / `file_upload` / `tabs` / `drag`+`drop`(触屏裁掉或少见)。
- `select_option`(下拉先靠 tap 展开 + tap 选项覆盖,不单列方法)。
- `element` 描述与节点的一致性校验(纯描述性,与 Playwright 一致,不强制 match)。
- iOS / 非 Android。
- MCP server 打包(已选保持 Claude Code skill 形态)。
- SDK 渲染树 `/screenshot`(`FlutterWrightRoot`)维持现状,本次不动。
