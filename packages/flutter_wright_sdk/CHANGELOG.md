# 更新日志

## 0.7.0 - 2026-05-27

### 新增
- **snapshot-first 交互层**(对齐 Playwright MCP):
  - `GET /snapshot`(带 `[ref=sN]` 的 YAML 语义树,`SemanticsSnapshot.serialize`)。
  - `POST /tap` `/long_press` `/scroll` `/type`(经 `SemanticsOwner.performAction` /
    `EditableTextState.userUpdateTextEditingValue`,请求体 `element`+`ref`,
    成功响应**自动回吐** `snapshot`)。
  - `GET /wait_for?text=|ref=|gone= [&timeout=ms]`(轮询条件,408 超时)。
  - `start()` 持有 `SemanticsBinding.instance.ensureSemantics()` 句柄,
    强制常开语义树(无障碍服务未开时也能读到节点);`stop()` 释放。
- skill 侧脚本:`snapshot.sh` / `tap.sh` / `long_press.sh` / `type.sh`(含 `submit=`
  发 ENTER) / `scroll.sh` / `wait_for.sh`(SDK);`press_key.sh` / `back.sh`
  (adb keyevent,免 SDK);`logs.sh`(读 daemon `app.log`,免 SDK)。

### 变更
- **navigatorKey 降级为可选**:`FlutterWright.start()` 仅当传了 `navigatorKey` 或
  `navigationAdapter` 才注册 `/navigate` `/reset` `/routes`;否则这三个端点回 501
  「navigation not configured」。交互闭环只需 `start()` 即可。
- `/navigate` `/reset` 的成功响应也附 `snapshot` 字段(与 /tap 等动作一致)。
- 示例 `dev/main_dev.dart` 显式传 `navigatorKey: FlutterWright.navigatorKey`。

### 测试 / 兼容
- 单元测试:`semantics_snapshot_test`、`semantics_action_test`、
  `start_navigation_test`(SDK)。
- E2E:`e2e_interaction_test`(snapshot/type→tap/wait_for/navigate 回吐)。既有
  `e2e_control_plane_test` 与各 example 测试改造 `withApp` 在测试体内 stop()
  以释放 SDK 持有的 `SemanticsHandle`(flutter_test 的 invariant 检查早于 tearDown)。
- API 全部兼容 Flutter 3.24(已下限)~3.44。

## 0.6.0 - 2026-05-25

> **破坏性变更。**

### 移除
- `FlutterWright.start(testRoutes:)` 参数；`FlutterWright.routes`(`RouteRegistry`)
  静态字段；`src/route_registry.dart` 整个文件及其 barrel export。路由发现改由
  `NavigationAdapter.discoverableRoutes` 提供。
- `POST /reload` 端点与 `ReloadHandler`;`vm_service` 依赖。热重载改由 flutter-wright skill
  经 `run` 持有的 `flutter run --machine` daemon(`app.restart`)驱动,不再经 SDK。SDK 自此
  只负责 `goto`/`reset`(导航)与 `/screenshot`(`FlutterWrightRoot`)、`/health`。

### 新增
- `NavigationAdapter.discoverableRoutes`(可选,默认 `null`):`GET /routes` 的唯一来源。
- `NavigatorKeyAdapter(.., {routes})` 与 `CallbackNavigationAdapter(.., {routesProvider})`
  用于喂路由发现。
- `FlutterWright.start({navigatorKey, routes})`:可传宿主自有 navigatorKey;`routes`
  路由名列表喂 `GET /routes`(取代 `testRoutes`)。
- (skill 侧)`run` / `stop` 方法:AI 持有一个后台 `flutter run --machine` daemon;`reload`
  重写为驱动该 daemon。env-check 从全局 `/health` 闸门拆为逐方法前提。

### 修复
- 统一版本号:`pubspec.yaml` 与代码 `version` 常量对齐为 0.6.0。

### 迁移
- `start(testRoutes: [...])` → Navigator 1.0(map)用 `start(routes: map.keys)`;
  Navigator 1.0(onGenerateRoute)暴露一次路由名常量 `start(routes: AppRouter.names)`;
  其他栈把路由放进 adapter 的 `routesProvider`。
- 自定义 `implements NavigationAdapter` 的 adapter 需补一行
  `Iterable<String>? get discoverableRoutes => null;`(不可枚举时)。
