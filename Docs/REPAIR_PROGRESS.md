# 修复进度

2026-10-16 开始；原审查结论未修改。状态必须以实际测试为依据。

## 阶段状态

| 阶段 | 状态 | 原因 |
| --- | --- | --- |
| 1 C09 | 已修复并验收 | 基线检查失败；专用 APK 检查、50 项 JVM、3 项专用隔离和完整 30 项设备测试通过 |
| 2 数据契约 | 契约基础回归通过，含遗留项 | C01/C07/C10/C14 已修复回归；C11 照片部分待 6，浏览器 UI 待 5 |
| 3 原子性 | 核心回归通过，尚未完整验收 | C04 已修复；C06 强杀/断电跨存储提交仍待验证 |
| 4 冲突 | 候选设计，未实现 | 文档已列 CAS/revision/幂等与旧端路径；三端收敛尚未执行 |
| 5 Web | 未开始 | 按顺序推进 |
| 6 照片 | 未开始 | 仅允许未来的只读 GC 扫描 |
| 7 统计/联动 | 未开始 | 按顺序推进 |
| 8 R01–R07 | 未验证 | 审查风险不等于本次已发生漏洞 |
| 9 性能/维护 | 未开始 | 先建立性能基线 |

## 阶段 1：C09

- 原因：旧设备测试复用正常应用包；清 app.store/Secrets 后 Activity 自动同步，测试恢复不能撤销云端修改。
- 基线失败测试：`python3 Tests/android-isolation.py Android/app/build/outputs/apk/debug/app-debug.apk`，断言失败 `UNSAFE test target package: ltd.apsonchian.liferecord`。未安装、未运行旧设备测试。
- 实现：新增 sandbox 构建与专用 Application；包名 `.instrumented`，自有 Android UID/私有目录，数据库 `instrumented.db`，Secrets `instrumented-secrets`/独立 Keystore alias；无 INTERNET 权限，内存 fake 拒绝其他域名；runner 在执行测试之前核验包与权限。
- 相关文件：`Android/app/build.gradle.kts`；`src/main/.../LifeRecordApplication.kt`、`data/Store.kt`；`src/sandbox/AndroidManifest.xml`、`IsolatedLifeRecordApplication.kt`；`src/androidTest/.../IsolatedTestRunner.kt`、`IsolationTest.kt`、`StorageTest.kt`、`AppFlowTest.kt`；`Tests/android-isolation.py`。
- 新增回归：检查成品 APK；运行时包名/权限/数据库检查；清测试库/密钥并注入取消异常后不影响独立前哨；fake sync；误配生产地址在 socket 前拒绝。
- 实际命令/结果：首次 offline 构建因本机缺失已声明的 espresso AAR 失败；随后下载已有依赖后重新构建通过，没有新增业务依赖。
- 兼容性：正常 Debug/Release 包名、数据库文件、偏好名、Keystore alias 和同步协议保持原值；不读取或迁移真实安装数据。设备测试改用 `connectedSandboxAndroidTest`。
- 回滚：撤销本阶段源码/构建变更即可；正常安装没有数据变更。即使回滚也禁止运行旧的共包设备测试。一次性模拟器和测试包可另行移除，不触及正常包。
- 验收：C09 的独立包/存储/网络隔离通过。没有在真实手机、真实账号或普通安装中运行设备测试。API 26–34 未重跑设备流程；本次设备为新建的 API 35 一次性模拟器。

### 阶段 1 实际执行记录

仓库根目录执行，Gradle 命令在 `Android/` 执行。ADB 只操作本次在 `/tmp/liferecord-repair-android/avd` 新建的 `liferecord_repair_isolated`（emulator-5584），此前设备列表为空。

