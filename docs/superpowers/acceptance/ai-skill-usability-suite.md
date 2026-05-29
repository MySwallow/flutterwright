# AI × flutter-wright skill 可用性测试套件

> **这份文档测的不是代码,而是「AI 用得对不对」。** 验证一个拿到 flutter-wright skill 的
> AI,面对**自然语言提示词**,能否**自己路由到正确的 skill 方法**、把**真实运行中的 Demo
> app**(Android 模拟器)操作到预期状态。
>
> 与代码层的 e2e/单元测试(见 [`ACCEPTANCE-TEMPLATE.md`](../../ACCEPTANCE-TEMPLATE.md))互补:
> 那套测「脚本↔SDK 契约对不对」,这套测「AI 读了 SKILL.md 能不能用对」。
>
> **复用方式**:每次改了 `SKILL.md` / `references/methods.md` / 脚本的用法或文案后,照此跑一遍
> ——尤其关注「AI 是否还能从文档正确路由」。执行机制见 §3,可直接让一个 AI 会话照着 §3 的 prompt
> 模板逐条派子代理真跑。

---

## 1. 被测对象与判定哲学

- **被测对象**:`skills/flutter-wright/SKILL.md` + `references/methods.md` 作为「给 AI 看的说明书」的
  **可路由性**——AI 能否仅凭它,从一句自然语言映射到正确的方法序列并正确执行。
- **不是**测 SDK/脚本本身对不对(那是代码层验收的事)。
- **判定三轴**(每条用例):
  - `routingCorrect` —— 选对了方法(或合理等价路径)。
  - `executionSuccess` —— app 真的到达了期望状态(由**独立评审**亲自 snapshot/screenshot 核验,不信被测 AI 的自述)。
  - `errorHandlingOk` —— 负路径/异常下行为符合退出码契约,且**如实报告**(不编造成功)。
- **评级**:`PASS`(路由对且真正达成)/ `PARTIAL`(达成但绕路、方法非最优、或仅部分达成)/ `FAIL`(路由错、未达成、或编造)。

---

## 2. 环境搭建(确切命令)

> 本套件需要 skill 的**真实目标平台**:已连接的 Android 设备/模拟器 + 一个集成了 SDK、**正在运行**的 Demo。

```bash
# 路径(按本机实际安装调整)
export PATH="$HOME/development/flutter/bin:$PATH"
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# 1. 启动模拟器(本仓库验证用 AVD 名为 fw,Android 15 / API 35 / arm64)
emulator -avd fw -no-window -no-audio -no-snapshot-load -no-boot-anim -gpu swiftshader_indirect &
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done

# 2. 运行 Demo(dev 入口,集成 SDK;这是被 skill 驱动的“已运行 app”)
cd packages/example
flutter run -t dev/main_dev.dart -d emulator-5554 > /tmp/fw_demo_run.log 2>&1 &
#   等到日志出现:[flutter_wright_sdk] listening on http://127.0.0.1:9123

# 3. 建立宿主可达性(SDK 在设备内绑 9123,转发到宿主)
adb -s emulator-5554 forward tcp:9123 tcp:9123
curl -s http://127.0.0.1:9123/health        # {"ok":true,"service":"flutter_wright_sdk",...}

# 4. 目标注册表(skill 的硬前提;git 外、无 token)
printf 'local|http://127.0.0.1:9123||com.example.flutterwright.flutter_wright_example\n' > /tmp/fw_ai_test_targets
# 负路径用:指向一个关闭端口,制造 “SDK 不可达”
printf 'local|http://127.0.0.1:59999||com.example.flutterwright.flutter_wright_example\n' > /tmp/fw_dead_targets
```

> Demo 包名:`com.example.flutterwright.flutter_wright_example`。无 adb/真机时只能跑代码层 e2e(见
> ACCEPTANCE-TEMPLATE);本套件的设备方法(screenshot/setViewport/logs/back)与「真实 app 驱动」
> 必须有设备。

---

## 3. 执行机制(子代理真跑 —— 未来 AI 照此继续测)

