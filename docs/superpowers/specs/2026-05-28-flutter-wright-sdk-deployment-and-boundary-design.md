# flutter-wright SDK 部署模型 + skill 边界 — 设计 spec(2026-05-28)

## 背景

对齐 Playwright MCP 的讨论中,用户提出三个超出「派发修复 spec」范围的诉求:

1. **适配性**:SDK 不该硬绑 debug 模式才能用。用户的提测包**也是 release 包**,debug 闸门会把 SDK 关在最需要它的地方。enable 应由集成方控制。
2. **多 App**:同一套 SDK 可同时集成在多个 app 里,AI 能选择驱动哪一个。
3. **安全**:加 token/签名机制,确保即使 SDK 进了 release 包也不被滥用。
4. **边界**:进程托管 + 热重载(`run`/`reload`)是否该由本 skill 负责;`logs` 能否不依赖 `run` 直接拿到。

本 spec 与已 commit 的「派发健壮性修复 spec」(`2026-05-28-flutter-wright-orchestration-robustness-design.md`)**并列、互不冲突**:那份修方法名→脚本名映射与 goto 退出码;本份重塑 SDK 的启用/鉴权/多目标模型与 skill 的职责边界。两份都会动 `_lib.sh` 与「派发约定」,实现时需协调(见 §与派发修复 spec 的关系)。

## 目标 / 非目标

**目标**

- SDK 启用与鉴权完全交集成方:`enabled` 开关 + 可选 `token`,默认关、fail-safe。
- 端点完全外置:`base`(IP+端口)由集成方定义、在 skill 注册表配置;脚本零硬编码 host/port。
- 支持多 App:skill 侧目标注册表 `{name, base, token?, package?}`,AI 按 `name` 选目标。
- `logs` 改 `adb logcat`,去掉对 `run` 的依赖。
- 把进程托管簇(`run`/`reload`/`stop`)移出 skill,交上游 AI。
- skill 收敛为「驱动 + 观察一个已在运行、且已可达的 app」。

**非目标(明确不做)**

- 任何交互能力补全(swipe/drag/doubleTap/fillForm/网络抓包/状态求值)。
- 服务端发现的全自动端口扫描(注册表为准;探活按需)。
- 给 SDK 内置环境检测——集成方已有「正式包/测试包」判断,SDK 只暴露开关接线。

## 设计

### A. SDK 启用与鉴权

`FlutterWright.start()` 顶层新增两个参数,移除 `FlutterWrightConfig.enableInDebugOnly`:

```dart
static Future<void> start({
  bool enabled = false,          // 集成方接到自己已有的「测试包?」判断:start(enabled: AppEnv.isTestBuild, ...)
  String? token,                 // 集成方自定;为空=该端不鉴权(仅 loopback)
  FlutterWrightConfig config = const FlutterWrightConfig(),  // 仍含 host/port(设备侧 bind)、screenshotMode、maxBodyBytes 等
  NavigationAdapter? navigationAdapter,
  GlobalKey<NavigatorState>? navigatorKey,
  Iterable<String> routes = const <String>[],
}) async {
  if (!enabled) return;          // 默认关 = 安全;正式包传 false → 永不绑端口、无运行时攻击面
  // 绑 config.host:config.port(默认 127.0.0.1);若 token 非空,除 /health 外所有请求校验 X-FW-Token,不符回 401(常量时间比对)
}
```

- enable 完全由集成方接线(默认 `false`)。不再有 `kDebugMode` 绑定。
- token **可选、推荐**:传了就校验,空就不鉴权。威胁模型见 §安全。
- `host` 保持默认 `127.0.0.1`;**永不 `0.0.0.0`**(LAN 暴露)。
- 破坏性 API 变更(移除 `enableInDebugOnly`)→ SDK 升 **0.8.0**,CHANGELOG 写迁移说明(`enableInDebugOnly: true` 等价于 `enabled: kDebugMode`,需改写)。

### B. 端点外置 + 目标注册表

