# 按生效日期保留和纠正健身目标

2026-10-22，Android beta.10 与同版 iOS 源码。新目标从保存当天起生效；更早日期继续使用当时的目标。记录有误时可以逐条修正，对应期间的圆环和达标统计随之重新计算。

## 使用

在“设置 → 个人与目标”保存新目标，在“设置 → 目标历史”查看并点“编辑此记录”。可以修改健身方向、起始体重、目标体重、每周变化及全部营养目标；普通记录还能纠正生效日期。最初保留的目标可以改数值，范围仍为历史基准。日期不能选未来；所选日期已有其他目标时，会提示编辑那一条，避免直接覆盖。

例如 21 日目标 100g、22 日开始 150g：常规目标更新不改变 21 日合环；如果后来确认 21 日实际应为 90g，可以编辑那条历史记录，21 日会按 90g 重算，22 日仍为 150g。修改一条记录只影响其生效日起至下一条记录前一天的区间；修改当前生效的记录同时更新当前个人目标。餐食或测量本身没有被冻结，补记与纠错仍会更新对应日期内容。

同一天多次普通保存仍以当天最后一版为准。仅改称呼/身高不新增版本，营养调整不重置体重阶段。模板与 AI 确认写入也保留历史。未保存退出有草稿放弃提示；非法输入、重复日期和被同步更新的草稿不会保存。

升级无法自动推断旧版本已经丢失的目标数字；首次变更前的当前值保存为“最初保留的目标”。现在可以自行纠正已保留的每条历史记录，尚未保留过的任意日期不提供新增历史条目的入口。当前版本没有删除或预定未来目标的入口。

## 协议与合并

`settings.goalHistory` 每条包含 `id`、Gregorian 民用日期 `effectiveDate`、原始 `updatedAt` 及八个完整目标字段：`fitnessGoal`、`baselineWeight`、`targetWeight`、`weeklyWeightTarget`、`calorieGoal`、`proteinGoal`、`carbsGoal`、`fatGoal`。`1970-01-01` 是最初目标的内部哨兵，不当作真实开始日期显示。

历史纠错保持 `id`，新增可选的 `revisionAt`、`revisionID`。同步先按 ID 合并，选择最新修订，再按日期选择当天版本；移动日期后，旧快照中的同 ID 旧日期不会重新出现。未修订的基准仍选择最早值，显式修订的基准优先使用最新修订。并发同时间修订用 `revisionID` 作稳定裁决。

同日普通保存复用该日可见记录 ID。保留原始同日不同 ID 条目用于离线合并，界面只显示该日当前版本。历史独立于当前资料时间戳合并；修订后重新推导当前目标，iOS 保留未知原始协议字段时也保留已推导的目标。空历史不能擦除已有版本。新安装首次同步旧账号不会把中性默认占位值伪造成历史。

`goalTimeZone` 提供 IANA 时区，已保存日期不随旅行移动；缺少时区的旧写入使用已存时区，否则 UTC。历史数值保持有限性验证，显式编辑按现有目标范围校验。多端都应升级以正确显示修订。配套后端已部署；自托管者需同时部署 `server.py` 和 `goal_history.py`。Web 读取适配进入源码，本轮未替换线上静态页面。

## 验证

- Android Debug / Release 各 79 项 JVM 回归通过，两个构建和 Lint 通过（Release 0 错误 / 16 警告，Sandbox 0 错误 / 15 警告）。
- Android 12 / API 31、Android 15 / API 35 各完整 68 项设备回归通过。新增实际编辑历史值、初始基准、原生日期选择、分段圆环和冷启动保留；原有按日期保留、同步、模糊、动画、键盘、存储回归保留。
- JVM 检查区间内外目标、移动日期后重放、基准修订、非法值、未来/重复日期、过期草稿和正常后续保存。
- Swift 脚本和 iOS 构建通过；实际 AppSettings 回归覆盖历史纠错、重载、立即再次保存、非法保存原子性及旧草稿。新增表单数字校验、未保存退出提示。CUA 坐标点击返回 `noWindowsAvailable`，无法切到未暴露于 AX 的底部设置标签，因此本轮未完成 iOS 新增编辑页的原生点击验收；beta.9 的界面记录保留为当时结果。
- 共享 Kotlin / Swift 编码与临时后端往返通过，修订字段单独解码和重编码验证；Web 的实际解析函数覆盖日期移动、旧快照和基准修订。
- 配套后端九项服务器 Python 3.10 隔离回归、公网合成账号功能与清理通过。[上线详情](goal-history-edit-deployment-2026-10-22.md)

## 安卓截图

仅使用离线测试包和合成数据，不作为厂商真机帧率或驱动一致性的证明。

| 平台 | 纠正生效日期 | 修改历史值 | 纠正基准后的昨天 |
| --- | --- | --- | --- |
| Android 12 | [编辑](../Android/screenshots/goal-history-edit-api31/correction-editor.png) | [历史](../Android/screenshots/goal-history-edit-api31/corrected-history.png) | [圆环](../Android/screenshots/goal-history-edit-api31/corrected-yesterday.png) |
| Android 15 | [编辑](../Android/screenshots/goal-history-edit-api35/correction-editor.png) | [历史](../Android/screenshots/goal-history-edit-api35/corrected-history.png) | [圆环](../Android/screenshots/goal-history-edit-api35/corrected-yesterday.png) |

beta.9 初始实现的说明与 iOS 界面验收见[当时发布记录](android-release-1.4-beta9.md)。