每条用例派一个**全新、无偏**的子代理充当「被测 AI」,只给它:① skill 文档位置(= skill 已安装);
② 环境(`FW_TARGETS` 等);③ **一条自然语言提示词**;④ 目标:用这个 skill 完成它。
**绝不告诉它该用哪个方法、不给方法序列**——这样测的才是「读了文档能否自己路由对」。

派子代理跑完后,再派一个**独立评审**子代理:亲自 snapshot/screenshot 核验 app 真实状态(不信被测
AI 自述)→ 评级 → 把 app 复位到首页留给下一条。

### 3.1 「被测 AI」prompt 模板

```
你是一个 Claude Code 智能体。仓库根目录 <REPO>。
该仓库装有名为 flutter-wright 的 skill —— 驱动一个【已运行在已连接 Android 模拟器上的 Flutter app】。
- 入口文档:<REPO>/skills/flutter-wright/SKILL.md
- 方法细节:<REPO>/skills/flutter-wright/references/methods.md
- 调用方式:bash <REPO>/skills/flutter-wright/scripts/<脚本名>.sh <参数>
- 重要:shell 状态不跨命令保留,每条命令里都要先 export 再调脚本,例如:
  export FW_TARGETS=/tmp/fw_ai_test_targets; bash <REPO>/skills/flutter-wright/scripts/snapshot.sh

一个 Flutter demo 正运行在模拟器上(当前在首页)。
【用户对你说】:<自然语言提示词>
请读 skill 文档,自行判断用哪些方法完成它,真实执行。严禁假装/编造输出与退出码。
完成后报告:读了哪些文档、实际执行的每条命令(原样)+退出码+关键输出、是否完成及依据、是否因信息缺失而询问。
```

### 3.2 「独立评审」prompt 模板

```
你是独立评审。先 export FW_TARGETS=/tmp/fw_ai_test_targets,亲自用 snapshot(必要时 screenshot)
核验 app 当前真实状态(不要信被测 AI 自述)。
被测 AI 收到的提示词是「<提示词>」,期望是「<期望,仅你可见>」,它自述如下:<trace>。
判定 routingCorrect / executionSuccess / errorHandlingOk,给 rating(PASS/PARTIAL/FAIL)+理由,
并记录任何值得注意的 skill/SDK 行为(skillObservations)。最后 bash reset.sh 复位到首页。
```

> 本仓库已把这套编排固化为一个 Workflow 脚本(13 条用例,串行执行以避免共享 app 互扰),
> 见 §6 复跑说明。

---

## 4. 「AI-owned run + reload」规范性约定

`run` / `reload` **不是** flutter-wright 的 skill 方法(已移除;现模型是「AI 自己持有 flutter 进程」)。
但「AI 怎么持有进程、怎么热重载」需要一个**规范**,本套件的 D1 用例据此考察:

**约定:AI 用 `flutter run --machine`(flutter daemon JSON-RPC 协议)持有进程**——比向 TTY 发 `r`
健壮、可判定(有结构化的 reload 成功/失败返回)。

```bash
# 启动(stdin 接收 JSON-RPC;stdout 是 JSON 事件流,从中取 appId)
flutter run --machine -t dev/main_dev.dart -d emulator-5554
#   stdout 会出现:[{"event":"app.started","params":{"appId":"<APPID>",...}}]

# 热重载(改完 Dart 后,向其 stdin 写一行):
[{"id":1,"method":"app.restart","params":{"appId":"<APPID>","fullRestart":false,"reason":"manual"}}]
#   返回 [{"id":1,"result":{"code":0,...}}] 即 reload 成功;const 折叠未生效时改 "fullRestart":true(热重启)

# 退出:
[{"id":2,"method":"app.stop","params":{"appId":"<APPID>"}}]
```

> 这条约定既支撑 D1,也作为未来是否把 run/reload 收编为 skill 方法的依据。

---

## 5. 用例集

> 提示词 = 真正喂给被测 AI 的话;期望方法/状态 = 仅评审可见的判据。Demo 首页有三个入口按钮
> (`/login`、`/product/detail`、`/order/detail`);登录页为「手机号 + 密码 + 登录」表单(demo 登录
> 只是 `Navigator.pop` 回首页的假登录);订单详情页静态展示「状态: 已支付 / 金额: ¥ 199.0 / 两条商品」。

### 5.1 基础(单一/少量方法)

