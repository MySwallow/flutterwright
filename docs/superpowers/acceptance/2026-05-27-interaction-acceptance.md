# 交互层验收 — 2026-05-27

> 对齐 Playwright MCP 的 snapshot-first 交互层(`flutter_wright_sdk` 0.7.0 + flutter-wright skill)。

## A. 自动验收(`flutter test`,已在本机可跑)

- [x] **`packages/flutter_wright_sdk`**:`flutter test` 全绿
  - `test/semantics_snapshot_test.dart`(serialize / resolve / containsText)
  - `test/semantics_action_test.dart`(tap / setText / scroll)
  - `test/start_navigation_test.dart`(未传 key → /navigate 回 501;传 key → 非 501)
- [x] **`packages/example`**:`flutter test --concurrency=1` 全绿
  - `test/e2e_control_plane_test.dart`(回归:health/routes/navigate/reset、`/screenshot` PNG、goto.sh/reset.sh、reload.sh exit 33)
  - `test/e2e_interaction_test.dart`(snapshot / type→tap / wait_for / navigate 回吐 snapshot / **脚本闭环**)
  - `test/e2e_navigation_adapter_test.dart`、`test/e2e_route_discovery_test.dart`(同源 SemanticsHandle 泄漏已修)
  - `test/getx_integration_test.dart`(**两个用例**:① 真实 GetMaterialApp + Get.toNamed 经 SDK 导航/args/reset;② **GetX 路径下 snapshot → type → tap 交互闭环**,证明交互层架构无关)
- [x] 两包 `flutter analyze lib/` 干净;`test/` 仅 `diag_test.dart`(本地诊断文件,untracked,不在范围)有 info。

> Note:`packages/example` 多个 e2e 都绑 9123——并发跑会撞端口,**用 `--concurrency=1`**(或给 `e2e_route_discovery_test.dart` 一样的独立端口 9125/9126 模式)。

## B. 真机手测(连一台开了 USB 调试的 Android,`Skill flutter-wright "run dev/main_dev.dart"`)

> 自动 e2e 跑在桌面 flutter_test(无 adb/真机);下列项需真机 + 真实 IME 验证。

### 观察
- [ ] `snapshot` 返回当前页语义树;登录/列表页元素都带 `[ref=sN]`。
- [ ] `screenshot /tmp/x.png` 出整帧 PNG(含状态栏)。
- [ ] `logs since=50` 打印 app 近期 `app.log`(需先 `run`)。

### 交互(snapshot-first)
- [ ] `tap "<x>" ref=<r>` 点中按钮,响应回吐的 snapshot 反映新页面。
- [ ] `type "<x>" ref=<r> text=... submit=true` 输入框出现文本、ENTER 提交生效(submit 走 adb keyevent 66)。
- [ ] **`type` 中文/Emoji 输入正常**(`userUpdateTextEditingValue` 路径,IME 无关)。
- [ ] **多输入框页面**:`type` 命中目标输入框,不误写到相邻输入框(几何匹配 + DPR 归一)。
- [ ] `scroll "<x>" ref=<r> dir=down` 长列表真的滚动(snapshot 出现新项的新 ref)。
- [ ] `longPress` 触发长按菜单/回调。
- [ ] `waitFor text=订单详情 timeout=3000` 目标出现即返回 200,不出现超时退 85。
- [ ] `pressKey enter|back|home`、`back`(adb keyevent,免 SDK)系统键生效。

### 导航降级
- [ ] **未传 navigatorKey** 的 `FlutterWright.start()` 下,`goto /x` 回「navigation not configured」(脚本退 41)。
- [ ] **传 navigatorKey**(如示例 `dev/main_dev.dart`)后 `goto`/`reset` 正常跳/回根。

### 进程
- [ ] `run dev/main_dev.dart` 起到 `app.started`;`reload`(改 Dart 后)生效;`stop` 干净退出。

## C. 退出码抽查

| 场景 | 期望脚本退出码 |
|---|---|
| 过期 ref → `tap` | 51 |
| 非输入框 → `type` | 54 |
| 非法 scroll dir(如 `dir=sideways`)→ `scroll` | 56 |
| `wait_for` 超时(条件不满足) | 85 |
| `logs` 未 `run` | 92 |
| `goto` 未传 navigatorKey(SDK 回 501) | 41 |

## D. 已知边界 / 偏差

- **`packages/flutter_wright_sdk/test/diag_test.dart`** 是本地诊断脚本(geometry/DPR 调查留下),`untracked`、不在仓库;analyze 会就此报 info,可忽略或本地删除。
- **`SemanticsHandle` 在 flutter_test 的释放时序**:`start()` 持有的 ensureSemantics 句柄必须在**测试体内** stop()(`_endOfTestVerifications` 早于 tearDown),既有/新 e2e 经 `withApp` / `withLoginApp` 包装器满足此约束。**生产真机不存在此约束**。
- **多 e2e 并发端口冲突**:多个 e2e 默认绑 9123,需 `--concurrency=1` 或文件内显式独立端口(参考 `e2e_route_discovery_test.dart` 的 9125)。
- **`setText` 实现**:走「几何匹配 EditableTextState + `userUpdateTextEditingValue`」而非 `SemanticsAction.setText`(后者 Flutter 不在 TextField 上暴露)。Unicode 安全,SDK-side,真实输入框命中靠全局矩形重叠面积。spec 第 1 节风险 #1 已通过此机制化解,真机 IME 行为由 B 段「中文/Emoji 输入正常」一项守护。

## 结论

- **通过条件**:A 段全勾(本机已验) + B/C 段在真机上全勾。
- 未达项请记录于此并附 issue 链接。
- 当前状态:A 段已通过(2026-05-27),B/C 段待真机验收。
