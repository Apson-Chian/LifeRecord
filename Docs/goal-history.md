# 按生效日期保留健身目标

2026-10-22。Android beta.9、iOS 源码及 Web 源码开始使用目标版本。保存目标当天及之后使用新值，更早日期继续使用当时的目标；不冻结餐食或身体测量本身，补记、纠错仍会更新对应日期的记录。

## 使用方式

在“设置 → 个人与目标”保存新目标，可在“设置 → 目标历史”查看日期和各版目标。手动编辑、建议模板与 AI 确认写入走同一套历史记录。同一天多次保存以该天最后一次为准。当前版本不提供回溯修改历史目标或预定未来目标的入口。

例如：21 日吃够蛋白质 100g，22 日把目标改为 150g。21 日仍按 100g 合环，22 日起按 150g 计算；首页、周历、iOS 月历和达标天数都按各自日期的目标计算。仅改称呼或身高不会新增目标版本。仅改营养目标不会重置体重计划阶段。

升级时无法知道旧版本已经覆盖掉的目标数字。因此第一次变更前的当前目标会保存为“最初保留的目标”，用于更早日期；本功能不能凭空恢复此前已丢失的变更记录。多端显示一致需要各客户端升级。完整离线历史合并需要同步服务同时更新 `server.py` 与 `goal_history.py`；只更换 APK 不能替代服务端更新。

## 数据协议与合并

`settings.goalHistory` 是可选数组，每个元素包含 `id`、`effectiveDate`、`updatedAt`，以及完整的 `fitnessGoal`、`baselineWeight`、`targetWeight`、`weeklyWeightTarget`、`calorieGoal`、`proteinGoal`、`carbsGoal`、`fatGoal`。旧数据缺少历史数组时继续读取当前目标，不需要数据库迁移。

`effectiveDate` 使用 Gregorian `yyyy-MM-dd` 民用日期，旅行或更换时区不会移动已经保存的版本。`1970-01-01` 是最初目标的内部哨兵，界面不把它显示为真实开始日期。`goalTimeZone` 保存 IANA 时区；新客户端和 Web 管理操作提供本地时区，后端据此兼容尚未提供历史数组的旧客户端。缺少时区元数据的旧写入使用已存时区，否则为 UTC。

同日版本按 `updatedAt`、`id` 选择最新值，初始基准则保留最早版本。历史数组独立于当前资料的时间戳合并：较早的离线资料可补充此前日期，同时不覆盖较新的当前目标；空历史数组不能擦除服务器已有版本。iOS 首次同步旧账号时直接接纳账号目标，不把新安装的默认占位值伪造成历史；保留原始未知协议字段时也保留新合并的历史。AI 请求携带历史并说明按生效日期评估。

## 验证

- Android Debug / Release 各 76 项 JVM 回归通过；Release / Sandbox 构建和 Lint 通过，分别为 0 错误 / 16 警告与 0 错误 / 15 警告。
- API 31（Android 12）与 API 35（Android 15）各完整 66 项设备回归通过。新增 2 项检查真实设置保存、昨日合环保持、今日新分母、冷启动、历史列表、改称呼不新增历史，以及较早离线版本补入。
- 首轮设备回归中旧测试仍查找“热量在目标 ±10% 内”，更新为“当日目标”后重跑。API 35 一次照片持久化的异步等待超时，随后单独运行同一版本完整 66 项通过；未以延长超时或跳过测试掩盖失败。
- iOS 模拟器构建、完整 Swift 脚本及实际设置/同步/AI 事务回归通过。专用模拟器手动把蛋白质从 100g 改为 180g：昨天仍为 100g，今天为 180g；冷启动后复核两个日期及历史列表。只使用独立示例数据，未操作真实账号。
- Python 临时数据库测试覆盖旧客户端、管理预览、午夜、较早离线历史、重放、空数组保护与无效日期整体回滚；共享 JSON 经实际 Kotlin、Swift、后端及 Web 往返通过。Web 的实际日期解析函数有无浏览器的断言。
- 本轮 Web 日期目标适配仅进入源码，未替换线上静态页面。生产后端已按明确授权部署并通过公网验收，见[部署记录](goal-history-deployment-2026-10-22.md)。

## 截图

安卓为合成餐食（100g 蛋白、250g 碳水），22 日改为 150g / 300g；iOS 为明确标记的示例数据。截图只用于验证功能，不作为厂商真机帧率或驱动一致性的证明。

| 平台 | 修改前的昨天 | 修改后的昨天 | 新目标当天 | 历史 |
| --- | --- | --- | --- | --- |
| Android 12 | [之前](../Android/screenshots/goal-history-api31/yesterday-before.png) | [之后](../Android/screenshots/goal-history-api31/yesterday-after.png) | [当天](../Android/screenshots/goal-history-api31/today-new-target.png) | [历史](../Android/screenshots/goal-history-api31/history-list.png) |
| Android 15 | [之前](../Android/screenshots/goal-history-api35/yesterday-before.png) | [之后](../Android/screenshots/goal-history-api35/yesterday-after.png) | [当天](../Android/screenshots/goal-history-api35/today-new-target.png) | [历史](../Android/screenshots/goal-history-api35/history-list.png) |
| iOS 26.5 | [之前](../iOS/screenshots/goal-history-2026-10-22/yesterday-before.png) | [之后](../iOS/screenshots/goal-history-2026-10-22/yesterday-after.png) | [当天](../iOS/screenshots/goal-history-2026-10-22/today-new-target.png) | [历史](../iOS/screenshots/goal-history-2026-10-22/history-list.png) |