skill 侧维护**目标注册表**,每条 target 一个完整 `base` + 可选 token + 可选包名:

```
# 存 git 外:env FW_TARGETS 指向的配置文件(下例 YAML 仅作直观示意,JSON 等具体格式由实现定);token/base 都不进仓库、不进 SKILL.md
targets:
  - name:    shop-qa
    base:    http://127.0.0.1:9123      # 集成方定义,operator 填入(已 adb forward 后的本地可达地址)
    token:   <可留空>
    package: com.acme.shop              # logs 用
```

- `base` 是**脚本实际 curl 的本地可达地址**(经 adb forward 后通常是 `127.0.0.1:<localport>`)。
- 单条目时即默认目标;多条目而调用未带 `target=` → 报错提示选哪个。

### C. SDK 脚本改造(`_lib.sh` 集中 + 9 脚本)

跟 SDK 通话的 9 个脚本:`snapshot` / `tap` / `type` / `scroll` / `long_press` / `wait_for` / `goto` / `reset` / `health`。

- `_lib.sh` 新增 `fw_resolve_target`:从 `"$@"` 抽出 `target=<name>`(没有则取默认那条),读注册表,export `FW_BASE` / `FW_TOKEN` / `FW_PACKAGE`,并返回剥掉 `target=` 后的剩余参数供脚本自身解析。
- `fw_need_sdk` 改造:**删掉 `adb forward`**(可达性移到注册时,见 D);只探 `GET $FW_BASE/health`(不带 token),不可达退 12;保留 curl 存在性检查(13)。
- 各脚本 curl 改为:`curl ... $(fw_auth_header) "$FW_BASE/<endpoint>"`,其中 `fw_auth_header` 在 `FW_TOKEN` 非空时输出 `-H "X-FW-Token: $FW_TOKEN"`,空则不加。
- 「派发约定」参数表新增 `target=`。

### D. 可达性 = 注册 target 时建立

`adb forward` 不再每次调用自动做,改为**注册 target 时一次性建立**。提供轻量管理入口(脚本或文档化步骤),职责:写注册表条目 +(本地需要时)`adb forward tcp:<localport> tcp:<deviceport>`。

- 与「skill 不托管进程/可达性」的边界一致:skill 只驱动已可达的 app。
- emulator 直连 / 已有 forward / 隧道等场景,注册时不做 forward 即可。

### E. logs 改 adb logcat(adb-only,去 run 依赖)

`logs` 从「读 `run` 的 daemon `app.log`」改为读 logcat,对任何在跑的 app 都管用:

- 有 `package`(注册表):`pid=$(adb shell pidof -s <package>)` → `adb logcat -d --pid=$pid`。
- 无 `package`:回退 `adb logcat -d -s flutter`(所有 Flutter app 的 print,多 app 时会混)。
- `since=<n>` → `-t <n>`;`grep=<pat>` → 管道 grep。
- adb-only,不需 token / base。

### F. 移除进程托管簇 run / reload / stop

`run` / `reload` / `stop` 围绕「skill 持有 flutter daemon」而生;既然 skill 不再托管进程,三者一并移除(`stop` 没有 daemon 可停,`reload` 没有 daemon 可热重载)。

- 删 `run.sh` / `reload.sh` / `stop.sh`;退出码段 33-38 退役。
- 上游 AI 自行 `flutter run`(需自动化热重载时,自行用 `--machine` + FIFO,或其它方式)。
- SKILL.md 加迁移说明:进程托管/热重载不再由本 skill 负责。

### G. /health 不校验 token

`/health` 不要求 token,返回**存活 + 应用身份**(name/package/version),供 skill 发现/探活;动作端点全部 token-gated。身份泄露面很小,换取发现体验。

### H. SKILL.md / 方法面变更

- 方法数 18 → **15**(移除 run/reload/stop)。
- 新增「目标(target)」概念段:base/token/package 注册表、`target=` 选择、默认目标规则。
- 「派发约定」加 `target=`;保留派发修复 spec 的 camelCase→snake 规则。
- `logs` 文档改 logcat 语义;退出码表去掉 33-38,调整 logs(92)。
- references/methods.md 同步:9 个 SDK 方法签名加 `target=`;删 run/reload/stop;改 logs。

