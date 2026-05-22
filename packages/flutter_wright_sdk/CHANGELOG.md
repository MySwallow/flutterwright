# 更新日志

## 0.2.0 - 2026-05-22

### 新增
- `POST /reload` 接口:通过 `vm_service.reloadSources` 触发 Flutter 热重载(VM service 进程内 RPC)。
- 新增 `vm_service: >=14.0.0 <16.0.0` 依赖。

### 变更
- SDK 环境约束收紧:`flutter: >=3.24.0`,`sdk: >=3.5.0`(原 `3.10.0` / `3.0.0`)。
- 文档标注"作为 [flutter_wright](../../README.md) monorepo 的一部分发布"。

## 0.1.0 (首次发布)

- 仅 debug 启用的 HTTP server,默认绑 `127.0.0.1:9123`(可配置)。
- 接口:`/health`、`/routes`、`/navigate`、`/reset`、`/mock`、`/screenshot`。
- `MockDataProvider` 接口 + `InMemoryMockDataProvider` 默认实现。
- `FlutterWrightRoot` Widget 包装,让 app 内截图更可靠。
- Release 构建是 no-op(由 `kDebugMode` 守门)。