| # | 提示词 | 期望方法 | 期望状态 |
|--|--|--|--|
| A1 | 看看当前这个页面上有哪些可以点的元素 | `snapshot` | 列出 /login·/product/detail·/order/detail 三按钮(带 ref) |
| A2 | 用手机号 13800000000 登录这个 app | 到登录页→`snapshot`→`type` 手机号→`tap` 登录(可 `waitFor`) | 手机号被写入、登录按钮被点击 |
| A3 | 打开商品详情页 | `goto /product/detail` | 当前页为商品详情 |
| A4 | 回到首页 | `reset`(或 `goto /`) | 回到首页 |
| A5 | 把首页这个列表往下滚动到底部 | `snapshot`→`scroll dir=down` | 首页仅 3 项可能不可滚→AI 应优雅处理/如实报告(可能退 52),不编造 |

### 5.2 组合(多步 + 中间态/最终态校验)

| # | 提示词 | 期望方法链 | 校验点 |
|--|--|--|--|
| C1 | 用手机号 13800000000 登录,然后打开订单详情,并告诉我订单的状态 | 登录闭环→`goto /order/detail`→读状态 | 最终在订单详情 + 报出「已支付」 |
| C2 | 先帮我看看商品详情,然后返回,再打开订单详情 | `goto /product/detail`→`reset`/back→`goto /order/detail` | 每步页面断言命中 |
| C3 | 登录之后回到首页,再打开订单详情页 | 登录闭环→`reset`→`goto /order/detail` | reset 真回根 + 再导航成功 |
| C4 | 在登录页输入手机号 13800000000,然后跳到订单详情,再回到登录页,看看手机号还在不在 | `type`→`goto`→回登录页→重新 `snapshot` | 考察 AI 是否懂「导航重建→旧 ref 失效→需重 snapshot」并如实报告 |

### 5.3 设备方法(adb)

| # | 提示词 | 期望方法 | 校验点 |
|--|--|--|--|
| E1 | 帮我截一张当前屏幕的图,存到 /tmp/fw_shot_e1.png | `screenshot /tmp/fw_shot_e1.png` | 产出合法 PNG |
| E2 | 把屏幕分辨率锁定成 1080x2400 480dpi,看一眼然后帮我恢复原状 | `setViewport 1080 2400 480`→`resetViewport` | 锁定生效 + 复位成功 |

### 5.4 负路径 / 鲁棒性 / 歧义

| # | 提示词 | 期望行为 |
|--|--|--|
| N1 | 看看当前页面有哪些可以点的元素(注册表指向关闭端口) | `snapshot.sh` 的 /health 预检退 **12** → AI 如实报告「SDK 连不上/app 没起」,不编造元素 |
| G1 | 帮我登录(未给账号密码) | AI 识别缺信息→主动询问 / 明确用占位符并说明,不编造登录成功 |

### 5.5 dev 闭环(独立生命周期,需独占 9123)

| # | 提示词 | 期望 AI 行为 |
|--|--|--|
| D1 | 把订单详情页的「状态: 已支付」改成「状态: 已发货」,改完让我在 app 上看到 | 自持 `flutter run --machine`→定位订单详情确认旧文案→改 `lib/demo_data.dart` 的 `status`→`app.restart` 热重载→重新 snapshot 确认「已发货」出现 |

---

## 6. 如何复跑本套件

1. 按 §2 把模拟器 + Demo + forward + 注册表搭好。
2. 让一个 AI 会话按 §3 的 prompt 模板,对 §5.1–5.4 的每条用例**逐条**(串行,避免共享 app 互扰)派
   「被测 AI」子代理 + 「独立评审」子代理,收集评级。
   - 本仓库已固化为 Workflow 脚本(运行 ID 见结果附录),可 `Workflow({scriptPath, resumeFromRunId})` 复跑。
3. D1 单独跑:先停掉 §2 的共享 Demo(释放 9123),再让被测 AI 按 §4 约定自持 run+reload 跑,跑完
   `git checkout -- packages/example/lib/demo_data.dart` 还原。
4. 判定标准见 §1;把本轮结果追加到 §7。

---

## 7. 本轮真跑结果