- 用过 `POST /reload` 或 skill `reload`(走 SDK)的:改用 flutter-wright skill 的 `run` 起 app,
  `reload` 即驱动该 daemon;或在自己的 flutter run 控制台按 `r`。

## 0.4.0 - 2026-05-25

> **破坏性变更。** 不保证低版本兼容。

### 移除
- **整个 mock 能力**:`MockDataProvider`、`InMemoryMockDataProvider`、`POST /mock`
  端点、`FlutterWright.start(mockProvider:)` 参数、`FlutterWright.mockProvider` getter
  全部删除。理由:让 `/mock` 真正改 UI 需要宿主把 provider 接进 repository/数据层,
  对大部分真实项目改动量太大、几乎没人会接入 —— 属伪需求。SDK 聚焦真正低成本、
  架构无关的能力(navigate / screenshot / routes / reset / reload / health)。
  - 配套移除 skill 的 `mock` 方法(`scripts/mock.sh`)与 `reset` 的 `clearMock` 参数;
    `POST /reset` 现在只接受空 body、只把 navigator pop 回根。

### 变更
- `ResetHandler` 不再持有 mock,只驱动 `NavigationAdapter.reset()`。
- 示例 app 去掉 mock 桥接(`DataStore` / `DevDataStore`),`dev/main_dev.dart` 复用
  `lib/app.dart` 的 `createApp()` 工厂,不再重复 app 启动逻辑(改善 dev 入口可维护性)。

## 0.3.0 - 2026-05-25

### 新增
- **可插拔导航(`NavigationAdapter`)**:`/navigate` 与 `/reset` 不再硬编码
  Navigator 1.0 的 `pushNamed`/`popUntil`,改为经 `NavigationAdapter` 适配,
  从而**路由架构无关**(Navigator 1.0 / GoRouter / GetX / auto_route 等)。
  - `NavigatorKeyAdapter` —— 默认实现(命名路由,行为同旧版)。
  - `CallbackNavigationAdapter` —— 逃生舱:宿主提供 `onNavigate`/`onReset`
    两个闭包,适配 GoRouter `router.go`、GetX `Get.toNamed` 等任意栈。
  - `FlutterWright.start` 新增可选参数 `navigationAdapter`;不传时默认
    `NavigatorKeyAdapter(navigatorKey)`,**完全向后兼容**。

### 变更
- 推荐集成方式改为 **`dev_dependencies` + 独立 debug 入口**(`dev/main_dev.dart`),
  使生产 `lib/` 对 SDK 零引用、release 构建零残留。`packages/example` 已按此范式重构
  (mock 经 app 本地 `DataStore` 接口解耦,`DevDataStore` 在 `dev/` 桥接 SDK 的
  `MockDataProvider`)。详见 `docs/integration-guide.md`。

### 修复
- `GET /screenshot`（flutter 渲染模式）恒返回 500 的真实 bug:`captureFlutterScreen`
  原先读取 `binding.rootElement.renderObject`(恒为 `RenderView`,永远不是
  `RenderRepaintBoundary`),导致 `FlutterWrightRoot` 包装器形同虚设。现改为给
  `FlutterWrightRoot` 的 `RepaintBoundary` 挂 `GlobalKey`(`fwRepaintBoundaryKey`)并经其定位
  捕获,回退到旧的根检查。Android 模拟器实测返回 200 PNG。

## 0.2.0 - 2026-05-22

### 新增
- `POST /reload` 接口:通过 `vm_service.reloadSources` 触发 Flutter 热重载(VM service 进程内 RPC)。
- 新增 `vm_service: >=14.0.0 <16.0.0` 依赖。

### 变更
- SDK 环境约束收紧:`flutter: >=3.24.0`,`sdk: >=3.5.0`(原 `3.10.0` / `3.0.0`)。
- 文档标注"作为 [flutter-wright](../../README.md) monorepo 的一部分发布"。

## 0.1.0 (首次发布)

- 仅 debug 启用的 HTTP server,默认绑 `127.0.0.1:9123`(可配置)。
- 接口:`/health`、`/routes`、`/navigate`、`/reset`、`/mock`、`/screenshot`。
- `MockDataProvider` 接口 + `InMemoryMockDataProvider` 默认实现。
- `FlutterWrightRoot` Widget 包装,让 app 内截图更可靠。
- Release 构建是 no-op(由 `kDebugMode` 守门)。
