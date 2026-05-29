# 更新日志

## 0.8.0

### 新增
- 初始仓库脚手架（monorepo：skill + SDK + example + docs）。
- SDK `flutter_wright_sdk` 0.8.0：
  - 启用改为宿主显式控制 `FlutterWright.start({bool enabled = false})`，默认 `false` → 不绑定控制面（fail-safe）；已移除 `FlutterWrightConfig.enableInDebugOnly`，SDK 不再识别构建模式。
  - 可选 `X-FW-Token` 鉴权：`start({String? token})` 非空时除 `GET /health` 外所有请求须带匹配 token（常量时间比对，否则 401），`/health` 始终豁免。
  - snapshot-first 交互层，共 11 个 HTTP 端点：`GET /health` `/routes` `/snapshot` `/screenshot` `/wait_for`、`POST /navigate` `/reset` `/tap` `/long_press` `/scroll` `/type`。
  - 导航端点 `/navigate` `/reset` `/routes` 仅当传 `navigatorKey` 或 `navigationAdapter` 才注册，否则回 501。
  - 移除 `POST /reload` 端点。
- Skill `flutter-wright`：转为驱动已运行的 app（移除 `run`/`reload`/`stop` 进程托管），支持多目标 `FW_TARGETS`。

完整发布历史参见 `packages/flutter_wright_sdk/CHANGELOG.md`；设计动机参见 `docs/superpowers/specs/2026-05-28-flutter-wright-skill-sdk-redesign-design.md`。
