# LifeRecord 1.4 公开邀请测试

Android / iOS / Web 默认从空白记录开始。新安装不自动加入示例数据，不再采用开发者的 181 cm / 64 kg 增肌档案。默认目标是通用占位值，用户需自行填写。已有用户自己的资料与记录保留。

## 用户与数据库

服务器使用 SQLite：`users` 保存独立用户及同步凭证摘要，`sessions` 保存随机会话摘要与到期时间，`user_records` 保存用户、类型、记录 ID、更新时间和删除状态，`record_fields` 用有类型的父子行保存字段和训练组，`user_images` 保存照片所有权与文件索引。数据库没有用一份 JSON 文件作为数据源，也不再把整条健康记录写入 payload 文本列。JSON 仅用于跨端协议、导出和 AI 交互。此结构保留不同客户端的可选字段，支持以后增加字段而无需丢弃旧数据。

Android 数据库版本 2 将旧 `records.payload`、档案、对话和偏好迁入 `documents/fields` 的有类型字段行。SQLiteOpenHelper 在事务内迁移；失败则回滚。iOS 继续使用 SwiftData 数据库，保留原有实体以兼容已安装用户；部分嵌套列表仍由 SwiftData 字段序列化。

后端第一次启动会把旧私人记录与照片只迁给 `legacy-owner`，其他用户从空白数据库空间开始。迁移事务完成后删除旧表。保留 `LIFERECORD_SYNC_TOKEN` 作为原有账号的凭证；绝不能发给测试者。测试者使用独立的随机 256 位同步密钥；服务器只保存 SHA-256 摘要。

在服务器加载服务的环境后创建测试用户（不要把命令输出放进公开日志）：

```sh
set -a
. /etc/liferecord-sync.env
set +a
python3 /opt/liferecord-sync/manage_users.py create '测试者名称'
python3 /opt/liferecord-sync/manage_users.py list
python3 /opt/liferecord-sync/manage_users.py revoke USER_ID
```

密钥只输出一次，分别私下给每位测试者。用户在 App 和网页填写自己的同一密钥。公开测试采用邀请方式，目前不开放无审核注册或密码找回。遗失密钥请联系组织者。撤销不会删除记录；网页注销账号则删除在线记录与照片并使所有会话及 App 凭证失效。

同一设备更换同步服务器或账号前，先导出、清除本机数据。客户端保留账号绑定，防止把上一个用户的健康记录上传给下一个用户。仅关闭同步不会解除绑定。客户端按完整 API 地址保存 AI Key；改变地址后需为新地址重新填写密钥。

## 自定义设置

两端支持 HTTPS Chat Completions 地址、自定义模型、Bearer / api-key / 自定义认证头、图片开关、1–12 张照片、256–65536 输出 Token、`max_tokens` / `max_completion_tokens`、Temperature 0–2 或不发送、可关闭 JSON response_format、额外请求参数 JSON（例如 top_p）、长期偏好与 AI 写入权限。扩展参数不能覆盖模型、消息、stream 与生成设置；不要在其中填密钥。AI 默认只读。iOS 可直接在教练输入框上方开启写入，按明确要求保存有效操作后显示数据库回执；关闭权限时会明确提示“未保存”。安卓在设置中开启写入后，仍需核对草稿并点击“确认并保存”才实际写入。

每个预设服务商可保留自己的配置。支持系统/浅色/深色主题、四种强调色，以及已有的称呼、每日目标、提醒、常用餐食和动作库。iOS LifeTrack 共享默认关闭。网页提供主题选择与隐私说明。

接口仍需兼容 OpenAI Chat Completions。未实现 Anthropic Messages / Gemini 原生协议；相应网关可配置为兼容接口。网页现支持预设和自定义接口、认证头、生成参数及服务商配置切换。自定义地址仅接受公网 HTTPS 443 端口、不含账号或查询参数；服务器校验所有 DNS 结果，固定本次连接的 IP 并验证 TLS 域名，不跟随重定向。网页 Key 只保存在页面内存，并按完整地址与认证配置隔离；刷新或退出后需重新填写。测试者需提供自己的 AI Key，不能使用原有私人账号的服务器 AI 额度。

网页设置集中管理 API、外观、导出与账号，手机底部提供导航。身体与训练记录支持直接编辑，训练动作、组数及自定义部位可维护。餐食与身体/训练历史列表每页 20 条；普通删除与包含删除的 AI 批量操作要求确认。自动刷新改为鉴权后的 ETag 条件读取，未变化返回 304，不再上传整份快照；失败后逐步延长重试间隔。数据发生变化时仍下载完整快照，尚不是逐条增量协议。按组织者要求，AI 数据范围保留原有方式。

## 安全检查与边界

已增加按用户隔离的记录、照片及删除标记、随机且可撤销的 7 天 Cookie 会话、CSRF Origin/JSON 校验、登录失败限速、反向代理请求/连接限速、请求超时与大小限制、每用户 30000 条记录、16 MiB 字段文字 / 600000 个字段节点、250 张照片限额、安全响应头、严格记录 ID、HTTP 明文拒绝、禁止带凭证的重定向、退出清空浏览器私有内容，以及禁止自动导入不属于当前账号的旧浏览器缓存。密钥继续使用 Android Keystore / iOS Keychain，服务端与网页不打印凭证或 AI 提示词。

数据库与照片以服务器文件权限保护，未提供数据库静态加密或端到端加密；运维管理员仍能访问服务器上的健康数据。备份必须保存在非 Web 目录、权限 0700/0600，并由组织者按保留策略清理。注销不能自动删除历史备份。公开分发前检查反馈渠道，反馈不要包含密钥或完整个人记录。不能将这些改动视为完整渗透测试或法律合规认证。

检查依据：[OWASP 会话管理](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)、[OWASP SSRF 防护](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)。

## 构建与回归

```sh
python3 Tests/public-beta.py
python3 Tests/sync-edit.py
python3 Tests/admin-api.py
python3 Tests/android-sync.py
./iOS/Tests/run.sh
# Android 工程内
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
./gradlew :app:connectedDebugAndroidTest
# Web：需 Playwright + Chrome
node Tests/web-smoke.cjs
```

APK 是调试测试包，非商店签名发布。iOS 工程可通过 Xcode 构建；对外通过 TestFlight 分发仍需要组织者自己的 Apple Developer 签名、上传和测试邀请。不要把开发者真机数据、同步密钥、服务端环境文件或 tester 凭证文件打入源码包或公开下载目录。