## 安全(威胁模型)

| 面 | 缓解 |
|---|---|
| 正式包被远程驱动 | `enabled=false` → 控制面不绑端口、无攻击面(**主防线,不靠 token**) |
| 测试包被同机其他 app 连 loopback | 可选 token;Android 上同机 app 通常能连到 `127.0.0.1:端口`,token 鉴权挡之 |
| adb 接入驱动 | 同上(token);仅绑 127.0.0.1 |
| snapshot 泄露满屏内容(手机号/验证码等) | token + 仅测试包启用 + 文档警示 |
| token 泄露 | token 只从 env/本地 config 读,**绝不进仓库 / SKILL.md / commit** |

要点:**配 base(IP+端口)只是"找得到",不是安全措施;安全来自 enable 开关(生产)+ 可选 token(测试包)。** token 可选,但分发面变广时强烈建议配置——文档须写明,避免会外发的测试包裸跑。

## 与派发修复 spec 的关系

- 两份都改 `_lib.sh` 与「派发约定」:派发修复加命名映射规则;本份加 `fw_resolve_target` + `target=`。实现时合并改动,避免互相覆盖。
- run/reload/stop 移除不影响派发修复涉及的 5 个 camelCase 方法(waitFor/longPress/pressKey/setViewport/resetViewport 全保留)。
- 建议:**先落派发修复 spec(小、独立、已审),再落本份**;或本份的 `_lib.sh` 改动包含派发修复的命名规则。

## 验收 / 测试

- **SDK**:`start(enabled:false)` → 不绑端口(无监听);`enabled:true, token:'x'` → 无/错 token 请求回 401,正确 token 200;`/health` 无 token 也 200 且含身份;`enabled:true, token:null` → 不鉴权可用。单元/集成测试覆盖。
- **脚本**:注册表含两条 target,`snapshot target=A` 打到 A 的 base、带 A 的 token;省略 `target=` 且多条目 → 报错;token 空的 target → 不发鉴权头仍可用。
- **logs**:配置 package 后按 PID 过滤;`since=`/`grep=` 生效;未 `run` 也能拿到(去依赖验证)。
- **移除**:run/reload/stop 脚本不存在;SKILL.md 方法表/退出码/references 无残留引用。
- **回归**:全部脚本 `bash -n`;两包 `flutter test` 全绿;既有导航/交互 e2e 适配 `enabled/token` 与端点外置(测试桩需带 token 或留空)。

## 范围与分期

本 spec 较大,建议实现时分期(由 writing-plans 细化排序):

1. **Phase 1(核心:适配性 + 安全)**:SDK `enabled`/`token`(A)+ 端点外置/单目标注册表(B 子集)+ 9 脚本 token/base 串联(C)+ /health 身份(G)。落地后即满足「release 可用 + 鉴权」。
2. **Phase 2(多 App)**:多目标注册表 + `target=` 选择 + 注册时 forward(B 全集、D)+ 探活/列举。
3. **Phase 3(边界清理)**:logs 改 logcat(E)+ 移除 run/reload/stop(F)+ SKILL.md/方法面收敛(H)。

## 风险 / 取舍

- **token 可选**:简单受控环境省 token 可接受,但分发面广时是风险——靠文档警示,不强制。
- **去掉自动 adb forward**:更灵活、更解耦,但首次注册需显式建可达性,turnkey 程度下降。
- **移除 run/reload**:丢开箱即用开发回路;上游 AI 需自理热重载(裸进程 reload 较繁)。换来 skill 单一职责。
- **破坏性 SDK API**:0.7.0 → 0.8.0,既有集成方需把 `enableInDebugOnly` 改写为 `enabled`。
- 端点外置依赖注册表正确性;`base` 配错只会连不上(快速失败),不引入安全风险。
