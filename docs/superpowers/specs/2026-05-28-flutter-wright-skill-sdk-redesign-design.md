# flutter-wright skill + SDK 重塑 — 设计 spec(2026-05-28)

> 本 spec 合并并取代两份早期草案:`…-orchestration-robustness-design.md`(派发修复)与
> `…-sdk-deployment-and-boundary-design.md`(部署模型 + 边界)。两条线都改 `_lib.sh` 与
> 「派发约定」,合并后改动统一协调。

## 背景

对齐 Playwright MCP 的过程中,两类问题浮出水面:

**(一)编排健壮性——探针实证。** 为验证「AI 用 skill 会不会卡死」,跑了编排探针:mock SDK(仿真 HTTP 契约)+ 假 adb 垫片,让真实脚本在无真机下被 3 个全新 subagent 驱动(只给 SKILL.md 当说明书)。结论:**skill 不会动辄卡死**——登录链路、ref 失效恢复、前提墙都被现有设计挡住;但挖到两个真实缺陷(见设计 1、2)。原先设想的「失败自解释大改造/前提墙标记」经证据**降级为非必需**。

**(二)部署模型与边界——用户诉求。** ① 适配性:提测包也是 release 包,SDK 不该绑 debug;enable 交集成方。② 多 App:一套 SDK 集成进多个 app,AI 选驱动哪个。③ 安全:加 token,确保进了 release 包也不被滥用。④ 边界:进程托管/热重载(run/reload)是否该归本 skill;logs 能否不依赖 run。

## 目标 / 非目标

**目标**

- 修两个真实缺陷:方法名→脚本名映射、goto 导航未配置退出码。
- SDK 启用/鉴权交集成方:`enabled` 开关 + 可选 `token`,默认关、fail-safe。
- 端点完全外置:`base`(IP+端口)集成方定义、skill 注册表配置,脚本零硬编码。
- 多 App:目标注册表 `{name, base, token?, package?}`,AI 按 `name` 选。
- `logs` 改 `adb logcat`,去 `run` 依赖。
- 移除进程托管簇 `run`/`reload`/`stop`,交上游 AI。
- skill 收敛为「驱动 + 观察一个已运行、已可达的 app」。

**非目标(明确不做)**

- 交互能力补全(swipe/drag/doubleTap/fillForm/网络抓包/状态求值)——证据显示都不是链路断点。
- 失败反馈大规模结构化改造——证据显示现状(响应体 + 退出码表)够 AI 自我恢复。
- 服务端全自动端口扫描发现——注册表为准,探活按需。
- SDK 内置环境检测——集成方已有「正式/测试包」判断,SDK 只暴露开关接线。

## 设计

### 1. 派发命名映射修复(🔴 必做,Phase 1)

**问题**:方法表第 1 列驼峰(`waitFor`/`longPress`/`pressKey`/`setViewport`/`resetViewport`),第 3 列脚本下划线(`wait_for.sh`…);「派发约定」第 3 步写 `bash scripts/<method>.sh`。照字面拼 → `waitFor.sh` 不存在 → **退 127,链路断**。探针两场景独立踩中 `waitFor`→127。

**方案(c)**:不改脚本名、不改对外方法名,在「派发约定」写明规则 + 5 例 + 以方法表脚本列为准:

> 3. 调用对应脚本 `bash skills/flutter-wright/scripts/<script>.sh <args>`。**脚本文件名是方法名的 snake_case**——驼峰每个大写字母转 `_<小写>`:`waitFor`→`wait_for.sh`、`longPress`→`long_press.sh`、`pressKey`→`press_key.sh`、`setViewport`→`set_viewport.sh`、`resetViewport`→`reset_viewport.sh`;其余方法(`snapshot`/`tap`/`type`/`scroll`/`goto`/`reset`/`health`/`logs`/`back`/`screenshot`)名一致。**以「方法」表脚本列为准。**

残留风险:依赖 AI 每次套规则。缓解:规则 + 全量例子 + 「以表为准」三重冗余 + 验收核对脚本(见验收)。

### 2. goto 导航未配置退出码修复(🟡 必做,Phase 1)

**问题**:`NavNotConfiguredHandler` 未配置导航返 **501**;`goto.sh` 的 case 只显式处理 503→41/500→42,**501 落通配 `*`→退 43**;文档写 41,且 43 语义是「SDK 不可达」,名不副实。`reset.sh` 501→71,与其文档一致(无需改退出码,但补人话)。

