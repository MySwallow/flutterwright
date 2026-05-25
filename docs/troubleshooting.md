# 故障排查

按 "现象在哪一层暴露" 分组。所有方法名为 flutter-wright v1 命名(`health/goto/screenshot/reload/setViewport/resetViewport/reset`)。

## `health` 失败

> **退出码 10-13 也可能从 `goto` / `screenshot` / `reload` / `reset` / `setViewport` 的首次调用触发** —— 这些方法在本 job 首次调用时会自动跑同一套环境检查（[SKILL.md §环境检查（自动）](../skills/flutter-wright/SKILL.md#环境检查自动)），失败统一以 health 段退出码退出。下面排查步骤对显式 `health` 和隐式触发都适用。

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

注册:`FlutterWright.routes.register('/your/route');`

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

### exit 31 (HTTP 503): VM service not available

`/reload` 靠 SDK 进程内自连 VM service,但 `flutter run` 的 DDS 会独占 VM service,导致自连被拒;release/profile 构建则根本没开 VM service。

**最可靠的热重载是在 `flutter run` 控制台直接按 `r`** —— SDK 的 `/reload` 只是"无人值守"场景下的尽力而为。确认 `flutter run` 是 debug 模式(默认就是)。

### exit 32 (其他 HTTP code)

可能是 reload 本身失败(语法错、`main()` 改了需 hot restart)。看 `flutter run` 控制台的 dart compile error。

需要 hot restart 时:目前 v1 没暴露,临时 workaround 是 `adb shell am force-stop <pkg>` + `flutter run` 重启。

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

期望:`All tests passed!`(含 `reload_handler_test`)。

### 第 3 步 — 启动 example app

```bash
cd packages/example
# 注意 -t:示例的 lib/main.dart 是零 SDK 的生产入口,debug 入口在 dev/main_dev.dart
flutter run -d $(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}') -t dev/main_dev.dart
```

等到看见:

```
[flutter_wright_sdk] listening on http://127.0.0.1:9123
```

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
```

### 第 5 步 — 确认设备被还原

```bash
adb shell wm size       # 只有 Physical size,无 Override
adb shell wm density    # 只有 Physical density,无 Override
```

### 完成 = 8 方法全部 exit 0 + 设备状态恢复
