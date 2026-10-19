# 默认 AI 服务

默认 AI 服务已并入 `main`，通过服务器代理提供智能服务。此前用于验证的独立分支已合并，后续统一维护主线。

- 含默认服务的网页：https://apsonchian.ltd/liferecord-default/
- 原有网页入口：https://apsonchian.ltd/liferecord/
- Android 当前版 1.4.0-default-beta.4（build 8）：[直接下载 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-default-v1.4.0-beta.4/LifeRecord-Android-1.4.0-default-beta.4.apk) · [Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-default-v1.4.0-beta.4)。beta.4 新签名不能覆盖 beta.3，安装前先阅读[迁移说明](android-release-1.4-beta4.md#签名与发布状态)。
- 原 2026-10-13 默认版（build 6）保留在独立测试网站，当前版以 GitHub Release 为准。
- iOS 1.4（build 6）工程：本机 `dist/default-ai-2026-10-13/LifeRecord-iOS-1.4-default-beta.zip`。尚未上传 TestFlight。

新安装默认使用“默认 AI 服务”，无需填写 AI Key。用户仍需通过自己的独立同步密钥连接账号；旧安装保留已经选用的自定义配置，也可以在设置中切换默认服务。用户可继续选择 DeepSeek、GLM 或新增并保存自己的兼容接口。

## 私有配置与接口

移动端统一请求鉴权后的 `POST /liferecord-api/ai/chat`；网页默认服务使用现有 `POST /liferecord-api/ai/plan`，记录范围与复核保存流程保持原样。默认请求不包含上游模型、地址或密钥，服务端不会采用客户端对默认配置的覆盖。返回仅包含必要内容，不转发上游元数据，错误采用统一服务提示。公开界面不展示底层供应商。自定义接口按用户自己的配置工作。

服务端配置仅放在 `/etc/liferecord-sync.env`，权限 0600，不纳入仓库或公开 Web 目录：

| 环境变量 | 用途 |
| --- | --- |
| `LIFERECORD_DEFAULT_AI_ENABLED` | `1` 开放；`0` 停止默认服务，自定义接口继续使用 |
| `LIFERECORD_DEFAULT_AI_ENDPOINT` | 私有 HTTPS Chat Completions 地址 |
| `LIFERECORD_DEFAULT_AI_MODEL` | 私有模型名称 |
| `LIFERECORD_DEFAULT_AI_KEY` | 私有服务端密钥 |
| `LIFERECORD_DEFAULT_AI_AUTH` | `bearer` / `api-key` / `custom` |
| `LIFERECORD_DEFAULT_AI_HEADER` | 自定义认证头名称（仅 custom） |
| `LIFERECORD_DEFAULT_AI_EXTRA` | 服务端 JSON 扩展参数，不能覆盖模型、消息或生成字段 |
| `LIFERECORD_DEFAULT_AI_IMAGE_DETAIL` | 可选图片 detail 参数 |
| `LIFERECORD_DEFAULT_AI_MAX_TOKENS` | 默认 4096，服务端上限最高 8192 |
| `LIFERECORD_DEFAULT_AI_DAILY_LIMIT` | 默认每账号每天 30 次 |
| `LIFERECORD_DEFAULT_AI_GLOBAL_DAILY_LIMIT` | 默认所有账号合计每天 300 次 |
| `LIFERECORD_DEFAULT_AI_CONCURRENCY` | 默认服务同时最多 4 次，每个账号同时最多 1 次 |

改配置后运行 `systemctl restart liferecord-sync`。调用计数存储在 SQLite `ai_daily_usage` 表，UTC 每日重置（北京时间 08:00），保留近 7 天；上游失败也计数，避免无限重试耗费额度。限制涵盖最大输出、文字长度、图片数量和大小；不接受远程图片 URL。请求仍经过公网 DNS 校验、IP 固定、TLS 域名验证与禁止重定向的传输。此额度是请求次数与输出上限，不是精确的人民币账单预算。

默认服务会将请求文字、相关记录和所选照片发送至云端 AI。网页隐私说明和移动端设置已明确说明，用户可改用自己的接口。服务端环境与运维备份仅管理员可访问，密钥不加入移动端分发包。

## 验证与上线

2026-10-13：`Tests/default-ai.py` 验证鉴权、配置覆盖拒绝、输出 Token 上限、图片 URL/输入限制、持久额度、账号独立额度、全局额度、并发、错误脱敏、默认网页预览与自定义回退。原有后端 4 项回归、网页配置/记录与 4 个宽度回归、Swift 回归、iOS 模拟器构建、Android 构建/单元测试/lint 均通过。

使用服务器私有配置做了最小真实请求及生产鉴权代理测试，结构化 JSON 返回通过，没有发送个人健康记录。生产响应未包含上游配置，原账号快照与 ETag 保持兼容，数据库 quick_check 为 ok，部署前后用户、记录、字段和照片索引一致。已确认私有密钥不在源码候选文件、APK 或 iOS 工程包中。APK 沿用原有公测签名，可覆盖升级。

本次私有数据库、代码、环境与 Nginx 备份：`/opt/liferecord-sync/backups/default-ai-20261013-094916/`。服务器后端同时支持两个现有网页入口；默认服务模块与路由现已包含在 main，部署时继续保留现有服务端私有配置。

2026-10-13 旧 APK SHA-256：`6b0fd24049126b3eed8521d668a2ddcaa7e4dd10484811fb79d81572c762b32d`。

iOS 工程包 SHA-256：`881d2c8d5d5eb0028e15246d555ff7b56f78ca3617f757a8b35a5a22b2fcd59f`。

本轮未重新执行模拟器设备 UI 测试、并发负载压测或完整渗透测试；iOS 仍仅交付工程，Android 为调试测试签名。

## 2026-10-16：同步主线安卓 UI 与训练部位模块

合并当前 main 的日历、教练自定义/头像/写入开关/停止请求、精简设置、玻璃导航与专用训练部位分类/管理/复核。默认服务请求同样支持取消；默认设置隐藏上游接口和密钥输入，客户端仅发送消息及输出长度，使用用户自己的同步账号鉴权。旧配置与用户健康数据保持兼容。

本轮只更新源码和客户端，不部署服务器，不读取或变更服务器真实密钥，也不使用计费 AI 测试。默认版 Debug / Release 构建成功，50 项 JVM 和 26 项 API 35 设备测试全部通过，无失败、错误或跳过；两者 Lint 均为 0 错误、16 警告。新增代理回归检查仅使用账号鉴权、请求字段白名单以及取消后不进入 DNS/网络。`Tests/default-ai.py`、安卓/后端协议和同步编辑检查通过，15 个 Swift 回归程序与 iOS 模拟器构建通过。测试使用模拟上游与合成记录。

Release 未启用应用调试，v2/v3 签名通过。专用 API 35 模拟器验证旧 beta.2 → 普通 beta.3 → 默认 beta.3 → 普通 beta.3 覆盖安装及冷启动，均成功，无崩溃。versionCode 同为 7，签名与旧测试版一致。

默认版 APK SHA-256：`b2d398206bfc3c09d657d0c1314aa24b3b626c88bdcbdfb41dc52dba7c7d36fc`。

## 2026-10-19：beta.4

默认服务版同步普通版的趋势日期修复、训练柱状图、身体总览与记录日历、键盘收起和教练失败恢复。build 8 已公开预发布；使用新签名，beta.3 不能直接覆盖，需先保留数据再卸载重装。私钥已持久加密保存并备份，后续使用固定证书；详情见签名说明。[更新、下载与验证](android-release-1.4-beta4.md)。