| 命令 | 结果 |
| --- | --- |
| `python3 Tests/android-isolation.py Android/app/build/outputs/apk/debug/app-debug.apk` | 修复前失败：共用用户包名；没有安装或运行旧 APK 的设备测试 |
| `./gradlew --offline --no-daemon :app:assembleSandbox :app:assembleSandboxAndroidTest :app:testDebugUnitTest` | 首次因本机缺失 Espresso 缓存失败 |
| `./gradlew --no-daemon :app:assembleSandbox :app:assembleSandboxAndroidTest :app:testDebugUnitTest` | BUILD SUCCESSFUL；JVM XML：50 tests / 0 failures / 0 errors / 0 skipped |
| `python3 Tests/android-isolation.py Android/app/build/outputs/apk/sandbox/app-sandbox.apk` | PASS：独立包名、fake Application、无 INTERNET、无 shared UID |
| `python3 -O Tests/android-isolation.py Android/app/build/outputs/apk/debug/app-debug.apk` | 仍拒绝；检查不依赖可被 `-O` 关闭的 Python assert |
| `/private/tmp/liferecord-android-sdk/platform-tools/adb -s emulator-5584 install -r Android/app/build/outputs/apk/sandbox/app-sandbox.apk` | Success；目标包仅 `.instrumented` |
| 同上 install：`Android/app/build/outputs/apk/androidTest/sandbox/app-sandbox-androidTest.apk` | Success；runner 包仅 `.instrumented.test` |
| `/private/tmp/liferecord-android-sdk/platform-tools/adb -s emulator-5584 shell am instrument -w -r -e class ltd.apsonchian.liferecord.IsolationTest ltd.apsonchian.liferecord.instrumented.test/ltd.apsonchian.liferecord.IsolatedTestRunner` | OK (3 tests) |
| 同上 instrument，去掉 `-e class …IsolationTest` | OK (30 tests)，91.188 秒；包括既有完整 UI/存储流程与 3 项新增隔离回归 |

原始日志：`/tmp/liferecord-c09-before.log`、`/tmp/liferecord-c09-build.log`、`/tmp/liferecord-c09-isolation-device.log`、`/tmp/liferecord-c09-device-all.log`。日志仅包含合成测试状态，不包含真实密钥或健康记录。

### 阶段 1 最终补充验证

- `./gradlew --offline --no-daemon :app:assembleSandboxAndroidTest :app:assembleDebug`：通过（7 秒）。普通 Debug 成品仍为 `ltd.apsonchian.liferecord` / versionCode 7 / `1.4.0-default-beta.3`，保留 INTERNET 权限，未混入 fake Application；没有安装该普通包。
- 为前哨检查补充取消异常注入后，仅重装隔离 runner 并重跑 `IsolationTest`：`OK (3 tests)`。独立前哨记录和密钥仍完整；完整 30 项设备流程结果见上表。
- `python3 Tests/android-sync.py`：通过，本次 JVM 生成的真实 Kotlin 样本仍可由原后端往返及处理训练删除。协议未变。
- `git diff --check`：通过。原审查文件没有修改；SHA-256 为 `9c500e42df48e72ded9b29083b5a336c14de11b58ab9356fe4a9018b0ce2ed0f`。
- 本阶段只有 C09 标记已修复；其余 19 项已确认问题及 7 项风险尚未完成。DATA_CONTRACT 是待测试的候选设计；冲突文档仍为阶段 4 占位，均不能作为阶段验收证明。

## 阶段 2：数据契约及第一批对应修复

