# SDK 可选化 + AI 持有 flutter run —— 设计 spec

**日期:** 2026-05-25
**状态:** 设计已认可,待写实施计划

## 目标

把 `flutter_wright_sdk` 从「所有 skill 方法的硬前提」降级为「只为 `goto`/`reset`(页面跳转)服务的可选增项」。截图与热重载不再依赖 SDK:截图走 `adb screencap`、热重载由 **AI 持有的 `flutter run --machine` daemon** 驱动。

一句话:**不集成 SDK,也能「人工开页面 + AI 截图 + AI 执行 reload」;集成 SDK 只额外解锁 `goto`/`reset`。**

## 背景与动机

现状(`feat/route-discovery-redesign` 分支,改动已 staged):

- 每个 skill 方法脚本开头都调用 `_lib.sh` 的 `fw_ensure_health`,其最后一步是 `GET /health`。没有 SDK 在跑 → exit 12,**连截图都走不到 `adb screencap` 那行**。
- `reload.sh` 走 SDK `POST /reload`(`reload_handler.dart` 内部用 `package:vm_service` 自连本进程 VM service)。但文档自己承认:`flutter run` 下 DDS 独占 VM service,SDK 的自连常被挤掉返回 503 —— 即 reload 在最主要的使用场景下基本不可用。

因此 SDK 实际上只有 `goto`/`reset`(以及 `FlutterWrightRoot` 的渲染树 `/screenshot`)是不可替代的;却被架成了所有能力的总闸门。本设计把依赖结构理顺。

## 改造后的能力矩阵

| 能力 | 底层依赖 | 需要 SDK? | 需要 AI 持有 flutter run? |
|---|---|---|---|
| **截图** | `adb exec-out screencap` | 否 | 否(任何在跑的 app 都能截) |
| **reload** | `flutter run --machine` daemon 的 `app.restart` | 否 | **是** |
| **goto / reset** | SDK HTTP `POST /navigate` `/reset` | **是** | 否(app 在跑 + 集成了 SDK 即可) |
| **setViewport / resetViewport** | `adb wm size/density` | 否 | 否 |

两种工作模式并存:

- **app 由 AI 起**(`run`)→ reload + 截图 + goto(若集成 SDK)全可用。
- **app 由你自己终端起**(或其它方式)→ 截图 + goto(若集成 SDK)可用,但 **reload 不可用**(AI 没持有那个进程,只能你自己在控制台按 `r`)。

## 组件设计

### 1. AI 持有 flutter run —— `flutter run --machine` daemon

用 Flutter 官方的 daemon JSON 协议(IDE 走的就是这个),比向交互控制台喂 `r` 键稳定:版本契约稳定、有结构化就绪事件、reload 成功/失败有结构化返回。

跨「无状态的逐方法 bash 调用」持有一个长生命周期进程,用 **FIFO + 日志文件 + 状态文件**(全部置于 `$CLAUDE_JOB_DIR`,job 结束自动清理):

- `$CLAUDE_JOB_DIR/fw_daemon.in` —— FIFO,向 daemon 喂命令。
- `$CLAUDE_JOB_DIR/fw_daemon.log` —— daemon 的 stdout(逐行 JSON 数组)。
- `$CLAUDE_JOB_DIR/fw_daemon.env` —— 记录 `appId` / `daemon_pid` / `holder_pid` / `device`。

启动序列(`run.sh`):

1. 定位 flutter 二进制(下方「flutter 定位」)。
2. 解析设备:`device=` 参数优先,否则取 `adb devices` 第一台。
3. `mkfifo $FIFO`;启动一个持有者保持 FIFO 写端常开,避免 daemon 读到 EOF 退出:`sleep infinity > $FIFO &`(记 `holder_pid`)。
4. `flutter run --machine -t <target> -d <device> < $FIFO > $LOG 2>&1 &`(记 `daemon_pid`,`disown`)。
5. 轮询 `$LOG`:从 `"event":"app.start"` 行抽 `appId`(grep/sed,**不引入 jq**),等到 `"event":"app.started"` 视为就绪(带超时,默认 180s)。
6. 写 `fw_daemon.env`,打印 `ok: appId=<id> device=<device>`。