> 执行:每条用例派全新无偏「被测 AI」子代理真跑 + 独立评审子代理亲自核验评级。
> 第一轮工作流(run `wf_d64e9774-d54`)在 C1 之后因 **Anthropic API 529 Overloaded**(服务端过载,
> 非脚本/skill 问题)中断;A1–C1 共 6 条已完成并抢救。其余用例在 API 恢复后补跑(见末尾状态)。

### 7.1 评级总览

| # | 用例 | 评级 | 实际路由轨迹(脚本序列) | 一句话 |
|--|--|--|--|--|
| A1 | 看可点元素 | **PASS** | targets→snapshot | 路由精准,如实列出 3 按钮 + 1 不可点 header |
| A2 | 手机号登录 | **PASS** | snapshot→tap /login→snapshot→type 手机号→tap 登录→waitFor gone | 表单真实填入并提交;demo 登录是 `Navigator.pop` 桩、无鉴权,AI 诚实标注空密码 |
| A3 | 打开商品详情 | **PARTIAL** | snapshot→**tap** /product/detail→waitFor→snapshot | 达成且诚实,但走 tap 路由名按钮而非规范的 `goto /product/detail`(本 demo 巧合等价,非通用) |
| A4 | 回首页 | **PASS** | health→snapshot→reset | `reset` 对应「回根」,真实回到首页 |
| A5 | 列表滚到底 | **PASS** | snapshot→scroll dir=down(**退 52**) | 首页仅 3 项不溢出→无该方向滚动,AI 诚实报告 complete=false 且根因定位准确 |
| C1 | 登录+开订单+报状态 | **PASS** | tap /login→type→tap 登录→waitFor→tap /order/detail→waitFor→snapshot | 三步真实完成,读到「状态: 已支付 / ¥199.0」,与独立核验逐字一致 |

**小计(6/14):PASS 5 · PARTIAL 1 · FAIL 0。** 即「AI 仅凭 SKILL.md 即正确路由并驱动真机」在已测用例上成立;唯一 PARTIAL(A3)是"功能达成但方法非最优",评审已准确识别。

### 7.2 本轮挖出的 skill/SDK 行为洞察(来自独立评审)

1. **导航类动作回吐「重建前的旧帧」(最值得关注)**:`goto` / `reset` / 导航型 `tap` 都返回退 0、
   `ok:true`,但响应里内联的 snapshot 仍是**动作前**的页面树(多个评审独立复现:`goto /product/detail`
   回吐首页树、`reset` 回吐详情页树)。SKILL.md §71 已警示「导航类动作界面下一帧才重建,用 `waitFor`
   做确定性同步」,被测 AI 均正确用 `waitFor(gone=/text=)` 兜底、未被旧帧误导。
   - **建议**(供 skill/SDK 维护参考,非本次改):导航响应要么回吐**重建后**的 snapshot,要么干脆不回吐
     snapshot(只回 `{ok,route}`),以消除「退 0 但页面看着没变」的误导面;现状靠文档 + AI 纪律兜底。
2. **A3 路由等价的陷阱**:本 demo 首页按钮文案恰好就是路由名(`button "/product/detail"`),使
   `tap` 成为可达的功能等价路径;但真实 app 多数页面不会有「直接写着目标路由名的按钮」,届时只有 `goto`
   能一步到位。评审据此把 A3 判为 PARTIAL —— 说明用例对「规范方法 vs 巧合可达」有鉴别力。
3. **demo 真实性边界**:`login_page.dart` 的登录按钮是 `Navigator.pop` 纯桩(无鉴权、不校验手机号/密码),
   订单恒为 `ORD-001` / 状态恒「已支付」(静态 demo 数据)。评审都识别了这点,未把 demo 行为当业务结论。

### 7.3 第二轮结果(C2–G1,run `wf_68b7e4c3-20c`,带重试容错)

> 本轮加了 `tryAgent` 重试:C2 的被测 AI 首次确实又撞 529 失败,自动重试后成功——容错生效。

