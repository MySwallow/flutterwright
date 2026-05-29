# FlutterWright skill ↔ SDK 验收模板

> **用途**:这是一份**可复用、不带日期**的验收清单 —— 每次改动 skill 脚本(`skills/flutter-wright/`)、
> SDK 源码(`packages/flutter_wright_sdk/`)或 example(`packages/example/`)后,照此跑一遍,
> 确认 **skill 与 SDK 的联动(HTTP 控制面契约)未回归**。
>
> **核心命题**:skill 的本质是「一组 bash 脚本经 `curl` 调用嵌入宿主 app 的 SDK HTTP 控制面」。
> 因此「联动是否符合预期」= **脚本发出的请求 + SDK 的响应 + 脚本对响应的退出码映射**三者对齐。
> 本模板把这条契约拆成可自动跑的三层 + 一份真机手测清单。
>
> 历史的、带日期的轮次验收记录见 [`ACCEPTANCE-REPORT.md`](./ACCEPTANCE-REPORT.md) 与
> [`superpowers/acceptance/`](./superpowers/acceptance/);本文件是它们的「活模板」继任者。

---

## 0. 环境前提

| 依赖 | 自动验收是否必需 | 说明 |
|---|---|---|
| Flutter / Dart | **是**(SDK 单测 + example e2e) | 本仓库验证用 Flutter 3.44.0 / Dart 3.12.0。`flutter --version` 应可用。 |
| `bash` / `curl` / `python3` | **是**(skill bash 脚本层) | macOS 自带即可;bash 3.2 亦可。 |
| `adb` + Android 设备/模拟器 | **否**(仅真机手测段需要) | 自动验收**不需要** adb —— SDK 控制面是纯 `dart:io HttpServer`,与 Android 无关。 |

> **关键洞察**:16 个 skill 方法里,只有 `screenshot` / `setViewport` / `resetViewport` /
> `pressKey` / `back` / `logs` / `type submit=true` 真正依赖设备(走 adb);其余交互/导航方法
> (`snapshot` / `tap` / `type` / `scroll` / `longPress` / `waitFor` / `goto` / `reset` / `health`)
> 是平台无关的纯 HTTP,**无真机即可真实验证联动**。

---

## 1. 三层测试总览

| 层 | 位置 | 验证什么 | 对手方 | 期望 |
|---|---|---|---|---|
| **L1 skill bash 脚本** | `test/flutter-wright/*.sh` | 脚本的参数解析、目标注册表解析、退出码、adb 包装逻辑 | `mock_sdk.py`(SDK 契约的最小桩)+ fake adb | **9/9 PASS** |
| **L2 SDK Dart 单元** | `packages/flutter_wright_sdk/test/*.dart` | SDK 内部单元:snapshot 序列化/ref 解析、semantics action、navigation adapter、token 鉴权、导航注册 | 纯单元 | **All tests passed**(基线 24) |
| **L3 example e2e(联动核心)** | `packages/example/test/e2e_*.dart` + `getx_integration_test.dart` | **真实 bash 脚本 / 真实 curl → 真实 SDK HTTP 控制面 → 真实 app**,跨 3 种路由架构 | 进程内真 SDK + 子进程真 curl/bash | **All tests passed**(基线 17) |

> L3 是「skill↔SDK 联动」的主战场:它在 `flutter test` 进程里 `FlutterWright.start()` 起真实
> HTTP 服务,再用**独立子进程**的 `curl` / `skills/flutter-wright/scripts/*.sh` 打它 —— 这正是
> 生产里 skill 实际走的路径。(`flutter_test` 的 binding 会把**进程内** `HttpClient` fake 掉,
> 所以必须用子进程 curl/bash,这也恰好覆盖了真实链路。)

---

## 2. 自动验收(无真机即可全跑)

### 2.1 L1 — skill bash 脚本层

```bash
cd test/flutter-wright
for t in *_test.sh; do bash "$t" && echo "PASS $t" || echo "FAIL $t"; done
```

