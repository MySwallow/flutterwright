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
| `/snapshot` 语义树 / `/screenshot` 截图暴露当前页面敏感内容（token、用户记录） | 仅绑定 `127.0.0.1`、不允许绑 `0.0.0.0`，并可选 `start(token: ...)` token 鉴权 |
| Wi-Fi 上的网络攻击者                          | 仅绑定 `127.0.0.1`                                                |
| 超大 body 导致 DoS                            | `maxBodyBytes` 默认 1 MiB，超过返回 413                           |
| 来自其他 app 的恶意 deep-link                 | HTTP 服务**不是** deep-link handler，没有 `adb forward` 别的 app 进不来 |
| 同 loopback 的其它本地进程 / 有代码执行能力者   | 调 `start(token: ...)` 后，除 `GET /health` 外所有端点须带匹配的 `X-FW-Token` 头，否则返回 401(常量时间比对);`token` 为空/null 时不鉴权，仅靠 `127.0.0.1` loopback |

## SDK 不防范的场景

- **同设备攻击者**：任何在你手机上有代码执行能力的人都能访问 `127.0.0.1:9123`。如果你的开发设备已被入侵，SDK 不是你最该担心的问题。作为纵深防御，可经 `start(token: ...)` 启用 token 鉴权(token 从环境变量 / 本地配置读取，绝不提交进仓库)。
- **`adb forward` 链路被嗅探**：电脑和设备之间的流量是明文的。不要在不可信的公共 USB hub 上跑循环。
- **页面内容泄露**：`/snapshot` 返回的语义树与 `/screenshot` 返回的截图会反映 app 当前页面，可能含敏感内容（auth token、用户记录）。缓解措施是仅绑定 `127.0.0.1` 外加可选的 `start(token: ...)` 鉴权；这些响应只在本机回传，不要把抓到的快照 / 截图提交进仓库。

## 在 CI / 共享开发环境里的加固建议

- 用 `enabled: kDebugMode`（或你自己的「测试包?」判断）接线,正式包让它为 `false`(默认)。
- 同一台电脑跑多个 Flutter 项目时，使用非默认端口：
  ```dart
  FlutterWrightConfig(port: 9124)
  ```
- CI 跑完确保执行 `adb forward --remove tcp:9123`（或 `--remove-all`），避免其他 job 误连到旧 server。
- 在 CI / 共享环境里给 `start()` 传 `token`，让除 `GET /health` 外的端点都要求匹配的 `X-FW-Token`。

## 支持的版本

| 版本    | 是否支持           |
|---------|--------------------|
| 0.8.x   | :white_check_mark: |
| < 0.8   | :x:                |