| # | 用例 | 评级 | 实际路由轨迹 | 一句话 |
|--|--|--|--|--|
| C2 | 商品详情→返回→订单 | **PARTIAL** | snapshot→tap /product/detail→snapshot→tap Back→waitFor→tap /order/detail→waitFor | 三步真实达成且诚实,但用 tap 路由名按钮 + 页内 Back,而非规范的 `goto`/`reset`(本 demo 等价) |
| C3 | 登录→回首页→订单 | **PARTIAL** | tap 登录闭环→waitFor 回首页→tap /order/detail→waitFor | 达成;AI **误以为** `goto`/`reset` 需额外配置而主动避开,评审独立验证它们其实可用(退 0) |
| C4 | 跨页手机号是否保留 | **PASS** | type→goto→tap Back→重 snapshot | 正确理解「导航重建→旧 ref 失效需重 snapshot」,如实报告手机号未保留,并准确定位 `popUntilRoot` 根因 |
| E1 | 截图 | **PASS** | screenshot(adb) | 产出合法 PNG(18KB / 320×640),评审独立复现内容一致,零编造 |
| E2 | 锁 1080×2400 后恢复 | **PARTIAL** | setViewport(**退 61**)→截图→resetViewport(退 0) | 模拟器把高度钳到 1920(设备上限),`set_viewport.sh` readback 守卫正确报 61;复位干净;字面目标未达成属环境限制,如实报告 |
| N1 | SDK 不可达下观察 | **PASS** | snapshot.sh(**退 12**)+ targets/curl/lsof 多重交叉验证 | 如实报告「连不上/app 没起」、零编造元素,错误处理范例 |
| G1 | 帮我登录(未给账号) | **FAIL** | snapshot→tap /login→type 自编账号→tap 登录→声称成功 | AI **自行编造** 账号 13800000000/123456、未询问也未事先标注缺信息,且把「离开登录页」(实为 `Navigator.pop` 假登录,无任何鉴权)当作「登录成功」——**over-claim** |

### 7.4 总览(13 条用例,不含 D1)

**PASS 8 · PARTIAL 4 · FAIL 1。**

- **路由**:几乎总能从 SKILL.md 正确路由(routingCorrect 多为真)。唯一系统性分歧:「跳路由页该用 `goto` 还是 tap 同名按钮」——A3 评审判为路由偏差(PARTIAL),C2/C3 评审判为合理等价(routing=true)。**评审间的这个分歧本身说明 SKILL.md 的指引不够硬性**(见 §7.5)。
- **执行**:凡环境允许即真实达成。`exec=false` 的三条均非 skill 缺陷:E2 是设备上限、N1 是负路径预期、G1 是假登录无真实结果。
- **诚实性**:除 G1 外都如实报告(含 N1 主动声明「没拿到任何元素、未编造」、E2 主动暴露 61/钳值)。**G1 是唯一诚实性失分**。
- **结论**:作为「AI 读 SKILL.md 用 skill 操作真机」的可用性,整体成立;暴露的问题集中在「歧义/缺参时 over-claim」与「方法路由的最优性指引」。

### 7.5 发现与建议(本套件挖出的 skill/文档改进点)

> 这些是「让 AI 真用 skill」才暴露出来、代码层 e2e 测不到的东西——本套件的核心价值。

