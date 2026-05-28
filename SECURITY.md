# 安全策略

## 如何上报漏洞

请通过 GitHub Security Advisory（不要开 public issue）上报安全问题：

https://github.com/MySwallow/flutterwright/security/advisories/new

48 小时内会有响应。

## 威胁模型 — SDK 防范哪些东西

`flutter_wright_sdk` 是**调试工具**，不是生产组件。它的威胁模型相对收敛：

| 威胁                                          | 缓解措施                                                          |
|-----------------------------------------------|-------------------------------------------------------------------|
| 误把HTTP 服务带到生产用户手里                  | `enabled` 默认 `false` — 不传 `enabled: true` 时 `start()` 是 no-op、不绑端口;集成方用 `enabled: kDebugMode` 或自己的「测试包?」判断接线 |
| 本地恶意软件读写 mock 数据                    | 仅绑定 `127.0.0.1`，不允许绑 `0.0.0.0`                            |
| Wi-Fi 上的网络攻击者                          | 仅绑定 `127.0.0.1`                                                |
| 超大 body 导致 DoS                            | `maxBodyBytes` 默认 1 MiB，超过返回 413                           |
| 来自其他 app 的恶意 deep-link                 | HTTP 服务**不是** deep-link handler，没有 `adb forward` 别的 app 进不来 |

## SDK 不防范的场景

- **同设备攻击者**：任何在你手机上有代码执行能力的人都能访问 `127.0.0.1:9123`。如果你的开发设备已被入侵，SDK 不是你最该担心的问题。
- **`adb forward` 链路被嗅探**：电脑和设备之间的流量是明文的。不要在不可信的公共 USB hub 上跑循环。
- **Mock 数据泄露**：Mock 值可能含敏感 fixture（auth token、用户记录）。它们存在 app 内存里，app 死了就没了。不要把真实生产密钥放进去。

## 在 CI / 共享开发环境里的加固建议

- 用 `enabled: kDebugMode`（或你自己的「测试包?」判断）接线,正式包让它为 `false`(默认)。
- 同一台电脑跑多个 Flutter 项目时，使用非默认端口：
  ```dart
  FlutterWrightConfig(port: 9124)
  ```
- CI 跑完确保执行 `adb forward --remove tcp:9123`（或 `--remove-all`），避免其他 job 误连到旧 server。
- 不要把含真实用户 PII 的 mock 数据提交进 example。

## 支持的版本

| 版本    | 是否支持           |
|---------|--------------------|
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |
