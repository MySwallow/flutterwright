# flutter-wright 编排健壮性修复 — 设计 spec(2026-05-28)

## 背景

担心点(用户原话):AI 拿着 flutter-wright **skill** 时,能否像用 Playwright **MCP** 那样自由选对方法、把多步操作串起来、且中途不卡死。MCP 是 23 个常驻类型化工具,SKILL 是一份 prose + bash 脚本,体验可能有差。

为把猜想变证据,跑了**编排探针**:用一次性 mock SDK(仿真 SDK 的 HTTP 契约)+ 假 adb 垫片,让**真实 skill 脚本**在无真机下被驱动;再派 3 个全新 subagent(只给 SKILL.md 当说明书,不告诉用哪些方法)各跑一个真实多步任务,分别打三种卡死模式。

探针结论:

| 场景 | 卡死模式 | 结果 |
|---|---|---|
| 登录(snapshot→type→type→tap→截图) | 方法选择 + 串链 | ✅ 完美自主完成 |
| 删空购物车(删除后 ref 变化) | ref 失效后恢复 | ✅ 主动用回吐 snapshot 的新 ref,零 51、零循环 |
| 打开 /order/detail(宿主没配 navigatorKey) | 前提墙 | 🟡 识别为宿主集成缺失、未死循环、如实止步 |

**核心结论:skill 不会动辄卡死**;ref 失效恢复、前提墙空转这两种担心,已被现有设计(动作后自动回吐 snapshot + 工作法文档 + 响应体里的人话)挡住。原先设想的「失败自解释大改造」「前提墙别重试标记」经证据**降级为非必需**。

但探针挖到两个真实缺陷,本 spec 只修这两个(+ 一个顺带小修)。

## 目标 / 非目标

**目标**

1. 消除「AI 选对方法却调不起来」的链路断点(camelCase 方法名 ↔ snake_case 脚本名)。
2. 让 `goto` 在「导航未配置」时给出与文档一致、语义正确的退出码与人话。

**非目标(明确不做)**

- 任何能力补全:swipe/drag/doubleTap/fillForm/selectOption/网络抓包/运行时状态求值。证据显示它们都不是链路断点。
- 失败反馈的大规模结构化改造。证据显示现状(响应体 + 退出码表)已够 AI 自我恢复。

## 改动

### 改动 1(🔴 必做)— 派发约定写明 camelCase→snake 映射

**问题**:方法表第 1 列方法名是驼峰(`waitFor`/`longPress`/`pressKey`/`setViewport`/`resetViewport`),第 3 列脚本是下划线(`wait_for.sh`…);而「派发约定」第 3 步写 `bash scripts/<method>.sh`。照字面拼 → `waitFor.sh` 不存在 → **退 127,链路断**。探针场景 1、3 各自独立踩中 `waitFor`→127。

**方案**:采用方案 (c) —— 不改脚本名、不改对外方法名,只在 SKILL.md「派发约定」里写明命名规则 + 5 个例子 + 指明以方法表第 3 列脚本名为准。

「派发约定」第 3 步,改为(措辞最终以实现为准):

> 3. 调用对应脚本:`bash skills/flutter-wright/scripts/<script>.sh <args>`。**脚本文件名是方法名的 snake_case 形式**——方法名里每个大写字母转成 `_<小写>`:
>    `waitFor`→`wait_for.sh`、`longPress`→`long_press.sh`、`pressKey`→`press_key.sh`、`setViewport`→`set_viewport.sh`、`resetViewport`→`reset_viewport.sh`;
>    其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`run`/`stop`/`health`/`logs`/`back`/`screenshot`/`reload`)方法名与脚本名一致。
>    **以「方法」表第 3 列的脚本名为准。**

不改:脚本文件、对外方法名(API 面不变,`Skill flutter-wright "waitFor …"` 仍是合法写法)。

**残留风险与缓解**:方案 (c) 依赖 AI 每次套用该规则,不如中央 dispatcher 确定。缓解:规则 + 全量例子 + 「以表第 3 列为准」三重冗余,且方法表本就列出正确脚本名;实现后用「方法名→脚本存在性」核对(见验收)兜底。若未来仍发现误拼,再考虑 (a) 重命名脚本或加 alias。

### 改动 2(🟡 必做)— goto.sh 501 显式退 41 + 人话;reset.sh 501 补人话

**问题**:`NavNotConfiguredHandler` 在未配置导航时返 **501**。`goto.sh` 的 `case` 只显式处理 `503→41`、`500→42`,**501 落到通配 `*`→退 43**;而文档(方法参考 + 退出码表)写「未配置→41」,且 43 的语义是「SDK 不可达」,名不副实。探针场景 3 的 agent 因此"多看了一眼确认"。`reset.sh` 的 501→`*`→71,与其文档「71 含 501」一致,退出码无需改,但同样只报「returned 501」、缺人话。

**方案**:

- `goto.sh`:在通配前加显式 `501)` 分支 → **exit 41** + 明确人话(「导航未配置:宿主需在 `FlutterWright.start()` 传 navigatorKey/navigationAdapter;这是一次性宿主设置,重试无效」),并保留把响应体 cat 到 stderr。`503`(未就绪/可能瞬态)仍 → 41,但消息区分"未就绪"。结果:41 同时覆盖「未配置(501)」与「未就绪(503)」,与文档「41 navigator 未配置或未就绪(501/503)」对齐。
- `reset.sh`:加显式 `501)` 分支,**退出码维持 71**(与其文档一致),但补同样的人话,避免只报「returned 501」。

不改文档退出码契约(goto 本就该是 41;reset 本就是 71)——这是让代码追上文档,不是改约定。

### 改动 3(⚪ 可选 / 暂缓)— setup-wall stderr 一句式提示

给少数"宿主一次性设置"类失败(`12` SDK 不可达 / `41` 未配置)在 stderr 末尾补一句「这是宿主设置,把这句告诉用户、勿重试」。证据显示 AI 已基本能自行判断,故列为可选;若实现 #2 时顺手,可一并做,否则暂缓。

## 验收

- **改动 1**:写一个核对——对方法表里每个方法名,按规则推导脚本名,断言 `scripts/<推导名>.sh` 存在(覆盖全部 18 方法,尤其 5 个驼峰)。可作为 CI/本地一次性检查脚本,或在现有测试里加。
- **改动 2**:
  - 复跑探针场景 3 的等价检查:`goto /x` 打未配置 SDK 时,脚本退 **41**(不再是 43),stderr 含"导航未配置/navigatorKey"字样。
  - `reset` 打未配置时,退 71,stderr 含同样人话。
  - 既有 e2e(`start_navigation_test` / `e2e_route_discovery_test`)仍绿;若它们断言了旧的 43,同步更新为 41。
- **回归**:`bash -n` 全部脚本;两包 `flutter test` 全绿(不受脚本改动影响,但确认导航相关 e2e 的契约一致)。

## 风险

- 改 `goto` 退 43→41:若有调用方/文档键在 43 上,需同步。退出码表与方法参考本就写 41,对齐方向正确;扫一遍仓库对 `43` 的引用即可。
- 方案 (c) 的依赖性风险见改动 1 的缓解。

## 范围确认

两个必做小修(SKILL.md 文案 + 2 个脚本各加一个 case)+ 一个可选项 + 一个核对脚本。聚焦,足够用一个实现计划完成。
