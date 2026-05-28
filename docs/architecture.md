# 架构

## 整体分层

flutter-wright 是 monorepo,既是 Claude Code skill,也拥有 `flutter_wright_sdk` SDK + demo + 技术文档。在更大的"Flutter UI 自动化"分层里它是 **Layer 2b**(设备/Flutter app 驱动)。

```
+--------------------------------------+
|  Layer 1: Higher-level user goals    |
|  - "UI 还原循环",E2E 测试,etc.        |
+--------------------------------------+
                  |
                  v
+--------------------------------------+
|  Layer 2a: Orchestration skills      |  (本仓库外:flutter-visual-loop 等)
|  - 读设计稿、视觉对比、改 Dart        |
+--------------------------------------+
                  |  Skill flutter-wright "..."
                  v
+--------------------------------------+
|  Layer 2b: flutter-wright (本仓库)    |
|  - 9 Playwright-style methods        |
|  - skills/flutter-wright/SKILL.md     |
+--------------------------------------+
                  |  bash scripts/*.sh
                  v
+--------------------------------------+
|  adb forward + curl                  |
|  adb exec-out screencap              |
+--------------------------------------+
                  |
                  v
+--------------------------------------+
|  Host Flutter app + flutter_wright_sdk SDK |
|  - HTTP server on 127.0.0.1:9123     |
|  - /health /snapshot /wait_for       |
|  - /tap /long_press /scroll /type    |
|  - /routes /navigate /reset          |
|  - /screenshot                        |
+--------------------------------------+
```

## 组件

### SDK (`packages/flutter_wright_sdk`)

- **`FlutterWright`** 门面 — start/stop,暴露 `navigatorKey`;`start(navigationAdapter:, navigatorKey:, routes:)` 注入路由适配器与可发现路由列表。`start()` 持有常开语义句柄(`SemanticsBinding.instance.ensureSemantics()`),`stop()` 释放。仅当传了 `navigatorKey` 或 `navigationAdapter` 才注册 `/navigate` `/reset` `/routes`;否则这三个端点回 **501**。
- **`SemanticsSnapshot`** — 纯逻辑单元。将语义树序列化为 Playwright 风格 YAML,附 `[ref=sN]` 节点标识符;提供 ref 解析(ref → `SemanticsNode`)与文本搜索能力。
- **`SemanticsActions`** — 封装语义交互。经 `SemanticsOwner.performAction` 执行 tap/longPress/scroll;经 `EditableTextState.userUpdateTextEditingValue` 执行 type(输入框写字)。
- **`FlutterWrightHttpServer`** — `dart:io HttpServer` 绑 `127.0.0.1:9123`(可配置),按 `path + method` 分发请求给 handler。
- **Handlers** — 每个 endpoint 一个文件,继承 `Handler` 抽象基类:SnapshotHandler / TapHandler / LongPressHandler / TypeHandler / ScrollHandler / WaitForHandler(交互层),NavigateHandler / ResetHandler / RoutesHandler(导航层,仅配置了 adapter 时注册),NavNotConfiguredHandler(未配置导航时的 501 占位),ScreenshotHandler / HealthHandler。
- **`NavigationAdapter`** — 把 `/navigate`、`/reset` 与路由栈解耦。`NavigatorKeyAdapter`(默认,命名路由)/ `CallbackNavigationAdapter`(GoRouter、GetX 等任意栈)。`GET /routes` 返回 adapter 的 `discoverableRoutes`;未配置时为 `[]`。
- **`FlutterWrightRoot`** — 可选 Widget 包装,让 `/screenshot` 可靠工作(提供 `RepaintBoundary`)。
### Skill (`skills/flutter-wright`)

- **`SKILL.md`** — 唯一对外接口,Playwright-style 9 methods 定义 + dispatch convention。
- **`scripts/`** — 9 个 bash 脚本(`run.sh / stop.sh / health.sh / goto.sh / screenshot.sh / reload.sh / set_viewport.sh / reset_viewport.sh / reset.sh`),封装 flutter daemon / adb / curl 细节。reload 经 `run` 持有的 `flutter run --machine` daemon(`app.restart`),不经 SDK。

## 双仓库职责

| 仓库 | 内容 | 职责层 |
|---|---|---|
| `flutter-wright/`(本仓库) | SKILL + 9 scripts + SDK + example + docs | Layer 2b 设备/Flutter app 驱动 |
| `flutter-visual-loop/`(瘦身后) | SKILL + 编排逻辑 | Layer 2a UI 还原循环编排 |

## 安全约束

- 当 `kDebugMode == false` 时,SDK 拒绝启动(默认 config 守门)。
- Server 仅绑 `127.0.0.1`,不暴露到 LAN。
- `adb wm size` / `wm density` 覆写由 skill 记录到 `$CLAUDE_JOB_DIR/fw_original.env`,任务结束或任何失败路径必须调 `Skill flutter-wright "resetViewport"` 还原。
- 每个 endpoint 在 debug console 输出一行汇总;超 `maxBodyBytes`(默认 1 MiB)的请求返 413。

## 集成分层

| 级别 | 需要什么 | 解锁能力 |
|---|---|---|
| **零集成** | 只需 `adb` + skill `run` | `run` / `reload` / `stop` / `screenshot`(adb screencap) / `setViewport` / `resetViewport` |
| **`FlutterWright.start()`** | SDK 加进 app,`start()` 无需任何 navigatorKey | 全套交互:snapshot / tap / type / scroll / longPress / waitFor;`health` 也走这条 |
| **+ `navigatorKey` 或 `navigationAdapter`** | 在 `start()` 传入 | 导航:goto(`/navigate`) / reset(`/reset`) / `GET /routes` 路由发现 |
| **+ `FlutterWrightRoot`** | 用 Widget 包根 | `/screenshot` 纯渲染树截图(不含 OS chrome) |

## 故意**不**做的事(v1)

- iOS 支持 — 全 adb-only。
- 视觉对比 — 在上层 Layer 2a 由 LLM 完成。
- Figma 客户端 — 上层 skill 用现有的 `figma-context` MCP。
