# 共享与跨平台回归

Android 设备测试先构建独立 sandbox 包并执行 `python3 Tests/android-isolation.py Android/app/build/outputs/apk/sandbox/app-sandbox.apk`，再在新建的一次性模拟器运行 `Android/` 下的 `./gradlew :app:connectedSandboxAndroidTest`。普通用户包不可作为设备测试目标；不得给测试包录入真实账号。数据库、密钥和网络均由测试包隔离，详情见 [Android 说明](../Android/README.md)。

以下命令在仓库根目录执行，使用临时数据库或模拟 API。

- `python3 Tests/account-register.py`：无邀请注册、自动登录、独立密码盐、注册并发/重复原子性、数据隔离、旧哈希升级与独立限流。
- `python3 Tests/account-password.py`：邀请账号设置、密码登录/修改、会话撤销、到期、退出、原密钥兼容、用户隔离与密码限流。
- `node Tests/web-account.cjs`：Playwright + Chrome，手机尺寸账号登录、自主注册、密码确认与敏感输入清理；使用模拟 API。

- `python3 Tests/default-ai.py`：鉴权、默认配置不下发、客户端覆盖拒绝、额度持久化、并发限制与自定义回退；不调用计费接口。

- `python3 Tests/public-beta.py`：私人数据库迁移、用户和照片隔离、会话到期/退出、跨站请求防护和账号删除。
- `python3 Tests/sync-edit.py`：餐食、训练、照片编号、删除标记、旧客户端字段保留与更新冲突。
- `python3 Tests/admin-api.py`：后台编辑与 AI 操作协议。
- `python3 Tests/web-optimizations.py`：自定义 API 的公网 HTTPS、DNS 与认证头防护、禁止重定向、生成参数和按用户鉴权的 ETag 条件读取；不调用真实计费接口。
- `python3 Tests/android-sync.py`：验证 Kotlin 实际生成的同步 JSON 与后端兼容；先在 `Android/` 运行 `./gradlew :app:testDebugUnitTest`。
- `node Tests/web-smoke.cjs`：需要 Playwright 与 Chrome，检查 Web 编辑、AI 复核、搜索和响应式布局。

Swift 回归已移至 `iOS/Tests/`，运行 `./iOS/Tests/run.sh`；安卓单元与设备测试位于 `Android/app/src/test/`、`Android/app/src/androidTest/`。

新增修复回归：

- `python3 Tests/data-contract.py`：共享范围/类型、整批拒绝、历史原样重放、UUID 别名及只读诊断。
- `python3 Tests/contract-roundtrip.py`：先运行 Android 单元测试生成 Kotlin 样本，再验证真实 Swift 编解码与临时后端往返。Node 的 JSON 检查不等于浏览器 UI 验证。
- `node Tests/web-contract.cjs`：Web 实际表单照片数量表达式与共享 JSON 样本。
- `python3 Tests/snapshot-atomicity.py`：独立 WAL 写连接交错删除/更新，不允许混合快照。
- `./iOS/Tests/sync-atomicity.sh`、`python3 iOS/Tests/coach-atomicity.py`：实际私有方法生成测试桥，内存数据库/独立偏好、保存失败/取消/无关草稿；已纳入 Swift run.sh，不访问网络或真实 Keychain。

导览与示例数据回归：Swift `demo-data`（已纳入 `iOS/Tests/run.sh`）、Android `DemoDataTest` 与 `AppFlowTest` 的两项 onboarding 流程；设备测试仍仅运行于新建一次性模拟器的 sandbox 包。[覆盖与预览](../Docs/onboarding-and-demo.md)。