**方案**:`goto.sh` 加显式 `501)` → **exit 41** + 人话(「导航未配置:宿主需在 start() 传 navigatorKey/navigationAdapter;一次性宿主设置,重试无效」),保留把响应体 cat 到 stderr。`reset.sh` 加显式 `501)` → 退出码维持 **71** + 同样人话。让代码追上文档,不改约定。

### 3. SDK 启用与鉴权(Phase 2)

`FlutterWright.start()` 顶层新增 `enabled`/`token`,移除 `FlutterWrightConfig.enableInDebugOnly`:

```dart
static Future<void> start({
  bool enabled = false,        // 集成方接到自己已有的「测试包?」判断:start(enabled: AppEnv.isTestBuild, ...)
  String? token,               // 集成方自定;为空 = 该端不鉴权(仅 loopback)
  FlutterWrightConfig config = const FlutterWrightConfig(),  // 仍含 host/port(设备侧 bind)、screenshotMode、maxBodyBytes
  NavigationAdapter? navigationAdapter,
  GlobalKey<NavigatorState>? navigatorKey,
  Iterable<String> routes = const <String>[],
}) async {
  if (!enabled) return;        // 默认关 = 安全;正式包传 false → 永不绑端口、无运行时攻击面
  // 绑 config.host:config.port(默认 127.0.0.1);token 非空时除 /health 外所有请求校验 X-FW-Token,不符回 401(常量时间比对)
}
```

- enable 完全集成方接线(默认 `false`),去 `kDebugMode` 绑定。
- token **可选、推荐**:传了校验,空则不鉴权(威胁模型见 §安全)。
- `host` 默认 `127.0.0.1`,**永不 `0.0.0.0`**。
- 破坏性变更 → SDK 升 **0.8.0**;CHANGELOG 写迁移(`enableInDebugOnly:true` ≈ `enabled: kDebugMode`)。

### 4. 端点外置 + 目标注册表(Phase 2/3)

skill 侧目标注册表,每条一个完整 `base` + 可选 token + 可选包名:

```
# 存 git 外:env FW_TARGETS 指向的配置文件(下例 YAML 仅示意,JSON 等格式由实现定);token/base 不进仓库 / SKILL.md
targets:
  - name:    shop-qa
    base:    http://127.0.0.1:9123     # 集成方定义,operator 填入(adb forward 后的本地可达地址)
    token:   <可留空>
    package: com.acme.shop             # logs 用
```

- `base` = 脚本实际 curl 的本地可达地址。单条目即默认;多条目而未带 `target=` → 报错提示选哪个。

### 5. SDK 脚本改造(Phase 2)

跟 SDK 通话的 9 脚本:`snapshot`/`tap`/`type`/`scroll`/`long_press`/`wait_for`/`goto`/`reset`/`health`。

- `_lib.sh` 新增 `fw_resolve_target`:从 `"$@"` 抽 `target=<name>`(无则默认),读注册表,export `FW_BASE`/`FW_TOKEN`/`FW_PACKAGE`,返回剥掉 `target=` 后的剩余参数。
- `fw_need_sdk`:**删掉自动 `adb forward`**(可达性移注册时,见 6);只探 `GET $FW_BASE/health`(不带 token),不可达退 12;保留 curl 检查(13)。
- 各脚本 curl 改 `curl ... $(fw_auth_header) "$FW_BASE/<endpoint>"`;`fw_auth_header` 在 `FW_TOKEN` 非空时输出 `-H "X-FW-Token: $FW_TOKEN"`,空则不加。
- 「派发约定」参数表加 `target=`(与设计 1 的命名规则同处协调)。

### 6. 可达性 = 注册 target 时建立(Phase 3)

`adb forward` 不再每次自动做,改注册 target 时一次性建立(轻量管理入口或文档化步骤:写注册表条目 + 本地需要时 `adb forward tcp:<localport> tcp:<deviceport>`)。emulator 直连 / 已有 forward / 隧道场景注册时不做 forward 即可。

### 7. logs 改 adb logcat(Phase 4)

- 有 `package`:`pid=$(adb shell pidof -s <package>)` → `adb logcat -d --pid=$pid`。
- 无 `package`:回退 `adb logcat -d -s flutter`(多 app 会混)。
- `since=<n>`→`-t <n>`;`grep=<pat>`→管道 grep。adb-only,不需 token/base,**去 `run` 依赖**。

### 8. 移除进程托管簇 run / reload / stop(Phase 4)

三者围绕「skill 持有 flutter daemon」而生;skill 不再托管进程,故一并移除。删 `run.sh`/`reload.sh`/`stop.sh`,退出码段 33-38 退役。上游 AI 自行 `flutter run`(需热重载自行用 `--machine`+FIFO 等)。SKILL.md 加迁移说明。

