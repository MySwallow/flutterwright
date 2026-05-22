# 平台脚手架

`android/` 和 `ios/` 目录**不**纳入版本管理。克隆后第一次使用时,在项目里生成一次即可:

```bash
cd example
flutter create . --platforms=android,ios --org com.example.visualloop
flutter pub get
```

这样做的好处:仓库小,避免平台相关文件在不同机器/版本之间漂移。`lib/` 下的 Dart 源码才是 source of truth。