- 编号：C01/C07/C10/C14 的本地回归通过；C11 的非 UUID 显式诊断、原始导出、UUID 别名处理已实现，照片归属/共享引用部分留给阶段 6，不能将 C11 整项标为全部解决。
- 修改文件：`Docs/DATA_CONTRACT.md`；`Tests/Fixtures/data-contract.json`、`data-contract.py`、`contract-roundtrip.py`、`web-contract.cjs`；`Backend/server.py`；Android `data/Models.kt`、`data/WorkoutParts.kt`、`AppViewModel.kt`、`ui/Editor.kt`、`ui/Trends.kt`、`src/test/.../DataContractTest.kt`；iOS `Services/SyncModels.swift`（原 Codable 类型拆出供真实编解码测试）、`SyncCompatibility.swift`、`RecordInput.swift`、`SyncService.swift`、`AppSettings.swift`、`CoachActions.swift`，`Views/EntryViews.swift`、`MealHistoryView.swift`、`FavoriteFoodsView.swift`、`CoachView.swift`、`SettingsHomeView.swift`；Swift `data-contract.swift`、`coach-meal-actions.swift`、`settings-privacy.swift`、`run.sh`；Web `app.js`。`Tests/public-beta.py` 增加诊断接口认证/账号隔离断言。
- 修复前：sync 缺少关键类型检查；iOS 严格 Codable 把合法旧字段缺省当错误，坏记录整批失败且非 UUID 静默遗漏；Android 新输入与历史读取共用狭窄范围，旧训练部位丢失；Web 只允许 6 图；iOS 餐食/目标可提交超范围值。
- 实现：写入校验与历史读取分开；原样/过期历史重放不写库，发生变化才按合并后的完整记录校验。后端保留旧端省略和未知扩展字段。Swift 只读投影隔离不可表示记录并列出原因，应用私有按账号摘要保存原始快照，导出带 compatibilitySnapshot，未修改版本上传重用原始 wire（不写回展示默认和随机动作 ID）。Android 保留原始 JSONObject 的历史数值；新输入使用统一范围。iOS 手动/AI/常用餐食采用统一上限，目标使用可保留的草稿、整体验证后提交。旧训练缺省 fallback，显式 [] 仍为空；编辑未动部位不写 []。Web 容许 12 图。
- 新增失败回归：后端无效类型/缺 date 批次；Swift 旧 meal 缺 kind；AI calories=20001；Kotlin 共享范围与数字字符串、旧部位、历史 bodyFat=0/缺 fiber；UUID 大小写重复；Web 7/12 图数量表达式；原样历史异常重放。失败日志：`/tmp/liferecord-contract-before-{python,kotlin,swift,coach,id,web,history,replay}.log`。新增 API 测试覆盖未认证拒绝和 A/B 账号隔离。
- 实际命令：`python3 Tests/data-contract.py`（最终 9 项，含 bool/number 重放区分与过期内容校验）；Android `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleSandbox`（54 项 JVM、构建通过）；`./iOS/Tests/run.sh`（19 个程序）；`xcodebuild -project iOS/LifeRecord.xcodeproj -scheme LifeRecord -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/liferecord-repair-ios-build CODE_SIGNING_ALLOWED=NO build`（完整构建通过）；`node Tests/web-contract.cjs`、`node --check Web/app.js`；`python3 Tests/contract-roundtrip.py`（真实 Kotlin wire→临时后端→Swift 解码/出站兼容编码→后端→Web JSON）；`python3 Tests/{sync-edit,admin-api,public-beta,default-ai,web-optimizations,android-sync}.py` 各自执行通过。细节日志在 `/tmp/liferecord-contract-*`、`/tmp/liferecord-repair-*.log`。
- 未解决/边界：Node 数量/JSON 回归不等于浏览器回归，真实后端 Playwright 留到阶段 5；本次尚未重跑修改后 Android 全 UI 或安装 iOS App；C11 照片部分待阶段 6；非 UUID 服务端兼容入口继续支持旧端，不声称已强制新 UUID 协议；复杂历史 schema/故障恢复/跨账号异步安全留待 R02/R04/R06。Python 3.14 报告原有 SQLite 连接未关闭警告，快照连接关闭将随 C04 修复，其余资源基线留阶段 9。
- 数据兼容：未新增数据库 schema、批改 ID/时间、清除 tombstone、删除历史记录/图片或修改密钥。新客户端仍生成 UUID；唯一 UUID 别名解析到原主键，多别名碰撞明确拒绝修改并提供只读导出。不把历史异常值夹紧到新范围。
- 回滚：撤销阶段 2 源码和界面变更即可，没有数据迁移需要反向执行；保留诊断导出文件，不能随回滚清理用户附件。旧客户端可继续使用原协议；历史档案/记录未被批量更新。
- 阶段验收：契约基础与上述回归通过，允许开始阶段 3 的隔离失败测试；C11、浏览器 UI 及生产准备状态继续保留未解决标记。

