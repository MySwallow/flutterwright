# 更新日志

## 0.2.0 - 2026-05-22

### Added
- `POST /reload` endpoint:Flutter hot reload via `vm_service.reloadSources`(VM service in-process RPC)。
- `vm_service: >=14.0.0 <16.0.0` 依赖。

### Changed
- SDK 环境约束收紧:`flutter: >=3.24.0`,`sdk: >=3.5.0`(原 `3.10.0` / `3.0.0`)。
- "shipped as part of [flutterwright](../../README.md) monorepo"。

## 0.1.0 (首次发布)

- 仅 debug 启用的 HTTP server,默认绑 `127.0.0.1:9123`(可配置)。
- Endpoints: `/health`, `/routes`, `/navigate`, `/reset`, `/mock`, `/screenshot`。
- `MockDataProvider` 接口 + `InMemoryMockDataProvider` 默认实现。
- `VisualLoopRoot` Widget 包装,让 app 内截图更可靠。
- Release 构建是 no-op(由 `kDebugMode` 守门)。
