# 默认 AI 服务版本

分支：`codex/default-ai-service`，基于 `main` 的 API 设置优化创建，提交说明“提供默认ai服务”。

- 主网站（main）：https://apsonchian.ltd/liferecord/
- 独立默认版本：https://apsonchian.ltd/liferecord-default/
- Android 1.4.0-default-beta（build 6）：https://apsonchian.ltd/liferecord-default/downloads/LifeRecord-1.4.0-default-beta.apk
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

本次私有数据库、代码、环境与 Nginx 备份：`/opt/liferecord-sync/backups/default-ai-20261013-094916/`。当前服务器运行此分支后端，同时提供 main 网页与独立默认版网页；以后重新部署 main 后端时需保留默认服务模块与路由，否则默认版客户端无法调用默认服务。

APK SHA-256：`6b0fd24049126b3eed8521d668a2ddcaa7e4dd10484811fb79d81572c762b32d`。

iOS 工程包 SHA-256：`881d2c8d5d5eb0028e15246d555ff7b56f78ca3617f757a8b35a5a22b2fcd59f`。

本轮未重新执行模拟器设备 UI 测试、并发负载压测或完整渗透测试；iOS 仍仅交付工程，Android 为调试测试签名。
