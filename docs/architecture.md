# 架构

## 整体分层

flutter_wright 是 monorepo,既是 Claude Code skill,也拥有 `flutter_wright_sdk` SDK + demo + 技术文档。在更大的"Flutter UI 自动化"分层里它是 **Layer 2b**(设备/Flutter app 驱动)。

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
                  |  Skill flutter_wright "..."
                  v
+--------------------------------------+
|  Layer 2b: flutter_wright (本仓库)    |
|  - 8 Playwright-style methods        |
|  - skills/flutter_wright/SKILL.md     |
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
|  - /health /routes /navigate /reset  |
|  - /mock /screenshot /reload (新)    |
+--------------------------------------+
```

## 组件

### SDK (`packages/flutter_wright_sdk`)

- **`FlutterWright`** 门面 — start/stop,暴露 `navigatorKey`、`routes`。
- **`FlutterWrightHttpServer`** — `dart:io HttpServer` 绑 `127.0.0.1:9123`(可配置),按 `path + method` 分发请求给 handler。
- **Handlers** — 每个 endpoint 一个文件,继承 `Handler` 抽象基类,通过 `ctx.request.writeJson/writeOk/writeError` 写响应。
- **`RouteRegistry`** — 包装宿主 app 的命名路由表;`GET /routes` 列出注册的路由。
- **`MockDataProvider`** — 宿主实现的接口。默认提供 `InMemoryMockDataProvider`。SDK 自身不读 mock 数据 — 只把控制命令路由给 provider。
- **`FlutterWrightRoot`** — 可选 Widget 包装,让 `/screenshot` 可靠工作(提供 `RepaintBoundary`)。
- **`ReloadHandler` (0.2.0+)** — 调 `vm_service.reloadSources` 触发本进程的 Flutter hot reload。

### Skill (`skills/flutter_wright`)

- **`SKILL.md`** — 唯一对外接口,Playwright-style 8 methods 定义 + dispatch convention。
- **`scripts/`** — 8 个 bash 脚本(`health.sh / goto.sh / screenshot.sh / reload.sh / set_viewport.sh / reset_viewport.sh / mock.sh / reset.sh`),封装 adb / curl / printf 细节。

## 双仓库职责

| 仓库 | 内容 | 职责层 |
|---|---|---|
| `flutter_wright/`(本仓库) | SKILL + 8 scripts + SDK + example + docs | Layer 2b 设备/Flutter app 驱动 |
| `flutter-visual-loop/`(瘦身后) | SKILL + 编排逻辑 | Layer 2a UI 还原循环编排 |

## 安全约束

- 当 `kDebugMode == false` 时,SDK 拒绝启动(默认 config 守门)。
- Server 仅绑 `127.0.0.1`,不暴露到 LAN。
- `adb wm size` / `wm density` 覆写由 skill 记录到 `$CLAUDE_JOB_DIR/fw_original.env`,任务结束或任何失败路径必须调 `Skill flutter_wright "resetViewport"` 还原。
- `/reload` 端点要求本进程 VM service 可用 — release 构建下 VM service 自动关闭,端点返 503,无安全暴露。
- 每个 endpoint 在 debug console 输出一行汇总;超 `maxBodyBytes`(默认 1 MiB)的请求返 413。

## 故意**不**做的事(v1)

- iOS 支持 — 全 adb-only。
- UI 交互(tap/swipe/text input) — 留 v2。
- Widget tree 检视 / locator — 留 v2。
- 视觉对比 — 在上层 Layer 2a 由 LLM 完成。
- Figma 客户端 — 上层 skill 用现有的 `figma-context` MCP。
