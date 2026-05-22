# 贡献指南

感谢你考虑贡献。这个项目刻意做得很小 — SDK 约 1k 行 Dart,Skill 几百行 bash。请保持这个状态。

## 基本原则

1. **SDK 不引入新依赖。** `dart:io` 和 `package:flutter` 是我们全部所需。引入 `http`、`riverpod`、`dio` 等的 PR 会被拒。宿主 app 不应该为它们用不到的依赖买单。
2. **生产安全优先。** 任何新代码路径必须由 `kDebugMode` 或一个默认关闭的 config 标志守门。Release 构建绝不绑 socket、绝不暴露数据。
3. **小文件。** 单文件保持在 400 行以内。每个 handler 一个文件。
4. **不写向后兼容垫片。** v0.x 是不稳定版本。破坏性变更没问题,只要在 `CHANGELOG.md` 里写清楚。

## 准备开发环境

```bash
git clone https://github.com/MySwallow/flutter-visual-loop.git
cd flutter-visual-loop/packages/flutter_visual_loop
flutter pub get
flutter test
```

跑 example app:

```bash
cd flutter-visual-loop/example
flutter create . --platforms=android,ios --org com.example.visualloop
flutter pub get
flutter run -d <device-id>
```

## 我们希望收到的 PR

- Bug 修复(先加一个失败的测试)
- iOS Simulator 平等支持(UNIX socket 或基于 simctl 的截图)
- Web 平台支持(SDK 跑在 Flutter Web 上)
- 更好的报错信息
- 文档改进

## 我们**不**希望收到的 PR

- 视觉对比算法 — 那是 LLM 在 skill 层做的
- HTTP 认证 — "绑 localhost" 就是安全模型
- 基于 stream 的"响应式"Mock 数据 — 保持 `MockDataProvider` 简单

## PR 检查清单

提 PR 前确认:

- [ ] `packages/flutter_visual_loop` 下 `flutter test` 通过
- [ ] `bash scripts/validate.sh` 显示 0 FAIL
- [ ] 加了新 endpoint? 更新了 `docs/api-reference.md` 和 `packages/flutter_visual_loop/README.md`
- [ ] 改了默认行为? 在 `CHANGELOG.md` 加了一条
- [ ] commit message 遵循 conventional commits(`feat:`、`fix:`、`docs:`、`refactor:`、`test:`、`chore:`)

## 评审流程

PR 由 maintainer(MySwallow)评审,通常一周内反馈。标准是"改动小、测试充分、影响面小"。

## 许可证

提交 PR 即视为同意你的代码采用 MIT 许可证。