## 阶段 3：原子性核心修复（C06 崩溃提交边界未完整验收）

- 编号：C04 已修复并通过确定性交错测试；C06 的入站预校验、隔离模型写入、偏好暂存、保存失败/取消与无关草稿保护已实现；跨存储进程强杀/断电提交仍未验证，C06 不标记完全解决。
- 文件：`Backend/server.py`；`Tests/snapshot-atomicity.py`；`iOS/LifeRecord/Services/SyncService.swift`、`Views/CoachView.swift`；`iOS/Tests/sync-atomicity.swift`、`sync-atomicity.sh`、`coach-atomicity.swift`、`coach-atomicity.py`、`run.sh`；测试说明。
- 修复前：后端字段读取不在同一事务；iOS 先改共享上下文再验证后续项，失败会留下模型，AI 的目标和动作库先写 UserDefaults，外层 rollback 会丢弃其他草稿。
- 实现：单连接显式 BEGIN 读事务在 WAL 中固定元数据与字段版本，finally 关闭连接；iOS 完整校验入站和计算目标后，使用独立 ModelContext，失败仅回滚该上下文，并拒绝覆盖同目标的未保存模型。目标档案在模型 save 成功后投影。AI 批次使用独立上下文与暂存档案/动作库，检查暂存期间版本，模型成功保存后同步投影偏好；移除 AI 回调对共享上下文的全局 rollback。
- 新增回归：后端独立连接在读元数据后并发删除餐食并更新身体；Swift 第 N 项非法部位、提交注入磁盘错误、取消、正常成功、其他草稿未被保存/回滚；实际 CoachView 私有 writer 注入保存失败，断言模型、目标、动作库均未变化，成功时仍保留无关草稿。
- 失败证据：`/tmp/liferecord-atomic-before-backend.log` 明确 mixed snapshot；`/tmp/liferecord-atomic-before-swift.log` 明确 failed sync leaked a meal（用 Git 基线真实 apply 方法加同文件测试桥复现）；`/tmp/liferecord-atomic-before-coach.log` 明确 failed AI batch changed profile/library preferences。最初测试构造/路径编译错误已修正，未将编译失败当作机制复现。
- 实测命令：`python3 Tests/snapshot-atomicity.py`；`./iOS/Tests/sync-atomicity.sh`；`python3 iOS/Tests/coach-atomicity.py` 均通过；完整 `./iOS/Tests/run.sh` 和模拟器 `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`；共享契约与往返命令见阶段 2，继续回归。
- 未解决：SwiftData 与 UserDefaults 没有共同持久事务/提交日志。本修复保证 save 失败/取消在提交前不修改偏好，提交与非抛出投影之间没有 await；**不能证明在模型已提交、偏好尚未持久落盘时进程强杀/断电的全量恢复**。需要持久提交日志或统一权威存储，并先在副本验证 schema 与恢复；关联 R02。AI 成功后回执消息保存失败仍可能显示“待核对”，幂等与目标版本由阶段 4 处理。本阶段未把这些标为安全。
- 数据兼容：无 schema 迁移、历史字段/ID 更新、生产写入或照片删除；读事务和内存上下文隔离不改变协议。偏好仍使用原键，隔离测试使用专用 suite。
- 回滚：撤销本阶段源码即可，无反向数据库迁移；保留阶段 2 的原始诊断导出。撤回后 C04/C06 会重新出现，因此不能把回滚当作生产修复。
- 阶段验收：C04 通过；C06 运行时失败核心回归通过，崩溃提交边界未验收。第 4 阶段只写候选设计，未修改冲突行为，未宣称三端收敛。

