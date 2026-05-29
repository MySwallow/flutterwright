# 架构

## 整体分层

flutter-wright 是 monorepo,既是 Claude Code skill,也带 `flutter_wright_sdk` SDK + demo + 技术文档。在更大的"Flutter UI 自动化"分层里它处于 **Layer 2b**(设备/Flutter app 驱动)。

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
|  - Playwright 风格交互方法 + 导航/截图/视口/按键/多目标(共 16 个) |
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

- **`SKILL.md`** — 唯一对外接口,Playwright 风格交互方法(snapshot/tap/type/scroll/longPress/waitFor 等)+ 导航/截图/视口/按键/多目标方法(共 16 个)定义 + dispatch convention。
- **`scripts/`** — 一组 bash 脚本(`_lib.sh / back.sh / goto.sh / health.sh / logs.sh / long_press.sh / press_key.sh / reset.sh / reset_viewport.sh / screenshot.sh / scroll.sh / set_viewport.sh / snapshot.sh / tap.sh / targets.sh / type.sh / wait_for.sh`,共 17 个),封装 adb / curl / 目标注册表细节。skill 只驱动**已经运行**的 app,不托管进程:起 app 由用户自己 `flutter run`,热重载由用户在自己的 `flutter run` 控制台按 `r`(skill 不再持有 daemon)。

## 双仓库职责

| 仓库 | 内容 | 职责层 |
|---|---|---|
| `flutter-wright/`(本仓库) | SKILL + scripts(交互/导航/截图/视口/多目标封装)+ SDK + example + docs | Layer 2b 设备/Flutter app 驱动 |
| `flutter-visual-loop/`(瘦身后) | SKILL + 编排逻辑 | Layer 2a UI 还原循环编排 |

## 安全约束

- 启用由宿主 `enabled` 标志显式控制(`start({bool enabled = false})`,默认 `false` → 立即返回、不绑定控制面,fail-safe);SDK 不再自动识别构建模式(常用 `enabled: kDebugMode` 在 release 关闭,提测包用 `enabled: AppEnv.isTestBuild`)。
- 可选 `token` 鉴权:`start(token:)` 非空时除 `GET /health` 外所有端点校验 `X-FW-Token`,缺失/错误返 **401**(常量时间比对);为空则仅靠 loopback 保护。
- Server 仅绑 `127.0.0.1`,不暴露到 LAN。
- `adb wm size` / `wm density` 覆写由 skill 记录到 `$CLAUDE_JOB_DIR/fw_original.env`,任务结束或任何失败路径必须调 `Skill flutter-wright "resetViewport"` 还原。
- 每个 endpoint 在 debug console 输出一行汇总;超 `maxBodyBytes`(默认 1 MiB)的请求返 413。

## 集成分层

| 级别 | 需要什么 | 解锁能力 |
|---|---|---|
| **零集成** | 只需 `adb`(起停 app 由用户自行 `flutter run`) | `screenshot`(adb screencap) / `setViewport` / `resetViewport` |
| **`FlutterWright.start()`** | SDK 加进 app,`start()` 无需任何 navigatorKey | 全套交互:snapshot / tap / type / scroll / longPress / waitFor;`health` 也走这条 |
| **+ `navigatorKey` 或 `navigationAdapter`** | 在 `start()` 传入 | 导航:goto(`/navigate`) / reset(`/reset`) / `GET /routes` 路由发现 |
| **+ `FlutterWrightRoot`** | 用 Widget 包根 | `/screenshot` 纯渲染树截图(不含 OS chrome) |

## 故意**不**做的事(v1)

- iOS 支持 — 全 adb-only。
- 视觉对比 — 在上层 Layer 2a 由 LLM 完成。
- Figma 客户端 — 上层 skill 用现有的 `figma-context` MCP。