覆盖:`dispatch_naming`(脚本名=方法 snake_case)、`resolve_target`(注册表解析 / 14/15 码)、
`goto_exit_code` / `reset_exit_code`(501→41 / 501→71)、`snapshot_smoke`(GET + X-FW-Token)、
`logs`、`targets_add` / `targets_forward` / `targets_list`。

### 2.2 L2 — SDK Dart 单元层

```bash
export PATH="$HOME/development/flutter/bin:$PATH"   # 按本机 flutter 安装路径调整
cd packages/flutter_wright_sdk && flutter test
```

覆盖:`semantics_snapshot`(serialize / resolve / containsText)、`semantics_action`
(tap / setText / scroll,含非法方向返回 false)、`navigation_adapter`、`enabled_token`
(`enabled:false` 不绑定、token 校验)、`start_navigation`(未传 key→/navigate 501;传 key→非 501)。
（`test/diag_test.dart` 为本地诊断文件,untracked,不在范围。）

### 2.3 L3 — example e2e 联动层(核心)

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd packages/example && flutter test
```

> **端口约定(重要)**:各 e2e 文件绑**互不相同**的端口,以便 `flutter test` 默认并行跑测试文件时
> 不撞车 —— control_plane=9123、navigation_adapter=9124、route_discovery=9125、getx=9126、
> interaction=9127。**新增 e2e 文件务必分配一个未占用端口**(经 `FlutterWrightConfig(port:)` +
> 对应注册表行),否则两文件共用一端口会在并行下 `Address already in use`(errno 48)产生**假阴性**。
> 兜底排查:`flutter test -j 1`(串行)能消除端口撞车 —— 若串行绿、并行红,即端口分配漏了。

### 2.4 一键全量

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
( cd test/flutter-wright && for t in *_test.sh; do bash "$t" || exit 1; done ) && echo "L1 OK"
( cd packages/flutter_wright_sdk && flutter test ) && echo "L2 OK"
( cd packages/example && flutter test ) && echo "L3 OK"
```

---

## 3. skill↔SDK 契约断言清单(L3 每条证明了什么)

逐条对照,确认「联动符合预期」:

**控制面 / 导航(`e2e_control_plane_test.dart`,9123,Navigator 1.0)**
- [ ] 真实 curl `GET /health` → `{ok:true, service:"flutter_wright_sdk", version:<ver>}`。
- [ ] `GET /routes` → 含 `/`、`/login`、`/order/detail`(来自 `start(routes:)`)。
- [ ] `POST /navigate /order/detail` → `find.byType(OrderDetailPage)` 命中(导航真的发生)。
- [ ] `POST /reset` → pop 回 `HomePage`。
- [ ] `GET /screenshot` → 200 + PNG magic(经 `FlutterWrightRoot` 的 keyed `RepaintBoundary`)。
- [ ] **真实 `goto.sh` / `reset.sh`** 驱动同一服务,exit 0 且页面真的切换/回根。

**交互层(`e2e_interaction_test.dart`,9127,登录页)**
- [ ] `GET /snapshot` → YAML 含 textfield/button,actionable 节点带 `[ref=sN]`。
- [ ] `POST /type` 写手机号 → 响应**自动回吐 snapshot**,`find.text('13800000000')` 命中。
- [ ] `POST /tap` 登录 → 200。
- [ ] `GET /wait_for?text=登录` → 已存在即 200。
- [ ] `POST /navigate` → 响应含 `snapshot` 键。
- [ ] **真实 `snapshot.sh → type.sh → tap.sh` 脚本闭环** 全 exit 0,UI 断言命中。

**错误路径退出码契约(`e2e_interaction_test.dart`,真实 SDK)**
- [ ] `tap.sh` 用未知/过期 ref → SDK 404 → **exit 51**。
- [ ] `type.sh` 写到按钮(非输入框)ref → SDK 422 → **exit 54**。
- [ ] `tap.sh` 缺 `ref=` → 脚本侧 → **exit 50**。
- [ ] SDK 不可达(注册表指向关闭端口)→ `fw_need_sdk` 预检 → **exit 12**。

