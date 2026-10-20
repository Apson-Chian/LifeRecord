# 账号密码与安卓界面更新

## 使用方式

Android 的「设置 → 账号与同步」和网页登录页支持用户自主注册，不需要邀请码、同步密钥或管理员分配。

1. 新用户选择「注册账号」，自行填写账号、密码和确认密码。注册成功后自动登录，并创建独立用户 ID 与空白云端数据空间。
2. 账号为 3–32 位字母、数字、下划线或点，以字母或数字开头，不区分大小写。密码为 10–128 个字符。
3. 其他设备直接使用同一账号密码登录。已有账号修改名称或密码时需要当前密码和两次新密码确认。
4. 原来使用同步密钥的用户仍可选择「密钥连接」，再设置账号密码，保留原用户 ID 和所有记录。这只是旧用户迁移入口，新用户无需使用。

未绑定账号的安卓本机记录可在注册后同步；设备已有账号归属时会在发起注册请求前阻止新注册，避免建出多余账号或混入其他用户数据。

登录沿用原用户 ID，原记录和照片保持归属。Android 对已有数据的设备核对原身份，另一个账号不能接收本机记录。需要切换账号时先导出并清除本机数据。关闭同步只移除本机登录凭据，保留本机记录和账号归属，以便重新登录原账号。

iOS 本轮继续使用原同步密钥；安卓、网页设置密码不会使原密钥失效。

## 安全与运维

- 密码使用每次独立随机盐的 scrypt 哈希（N=131072、r=8、p=1，128 MiB 内存成本，参数随哈希保存）保存，不保存明文密码。Android 只在请求期间持有密码，返回的会话凭据由 Keystore 加密；网页只使用 HttpOnly、Secure、SameSite=Strict Cookie，不把密码或登录令牌写入浏览器存储。
- 密码登录会话有效期沿用现有 7 天；到期后重新登录。改密立即撤销该用户原有浏览器和设备会话，再签发当前会话；原同步密钥保持兼容。注销账号同时移除活动数据库中的密码哈希。
- 密码错误和未知账号返回相同错误；登录和注册分别按来源 IP 限流，成功注册也计入注册预算，不能用有效同步请求重置这些预算。重复账号及并发同名注册不会生成多余用户。
- 兼容旧版 scrypt 哈希，旧用户成功登录后自动升级计算成本。参数参考 [OWASP 密码存储建议](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)，不使用可逆加密保存密码。
- 运维可在同步服务环境内执行 `python3 Backend/manage_users.py set-password 用户ID 账号名`，交互输入并确认新密码。密码不放入命令行参数。此操作可用于首次设置或遗忘密码恢复，撤销旧会话，保留记录及原同步密钥。

新增 API：`GET /account/me`（认证）、`POST /account/register`（开放注册并自动登录）、`POST /account/login`（账号密码）、`POST /account/credentials`（认证；修改需 currentPassword）。路径均位于 `/liferecord-api`。登录与设置成功返回 userId、username、token、expiresAt，并设置浏览器会话 Cookie。Bearer 会话可用于既有同步、照片与默认 AI API；退出时可撤销当前 Bearer 会话。

更新后端代码并重启服务即可在初始化时创建凭据表；现有用户、同步记录、同步密钥不变。本次只在本机实现与验证，未部署线上服务。

## 安卓界面

统一中性背景、白色/深色卡片、字号和紫色强调色；首页标题与添加入口同排，周历改为清晰的日期格，热量与目标进度集中展示。营养环采用扁平描边，快捷记录入口缩短；设置首页新增账号卡片，底部导航增加选中反馈。历史日期显示「当日摄入」，窄屏和大字体下营养摘要改为纵向布局。

## 回归

- `python3 Tests/account-register.py`：无邀请注册、自动登录、相同密码独立盐、会话摘要存储、重复/并发注册原子性、数据隔离、旧哈希升级和注册限流。
- `python3 Tests/account-password.py`：临时 SQLite/HTTP，验证邀请绑定、账号规范化、哈希、改密与会话撤销、到期、退出、数据隔离、CSRF、密码限流。
- `node Tests/web-account.cjs`：Playwright + Chrome、模拟 API，验证手机视口登录、错误重试、自主注册、密码确认、字段清理与存储隐私。
- `node Tests/web-smoke.cjs`：原有网页编辑和多尺寸回归，旧密钥登录场景显式选择「同步密钥连接」。
- Android `AccountFlowTest`：只在无 INTERNET 权限的 sandbox 包中运行，验证实际 ViewModel 的自主注册、自动登录、原密钥迁移、重新登录、更换凭据与跨账号阻拦。

设备测试必须遵循 [Android 隔离说明](../Android/README.md)，使用一次性模拟器并先执行 APK 隔离检查。

## 2026-10-19 本机验证结果

- Debug 与 sandbox APK 构建成功；67 项 JVM 单元测试通过，Lint 无错误（保留项目原有警告）。
- 新建 Android 15 / API 35 一次性模拟器，最终 35 项功能设备测试通过，包含自主注册与自动登录、确认密码、已绑定设备注册阻拦、旧密钥迁移，以及 1.6 倍字体的表单与导航可达性。
- 账号密码 HTTP 集成测试、默认 AI 网关回归、9 项共享数据协议测试、网页账号流程与现有网页完整回归通过。全部使用临时数据或模拟 API，未连接真实账号或计费 AI。
- 一轮连续截图曾出现 UiAutomation 连接故障；重启一次性模拟器后，功能回归与截图分开执行。此问题不计为应用功能通过的依据。

实际界面截图（示例/合成数据）：[浅色首页](../Android/screenshots/account-update/today-light.png)、[深色首页](../Android/screenshots/account-update/today-dark.png)、[设置首页](../Android/screenshots/account-update/settings-light.png)、[账号登录](../Android/screenshots/account-update/account-login.png)、[注册账号](../Android/screenshots/account-update/register.png)。
