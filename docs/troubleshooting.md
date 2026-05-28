# 故障排查

按 "现象在哪一层暴露" 分组。涉及方法:`health` / `targets` / `snapshot` / `tap` / `type` / `scroll` / `goto` / `reset` / `screenshot` / `setViewport` / `resetViewport` / `logs`。(本 skill 不再托管 flutter 进程——`run`/`reload`/`stop` 已移除,见「起停 app / 热重载」段。)

## `health` 失败

> **退出码 12-15 来自需要 SDK 的方法(`snapshot`/`tap`/`type`/`scroll`/`longPress`/`waitFor`/`goto`/`reset`/`health`)** —— 它们要 `curl`(13)+ 目标注册表可解析(14 注册表缺失或空 / 15 目标歧义或未找到)+ `GET <base>/health` 通(12 不可达)。`screenshot`/`setViewport`/`resetViewport`/`pressKey`/`back`/`logs` 只查 `adb` + 设备(10/11)。可达性不再每次自动建,见 `targets forward`。

### exit 10:adb 未安装

```bash
# macOS
brew install --cask android-platform-tools
# Ubuntu
sudo apt install adb
# 验证
adb --version
```

### exit 11:无 adb 设备

```bash
adb devices
# 空 → 手机开 USB 调试,接受 RSA 指纹弹窗。
```

模拟器:

```bash
emulator -list-avds
emulator -avd <name> -no-snapshot-load &
```

### exit 12:SDK 在注册表 `base` 不可达

`base` 是目标注册表(`$FW_TARGETS`)条目里的本地可达地址(如 `http://127.0.0.1:9123`)。

- app 还在跑吗,且 `start(enabled: ...)` 的 `enabled` 为真?  `pgrep -f 'flutter run'`
- 可达性建了吗?  `Skill flutter-wright "targets forward target=<name>"` 跑一次 `adb forward`;`adb forward --list` 看有没有对应转发
- SDK 真的 bind 了?`flutter run` 输出应有 `[flutter_wright_sdk] listening on http://127.0.0.1:<port>`
- 本地端口被占?  `lsof -i :<port>`
- 不确定哪个目标连得上?  `Skill flutter-wright "targets"` 列举所有条目并逐条探活(HEALTH=ok/unreachable)

### exit 13:curl 未安装

`brew install curl` / `sudo apt install curl`。

## `goto` 失败

### exit 41 (HTTP 503): navigator not ready

App 在启动。两选一:
- 等 ~500ms 重试。
- `FlutterWright.start(autoStart: false)` + 第一帧后调 `FlutterWright.bind()`。

### exit 42 (HTTP 500): push failed

路由没匹配上 `onGenerateRoute`/`routes` map。查:

```bash
curl http://localhost:9123/routes   # 已注册的路由
```

`GET /routes` 返回 adapter 的 `discoverableRoutes`;若返回 `[]` 说明未配置 `routes:` 或 `routesProvider:`,属正常,不影响 `goto`。

### 页面切换但 UI 没刷新

通常是 state 没刷。`Skill flutter-wright "reset"` 回根,然后重新 `goto`。

## `screenshot` 失败

### exit 20/21 (empty 或 < 1KB)

设备屏幕灭了 → `adb shell input keyevent 26` 唤醒;锁屏 → 测试期间关闭锁屏。

### exit 22 (not PNG)

设备锁屏 / shell 吃掉了二进制流。先唤醒,再重试。

### 截图被缩放

漏了 `adb forward` 或 `wm size`/`wm density` 不匹配。`adb shell wm size` 查当前值。

如果 `setViewport` 后还有 Override 但分辨率不对,直接:

```bash
adb shell wm size reset
adb shell wm density reset
```

## 起停 app / 热重载(本 skill 不再托管)

`run` / `reload` / `stop` 已移除——本 skill 只驱动一个**已在运行**的 app,不托管 flutter 进程。对应操作改为:

- **起 app**:你自己 `flutter run`(集成 SDK 时跑 dev 入口,如 `flutter run -t dev/main_dev.dart`)。找不到 flutter 就把它加进 PATH——本 skill 不再代起进程,故无 `FLUTTER_BIN`。
- **热重载**:在你那个 `flutter run` 控制台按 `r`(需 hot restart 按 `R`)。
- **看日志**:`Skill flutter-wright "logs [since=<n>] [grep=<pat>]"` —— `adb logcat`,不依赖进程托管;注册表有 `package` 时按 pid 精确过滤,否则 `-s flutter`(见 `logs` 退出码 92 参数错 / 93 指定 package 未运行)。
- **建可达性**:`Skill flutter-wright "targets forward target=<name>"` 跑一次 `adb forward`(注册 target 时一次性建,不再每次自动)。

## `setViewport` 失败 / 任务结束后设备状态奇怪

### exit 61: wm 覆写被静默拒(厂商 ROM)

MIUI / HarmonyOS / ColorOS 等会拒 `wm size`/`wm density`。绕开:
- 不锁视口,接受设备默认。
- 换一台 stock Android 设备。

### 任务结束后 `wm size` 仍有 Override

```bash
adb shell wm size reset
adb shell wm density reset
```

App 卡在奇怪路由:`Skill flutter-wright "reset"` 或 `adb shell am force-stop <pkg>` 重启。

## snapshot / tap / type / scroll 相关

### snapshot 返回空(只有 `# (no semantics ...)` 占位)

`GET /snapshot` 返回的 YAML 只有注释行,没有任何节点。原因与排查:

- **没调 `FlutterWright.start()`**:SDK 的 `start()` 持有常开语义句柄(`ensureSemantics`)。若未调用,语义树为空。确认 `dev/main_dev.dart`(或对应入口)里有 `await FlutterWright.start(...)` 且在 `runApp` 之前。
- **`start()` 未启用**:`enabled` 默认 `false`,`start()` 直接 no-op、不开语义树。确认传了 `enabled: true`(或 `enabled: kDebugMode` 而当前是 debug 构建)——SDK 不再自动感知构建模式,启用与否由调用方传的 `enabled` 决定。
- **验证**:`curl http://localhost:9123/snapshot` 应返回包含节点的 YAML;`GET /health` 应回 `{"ok":true}`。

### `tap` / `type` / `scroll` / `long_press` 返回 404「ref not in latest snapshot」

ref 已过期 — 自上次 snapshot 后,UI 发生了变化(页面跳转、弹窗消失、列表刷新等),节点 ref 已失效。

**解决**:重新调 `GET /snapshot` 获取最新快照,用新 ref 重试操作。每次 UI 发生实质性变化后都应重新 snapshot。

### `type` 返回 422「not an editable text field」

目标节点不是可编辑输入框。可能原因:

- `<element>` / `<ref>` 对应的节点是普通 text 或 button,不是 TextField。
- 多输入框布局中坐标/ref 解析命中了错误节点。

**解决**:确认 `/snapshot` 里目标节点的角色是 `textfield`(而非 `text` 或其他),用该节点对应的 ref 重试。

### `goto` / `reset` 返回 501「navigation not configured」

host app 在调用 `FlutterWright.start()` 时没有传 `navigatorKey` 或 `navigationAdapter`,导致 SDK 不注册导航端点。

**解决**:按 integration-guide 的 §3 接入:Navigator 1.0 传 `navigatorKey: FlutterWright.navigatorKey` + 注入 `MaterialApp`;GoRouter/GetX 传对应 `CallbackNavigationAdapter`。只需交互(tap/type 等)不需要 goto 时,这个 501 是预期行为,无需处理。

---

## 平台限制 — "Android 上没问题,iOS 上不行"

v1 是 Android-only。原因:

- iOS Simulator 截图能用(`xcrun simctl io booted screenshot`),但脚本全用 `adb` 还没分流。
- iOS deep-link / port forward 没有 `adb forward` 直接等价物。

v2 计划支持 iOS — 见 spec §10.2。

---

## 附录:E2E 验证清单(release 前手动跑)

> 旧 `docs/e2e-checklist.md` 已并入这里。每次发新版前 clone 仓库后跑一遍。

### 前置条件

- macOS / Linux,装了 Flutter SDK 3.24+(`flutter doctor` 全绿)
- Android 真机 USB 调试已开,或 Android 模拟器在跑
- `adb devices` 显示设备状态为 `device`

### 第 1 步 — example app 生成平台脚手架

```bash
cd packages/example
flutter create . --platforms=android --org com.example.flutter_wright
flutter pub get
```

### 第 2 步 — SDK 单元测试

```bash
cd packages/flutter_wright_sdk
flutter pub get
flutter test
```

期望:`All tests passed!`。

### 第 3 步 — 启动 example app(你自己起)

在一个终端里(cwd = `packages/example`):

```bash
flutter run -t dev/main_dev.dart
# 等首帧;输出里应有 [flutter_wright_sdk] listening on http://127.0.0.1:9123
```

(`dev/main_dev.dart` 是集成了 SDK 的 debug 入口,`start(enabled: kDebugMode)` 解锁控制面 + goto;`lib/main.dart` 是零 SDK 生产入口。需要热重载就在这个控制台按 `r`。)

### 第 4 步 — 注册目标 + 端口转发 + 方法烟雾测试

先写目标注册表(git 外)并建可达性:

```bash
printf 'example|http://127.0.0.1:9123||com.example.flutter_wright\n' > /tmp/fw-targets
export FW_TARGETS=/tmp/fw-targets
Skill flutter-wright "targets forward target=example"
# → forwarded tcp:9123 -> device tcp:9123 (example)
```

在 Claude Code 会话里(任何 cwd,只要装了 skill 且 `FW_TARGETS` 已设):

```
Skill flutter-wright "targets"
# → 列出 example,HEALTH=ok

Skill flutter-wright "health"
# → ok: base=http://127.0.0.1:9123 package=com.example.flutter_wright

Skill flutter-wright "goto /home"
# → {"ok":true,"route":"/home"}  设备应跳到 /home

Skill flutter-wright "snapshot"
# → 当前页 Semantics YAML(可操作节点带 [ref=sN])

Skill flutter-wright "screenshot /tmp/fw-smoke.png"
# → captured: /tmp/fw-smoke.png (<size> bytes)

Skill flutter-wright "goto /order/detail"
# 设备应显示 order 详情页

# 改 example/lib/pages/home_page.dart 任一文字,在你的 flutter run 控制台按 r 热重载,设备应反映改动

Skill flutter-wright "setViewport 1080 2400 480"
# → viewport: 1080x2400 @ 480dpi

Skill flutter-wright "reset"
# → {"ok":true}

Skill flutter-wright "resetViewport"
# → restored: size=<orig> density=<orig>

Skill flutter-wright "logs since=50"
# → 最近 50 行 adb logcat(注册表有 package 时按 pid 过滤)
```

### 第 5 步 — 确认设备被还原

```bash
adb shell wm size       # 只有 Physical size,无 Override
adb shell wm density    # 只有 Physical density,无 Override
```

### 完成 = 烟雾序列各方法全部 exit 0 + 设备状态恢复