**路由架构无关性(证明 SDK 不绑死 Navigator 1.0)**
- [ ] `e2e_navigation_adapter_test.dart`(9124):`CallbackNavigationAdapter` 驱动 `ValueNotifier`
      声明式路由,curl `/navigate /cart`、`/profile`、`/reset` 真的换页;`/routes` 来自 `routesProvider`;
      发现与导航解耦(跳未登记路由仍 200)。
- [ ] `e2e_route_discovery_test.dart`(9125):传 navigatorKey 但无 routes → `/routes` 返回 `[]`;
      自定义 key 驱动 `pushNamed`。
- [ ] `getx_integration_test.dart`(9126):**真实 `get` 包** GetMaterialApp + `Get.toNamed` 经
      `CallbackNavigationAdapter`;`/navigate` args 透传、`/reset` 经 `Get.until` 回根;
      **GetX 页内 `/snapshot → /type → /tap` 交互闭环**(交互层架构无关)。

---

## 4. 退出码契约矩阵

> SKILL.md / `references/methods.md` 是退出码的权威定义。下表标注每个码**当前由哪一层覆盖**。
> 改动任一方法的退出码语义时,先更新 methods.md,再确认对应层用例同步。

| 退出码 | 含义 | 覆盖层 |
|---|---|---|
| 0 | 成功 | L1 / L3(各 happy path) |
| 10 / 11 | adb 缺失 / 无设备 | 真机手测(§5);L1 用 fake adb 覆盖逻辑 |
| **12** | SDK 不可达(所有 SDK 方法预检) | **L3 错误路径** |
| 13 | 无 curl | 代码审查(环境码) |
| 14 / 15 | 注册表缺失/空 · 目标歧义或未找到 | **L1** `resolve_target_test` |
| 16 | adb forward 失败 | L1 `targets_forward_test`(fake adb fail) |
| 17 / 18 | targets 未知子命令 / add 参数非法或重名 | **L1** `targets_add_test` |
| 20–22 | screenshot(空 / <1KB / 非 PNG) | 真机手测(§5) |
| 40–43 | goto(缺 route / 501·503 / 500 / 非预期) | **L1** `goto_exit_code`(501→41);真机补 500/503 |
| **50 / 51 / 52** | tap:缺 ref / ref 过期(404)/ 无 tap action(422) | **L3 错误路径**(50、51);52 见真机 |
| **54** | type 非输入框(422) | **L3 错误路径** |
| 53 / 55 | type 参数错 / 其它非 200 | L3 happy path 反证;53 见 §5 |
| 56 / 57 | scroll 参数错 / 交互其它非 200 | 真机手测(§5) |
| 60 / 61 | setViewport 缺参 / 覆盖被拒 | 真机手测(§5) |
| 70 / 71 | reset 多余参数 / 501(导航未配置) | **L1** `reset_exit_code`(501→71) |
| 80 | snapshot 非 200 | L3 happy path 反证 |
| 84 / 85 | waitFor 参数错 / 超时 | 真机手测(§5) |
| 90 / 91 | pressKey 未知 key / adb 失败 | 真机手测(§5) |
| 92 / 93 | logs 参数错 / package 未运行 | **L1** `logs_test`;93 见 §5 |

---

## 5. 真机 / 模拟器手测清单(adb 依赖,自动验收不覆盖)

> 连一台开了调试的 Android,在集成了 SDK 的 app 里自行 `flutter run`(dev 入口),
> 等 `[flutter_wright_sdk] listening ...`,`targets add` + `targets forward` 建可达性后逐条手测。

### 设备方法(仅 adb,不碰 SDK)
- [ ] `screenshot /tmp/x.png` 出整帧 PNG(含状态栏);锁屏时退 22。
- [ ] `setViewport 1080 2400 480` 改分辨率 + 回读校验;模拟器钳值时退 61;**`resetViewport` 必复位**(恒 0)。
- [ ] `pressKey enter|back|home|tab`、`back`(adb keyevent)系统键生效。
- [ ] `logs since=50 grep=ERROR`:有 `package` 时按 pid 精确过滤;未运行的 package 退 93。