`target` 默认 `lib/main.dart`;要用 `goto` 时由调用方传集成了 SDK 的 dev 入口(如 `dev/main_dev.dart`)。

### 2. `reload` 重写

`reload.sh` 不再碰 SDK,改为向 daemon 发热重载命令:

1. 读 `fw_daemon.env`;不存在 → 退出码 33 + 提示「先 `run`,或自己在 flutter run 控制台按 `r`」。
2. 校验 `daemon_pid` 仍存活(`kill -0`);已死 → 退出码 34。
3. 向 FIFO 写一行:`[{"id":<n>,"method":"app.restart","params":{"appId":"<id>","fullRestart":false,"pause":false,"reason":"manual"}}]`。
4. 轮询 `$LOG` 取匹配 `"id":<n>` 的响应(带超时);`"result":{"code":0` → 成功打印 `reloaded`;非 0 或超时 → 退出码 35 + 把 daemon 报的错带到 stderr。

> `fullRestart:false` = 热重载;热重启(`R`)本次不做(YAGNI,见「范围外」)。

### 3. `stop`(新增)

`stop.sh`:向 FIFO 写 `app.stop`,再 `kill` `daemon_pid` 与 `holder_pid`,删除 FIFO / env。**总是退出 0**(可安全用于清理钩子)。

### 4. env-check 重构 —— 从全局闸门到逐方法前提

废掉「任何方法首调必过 `/health`」的全局闸门。`_lib.sh` 拆成按能力分组的小检查,每个方法只调自己需要的那个:

- `fw_need_adb` —— `adb` 在 PATH + 至少一台设备(`adb` / 设备缺失退出码沿用 10 / 11)。截图、setViewport、`run` 用。
- `fw_need_curl` —— `curl` 在 PATH(13)。goto / reset 用。
- `fw_need_sdk` —— `fw_need_adb` + `adb forward tcp:$PORT` + `GET /health`(SDK 不可达 12)。**只** goto / reset 用。
- reload 不调上述任何一个;它只校验 owned daemon(33/34)。

`health` 方法收窄为「显式 SDK 探针」(等价 `fw_need_sdk` + 打印),只对 goto/reset 有意义。`fw_health_done` fast-path 标记保留(现在标记的是「SDK 探针已通过」)。

### 5. SDK 侧改动(破坏性)

- 删除 `lib/src/handlers/reload_handler.dart` 与 handler 列表中的 `ReloadHandler()`(`flutter_wright.dart:71` 及第 11 行 import)。
- 从 `pubspec.yaml` 移除 `vm_service` 依赖(经核实,仅 `reload_handler.dart` 用到)。
- `POST /reload` 端点随之消失。
- 版本号在本分支已 staged 的 `0.5.0` 基础上 bump 到 **`0.6.0`**(breaking),CHANGELOG 加条目。

### flutter 定位

机器上 `flutter` 不一定在 PATH(本机在 `/Users/mini/development/flutter/bin`)。`run.sh` 解析顺序:`$FLUTTER_BIN` 环境变量 → `command -v flutter` → 常见路径(`$HOME/development/flutter/bin/flutter`、`$HOME/flutter/bin/flutter`)→ 都没有则报清晰错误(新退出码 36)。

## 方法面(改造后)

| 方法 | 状态 | 说明 |
|---|---|---|
| `run <target> [device=<id>]` | **新增** | 后台启 `flutter run --machine`,等就绪,持有 daemon |
| `stop` | **新增** | 停止 daemon + 清理 |
| `reload` | **重写** | 向 owned daemon 发 `app.restart{fullRestart:false}` |
| `health` | 收窄 | 显式 SDK 探针(仅 goto/reset 相关) |
| `screenshot <out>` | 不变(解绑) | `adb screencap`;不再被 `/health` 闸门挡 |
| `goto <route> [...]` | 不变 | SDK `/navigate`;前提改为只查 `fw_need_sdk` |
| `reset` | 不变 | SDK `/reset`;同上 |
| `setViewport` / `resetViewport` | 不变(解绑) | `adb wm`;只查 `fw_need_adb` |

