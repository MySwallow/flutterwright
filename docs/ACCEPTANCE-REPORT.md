# FlutterWright 验收报告

> 目标：在**无预装 Flutter 环境、无 Flutter 业务项目、无 Android 实体机**的机器上，
> 把 SDK 集成 → 运行 → skill 对接完全打通，证明现有功能**真实可用**（非纸面）。
>
> 验收机器：macOS (darwin arm64)，初始无 flutter / dart / adb / JDK。

## 结论速览

| 能力 | 验证方式 | 结果 |
|---|---|---|
| Flutter/Dart 工具链 | 安装 Flutter 3.44.0 (Dart 3.12.0) | ✅ |
| SDK 单元测试 | `flutter test`（mock/route/reload-handler） | ✅ 12/12 通过 |
| SDK HTTP 控制面 | 真实 curl 打 `/health /routes /navigate /mock /reset /screenshot` | ✅ |
| `goto`（导航） | 真实 `goto.sh` → curl → app，断言页面真的切换 | ✅ |
| `mock`（注入） | 真实 `mock.sh set` 后 UI 文案真的改变（已支付→已退款→脚本注入） | ✅ |
| `reset`（回根） | 真实 `reset.sh` → 页面 pop 回首页 | ✅ |
| `reload`（热重载） | `reload.sh` 在无 VM service 时按设计返回退出码 31 | ✅ 路径正确 |
| 截图像素管线 | `RenderRepaintBoundary.toImage→PNG` 产出合法 PNG | ✅ |
| SDK `/screenshot`（渲染树） | Android 模拟器实测返回 200 PNG（**修复了一处真实 bug**） | ✅ |
| `screenshot`（adb 整帧） | Android 模拟器实测 adb `screencap` → 真实 PNG | ✅ |
| `setViewport` / `resetViewport`（wm） | Android 模拟器实测 `wm size/density` happy path + 回读校验 | ✅ |
| `health`（完整 adb 链路） | Android 模拟器实测 devices/forward/curl 全链路 | ✅ |
| `reload`（自连 VM service） | `flutter run`+DDS 下自连被拒——架构/环境限制 | ⚠️ 见下 |

## 关键技术洞察

flutter_wright_sdk 的 HTTP 控制面是**纯 `dart:io HttpServer`**，与 Android 无关。因此
8 个 skill 方法里只有 2 个真正依赖设备（`screenshot` 走 `adb screencap`、`setViewport`
走 `wm size`）；其余 6 个是平台无关的纯 Dart，**无需真机即可真实验证**。

`flutter test` 的 `TestWidgetsFlutterBinding` 会把**进程内** `HttpClient` 全部 fake 成
返回 400。因此验收测试一律用**独立进程的真实 curl / skill bash 脚本**发起 HTTP —— 这
既绕开了 fake，也恰好是 skill 在生产里真实走的路径。

## 验收测试

新增 `packages/example/test/e2e_control_plane_test.dart`（4 个测试，全绿）：

1. **SDK 控制面：真实 curl 端到端** —— 启动真实 HTTP 服务（127.0.0.1:9123）+ 挂载真实
   example app，用 curl 验证 health/routes/navigate/mock/reset；断言：
   - `/navigate /order/detail` 后 `find.byType(OrderDetailPage)` 命中（导航真的发生）；
   - `/mock set order.status=已退款` 后再导航，页面文案真的从「已支付」变「已退款」；
   - `/reset clearMock=true` 后回到 `HomePage` 且 mock keys 清空。
2. **/screenshot 端点 + PNG 像素管线** —— `/screenshot` 在测试 binding 下根非
   RepaintBoundary，真实服务返回**设计内的 500**；同时用相同的 `toImage→PNG` 调用证明
   像素管线产出合法 PNG（magic 89 50 4E 47）。