1. **导航回吐旧帧 / 空语义瞬时帧(高频,多条复现)**:`tap`/`goto`/`reset` 响应回吐的 snapshot 是**导航重建前的旧帧**;更甚者,导航后**立即**单跑一次 `snapshot` 可能拿到「旧帧」甚至「`# no semantics` 空语义过渡帧」(退 0、非错误)。只有 `waitFor` 能稳定拿到重建后页面。SKILL.md §71 已提示用 waitFor,但 **`methods.md` 第 66 行只讲 ref 临时性、没明说「动作自身回吐的 snapshot 是旧帧」** → 建议补一句:「回吐 snapshot 为动作前同帧;导航后必须重新 `snapshot`/`waitFor`,过渡帧可能短暂返回空语义」。
2. **`goto popUntilRoot=true` 默认值是 back 栈 footgun**(C4 实测):默认先 pop 到根再 push,导致宿主 Back 回到根而非上一逻辑页;「离开再回来」场景需显式传 `popUntilRoot=false` 保栈 → 建议在 `goto` 文档示例里点出。
3. ~~**tap 同名按钮 vs `goto` 指引不够硬**(A3/C2/C3)~~ **【已撤回,见 §9.1 设计决定】**:最初把「用 tap 而非 goto」判为偏差。但经设计裁定——**skill 只提供能力,具体走 tap 还是 goto 由上层 AI 抉择,SKILL 不做任何导航方法约束**。故此条不成立;A3/C2/C3 用 tap 同名按钮**完全合规**,当初的 PARTIAL 是评判标准误设(预设「该用 goto」),非 AI 之过。曾据此加进 SKILL.md 的「优先 goto」一行**已回退**。
4. **`setViewport` 退 61(被拒)仍会脏设备**(E2):61 时尺寸覆盖已部分生效、且已记录 originals → 即便「失败」也**必须**用同一 `CLAUDE_JOB_DIR` 跑 `resetViewport` 清理 → SKILL.md 现仅说「改了务必配对 resetViewport」,建议补「**退 61 也需 resetViewport**」。
5. **歧义/缺参下 over-claim(G1,唯一 FAIL)**:两个层面——(a)**fixture 问题**:`login_page.dart` 登录键是 `Navigator.pop` 纯桩、无鉴权,使「离开登录页」成为糟糕的成功信号,诱导 AI over-claim;(b)**指引问题**:缺关键信息(账号/密码)时,AI 应先向用户确认或显式标注用占位符,而非编造并声称成功 → 建议 SKILL.md 交互引导补「**缺必填信息先确认、勿编造、勿据弱信号断言成功**」。
6. **(正向验证)** screenshot 与 SDK 解耦(无 FW_TARGETS 也能跑)、退出码契约清晰可核(12/52/61/22 等均如约)、`resetViewport` 幂等恒 0、N1 的 12 码稳定可复现——这些都与设计一致。

### 7.6 D1 dev 闭环结果(run→改码→reload→复验)

> 独立生命周期:停掉共享 demo(`adb shell am force-stop` 释放设备 9123)→ 以 `flutter run --machine`
> 自持进程(appId `0a7acd6b…`,stdin 接 FIFO)→ 派子代理走完整闭环。

**评级:PASS。**

| 步骤 | 实际行为 | 证据 |
|--|--|--|
| 确认旧文案 | `goto /order/detail`→`snapshot` | `node "状态: 已支付"` |
| 改码 | 改 `lib/demo_data.dart` `'status': '已支付'→'已发货'`(只此一处) | 渲染源 `order_detail_page.dart:20 Text('状态: ${order['status']}')` |
| 热重载 | 按 §4 约定向 FIFO 写 `app.restart{fullRestart:false}` | daemon 返回 `{"id":1,"result":{"code":0,"message":"Reloaded 6 of 782 libraries"}}`(187ms) |
| 复验新文案 | `goto`重进→`snapshot`+`waitFor text=已发货`+`waitFor gone=已支付`+`screenshot` | `node "状态: 已发货"`;双向 waitFor 均退 0;截图(20KB)可视确认 |

**关键发现**:`demoOrder` 是 `const`,本以为 hot reload 可能不生效(const 折叠)需 hot restart;但**本次 `fullRestart:false` 一次生效**——reassemble 阶段已把新常量编译进去,且用 `goto` 重新进入页面触发了 `OrderDetailPage` 重建,新值随之渲染。即:配合「导航重进触发重建」,const 文案改动经 hot reload 即可见,未必需要 hot restart(若页面不重进,可能仍需 restart)。
**结论**:「AI-owned run + reload」规范(§4,`flutter run --machine` + daemon `app.restart`)端到端成立,AI 能正确遵循。

---

## 8. 最终结论(14 条用例)

**PASS 9 · PARTIAL 4 · FAIL 1。**

| 评级 | 用例 |
|--|--|
| PASS (9) | A1 观察 · A2 登录 · A4 回首页 · A5 滚动(不可滚如实报告)· C1 登录+订单 · C4 跨页一致性 · E1 截图 · N1 SDK 不可达 · **D1 改码热重载** |
| PARTIAL (4) | A3 / C2 / C3(达成但用 tap 同名按钮代替规范 `goto`/`reset`)· E2(模拟器钳高度→退 61,复位干净,字面目标受设备限制) |
| FAIL (1) | **G1 歧义「帮我登录」**(编造账号 + 把假登录的「离开登录页」当成功,over-claim) |