## 当前代码定位（本次工作区）

原审查行号仍指 ca552f1f 基线，报告不改写；以下是本次修改入口。

| 编号 | 当前入口 |
| --- | --- |
| C09 | `Android/app/build.gradle.kts:15,22,30`；`src/androidTest/.../IsolatedTestRunner.kt`；`src/sandbox/.../IsolatedLifeRecordApplication.kt` |
| C01 | `Backend/server.py:131,200,255`；`iOS/LifeRecord/Services/SyncModels.swift`、`SyncCompatibility.swift`；Android `data/Models.kt:58` |
| C07 | `iOS/LifeRecord/Services/RecordInput.swift`；`AppSettings.swift:83,334`；`Views/SettingsHomeView.swift:62`；手工/AI/常用餐食调用点见阶段 2 文件表 |
| C10 | Android `data/Models.kt:95,122`；`Web/app.js:2` 的 MAX_MEAL_PHOTOS 与保存检查；共享样本 limits |
| C11（部分） | `Backend/server.py:239,358`；`iOS/LifeRecord/Services/SyncService.swift:42,44,174`；`SyncCompatibility.swift` |
| C14 | Android `data/WorkoutParts.kt:20`、`ui/Editor.kt:104,127`、`ui/Trends.kt:90` |
| C04 | `Backend/server.py:332` |
| C06（部分） | `iOS/LifeRecord/Services/SyncService.swift:276`；`Views/CoachView.swift:755,774,1021` |

### 最终回归与发现的退化

- 最终重跑 `Tests/sync-edit.py` 发现新引入的“过期请求提前跳过”绕过动作校验；已移除提前跳过，继续先校验发生变化的内容，再按既存版本忽略过期写入。未修改原测试来掩盖退化。新增 `test_changed_invalid_stale_request_still_validates`；最终契约测试为 9 项。
- `python3 Tests/{sync-edit,admin-api,public-beta,default-ai,web-optimizations,data-contract,snapshot-atomicity,android-sync,contract-roundtrip}.py` 各自实际执行。最终全部通过；往返使用本次 JVM 重新生成的样本。
- Android 最终 `./gradlew --offline --no-daemon :app:testDebugUnitTest :app:assembleSandbox :app:assembleSandboxAndroidTest`：通过；XML 汇总 **54 tests / 0 failures / 0 errors / 0 skipped**。
- Swift 最终 `./iOS/Tests/run.sh`：19 个既有/契约程序加同步、AI 原子性两个真实方法流程，共 **21 个程序/流程通过**。完整 iOS 模拟器构建 `BUILD SUCCEEDED`，没有安装运行 iOS App。
- `node Tests/web-contract.cjs`、`node --check Web/app.js`、`git diff --check`：通过。
- 日志：`/tmp/liferecord-final-*.log`。测试生成数据仅在临时目录/独立模拟器；仓库业务和文档修改均未提交。

### 最终隔离设备验收

- 对最终构建再次运行 APK 隔离检查：通过；只在本次新建的 emulator-5584 安装 `.instrumented` / `.instrumented.test`。
- 执行 `/private/tmp/liferecord-android-sdk/platform-tools/adb -s emulator-5584 shell am instrument -w -r ltd.apsonchian.liferecord.instrumented.test/ltd.apsonchian.liferecord.IsolatedTestRunner`：**OK (30 tests)**，79.264 秒；日志 `/tmp/liferecord-final-device.log`。包括修改后的契约/历史读取代码所依赖的现有 UI/持久存储流程。
- 运行完关闭本次一次性模拟器。未安装普通 Debug/Release 包到任何用户设备，也未运行旧共包设备测试。

当前任务未全部完成：阶段 3 的跨存储崩溃提交边界仍需补齐与验证，不能以运行时异常测试通过替代；C11 照片部分、阶段 4–9 以及 R01–R07 的完整验证均尚未完成。生产发布保持阻断；本记录不宣称 20 项问题全部修复。