### 交互/导航中需设备或真机渲染的项
- [ ] `type ... submit=true`:ENTER 经 `adb keyevent 66` 提交(额外需 adb,无设备退 10/11)。
- [ ] **`type` 中文 / Emoji** 正常(`userUpdateTextEditingValue` 路径,IME 无关)。
- [ ] **多输入框页面**:`type` 命中目标框,不误写相邻框(几何匹配 + DPR 归一)。
- [ ] `scroll ... dir=down` 长列表真滚动(snapshot 出现新项新 ref);非法 `dir` 退 56;不可滚节点退 52。
- [ ] `longPress` 触发长按回调/菜单;无 longPress action 节点退 52。
- [ ] `waitFor text=... timeout=3000` 出现即 200,不出现超时退 85;`gone=` / `ref=` 形式各验一次。
- [ ] `goto` 未传 navigatorKey/adapter 的 app 上 → 501 → 退 41;`reset` 同条件 → 退 71。
- [ ] `targets`(无参)列举 + 探活每条 `HEALTH=ok|unreachable`;`targets forward` 建 `adb forward`。

### token 鉴权(端到端)
- [ ] 服务端 `start(token:)` 开启 + 注册表第 3 字段填对 token → 端点 200。
- [ ] 注册表缺/错 token → 端点 401 → 落入该方法「其它非 200」码(tap 57 / type 55 / snapshot 80)。

---

## 6. 判定标准

- **自动验收通过** = L1 9/9 + L2 全绿 + L3 全绿(默认并行 `flutter test` 即应全绿,无需 `-j 1`)。
- **联动通过** = §3 契约清单全勾(随 L3 全绿自动满足)。
- **完整验收** = 自动验收通过 **且** §5 真机手测在一台真实 Android 上全勾。
- 任一未达项:记录现象 + 退出码 + 对应层/文件,附 issue;**不要**把假阴性(端口撞车、并发干扰)
  当真失败 —— 先按 §2.3 兜底用 `-j 1` 复核,再下结论。

---

## 7. 维护规则:改了 X 就补 Y

| 改动 | 必须同步 |
|---|---|
| 新增/改 SDK endpoint | L2 加 handler 单元;L3 加 curl + 对应 `*.sh` 脚本的真实驱动用例 |
| 新增/改 skill 方法或脚本 | SKILL.md「方法」表 + `references/methods.md`;L1 加脚本测试;若是 SDK 方法,L3 加端到端 |
| 改任一退出码语义 | 先改 methods.md,再改 §4 矩阵 + 对应层用例 |
| 新增 e2e 测试文件 | **分配一个未占用端口**(见 §2.3),`FlutterWrightConfig(port:)` + 注册表行一致 |
| 删除某方法/脚本 | 同步删 L1/L3 中引用它的用例(否则测试引用已删脚本会 exit 127 漂移) |

---

## 附:已知坑与边界

- **`SemanticsHandle` 释放时序**:`FlutterWright.start()` 持有的 `ensureSemantics` 句柄必须在
  **测试体内** `stop()`(`_endOfTestVerifications` 早于 tearDown)。L3 用例经 `withApp` / `withLoginApp`
  包装器满足;真机生产无此约束。
- **端口撞车假阴性**:见 §2.3 —— 这是历史上最常见的 L3 假失败来源。
- **`setText` 实现**:走「几何匹配 EditableTextState + `userUpdateTextEditingValue`」,而非
  `SemanticsAction.setText`(Flutter 不在 TextField 上暴露后者)。Unicode 安全;真机 IME 行为由
  §5「中文/Emoji」一项守护。
- **`flutter test` 进程内 HttpClient 被 fake**:所以 L3 一律用**子进程** curl/bash,不可改用
  进程内 `HttpClient`,否则测的不是真实链路。