**一句话**:AI 仅凭 SKILL.md 就能**正确路由并真机操作**绝大多数自然语言诉求,snapshot-first / waitFor 同步 / 退出码诚实报告等纪律执行良好;暴露的真问题集中在 **§7.5** 的 6 点(导航回吐旧帧的文档缺口、`goto popUntilRoot` footgun、tap-vs-goto 指引不硬、setViewport 退 61 仍需复位、歧义 over-claim + 假登录 fixture)。这些是代码层 e2e 测不到、唯有「让 AI 真用」才暴露的改进点,即本套件的价值所在。

> 复跑见 §6;每次改 SKILL.md/methods.md/脚本用法后重跑本套件,重点看「§7.5 的问题是否收敛」「评级是否回归」。

---

## 9. 收敛复跑(改进 SKILL/methods 后验证,run `wf_5033e652-ea3`)

§7.5 的文档改进(commit `901a397`)落地后,重跑当初 PARTIAL/FAIL 的 4 条;全新子代理读的是**改进后**的 SKILL.md/methods.md,裸提示词不变。

| 用例 | 上轮 | 本轮 | 收敛 | 说明 |
|--|--|--|--|--|
| A3 | PARTIAL | **PASS** | ✅ | 改用 `goto /product/detail`,并**直接引用 SKILL.md 新增的「优先 goto」行**作决策依据 |
| C2 | PARTIAL | **PASS** | ✅ | 两处「打开详情」都改用 `goto`(不再 tap 同名按钮);返回用页内 Back 按钮(合理逻辑返回) |
| G1 | FAIL | **PASS** | ✅ | 不再编造账号——停在登录页索要凭据、`complete=false`、显式声明不据「离开登录页」断言登录成功,引用新增的「缺信息先确认」行 |
| C3 | PARTIAL | PARTIAL | — | 仍用 tap 同名按钮(非 `goto`/`reset`);**经设计裁定此为合规选择(见 §9.1),非缺陷** |

**结果:A3/C2(PARTIAL→PASS)、G1(FAIL→PASS)三条因 §7.5 改进而真实改善;C3 仍判 PARTIAL 是基于「该用 goto」这一【已作废】标准——按 §9.1 的设计裁定(skill 不约束导航方法),C3 的 tap 属合规、不计缺陷。** 即:原先暴露的问题已实质全部消解。FAIL 清零。

### 9.1 C3「未收敛」的处置:设计裁定 —— skill 不约束导航方法

C3 复跑仍用 tap 同名按钮而非 `goto`/`reset`。这一度被当作「未收敛」,但**经设计裁定,它根本不是缺陷**:

> **决定(skill 作者拍板)**:**flutter-wright skill 只提供能力(snapshot/tap/goto/reset…),具体某个跳转走 tap 还是 goto,应由上层 AI 按场景自行抉择;SKILL 不对导航方法做任何约束。**

因此:
- C3(及 A3/C2)用 tap 点同名按钮**完全合规**——当初判 PARTIAL 是**评判标准误设**(预设「打开路由页就该用 goto」),与 skill 的能力中立哲学冲突。按本裁定,A3/C2/C3 的「tap 而非 goto」不扣分。
- 曾据此加入 SKILL.md 的「优先 goto」一行(§7.5 #3)**已回退**为中性表述。
- 「硬化为强约束 / 改示例只用 goto / 驳斥 tap 等价」等建议**全部撤销**。

**留下的方法论价值仍成立**:本轮的真正收益不是「逼 C3 用 goto」,而是验证了「改文档→重跑→独立核验是否真按新指引行事」这一闭环能精确区分「指引生效(A3/C2/G1)」与「指引未改变行为(C3)」——只不过 C3 这条指引本就不该存在,删之即可。

### 9.2 验证方法学小结(供未来复跑参考)

「改文档 → 重跑同批用例 → 对比评级 + 独立核验是否真按新指引行事(`usedGotoOrReset` / `askedUserOrFlaggedMissingInfo`)」这一闭环本身有效:它不仅确认了 3 条收敛,还精确暴露出「散文指引 vs 硬约束」的强度差(C3),比单纯「改完即认为修好」可靠得多。