3. **skill bash 脚本真实驱动真实 app** —— 经 marker 文件走脚本自身的 fast-path 跳过
   adb 检查，真实执行 `goto.sh /login`（→LoginPage）、`mock.sh set`（→「脚本注入」文案）、
   `reset.sh`（→HomePage），全部 `exitCode==0` 且 UI 断言命中。
4. **reload.sh 退出码** —— 无 VM service 时返回 31（与 SKILL.md 契约一致）。

复现：

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd packages/flutter_wright_sdk && flutter pub get && flutter test          # 12/12
cd ../example && flutter pub get && flutter test test/e2e_control_plane_test.dart  # 4/4
```

## skill ↔ SDK 对接机制（验证所得）

- skill 脚本通过 `curl` 把 JSON 指令 POST 到 `127.0.0.1:$VL_PORT`（默认 9123）。
- 每个方法首次调用先跑 `fw_ensure_health`：检查 adb→curl→设备→`adb forward`→`/health`，
  通过后写 marker `$CLAUDE_JOB_DIR/fw_health_done`，后续走 fast-path 跳过链路检查。
- **验证确认**：写入 marker 即可让脚本跳过 adb 检查，直接 curl 到本机服务（这正是无真机
  环境下驱动 desktop/test 进程的合法路径）。无 marker 且无 adb 时按设计 `exit 10`。

## 静态检查

`shellcheck -x skills/flutter-wright/scripts/*.sh` 仅 INFO 级提示（SC1091 source 跟踪误报、
SC1003 对 `*'\'*` 反斜杠匹配的提示，代码本身正确），无 warning/error。

## 设备特有命令（adb）

以下两条本质是**设备/模拟器特性**，逻辑为标准 adb 包装，经源码审查 + shellcheck 确认正确：

- `screenshot.sh`：`adb exec-out screencap -p > out.png` + PNG magic 校验（exit 20/21/22）。
- `setViewport` / `resetViewport`：`adb shell wm size/density` + 回读校验（exit 60/61）；
  `resetViewport` 恒 exit 0，可安全用于 cleanup。
- `health.sh` 完整链路（adb devices / adb forward）同样需要设备。

### Android 模拟器实测（完整 README 流程，真实跑通）

为兑现"全部都要解决"，在本机额外安装 JDK 17（openjdk@17，免 sudo）+ Android
cmdline-tools + 系统镜像，建无窗口 AVD（`system-images;android-35;google_apis;arm64-v8a`），
按 README quickstart 把 example app **真实构建并运行在模拟器上**：

```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
[flutter_wright_sdk] listening on http://127.0.0.1:9123   ← SDK 在真实设备内绑定
```

随后用 skill 脚本（真实 adb，**未**绕过 `fw_ensure_health`）逐条驱动：

| 命令 | 实测输出 | 退出码 |
|---|---|---|
| `health.sh` | `ok: device=emulator-5554 port=9123`（真实 adb devices/forward/curl） | 0 |
| `goto.sh /order/detail` | `{"ok":true,"route":"/order/detail"}` | 0 |
| `screenshot.sh` | `captured: /tmp/fw_order.png (19700 bytes)` PNG 320x640 RGBA | 0 |
| `mock.sh set` / `list` | `{"ok":true,"key":"order"}` / `keys:["order","product"]` | 0 |
| `set_viewport.sh 1080 1920 480` | `viewport: 1080x1920 @ 480dpi`，回读 `Override size: 1080x1920` | 0 |
| `set_viewport.sh 1080 2400 480` | 模拟器钳到 1080x1920，**回读校验正确检测并报错** | 61（设计内） |
| `reset_viewport.sh` | `restored: size=320x640 density=160` | 0 |
| `reset.sh` | `{"ok":true,"clearedMock":true}` | 0 |
| SDK `GET /screenshot` | **修复后** `http=200 ct=image/png size=17917`，PNG 经肉眼确认为订单页 | — |

SDK `/screenshot` 返回的渲染树截图经肉眼确认：标题「订单 ORD-001」、状态「已支付」、
金额「¥199.0」、两条商品行——即经 `/navigate` 导航 + 默认 mock 填充的真实页面。

## 发现的问题与处理

验收过程中暴露两处真实问题（这正是验收的价值）：

### 1. SDK `/screenshot`（flutter 渲染模式）恒返回 500 —— 已修复

- **根因**：`captureFlutterScreen` 读 `binding.rootElement.renderObject`，但它恒为
  `RenderView`（永远不是 `RenderRepaintBoundary`）；`FlutterWrightRoot` 安装的
  `RepaintBoundary` 位于该 View **之下**，故检查永不通过——`FlutterWrightRoot` 包装器
  形同虚设。在测试 binding 与真机 `runApp` 下都 100% 复现。
- **修复**（最小改动，未新增功能）：给 `FlutterWrightRoot` 的 `RepaintBoundary` 挂一个
  SDK 持有的 `GlobalKey`（`fwRepaintBoundaryKey`），`captureFlutterScreen` 优先经该 key
  定位边界，回退到旧的根检查。见 `packages/flutter_wright_sdk/lib/src/screenshot.dart`。
- **验证**：e2e 测试断言收紧为 `/screenshot == 200 + PNG`（修复前为 500，构成回归守卫）；
  模拟器实测 200 PNG 并肉眼确认。

### 2. `reload`（SDK 自连 VM service）在 `flutter run` 下连接被拒 —— 记录为架构/环境限制

- **证据**：`/reload` 报 `Connection refused`，目标端口**每次调用都变**（43572 → 50254），
  且都不在设备实际监听端口（`netstat`：9123 本 SDK、38835/8872 DDS/VM-service、5555 adb）之列。
  `dart:developer Service.getInfo().serverUri` 交回的是一个不可连接的临时 URI。
- **佐证**：`flutter run` 工具**自身**也连不上 VM service（`Error connecting to the service
  protocol ... Connection refused port 49966`）——确认是该模拟器下 VM-service/DDS 直连问题。
- **根因**：`flutter run` 启动的 DDS 独占 VM service，进程内"自连自己的 VM service 调
  `reloadSources`"这一设计与之冲突；且自连即便成功，没有 flutter 工具驱动的前端编译器也
  无法真正拾取源码改动。属**架构/环境限制**，非 wiring bug。
- **处理**：遵循"不新增功能"，**不**重构 reload 机制。`reload.sh` 对 500 的处理正确
  （→ exit 32）；单测覆盖了 handler 注册。本报告如实记录该限制。

## 给真机/模拟器用户的确切验证命令

```bash
# 1. 起模拟器或连真机后：
adb devices                                   # 至少一台 device
# 2. 在集成了 SDK 的 app 里 flutter run，等待 "[flutter_wright_sdk] listening ..."
adb forward tcp:9123 tcp:9123
curl http://localhost:9123/health             # {"ok":true,"version":"0.3.0",...}
# 3. 截图（设备整帧）：
adb exec-out screencap -p > /tmp/frame.png && file /tmp/frame.png   # PNG
# 4. viewport：
adb shell wm size 1080x2400 && adb shell wm density 480 && adb shell wm size
```

---

# 第二轮验收:通用性 + `dev_dependencies`(2026-05-25,SDK 0.3.0)

> 目标:解决 SDK 通用性差的问题 —— 真实项目可能是 GetX / Provider 架构、**路由方式完全不同**;
> 各项目**是否支持 mock、mock 方式也不同**;且这个库**理论上只应进 `dev_dependencies`**。

## 结论速览

| 问题 | 解决方案 | 验证方式 | 结果 |
|---|---|---|---|
| 导航硬编码 Navigator 1.0 `pushNamed` | 抽出 `NavigationAdapter`;`/navigate`、`/reset` 经它适配 | 单测 + e2e | ✅ |
| 路由方式完全不同(GoRouter/GetX) | `CallbackNavigationAdapter`(宿主给 `onNavigate`/`onReset` 闭包) | **真实 curl 驱动非 Navigator-1.0 声明式路由** | ✅ |
| 命名路由仍要简单可用 | `NavigatorKeyAdapter` 默认实现,`start()` 不传 adapter 时自动用 | 原 4 个 e2e 全绿(行为不变) | ✅ |
| mock 方式不同 / 项目不支持 mock | mock 本就是**可选接口**;不传 → `/mock` 返回 501 | 设计 + 文档 recipe | ✅ |
| 库应只在 `dev_dependencies` | `dev_dependencies` + 独立 `dev/main_dev.dart` 入口;`lib/` 零 SDK 引用 | analyze + 静态 import 证明 + release bundle 构建 | ✅ |
| mock 与 `lib/` 解耦 | `lib/` 定义本地 `DataStore` 接口;`dev/DevDataStore` 桥接 SDK 的 `MockDataProvider` | example 重构后 e2e 全绿 | ✅ |

## 改了什么(最小、向后兼容)

**SDK(`packages/flutter_wright_sdk`)**
- 新增 `lib/src/navigation_adapter.dart`:`NavigationAdapter` 抽象 + `NavigatorKeyAdapter`(默认)+ `CallbackNavigationAdapter`(逃生舱)。
- `NavigateHandler` / `ResetHandler` 改为依赖 `NavigationAdapter`,不再直接持有 `navigatorKey`。
- `FlutterWright.start` 新增可选 `navigationAdapter`;不传时 = `NavigatorKeyAdapter(navigatorKey)`,**完全向后兼容**。
- 导出三个新类型;版本 0.2.0 → **0.3.0**。

**example(`packages/example`)—— 重构为 dev_dependencies 范式**
- `lib/` 对 SDK **零引用**:新增 `lib/data/data_store.dart`(本地 `DataStore` 接口 + `StaticDataStore`)、`lib/app.dart`(根 widget 接受可注入 navigatorKey)。`lib/main.dart` 成为零 SDK 的生产入口。pages 改读 `DataStore`。
- 新增 `dev/`:`dev_data_store.dart`(`DevDataStore extends InMemoryMockDataProvider implements DataStore` —— 同一对象既是 SDK provider 又是 app 数据源,零胶水)、`dev/main_dev.dart`(唯一 import SDK 的 debug 入口)。
- `pubspec.yaml`:`flutter_wright_sdk` 从 `dependencies` 移到 `dev_dependencies`。

## 验证测试(全绿)

- SDK 单测 **18/18**(新增 `test/navigation_adapter_test.dart`:`CallbackNavigationAdapter` 正确转发 route+args+popUntilRoot、reset、readiness 门控)。
- example e2e **5/5**:
  - 原 4 个(control-plane / screenshot / skill 脚本 / reload)在重构后**仍全绿**,证明 `NavigatorKeyAdapter` 默认路径 + mock 解耦无回归。
  - **新增** `test/e2e_navigation_adapter_test.dart`:一个**故意不用 Navigator 1.0**的声明式路由 app(导航 = `ValueNotifier<String>` 驱动树重建,类比 GoRouter/GetX),经 `CallbackNavigationAdapter` 接到 SDK,用**真实 curl** 打 `/navigate /cart`、`/navigate /profile`、`/reset`,断言页面真的随之切换 —— 全程零 `pushNamed`。这是"路由架构无关"的端到端实证。

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd packages/flutter_wright_sdk && flutter analyze && flutter test     # 0 issues, 18/18
cd ../example && flutter analyze && flutter test                      # 0 issues, 5/5
```

## "生产零残留"如何证明

1. **静态 import 证明(airtight)**:Dart/Flutter 编译是导入可达性驱动的。`grep -rl "import 'package:flutter_wright_sdk" lib/` → **空**。生产入口 `lib/main.dart` 的传递 import 闭包 ⊆ `lib/`,故 release 产物不可能含 SDK。SDK 仅经 `dev/` 与 `test/` 进入。
2. **`flutter analyze` 干净**:`dev/`(在 `lib/` 之外)引用 dev_dependency 合法,不触发 `depend_on_referenced_packages`。
3. **依赖归类**:`flutter pub deps` 中 `flutter_wright_sdk` 在 dev 依赖侧。
4. **release 构建**:`flutter build bundle --release`(默认 `lib/main.dart`)成功。

> 启用自动化运行时改用 debug 入口:`flutter run -t dev/main_dev.dart`。

## mock 通用性说明

`MockDataProvider` 是**接口**,SDK 自身从不读 mock 数据,只把 `/mock` 指令路由给它 —— 因此与 Provider / Riverpod / GetX / BLoC 无关,宿主自行决定接到数据层哪一环。mock 完全**可选**:不传 `mockProvider`,`/mock` 返回 501,其余能力照常。example 用 `DataStore`(lib 本地接口)+ `DevDataStore`(dev 侧桥接)演示了在 `lib/` 不依赖 SDK 的前提下让 skill 仍能改 UI 数据。集成 recipe(含 GoRouter/GetX 导航、mock 分层、dev 入口)见 [`integration-guide.md`](./integration-guide.md)。

> **注(第三轮已推翻 mock):见下。**

---

# 第三轮验收:移除 mock + 精简集成(2026-05-25,SDK 0.4.0)

> 反馈:① mock 要改宿主数据层、成本太高、没人会接入 —— **伪需求**;② `dev/main_dev.dart` 可维护性差;③ 不需要低版本兼容。

## 处理

| 反馈 | 处理 | 验证 |
|---|---|---|
| mock 是伪需求 | **彻底移除**:删 `MockDataProvider` / `InMemoryMockDataProvider` / `POST /mock` / `start(mockProvider:)` / `mockProvider` getter;skill 删 `mock.sh`、`reset` 去掉 `clearMock`;`/reset` 只 pop 回根 | SDK 12/12、example 5/5 全绿;全仓 grep 无 mock 残留(除历史 specs) |
| main_dev 可维护性差 | 保留 dev_dependencies 零残留,但 `dev/main_dev.dart` 改为复用 `lib/app.dart` 的 `createApp()` 工厂 —— 不再重复 app 启动逻辑,dev 入口仅 ~8 行(start + 包 FlutterWrightRoot + 注入 key) | analyze 干净;`lib/` 仍零 SDK import;e2e 全绿 |
| 不需低版本兼容 | 直接破坏性删 API、清理 `start()` 签名,版本 0.3.0 → **0.4.0** | — |

## 移除后 SDK 的能力(全部低成本、架构无关)

`health` / `routes` / `navigate`(经 `NavigationAdapter`,Navigator 1.0 / GoRouter / GetX 通吃)/ `reset` / `screenshot`(adb 整帧 或 Flutter 渲染树)/ `reload`。这些都不要求改宿主数据层 —— 这正是"低成本、大部分项目能直接接入"的核心。

## 验证(全绿)

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd packages/flutter_wright_sdk && flutter analyze && flutter test   # 0 issues, 12/12
cd ../example && flutter analyze && flutter test                    # 0 issues, 5/5
```

- 文档全量同步去 mock:`api-reference`(删 `/mock`、`/reset` 去 clearMock)、`integration-guide`(删 mock 分层/auth 节,重编号)、`integration-guide-for-ai`(删 Step 5、pre-check ⑦、相关错误行)、`architecture`、`troubleshooting`、两个 README、`SKILL.md`(8→7 方法)。
- example 结构进一步简化:`lib/{main,app,demo_data,router,pages}` 全部零 SDK;`dev/main_dev.dart` 复用 `createApp()`。