### 9. /health 不校验 token(Phase 2)

`/health` 不要求 token,返回**存活 + 应用身份**(name/package/version),供发现/探活;动作端点全部 token-gated。

### 10. SKILL.md / 方法面变更(Phase 4)

- 方法数 18 → **15**(移除 run/reload/stop)。
- 新增「目标(target)」概念段:注册表、`target=` 选择、默认目标规则。
- 「派发约定」:加 `target=` + 设计 1 的 camelCase→snake 规则。
- `logs` 文档改 logcat;退出码表去 33-38、调整 logs(92)。
- references/methods.md 同步:9 个 SDK 方法签名加 `target=`;删 run/reload/stop;改 logs;goto/reset 退出码按设计 2。

## 安全(威胁模型)

| 面 | 缓解 |
|---|---|
| 正式包被远程驱动 | `enabled=false` → 控制面不绑端口、无攻击面(**主防线,不靠 token**) |
| 测试包被同机其他 app 连 loopback | 可选 token;Android 同机 app 通常能连 `127.0.0.1:端口`,token 鉴权挡之 |
| adb 接入驱动 | 同上;仅绑 127.0.0.1 |
| snapshot 泄露满屏内容(手机号/验证码) | token + 仅测试包启用 + 文档警示 |
| token 泄露 | token 只从 env/本地 config 读,**绝不进仓库 / SKILL.md / commit** |

要点:**配 base(IP+端口)只是"找得到",不是安全措施;安全来自 enable 开关(生产)+ 可选 token(测试包)。** token 可选,分发面变广时强烈建议配置——文档须写明,避免会外发的测试包裸跑。

## 验收 / 测试

- **设计 1**:核对脚本——对方法表每个方法名按规则推导脚本名,断言 `scripts/<推导名>.sh` 存在(覆盖全部方法,尤其 5 个驼峰)。
- **设计 2**:`goto` 打未配置 → 退 **41**(非 43),stderr 含「导航未配置/navigatorKey」;`reset` 打未配置 → 退 71 + 同样人话;既有 `start_navigation_test`/`e2e_route_discovery_test` 绿,若断言旧 43 则改 41。
- **SDK(3、9)**:`enabled:false`→不绑端口;`enabled:true,token:'x'`→无/错 token 401、对 token 200;`/health` 无 token 也 200 且含身份;`token:null`→不鉴权可用。
- **脚本(5)**:注册表两条 target,`snapshot target=A` 打 A 的 base/带 A 的 token;多条目省 `target=`→报错;token 空→不发头仍可用。
- **logs(7)**:配 package 后按 PID 过滤;`since=`/`grep=` 生效;未 `run` 也能拿到。
- **移除(8)**:run/reload/stop 脚本不存在;SKILL.md 方法表/退出码/references 无残留引用。
- **回归**:全部脚本 `bash -n`;两包 `flutter test` 全绿;导航/交互 e2e 适配 `enabled/token` 与端点外置(测试桩带 token 或留空)。

## 范围与分期

由 writing-plans 细化排序;建议:

1. **Phase 1 — 派发修复**(设计 1、2):小、独立、低风险、已有探针证据。可最先单独落地。
2. **Phase 2 — 适配性 + 安全**(设计 3、5、9 + 4 单目标子集):SDK enable/token、端点外置、脚本 token/base 串联、/health 身份。落地即满足「release 可用 + 鉴权」。
3. **Phase 3 — 多 App**(设计 4 全集、6):多目标注册表、`target=` 选择、注册时 forward、探活/列举。
4. **Phase 4 — 边界清理**(设计 7、8、10):logs 改 logcat、移除 run/reload/stop、SKILL.md/方法面收敛。

## 风险 / 取舍

- 方案 (c) 依赖 AI 套命名规则——三重冗余 + 核对脚本缓解。
- 改 goto 43→41:扫一遍仓库对 `43` 的引用同步;退出码表/方法参考本就写 41,方向正确。
- token 可选:受控环境省 token 可接受,分发面广时是风险——靠文档警示,不强制。
- 去自动 adb forward:更解耦,但首次注册需显式建可达性,turnkey 程度下降。
- 移除 run/reload:丢开箱即用开发回路,上游需自理热重载;换 skill 单一职责。
- 破坏性 SDK API:0.7.0 → 0.8.0,既有集成方把 `enableInDebugOnly` 改写为 `enabled`。
- 端点外置依赖注册表正确性;`base` 配错只连不上(快速失败),不引入安全风险。
