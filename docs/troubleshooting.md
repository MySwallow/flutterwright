# 故障排查

按 "现象在哪一层暴露" 分组。所有方法名为 flutter-wright v1 命名(`run/stop/health/goto/screenshot/reload/setViewport/resetViewport/reset`)。

## `health` 失败

> **退出码 10-13 来自需要 SDK 的方法(`goto`/`reset`/`health`)** —— 它们检查 `adb` + 设备 + `adb forward` + `GET /health`。`screenshot`/`setViewport`/`run` 只查 `adb` + 设备(10/11)。`reload` 不查这些,只校验 owned daemon(见下方 `reload` 段)。

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

### exit 12:SDK 在 `127.0.0.1:9123` 不可达

- `flutter run` 还在跑吗?  `pgrep -f 'flutter run'`
- 端口转发?  `adb forward --list | grep 9123`(没有就 `adb forward tcp:9123 tcp:9123`)
- SDK 真的 bind 了?`flutter run` 输出应有 `[flutter_wright_sdk] listening on http://127.0.0.1:9123`
- 主机上 9123 被占?  `lsof -i :9123`

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

## `reload` 失败

新模型:`reload` 向本 skill `run` 持有的 `flutter run --machine` daemon 发 `app.restart`,**不经 SDK**。

### exit 33: 没有 owned daemon

没 `run` 过(无 `$CLAUDE_JOB_DIR/fw_daemon.env`),或你自己终端起了 flutter run(本 skill 持有不了)。两选一:
- 先 `Skill flutter-wright "run dev/main_dev.dart"` 让 AI 起 app;
- 你自己终端起的就在那个控制台按 `r`。

### exit 34: daemon 已死

`run` 起的进程退出了(可能 app crash 或被 kill)。看 `$CLAUDE_JOB_DIR/fw_daemon.log`,重新 `run`。

### exit 35: 重载失败或超时

dart 编译错误(语法错、`main()` 改了需 hot restart),或 60s 内没拿到响应。看 `$CLAUDE_JOB_DIR/fw_daemon.log` 末尾的 reload 结果。需要 hot restart 时 v1 未暴露,临时 workaround:`stop` 后重新 `run`。

### exit 36: 找不到 flutter(`run`)

`run` 定位不到 flutter 二进制。设 `FLUTTER_BIN=/path/to/flutter`,或把 flutter 加进 PATH。

### exit 38: app 未在 180s 内启动(`run`)

看 `$CLAUDE_JOB_DIR/fw_daemon.log`:常见是 build 失败、设备未授权、或 target 入口路径错。

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
- **release / profile 构建**:`kDebugMode == false` 时 SDK 自动不启动(no-op),语义树不会开启。确认是 debug 构建。
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

### 第 3 步 — 用 skill 启动 example app

在 Claude Code 会话里(cwd 切到 `packages/example`):

```
Skill flutter-wright "run dev/main_dev.dart"
# → ok: appId=<id> device=<id> target=dev/main_dev.dart
```

(`dev/main_dev.dart` 是集成了 SDK 的 debug 入口,启用 goto;`lib/main.dart` 是零 SDK 生产入口。)

### 第 4 步 — 端口转发 + 方法烟雾测试

在 Claude Code 会话里(任何 cwd 都行,只要安装了 flutter-wright skill):

```
Skill flutter-wright "health"
# → ok: device=<id> port=9123

Skill flutter-wright "goto /home"
# → {"ok":true,"route":"/home"}  设备应跳到 /home

Skill flutter-wright "screenshot /tmp/fw-smoke.png"
# → captured: /tmp/fw-smoke.png (<size> bytes)

Skill flutter-wright "goto /order/detail"
# 设备应显示 order 详情页

# 改 example/lib/pages/home_page.dart 任一文字(比如"Hello" → "Hi")
Skill flutter-wright "reload"
# → reloaded   设备应反映改动

Skill flutter-wright "setViewport 1080 2400 480"
# → viewport: 1080x2400 @ 480dpi

Skill flutter-wright "reset"
# → {"ok":true}

Skill flutter-wright "resetViewport"
# → restored: size=<orig> density=<orig>

Skill flutter-wright "stop"
# → stopped: appId=<id>
```

### 第 5 步 — 确认设备被还原

```bash
adb shell wm size       # 只有 Physical size,无 Override
adb shell wm density    # 只有 Physical density,无 Override
```

### 完成 = 烟雾序列各方法全部 exit 0 + 设备状态恢复