## 退出码(改造后)

| 区间 | 类别 |
|---|---|
| 0 | 成功 |
| 10-13 | 环境(10 adb / 11 设备 / 12 SDK 不可达 / 13 curl) |
| 20-22 | 截图 |
| 33-36 | reload / run(33 未 `run` / 34 daemon 已死 / 35 重载失败或超时 / 36 找不到 flutter) |
| 40-43 | 导航(goto) |
| 60-61 | Viewport |
| 70-71 | reset |

> 旧的 30-32(SDK `/reload`)废弃;reload 改用 33-35。

## 测试策略

daemon 驱动的 `run`/`reload`/`stop` 本质依赖真机 + 真实 flutter 进程,`flutter test` 进程内跑不了 → **手工在设备上验证**(spec 不强制单测,与项目既有取向一致)。可自动化的部分:

- **保留** `e2e_control_plane_test.dart` 里 `goto.sh`/`reset.sh` 真实驱动 SDK 的测试(机制未变)。
- **改写** 该文件中 `reload.sh` 那条测试(原断言 exit 0/31 测的是 SDK `/reload`):新断言为「未 `run`(无 `fw_daemon.env`)调 `reload.sh` → 退出码 33」的 bash 层契约测试。
- `goto.sh`/`reset.sh` 的 `fw_health_done` fast-path 注入技巧保留,但需适配新的 `fw_need_sdk` 标记语义。
- SDK 两包 `dart analyze` 干净;`flutter test` 全绿。

## 需要更新的文档

- `skills/flutter-wright/SKILL.md` —— 大改:硬前提段(line 12-20)从「SDK 必须运行」改为「按能力分前提」;「概念」「方法」表加 `run`/`stop`、改 `reload`、收窄 `health`;退出码总表;「何时使用」重写为「SDK 可选」视角。(注:该文件当前还有上次会话未提交的 prose 改动,实施时一并处理。)
- `docs/api-reference.md` —— 删 `POST /reload` 段;`/health` 版本号 0.6.0;`start()` 参数表不变。
- `docs/integration-guide.md` / `integration-guide-for-ai.md` —— 「你想用 reload」一行从「`FlutterWright.start()`」改为「让 AI `run` 你的 app(无需 SDK)」;reload 不再属 SDK 集成项。
- `docs/architecture.md` —— 控制面组件图去掉 ReloadHandler;补 daemon 持有模型。
- `docs/troubleshooting.md` —— reload 排查从「VM service / DDS」改为「未 `run` / daemon 已死 / flutter 定位」。
- `README.md` / 各 `README.md` —— 「SDK 是硬前提」表述改为「SDK 可选,只加跳转」。
- `packages/flutter_wright_sdk/CHANGELOG.md` —— 0.6.0 条目(移除 `/reload` + `vm_service`)。

## 前提与排序(重要)

本设计与上一项「路由发现重设计」动同一批文件(`flutter_wright.dart` handler 列表、SKILL.md、多份 docs、`pubspec.yaml` 版本号),而那批改动**当前 staged 在 `feat/route-discovery-redesign` 分支、尚未 commit**。

实施前需用户决定排序:

- **(a)** 先 commit 路由发现那批(0.5.0)→ 再在其上做本次(0.6.0);或
- **(b)** 本次叠加进同一批未提交改动,合成一次提交;或
- **(c)** 本次另起分支。

实施计划默认按 **(a)** 假设(在 0.5.0 已落地的基础上增量),具体以用户 commit 决策为准。

## 范围外(YAGNI)

- 热重启(`R` / `fullRestart:true`):用户只要 reload。
- iOS / 非 Android 设备。
- AI attach 到「你自己终端起的」flutter run 做 reload(即被否决的 VM service 旁路方案)。
- tmux/screen 等额外进程管理依赖(只用 coreutils + FIFO)。
- SDK 侧渲染树 `/screenshot`(`FlutterWrightRoot`)维持现状,本次不动。
