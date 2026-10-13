# 1.4 公开测试验证记录

验证日期：2026 年 10 月 13 日。

仓库提交前再次复核：`Tests/public-beta.py`、`Tests/web-optimizations.py`、`Tests/admin-api.py`、`Tests/sync-edit.py` 与 `Tests/web-smoke.cjs` 均通过；Python/JavaScript 语法检查及 `git diff --check` 通过，线上健康接口返回正常。候选源码文件没有匹配本机私有测试者凭据或常见密钥格式，`dist/` 分发包与凭据继续被 Git 忽略。本次提交没有重新构建移动端，移动端验证沿用下述已完成结果。

同日网页后续优化已上线：设置面板、自定义 API、训练动作/组编辑、误删确认、20 条分页和 ETag 条件读取。新增 `Tests/web-optimizations.py` 验证内网/混合 DNS 拒绝、TLS 域名与 IP 固定、禁止重定向和认证头注入、生成参数及条件读取鉴权；网页回归增加训练嵌套字段保留、取消/确认删除、分页、只读刷新、配置预设和临时密钥隔离，均通过。原有用户隔离、同步和后台编辑回归仍通过。线上验证新资源校验值、服务健康、数据库 quick_check、原有凭证鉴权、304 响应及自定义地址拒绝内网；没有调用计费 AI。详情见 `Docs/web-optimization.md`。

- Android：31 项单元测试通过；Debug APK 与 lint 构建成功；独立 Android 15 模拟器 16 项设备测试全部通过，包括 SQLite v1 → v2 嵌套训练数据迁移、持久化、清除数据与密钥、界面操作。
- Android 协议：真实 Kotlin 生成的同步样本经 Python 后端往返验证通过。
- iOS：Xcode 模拟器构建成功；13 个 Swift 回归程序通过，包括新的通用默认资料、默认关闭共享和 AI 写入、独立 UserDefaults、服务商配置切换与隐私重置检查。
- Backend：现有同步、后台编辑回归通过；新增临时 HTTP 测试覆盖旧库迁移、同 ID 的跨用户隔离、照片越权拒绝、会话到期、退出撤销、CSRF、JSON Content-Type 和删除账号。
- Web：Playwright 模拟 API 回归通过，覆盖编辑、AI 预览保存、XSS 转义、4 个响应式宽度、深色主题背景、重新登录和注销按钮；真实线上 Chrome 用空白测试账号验证登录、加载、主题、退出会话失效与隐私页面，无 JavaScript 异常。
- 线上：迁移前使用 SQLite backup 创建一致备份，先迁移副本并逐条比较。308 条原有记录只属于 legacy-owner；5 个新用户的记录、照片和目标均为空。数据库 integrity_check 为 ok，原有凭证可继续访问。
- 服务：liferecord-sync 为 active；nginx -t 通过。CSP、no-store、nosniff、Referrer-Policy、X-Frame-Options、Permissions-Policy、HSTS、HTTP → HTTPS 跳转与 API 请求限速已部署。
- 分发：最终 APK 与旧版 1.3 使用同一调试证书，可覆盖升级。私有邀请凭证独立保存在 dist/private/，被 Git 忽略，不包含在下载包中。

局限：未使用用户的真实 AI Key 做计费接口测试；这不是完整渗透测试。服务器数据库未做静态加密或端到端加密，备份删除需运维处理。iOS 尚未上传 TestFlight：本机找到开发证书，未找到发布证书，仍需要发布签名与 App Store Connect 上传配置。APK 为测试调试版本，不是商店生产发布签名。

服务器备份（非 Web 目录）：`/opt/liferecord-sync/backups/public-beta-20261013/`。独立测试者凭证文件权限 0600；本机私有凭证目录权限 0700。
