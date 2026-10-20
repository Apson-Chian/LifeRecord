# LifeRecord 工程质量审查

审查日期：2026-10-16（Asia/Shanghai）。仓库：`Apson-Chian/LifeRecord`；审查基线：`codex/default-ai-service`，`ca552f1f1af2165b93fc4e3cc36e3311b7f2ebc6`。

本文件是第一阶段审查报告。没有修复业务代码、修改用户数据、执行数据库升级或清理、部署、提交或推送 Git。探针只使用临时目录、合成记录、隔离偏好和内存数据库；没有读取真实同步密钥、访问线上健康记录或调用计费 AI。

范围覆盖 README、Docs、Tests、Android、iOS、Backend、Web，包含构建/部署配置、模型、存储、同步、AI、图片、界面状态及测试调用关系。关键数据和安全路径进行了逐行核查与隔离探针验证。界面部分是源码层面的审查，未重新运行三端完整 UI 流程，也未把仓库历史截图当作本次运行证据。线上部署、实际权限、备份、真机行为及压测结果不能由当前源码证明。

## 1. 项目架构

### 1.1 组件与数据流

| 组件 | 实现与职责 | 主要入口 |
| --- | --- | --- |
| iOS | SwiftUI + SwiftData，iOS 17+；健康记录/对话在 SwiftData，目标、动作库及偏好在 UserDefaults，密钥在 Keychain | `iOS/LifeRecord/App/LifeRecordApp.swift:10–21`；`Services/AppSettings.swift:83–184`；`Services/KeychainStore.swift:4–86` |
| Android | Compose + ViewModel/StateFlow；SQLiteOpenHelper v2，以 documents/fields 保存嵌套数据；Keystore 加密密钥 | `Android/app/src/main/java/ltd/apsonchian/liferecord/AppViewModel.kt:95–194`；`data/Store.kt:18–119` |
| Web | 原生 HTML/CSS/JavaScript；健康数据在页面内存，API 配置和外观在 localStorage；通过 Cookie 调用后端 | `Web/app.js:25–137`；`Web/settings.js:1–59`；`Web/admin.js:18–39` |
| 后端 | Python ThreadingHTTPServer + SQLite WAL；用户、会话、记录元数据、EAV 字段、图片索引；Nginx 反向代理 | `Backend/server.py:82–93,483–723`；`Backend/database.py:12–86` |
| AI | 移动端自定义接口直连；默认服务经过鉴权代理；Web 由后端生成修改预览，再通过 admin 操作应用 | `iOS/LifeRecord/Services/AIClient.swift:244–374`；Android `service/Network.kt:38–82`；`Backend/server.py:436–480` |
| 照片 | 后端目录保存压缩图片，数据库保存所有权；iOS 缓存服务器图片；Android 另有持久本地照片与待上传元数据 | `Backend/server.py:226–274`；iOS `Services/MealPhotoStore.swift:20–112`；Android `service/Photos.kt:17–107` |

移动端前台约每 15 秒发送完整快照并合并返回数据；Web 周期执行带 ETag 的 GET，修改通过 `/admin` 提交。协议使用 Unix 秒、记录 ID、`updatedAt` 和 `{id, recordType, deletedAt}` 删除标记。冲突主要按客户端时间比较，尚无统一的服务器版本号、设备确认水位或字段级冲突记录。

### 1.2 跨端契约核对

以下 Android 路径均相对于 `Android/app/src/main/java/ltd/apsonchian/liferecord/`。

| 项目 | iOS | Android | Web / 后端 | 结论 |
| --- | --- | --- | --- | --- |
| 记录集合 | meal/body/workout | 同左；favorite/exercise 仅本机 | 同步前三类及 settings | 主集合兼容；本机专属数据不能当作云端备份 |
| ID | 解码字符串后只接受 UUID；发送小写 | 创建 UUID；合并时忽略大小写 | 同步接受 1–80 字符，SQLite 区分大小写 | C11 |
| 必填字段 | `SyncedMeal` 多个非可选字段 | JSONObject，部分字段有默认值 | sync 校验弱于 admin | C01、C08 |
| 体脂率 | 录入 1–80 | 录入/合并 0–75；分析使用 1–80 | admin 1–80；sync 不校验体脂 | C10 |
| 身高/周变化 | AI 50–300、-5–5；手工设置无边界 | 80–250、-2–2 | 50–300、-5–5 | C07、C10 |
| 营养目标 | AI 热量 500–10000、P 1–600、C 1–1200、F 1–500 | 热量 1–20000，其他 1–3000 | 与 iOS AI 相同 | Android 可保存无法上传的设置，C10 |
| 照片上限 | 配置最多 12 | 每条最多 12 | 后端最多 12；Web 编辑最多 6 | 7–12 张照片的既有餐食在 Web 无法原样保存，见 C10 |
| 删除胜负 | 有本地 tombstone 就跳过远端记录 | 记录时间晚于 tombstone 可保留 | 记录时间晚于或等于现值可覆盖 | C02、C03 |
| 旧训练部位 | 缺省时从 exercises 推导 | 缺省直接空数组 | 省略保留，显式空数组表示清空 | C14 |
| 趋势口径 | 日中位数 + 按间隔平滑 | 同左 | `Web/admin.js:48–78` 使用每日最后一次 | 明确展示口径，不应承诺三端相同数值 |

### 1.3 已有保护与边界

- 后端记录、照片、会话查询通常带 `user_id`；独立随机账号凭证保存摘要，Cookie 为随机、可撤销、7 天会话。隔离回归通过，未发现可直接确认的未鉴权跨用户读取路径。依据：`Backend/server.py:208–212,268–274,628–680`、`Backend/database.py:77–86`。
- Web 写请求检查 Origin、Sec-Fetch-Site、JSON Content-Type；部署模板提供 CSP 和请求/连接限速。自定义 AI 地址限制公网 HTTPS、校验全部 DNS、固定连接 IP、验证 TLS 域名并拒绝重定向。依据：`Backend/server.py:544–554`、`Backend/ai_transport.py:11–76`、`Backend/liferecord-nginx.conf:1–45`。这些是源码与模板证据，不代表线上配置已重新核验。
- 后端合并有事务，Android commit/升级有事务；旧端省略的训练字段和餐食来源字段有保留逻辑。不能因此推断客户端合并、照片文件和偏好也处于同一事务。依据：`Backend/server.py:200–220`、`Backend/database.py:22–36`、Android `data/Store.kt:25–37,80–97`。
- `WaterEntry`、旧 Dots 迁移和后端 legacy-owner 迁移承担兼容职责。不能以“未使用”为由直接删除这些兼容路径。

## 2. 已确认的问题

优先级：P0 为已证实的系统性重大数据损毁/越权；P1 为数据丢失、错误覆盖、同步阻断或敏感数据风险；P2 为局部正确性、可靠性、资源及可恢复性问题；P3 为维护性问题。当前没有足够证据认定 P0，**不代表排除了 P0**。

本节共 20 项：P0 0 项、P1 9 项、P2 10 项、P3 1 项。“已确认”指代码机制或隔离复现成立，不表示已在生产用户身上发生。代码位置对应上述基线。

### C01 · P1 · 同步入口可持久化三端无法解码的数据

- **位置**：`Backend/server.py:106–134,167–176,315–335`；`iOS/LifeRecord/Services/SyncService.swift:21–48,300–314`；Android `data/Models.kt:100–112`。
- **证据/影响**：sync 只检查餐名、部分营养和体重等，没有校验 meal/body 的 date、note、kind、source、createdAt 的完整类型，也未校验 bodyFat/waist。探针证实缺少 date 且 note 为数组的餐食成功进入快照。iOS 整份 Codable 解码失败，Android 合并也可能失败；一条坏记录就能阻断账号同步。仅该账号内可写入，不应描述为已证实跨用户攻击。
- **复现**：在临时库调用 `merge_snapshot({'meals':[合法餐食去掉 date 并设置 note=[]]})`，再读取快照；写入不报错，返回记录仍缺 date。
- **建议**：sync/admin 使用同一份规范化校验，但为旧端明确允许的缺省字段提供兼容默认；区分缺省/null/空数组。先给历史异常记录做只读诊断，不能直接批量清除或强行重写。
- **回归**：逐字段缺失、错误类型、未知枚举、bool 冒充数字、非有限值、超长文本；新旧端样本必须同时经过真实后端和两端解码。批次任何一项错误必须全部不写入。

### C02 · P1 · 同时间戳冲突不收敛，时钟偏差可压制后续修改

- **位置**：`Backend/database.py:38–43`；`Backend/server.py:113–114,189–196,363–366`；Android `data/Models.kt:98–110`；iOS `Services/SyncService.swift:354–355,397–398`。
- **证据/影响**：后端仅拒绝旧时间（`>`），相等时也覆盖；客户端只接受严格更新的记录。两个不同内容但相同时间的版本可交替覆盖服务器，客户端却拒绝相等版本。探针还证实同时间删除后重放餐食可复活；客户端时间快 30 天的记录会使正常时间的后续修改被静默忽略。
- **复现**：A、B 同 ID、同 `updatedAt=1000`、不同 name，交替上传；或删除时间 1000 后上传更新时间 1000 的原餐食；或先上传未来 30 天版本，再上传正常时间版本。
- **建议**：先统一“相同时间删除优先、相同内容幂等、不同内容显式冲突”的兼容规则；新增可选服务器 revision/baseVersion 供新端使用，旧字段继续可读。不要单纯用服务端当前时间覆盖所有客户端时间；不要未经确认批改历史时间。
- **回归**：三端 A→B/B→A 排列、同时间删除/编辑、快速连续操作、时钟前后偏移、离线重连，最终内容和删除状态必须一致。

### C03 · P1 · iOS 永久按删除标记键屏蔽更晚的记录

- **位置**：`iOS/LifeRecord/Services/SyncService.swift:327–352,394–395,412–413`；对照 Android `data/Models.kt:96–110` 和 `Backend/database.py:38–43`。
- **证据/影响**：iOS 将全部 tombstone 的 key 放进 deletedKeys；后续不比较记录和删除时间，直接跳过。原同步实现的内存数据库探针证实：本地删除时间 1100，远端同 ID 更新时间 1200，iOS 仍无餐食；后端接受 1200 的记录。删除/离线编辑交错后，设备长期不同步，用户可能误以为记录丢失。
- **复现**：iOS 保存 tombstone；另一设备离线编辑同条记录且更新时间更晚，随后上传；iOS 同步返回较新记录仍跳过。
- **建议**：先决定并统一删除冲突政策。若沿用现有 LWW，逐条比较 record/tombstone 时间；若永久删除优先，服务端与 Android 也必须采用兼容策略并提供明确恢复方式。不要直接删除所有本地 tombstone。
- **回归**：1100 删除与 1099/1100/1200 编辑的全部排列；覆盖 meal/body/workout、本地存在/不存在记录、重启再同步。

### C04 · P1 · `/sync` 返回快照可能混入并发删除后的空对象

- **位置**：`Backend/server.py:277–298,509–510,566–573`。
- **证据/影响**：current_snapshot 只在读取元数据列表时持锁，之后每条记录另开连接读 fields。GET snapshot/admin 外层持锁，但 `/sync` 的返回快照没有。元数据读到未删除记录后，另一请求删除其 fields，当前响应就可能出现 `meals:[{}]`。确定性交错探针已复现，客户端整份解码/合并失败。
- **复现**：在 current_snapshot 已读完 user_records、尚未 read_record 的边界，让另一同步请求删除该餐食，再继续读 fields。
- **建议**：用单个连接、显式一致性读事务构建完整快照；元数据和字段来自同一数据库快照。进程内锁可作为短期修复，但不能替代多进程下的数据库事务。
- **回归**：用 barrier 控制并发新增/更新/删除与 snapshot/sync/admin 响应，不允许空对象、字段混合版本或缺失必填字段。

### C05 · P1 · iOS 训练编辑和通用 AI 写入没有过期版本保护

- **位置**：`iOS/LifeRecord/Views/WorkoutViews.swift:101–109,214–261`；`Views/CoachView.swift:629–653,809–868,905–940`。对照已有保护：`Views/MealHistoryView.swift:407–409`、`Views/EntryViews.swift:490–493`、Android `AppViewModel.kt:380`。
- **证据/影响**：训练编辑保存的是打开时拷贝的字段，没有比较 originalUpdatedAt 或检查原对象已删除；通用 AI 请求只保留文本上下文，没有保留目标版本，返回后直接改当前对象。期间的同步/手动更新可能被旧草稿覆盖。该保护在餐食/身体编辑和训练部位专用预览中已有实现，通用路径未接入。
- **复现**：打开训练编辑页；另一设备更新备注、时间或组数据并同步；在旧编辑页保存。AI 路径则阻塞模型响应，更新目标记录后返回旧 action。
- **建议**：保存前重新获取 ID，检查存在性与生成时版本，发现变化要求重新核对；AI 操作按目标记录检查，避免无关记录更新使全部请求无效。拒绝覆盖时保留草稿。
- **回归**：编辑中被修改、删除、同步更新；AI 返回时目标版本变化；无关记录变化；两对话同时改同一目标。

### C06 · P1 · iOS 合并失败残留部分修改，偏好不受 SwiftData 回滚保护

- **位置**：`iOS/LifeRecord/Services/SyncService.swift:149–165,317–437`；`Services/AppSettings.swift:115–126,314–340`；`Views/CoachView.swift:777–808,942–994,677–693`。
- **证据/影响**：同步依次修改/插入对象，较晚的训练校验可抛错，catch 没有 rollback。使用原 apply 实现的内存探针证实“先插入合法 meal，后遇重复训练部位失败”，context 仍 hasChanges，随后 save 会持久化该 meal。同步档案和 AI 目标/动作库又立即写 UserDefaults，`modelContext.rollback()` 无法撤销这些写入，可能出现部分执行但失败提示。
- **复现**：同一入站快照放合法餐食与非法训练部位；捕获错误后执行一次普通保存，读取部分餐食。AI 批次先修改目标/动作库，随后取消、图片失败或数据库保存失败。
- **建议**：先完整解码、校验、生成变更集，再在隔离 ModelContext 中保存；异常回滚该操作，避免回滚共享上下文里其他用户编辑。偏好、动作库和回执明确设计提交与补偿边界。
- **回归**：第 N 条失败、取消、磁盘满/保存失败；验证全部持久模型、UserDefaults、动作库、回执和更新时间一致，且不影响无关草稿。

### C07 · P1 · iOS 可保存不符合服务器要求的餐食和目标，阻断全量同步

- **位置**：`iOS/LifeRecord/Views/EntryViews.swift:300–345`；`Views/MealHistoryView.swift:407–418`；`Services/CoachActions.swift:85–99`；`Views/SettingsHomeView.swift:80–91,510–524`；`Backend/server.py:118–120,329–336`。
- **证据/影响**：新增餐食仅要求至少一项营养大于零，没有逐项有限值/非负/上限检查；编辑/教练只查非负但无服务器上限；目标 TextField 直接绑定持久偏好，无范围校验。`calories=600, protein=-1` 或超限热量可本地保存；目标热量 100 也会立即持久化。每次完整上传都被后端拒绝，其他正常记录也无法同步。
- **复现**：在 iOS 餐食输入/AI mock 中产生上述值，或将每日热量设为 100；保存后手动同步，得到 400。代码路径确认，未在个人设备注入异常数据。
- **建议**：模型提交边界统一校验，手工、AI、常用餐食、同步都使用同一规则；目标先编辑草稿、校验后整体提交。对已存在异常记录提供定位和修正入口，不能擅自丢弃。
- **回归**：负值、极大值、非有限值、零值和边界值；既有坏记录必须可导出/修正，错误须指明记录与字段。

### C08 · P1 · Web 无法编辑带移动端来源字段的餐食

- **位置**：`Web/app.js:493–509`；`Backend/server.py:306–310,371–380`；iOS `Services/SyncService.swift:245–247`；Android `data/Models.kt:35`。
- **证据/影响**：Web 展开 existing 再仅移除 id/updatedAt/createdAt，inputText、sourceConversationID 以及 Android 其他扩展字段随 fields 发出；后端 FIELDS 不允许这些字段。探针以现代移动端餐食构造同一请求，稳定返回“修改字段为空或包含不支持的字段”。即使原始描述为空也会失败。Web smoke 的模拟后端不执行白名单，因此未发现此问题。
- **复现**：App 新增餐食并同步，Web 修改任一营养值或备注保存；或用与 Web 相同的字段拆分调用 apply_admin_actions。
- **建议**：Web 仅发送明确可编辑字段，后端基于已有记录合并，保留只读来源及未知扩展字段；需要编辑来源时设计专门白名单，不能直接放开所有字段。
- **回归**：真实后端驱动浏览器编辑 iOS/Android 样本，包含空/非空 provenance 与未知扩展字段，断言 ID、照片、来源描述均保留。

### C09 · P1 · Android 设备测试会使用当前应用数据与密钥

- **位置**：`Android/app/src/androidTest/java/ltd/apsonchian/liferecord/AppFlowTest.kt:31–48,50–58`；`Android/app/src/androidTest/java/ltd/apsonchian/liferecord/StorageTest.kt:63–78`；`Android/app/src/main/java/ltd/apsonchian/liferecord/MainActivity.kt:32–33`；`AppViewModel.kt:271–307`。
- **证据/影响**：AppFlowTest 直接清空 app.store 的健康记录后启动 MainActivity，没有替换网络、关闭同步或隔离原同步密钥；启动后会自动同步合成数据。StorageTest 的 secrets 测试直接 `reopened.clear()` 清除全部应用密钥。finally/@After 不能撤销已上传云端数据，也不能恢复被清除的真实密钥。风险条件是测试运行在已有用户数据的同包名安装中；本次未执行设备测试。
- **复现**：仅在一次性模拟器用合成密钥连接本机假服务，执行设备测试，记录自动同步请求和密钥状态；禁止用真实账号复现。
- **建议**：设备测试使用独立 applicationId、数据库、Secrets 命名空间及网络 fake；测试启动前强制拒绝生产地址/已有账号。不能把“备份后恢复应用表”当作隔离。
- **回归**：探测测试期间零生产网络请求；测试完成后测试前哨记录与密钥完全不变；异常中断也不得写入真实配置。

### C10 · P2 · 各端合法范围和照片上限不同，正常数据可能无法同步或编辑

- **位置**：Android `data/Models.kt:66,84–88,111`；`Backend/server.py:325–336`；iOS `Views/EntryViews.swift:495–498`、`Views/CoachView.swift:943–952`；`Web/app.js:495`。
- **证据/影响**：后端可保存体脂 78、身高 70 或每周变化 3，Android Merge 校验会拒绝；Android 允许热量目标 100，而后端拒绝。Web 用 6 张上限检查既有记录，移动端合法的 7–12 张餐食连改备注也失败。服务端合成探针已验证身高 70/每周变化 3 可写入，Android 拒绝条件由源码确认。
- **复现**：通过 Web/隔离 API 写入上述合法后端样本再 Android 同步；在移动端保存 7 张照片并在 Web 原样编辑。
- **建议**：建立共享契约样本和边界表；区分“新录入建议范围”与“历史数据读取范围”，避免为了缩窄输入范围拒绝整个入站快照。Web 可限制新增图片，但应保留既有合法数量。
- **回归**：每个边界的 low-1/low/high/high+1、null/缺省、0/75/78/80 体脂、0/6/7/12/13 张照片双向往返。

### C11 · P2 · ID 规则与大小写不一致，可能静默漏记录、重复及漏清照片

- **位置**：`Backend/server.py:109–112,211,215–216,252,260`；`Backend/database.py:16,38–42`；iOS `Services/SyncService.swift:328,352,395,413`；Android `data/Models.kt:94–104`。
- **证据/影响**：同步接受非 UUID，iOS 则静默 continue；服务器把大小写 UUID 当两条，两个客户端把它们当同一 ID。图片 meal_id 转小写，但删除照片查询使用传入 record_id。探针证实大小写版本同时存在，以及删除大写 ID 记录后图片仍可读取。
- **复现**：同一 UUID 分别大写、小写上传；大写记录上传照片后按该 ID 删除；另上传 `meal-test` 并观察 iOS 不接收。
- **建议**：新写入先规范 UUID；历史非 UUID 必须保留可导出并明确告知兼容限制。先只读检测大小写碰撞并制定迁移映射，不能直接 lower() 全表造成主键覆盖。照片查询也使用规范 ID。
- **回归**：大小写、无效/旧 ID、跨用户相同 ID、碰撞检测、照片绑定与删除、迁移回滚。

### C12 · P2 · 照片缺少完整引用生命周期，孤儿和本地残留长期占空间

- **位置**：`Backend/server.py:198–223,226–265,394–410`；`Backend/database.py:19–20`；Android `AppViewModel.kt:195–210,381–392`、`service/Photos.kt:71–80`。
- **证据/影响**：后端允许先上传到不存在的 mealId，文件/索引没有餐食外键或过期回收；上传后保存失败、取消或只上传部分照片会留下孤儿，持续消耗 250 张额度。普通 sync 替换 photoIDs 没有清除移除引用，只有 admin 有处理。Android 删除餐食/常用餐食不调用 deleteLocal，文件不受 128 MB 缓存预算约束。探针确认无餐食的上传仍可读取。
- **复现**：临时账号上传但不创建餐食；重复后观察配额。Android 保存带本地照片的餐食再删除，检查 meal-photos 文件仍在。一次 AI 操作可让多条新餐食共享同一本地文件，清理必须考虑引用计数。
- **建议**：待提交上传有短期状态和宽限期；提交成功绑定引用，后台只读盘点后回收确定无引用的文件；本地采用引用扫描/计数并延迟清理。不要直接删除“不在当前页面显示”的照片。
- **回归**：半批上传失败、取消、删除与上传并发、共享照片、保存失败、崩溃恢复、重复上传临近配额、GC 不误删有效图片。

### C13 · P2 · iOS 普通记餐上传失败后没有持久重试队列

- **位置**：`iOS/LifeRecord/Views/EntryViews.swift:320–357`；`Services/SyncService.swift:170–196`；对照 Android `AppViewModel.kt:287–300`。
- **证据/影响**：照片上传任意一张失败即丢弃本次返回 ID 数组，以 photoIDs=[] 保存餐食后关闭页面；普通记餐原图只在 @State，未持久保存。已有配置但临时断网时，营养保存成功，选定附件没有后续上传途径；已成功上传的部分还成为 C12 孤儿。教练消息另有图片持久化，不能据此推断普通记餐也具备重试能力。
- **复现**：配置同步后选择两张合成图片，让第二次上传失败；保存、关闭记餐页、重启，餐食无照片且无待上传任务。
- **建议**：保存前持久化附件草稿与上传进度，重试沿用同一餐食 ID；清楚显示“本地已保存/待上传/需重选”。保留无同步配置时的明确提示。
- **回归**：无网络、第一/第 N 张失败、超时结果未知、进程重启、取消保存、恢复上传不重复照片。

### C14 · P2 · Android 编辑旧训练可能写空原有部位

- **位置**：Android `data/WorkoutParts.kt:20`、`ui/Editor.kt:104,127`；iOS `Models/HealthModels.swift:355–360`；`Backend/server.py:204–207`。
- **证据/影响**：旧记录只有 exercises[].bodyPart、没有 bodyParts 时，iOS 从动作推导，Android 当作空。Android 编辑备注后会显式写 bodyParts=[]；后端将其视为主动清空，iOS 此后也不再使用旧字段 fallback，原有统计标签消失，动作本身仍在。
- **复现**：同步一条仅有 exercises:[{name:'划船',bodyPart:'背部',sets:[]}] 的旧训练，Android 只改备注保存；检查 bodyParts=[]，再 iOS 同步。
- **建议**：缺省与显式空列表分开；旧记录展示 fallback 一致，未编辑部位时保留缺省或按明确规则补全，禁止把读取默认值当成用户清空操作。
- **回归**：旧端缺省、新端显式空、自定义部位、仅改备注/时间的三端往返，部位与逐组数据都不丢失。

### C15 · P2 · Web “截至所选日期”会包含次日上午测量

- **位置**：`Web/app.js:14–15,176–179,328–336`。
- **证据/影响**：parseDate 构造当地中午 12 点，epochForDateKey 再加 86400 得到次日中午；因此当天体重卡与明细可能显示次日 08:00 的记录，固定秒数也不适合夏令时边界。
- **复现**：当天 08:00 体重 70、次日 08:00 体重 72，选择当天，最新体重可能为 72。
- **建议**：用当地下一日 00:00 的排他边界，使用日历构造而非固定 86400 秒。
- **回归**：当天 23:59、次日 00:00/08:00、夏令时 23/25 小时日、不同时区。

### C16 · P2 · Web 照片 alt 属性使用了不适合属性上下文的转义

- **位置**：`Web/app.js:248–249,342–344`；对照正确属性转义使用处 `Web/workouts.js:12`；CSP 模板 `Backend/liferecord-nginx.conf:30`。
- **证据/影响**：escapeHtml 通过 textContent/innerHTML 转义文本，双引号不会被转义；结果直接插入双引号包围的 alt。餐名含 `" data-audit="yes` 可改变生成 DOM 属性。确认的是属性注入；**没有证明在部署 CSP 下可执行脚本，不能称为已证实的生产 XSS**。CSP 也不能替代正确构造 DOM。
- **复现**：合成餐名设为上述引号字符串，打开带照片详情，检查新增 data-audit 属性；在隔离页面验证，不上传攻击文本至真实记录。
- **建议**：用 DOM API 设置 img.alt/src，或统一 escapeAttribute；继续保留 CSP。
- **回归**：带引号、尖括号、换行、事件属性形式、URL 形式的餐名；断言只有预期 DOM 属性且无脚本/额外请求。

### C17 · P2 · 新增操作缺少稳定幂等身份，超时后重试可生成重复记录

- **位置**：`Web/app.js:488,509,521–525`；`Web/admin.js:38–39`；`Backend/server.py:354–359,375–379`。
- **证据/影响**：身体/训练 add 无稳定 recordID，后端每次生成 UUID；餐食 id 在每次 submit 中新建。数据库已提交而响应丢失时，用户重试可创建第二条相同记录。已有 updatedAt 乐观锁仅保护 update/delete，不保护新建。
- **复现**：临时库连续提交同一个无 recordID 的合法 body add 两次，得到两个 ID；端到端用代理在提交后丢弃首个响应，再点保存。
- **建议**：草稿生命周期生成并复用客户端 recordID，或添加可选 requestID/幂等表；重放返回已提交结果，保持旧客户端协议可用。
- **回归**：提交后断网、超时、重复点击、页面恢复及同 requestID 不同内容，不能双写或误用结果。

### C18 · P2 · iOS 训练趋势的“完成”条件弱于日历和 Android

- **位置**：`iOS/LifeRecord/Views/WorkoutTrendCard.swift:19,162–164`；对照 `Services/WorkoutCalendar.swift:23–26`、`Services/GoalFeedback.swift:69–73`；Android `ui/Trends.kt:81`；`Backend/server.py:136–139`。
- **证据/影响**：iOS 趋势仅要求 endDate 非空且开始时间不晚于现在；后端允许未来结束时间。一个开始于昨天、结束在明天的同步训练会被 iOS 趋势当成完成，日历/目标反馈/Android 则不计入，次数和部位统计不同。
- **复现**：在临时 API 写入上述训练，比较各页面完成次数。机制由过滤条件确认，未在个人设备写入未来训练。
- **建议**：统一纯函数判断 start≤end≤now，全部训练统计复用；保留原记录并提示核对，不自动改时间。
- **回归**：进行中、未来开始、未来结束、负时长、跨午夜、正常长训练，同一快照各页面统计一致。

### C19 · P3 · 遗留页面、不可达预览与过时文档增加维护误判

- **位置**：`iOS/LifeRecord/Views/SettingsView.swift:4` 的 private LegacySettingsView；`Views/SettingsHomeView.swift:4` 的实际 SettingsView；`Services/AIClient.swift:483–490` 的未调用 mimeType；`Backend/server.py:7,17–18,53` 的未使用导入/常量；Android `AppViewModel.kt:18,146,355,396–400`、`ui/Coach.kt:131–135` 的 Proposal 路径；`Docs/public-beta.md:30`；`iOS/README.md:71`。
- **证据/影响**：当前通用教练流程直接 acceptCoachReply，未发现把非空 Proposal 赋给 proposal 的生产路径，但 UI/文档仍描述确认预览；iOS README 写 12 个回归，实际脚本运行 18 个。可能改错页面、误解 AI 写入安全或遗漏检查。
- **复现**：全仓搜索上述符号的定义/调用及 proposal 赋值，与真实 RootView/acceptCoachReply 对照。
- **建议**：先标注实际入口与兼容用途，后续小批清理纯死代码并更新文档。SettingsView.swift 还包含被使用的编辑组件，不能整文件删除；WaterEntry/Dots 不属于本项可直接清理对象。
- **回归**：构建和导航 smoke，AI 行为与说明一致；文档测试数量从脚本提取，避免手工维护重复数字。

### C20 · P2 · LifeTrack 每日共享摘要不会随同数量餐食编辑更新

- **位置**：`iOS/LifeRecord/Views/TodayView.swift:96–105,252–254`；`Services/SharedProfileStore.swift:68–78`。
- **证据/影响**：摘要仅在 onAppear、所选日期或 selectedMeals.count 变化时发布。改营养、同步同一餐的值都不改变数量，当前页面继续显示新值，App Group 仍可能是旧值；已开启的联动功能因此出现不一致。
- **复现**：开启共享，进入今日，编辑同一餐热量但不新增/删除、不重新进入页面，读取共享 daily.calories；或同步远端对同一餐的修改。
- **建议**：按当天记录 ID+版本/营养摘要变化发布，开启共享时立即推送当前摘要；仅在启用联动时执行，避免增加未授权数据发送。
- **回归**：同数量编辑、远端更新、开关切换、跨日、取消共享后键值清理；使用隔离 suite/fake，不读写真正 App Group。

## 3. 潜在风险

下列风险有明确代码边界，但尚未证明完整触发条件、线上利用或真实损害；不能与上一节的隔离复现混为一谈。

### R01 · P1 · AI 写入开关不能保证本次用户只读意图

- **位置**：`iOS/LifeRecord/Services/CoachActions.swift:63–72`、`Views/CoachView.swift:640–653,926–940`；Android `service/CoachPolicy.kt:5–10`、`AppViewModel.kt:372–394`。
- **影响**：开关打开时，格式正确的 delete/update 可以直接执行；代码没有按本次用户要求限定类型、目标、删除确认。提示词只是模型指令，无法强制抵御模型误判或记录文本中的指令污染。未进行真实模型攻击，未认定已经发生越权删除。
- **验证方式**：用假模型在“只分析，不要改记录”请求后返回合法删除 action，检查是否执行；再测试含恶意备注的记录及两轮上下文。
- **建议/回归**：删除及批量覆盖增加具体目标预览与确认；执行器限制操作范围、数量、版本；保留已有普通新增体验。测试只读、显式拒绝写入、删除歧义、图片分类及提示词污染，禁止依赖关键词正则作为唯一权限判断。

### R02 · P1 · 数据迁移和恢复保障尚不足以证明生产可恢复

- **位置**：`Backend/database.py:12–36`、Android `data/Store.kt:25–37`、`iOS/LifeRecord/App/LifeRecordApp.swift:20–21`；`iOS/Tests/favorite-food-storage.swift:30–46`；`Docs/web-optimization.md:23–25`。
- **影响**：后端启动无条件设置 user_version=2，未拒绝更高版本；SwiftData 无显式 VersionedSchema/迁移计划；现有 Swift 测试是当前模型建立库后扩展模型，不能等同于每个历史发布 schema 的升级。仓库文档承认未实现定时备份；迁移破损、磁盘满和恢复流程没有足够证据。
- **验证方式**：只对脱敏副本构造真实历史 schema、损坏 JSON、缺表、磁盘配额耗尽、迁移中断、未来版本和重启，逐条比对数据及图片索引。
- **建议/回归**：版本前置检查、迁移台账、SQLite 一致备份与恢复演练；迁移前后 count/内容摘要/foreign_key_check/integrity_check；失败保留旧库并可再次迁移。禁止拿真实用户库试错，禁止因启动失败创建空库替换。

### R03 · P1 · 自定义 AI 和全量同步缺少应用级总体资源预算

- **位置**：`Backend/server.py:167–220,436–480,577–598,719–723`；`Backend/default_ai.py:103–149`；`Backend/liferecord-nginx.conf:5–7`；`Backend/ai_transport.py:61–74`。
- **影响**：默认 AI 有并发和额度限制，自定义 ai/plan 路径没有同等执行并发限制；每个请求可占线程约 75 秒。全量快照重建和写入共享锁，单账号高成本请求可能影响其他用户。Nginx 按 IP 限流不等于按账号或总成本隔离。没有压测，不给出吞吐或必然服务中断结论。
- **验证方式**：隔离进程/假上游中并发慢 AI、同步和条件 GET，测线程数、锁等待、P95/P99、RSS/FD 和其他用户延迟。
- **建议/回归**：所有 AI 路径统一每用户与全局并发预算，过载快速 429；请求复杂度与响应体积设上限，排队有界；慢请求时普通同步仍可完成。

### R04 · P1 · 换账号/清除数据与多步骤异步任务可能交错

- **位置**：`Web/app.js:61–87,279–286,486–509,590–601`；iOS `Services/SyncService.swift:170–196`、`Views/EntryViews.swift:320–357`、`Views/SettingsHomeView.swift:478–500`。
- **影响**：Web 单次 api 有 generation 校验，但图片压缩→多张上传→保存跨越多次调用，整个操作没有固定账号代次；iOS 照片上传不如 sync/default AI 那样校验请求前后身份，普通记餐保存任务也不属于清除数据的全局 busy gate。是否会跨账号写入取决于 UI 时序，尚未复现。
- **验证方式**：fake 网络在压缩后/第 N 张上传后/提交前设置 barrier，执行退出登录、重新登录或清除数据，再释放；检查旧数据不会出现于新身份或已清除库。
- **建议/回归**：为整项操作固定用户身份与代次，切换时取消/失效所有任务，写入前再次比较；服务器上传凭据和记录归属一致；覆盖所有等待点。

### R05 · P2 · 图片解码和响应大小仍可能形成内存峰值

- **位置**：`Backend/server.py:240–247`、`Backend/default_ai.py:79–85`；iOS `Services/AIClient.swift:464–476`；Android `ui/Editor.kt:255–257`、`service/Network.kt:22–23`；`Web/app.js:261–275`。
- **影响**：后端只检查图片魔数，未验证像素/解码有效性；移动端完整接收自定义响应，Android PhotoBytes 完整解码，iOS 在主线程路径使用 UIImage/renderer。压缩后字节限制不代表解码后内存安全。Android Photos.read 已采样，iOS 服务器缩略图有后台缩略解码，应保留这些措施。
- **验证方式**：合成大像素小文件、截断图片、12 图连选、超大自定义 AI 响应、低内存设备滚动与反复打开详情，记录峰值和取消释放。
- **建议/回归**：限制像素与解码预算，缩略图采样，后台执行，流式有上限读取；有效图、坏图及取消都释放资源，不缓存无效数据。

### R06 · P2 · 导出不足以恢复本机专属数据和照片

- **位置**：iOS `Services/SyncService.swift:223–297`、`Views/SettingsHomeView.swift:464,478`；Android `AppViewModel.kt:412`、`ui/Settings.kt:85–87`；Web `app.js:545–548`。
- **影响**：iOS 导出不含常用餐食、动作库、对话和照片字节，Android 导出也不是完整附件备份；未发现配套完整导入恢复入口。说明有部分披露，但“先导出再清除”不能保证本机专属内容可恢复。未实施恢复演练。
- **验证方式**：在隔离安装生成全部类型与附件，导出、清空一次性环境、尝试恢复并比较完整性。
- **建议/回归**：保留轻量协议 JSON 导出，另提供版本化完整备份包/恢复预览和校验和，密钥默认不导出；清除前具体列出不可恢复项。

### R07 · P2 · 认证防护依赖单进程内存与部署边界

- **位置**：`Backend/server.py:46–47,58–79,664–687`；`Backend/database.py:83–86`；`Backend/liferecord-nginx.conf:1–18`。
- **影响**：legacy token 最短仅 6 字符；失败计数按 IP 且在进程内，成功请求会清同 IP 失败计数；共享 NAT 误封、重启失去失败计数、弱历史凭证暴力尝试需评估。新建账号是随机高熵凭据，不应把二者混为一谈。未对线上实施尝试。
- **验证方式**：隔离 HTTP 测试弱历史配置、共享 IP、多账号成功/失败交错、反向代理 header 信任、重启及撤销后的已在途请求。
- **建议/回归**：新配置要求强随机密钥，旧凭证提供明确轮换流程；兼顾按来源与总量的有界限速，避免凭证存在性泄漏；确认仅可信代理可接触监听端口。不能静默轮换用户现有凭证。

## 4. 测试覆盖情况

### 4.1 本次实际执行

| 检查 | 本次结果 | 证据边界 |
| --- | --- | --- |
| `python3 Tests/sync-edit.py` | 通过 | 临时库；同 ID、过期更新、来源字段、训练与删除兼容 |
| `python3 Tests/admin-api.py` | 通过 | 临时库 + mock AI；CRUD、版本锁、预览；没有真实浏览器字段拼装 |
| `python3 Tests/public-beta.py` | 通过 | 本机随机端口；迁移、用户/图片隔离、会话、CSRF、注销 |
| `python3 Tests/default-ai.py` | 通过 | 模拟上游；鉴权、配置保护、持久额度、并发入口；无计费请求 |
| `python3 Tests/web-optimizations.py` | 通过 | mock DNS/TLS + 本机 HTTP；SSRF、请求头、重定向、参数、ETag |
| `./iOS/Tests/run.sh` | 18 个回归程序通过 | macOS Swift/SwiftData，不是完整 iOS UI 或真机测试 |
| Android `./gradlew --offline --no-daemon :app:testDebugUnitTest` | 50 测试，0 失败/错误/跳过 | JVM 测试；未执行设备测试、Lint 或本次完整发布构建 |
| `python3 Tests/android-sync.py` | 通过 | 已在本次 JVM 测试后重生成 Kotlin 样本；不是陈旧缓存样本 |
| `node Tests/web-smoke.cjs` | 未运行成功：缺少 `playwright` | 没有安装依赖、未宣称浏览器 smoke 通过 |
| 审查额外 Python 探针 | 11 个机制检查成立 | C01/C02/C04/C08/C10/C11/C12；临时库，包含确定性交错 |
| 原 iOS apply 临时 Swift 探针 | 2 个检查成立 | C03/C06；原源码加同文件测试访问桥，网络/Keychain/App Group stub；内存库，未改仓库实现 |
| Web 日期函数 Node 探针 | 1 个检查成立 | C15；提取原日期函数执行，排他边界为次日 12 点，确实包含次日上午 |

沙箱最初阻止本机端口与 Swift 宏插件；放开这些测试所需的本机执行限制后，上述对应检查通过。Android 首次使用空的临时 Gradle home 时缺少 wrapper 且无法解析下载域名；随后复用已有缓存离线运行成功。失败尝试不计为通过。

探针与日志仅放 `/tmp/liferecord-audit-*`，不作为项目新依赖或已合入的回归测试。第二阶段应把相应最小用例纳入仓库；第一阶段没有先改实现使测试变绿。

### 4.2 覆盖不足及建议验收矩阵

| 缺口 | 现有证据位置 | 第二阶段必须增加 |
| --- | --- | --- |
| 三端真实闭环 | `Tests/android-sync.py:17–34` 主要是 Android→Python；Swift run.sh 不编译 SyncService | iOS/Android 编码→真实服务→另端解码；Web 浏览器→真实服务，不再仅 mock |
| mock 与后端规则不同 | `Tests/web-smoke.cjs:18–27` 不校验 FIELDS/expectedUpdatedAt | 正常来源字段编辑、400/409/429、请求提交后丢响应 |
| 冲突收敛 | Android `CoreTest.kt:14–29`；`Tests/sync-edit.py:1–107` | 相同时间、未来时钟、删除/编辑全排列、旧设备多次重连、两端最终一致 |
| 原子失败和恢复 | Android `StorageTest.kt:13–22,39–61` 具有事务与迁移成功用例 | iOS apply/AI 偏好原子性、真实历史库、迁移中断与重试、磁盘满 |
| 图片完整生命周期 | iOS `Tests/meal-photo-cache.swift`；Android `StorageTest.kt:80–97` | 孤儿回收、部分上传、删除/上传并发、共享文件引用与配额 |
| 身份与 AI 权限 | `Tests/public-beta.py:32–49`；Android `CoachParityTest.kt:18–25` | 多步骤换身份、显式只读下错误 action、过期目标、撤销中在途请求 |
| UI 故障路径 | `Tests/web-smoke.cjs`、Android `AppFlowTest.kt` | 保存中断、后台/进程重建、无障碍键盘、表单草稿与状态恢复；全部用隔离安装 |
| 自动门禁 | 当前跟踪文件未包含 `.github/workflows` 或统一 CI 配置 | 锁定工具链/测试依赖，分别运行 Python、JVM、Swift、浏览器契约；产出日志与失败状态 |

没有运行行/分支覆盖率工具，不给出推测性覆盖率百分比。测试数量和历史构建通过均不能证明生产安全、数据可恢复或达到上线容量。

## 5. 性能优化建议

以下是代码证据支持的工作量与瓶颈候选；未做负载/功耗测量，不承诺加速倍数。先测量，再做局部改动，不引入大批依赖。

| 优先级 | 位置与现状 | 建议和验证 |
| --- | --- | --- |
| P2 | `Backend/server.py:277–297,509–512`：N 条记录逐条新建连接/查询并重建 JSON；304 也先重建快照 | 在一致读事务中批量读取字段；缓存按用户 revision 的 ETag；测 1k/5k/10k 记录的连接数、查询数、P95。Python sqlite 连接的 with 主要负责事务，需显式 close，避免依赖 GC 释放资源 |
| P2 | Android `data/Store.kt:80–92` 每次 commit 删除并重写全部记录；`AppViewModel.kt:194,299,306` 在 ViewModel 主线程持久化；每张照片上传成功又提交一次 | 改为单串行存储执行器上的增量事务；保持内存状态只在提交成功后发布；确保不会将旧快照排队后覆盖新快照。测主线程帧耗时、SQL 写放大和 12 图批次 |
| P2 | iOS `Services/SyncService.swift:151,227–297`、Android `AppViewModel.kt:302–306` 每 15 秒全量上传，后端 `database.py:40–61` 相等时间也重写字段 | 相同时间相同内容跳过写入；优先消除无变化写入和不必要轮询。后续增量协议新增可选 cursor/revision，保留原完整快照路径，不能直接替换旧协议 |
| P2 | `Backend/server.py:172,187,217–220` 每集合/删除数组最多 10000，但总记录允许 30000，且客户端全量上传 tombstone | 接近边界前做容量回归与用户提示；分页/增量上传要有兼容设计。删除标记不能按天数盲目清理，否则长期离线设备会复活旧数据 |
| P2 | `Web/app.js:217–220` 循环内反复 recordedDates；`Web/admin.js:95–104` 每格扫描历史；iOS `Views/ProgressDashboardView.swift:58–88` 多次重算趋势 | 每次数据版本变化构建按日索引、汇总和趋势缓存；日期切换重用结果。保持日中位数/缺测语义，用大历史样本检查正确性与渲染耗时 |
| P2 | Android `service/Photos.kt:94–105` 没有同图在途下载合并；`ui/Editor.kt:255–257` 完整解码；iOS AI 转码 `Services/AIClient.swift:464–476` | 参考 iOS MealPhotoStore 的并发合并；缩略解码、后台转码、预算淘汰；区分缓存和用户原图，不能为优化误删附件 |
| P2 | iOS `Views/CoachView.swift:1089–1136`、Android `AppViewModel.kt:358–361`、`Backend/server.py:442–446` 每次 AI 携带大量历史，后端超过 160000 字符直接拒绝 | 先显示上下文大小/超限原因并缓存不变序列化；将来提供用户明确选择的范围/检索，不擅自缩减现有可操作历史范围 |

## 6. UI/UX 优化建议

本节为源码可见行为建议，未做本次视觉评分、完整无障碍认证或三端截图对照。

| 优先级 | 位置 | 建议与验收 |
| --- | --- | --- |
| P1 | iOS `Views/EntryViews.swift:351–357`、Android `AppViewModel.kt:306`、Web `app.js:123–128` | 分别显示本地保存、云端提交、照片状态；同步失败不能只给笼统失败。针对 C01/C07 显示可定位的记录/字段并保留输入 |
| P1 | C05/C06 涉及的编辑页和 AI 回执 | 冲突显示原版本/当前版本并保留草稿；部分成功必须逐项回执，失败状态不应覆盖已执行事实；破坏性 AI 提供具体记录确认 |
| P2 | `Web/app.js:248–250,511–512,526`、`Web/index.html:149–157` | 体重错误目前主要用短 Toast，增加持久表单错误、字段关联与焦点；auth dialog 补明确可访问名称。用键盘和读屏验证，不仅检查 aria 字符串存在 |
| P2 | `Web/app.js:133–135`、`Web/admin.js:48–78` | 周期 render 会重建图表 DOM，需验证键盘焦点/选择不丢失；没变化时避免无关 DOM 重建 |
| P2 | `Web/admin.js:48–78`、iOS `Services/BodyTrend.swift:35–47`、Android `data/Analysis.kt:13–23` | 三端趋势明确标注“最后一次/中位数/平滑”，提供同日原始测量明细，避免把不同算法显示为同步失败 |
| P2 | iOS `Views/SettingsHomeView.swift:464,478`、Android `ui/Settings.kt:85–105` | 清除前区分云端可恢复记录与本机专属内容，导出后提示实际包含项；不要用一个“已导出”暗示完整备份 |
| P2 | iOS `Views/EntryViews.swift:134–138,326`、Android `ui/Editor.kt:44–52,151–158` | 核查保存/AI/图片读取中取消和页面关闭：持久草稿、明确取消语义、无孤儿附件；旋转/进程重建后不重复提交 |

## 7. 功能优化建议

不以新增功能替代正确性修复。以下均待第二阶段确认后拆分实施。

1. **P1：只读数据健康诊断与恢复入口**。基于 `Backend/server.py:106–165`、iOS `Services/RecordQuality.swift:59–128` 和 Android `data/Analysis.kt:30–88`，列出无法同步的具体记录、字段、版本和图片引用；允许导出、人工修正，禁止自动删除或合并原始数据。验收：异常数据仍完整可导出，修正后其他端恢复同步。
2. **P1：冲突审阅与受控恢复**。围绕 `Backend/database.py:38–43`、`server.py:339–387` 增加可选版本/操作日志；离线编辑覆盖、删除和恢复可解释。回收站若采用延迟删除图片，需明确保留期；不得声称现有已物理删除图片可以恢复。验收：旧客户端仍能同步，新端能查看冲突且不静默丢版本。
3. **P1：备份与恢复演练**。针对 `Backend/database.py:12–36`、`liferecord-sync.service:7–17` 和 R06，建立一致数据库+图片备份、校验、保留期、恢复到隔离环境的流程。验收：恢复内容与原副本逐项一致；备份目录不在 Web 下，不在报告/日志泄漏密钥。
4. **P2：附件任务中心**。基于 iOS `Services/SyncService.swift:170–196` 与 Android `AppViewModel.kt:287–300`，提供待上传/失败重试/已同步状态及安全清理。验收：离线创建和重启恢复不丢图片、不重复绑定、不跨账号。
5. **P2：完整本机备份和恢复预览**。保留现有协议 JSON 导出，补充常用餐食、动作库、对话和附件的可选完整包，恢复前显示新增/冲突/跳过清单；以 C11/R06 的样本检查 ID 映射及版本兼容。
6. **P2：可撤销设备会话与温和密钥轮换**。当前 `Backend/database.py:14–15,77–86` 只有账号共享 Bearer 与浏览器 sessions；设备独立凭证可减少遗失设备的影响面。需兼容旧账号，不自动使现有用户离线；验收覆盖单设备撤销、全部撤销及历史凭证迁移。

## 8. 分阶段实施计划

### 阶段 0：确认与建立修复基线

- 本阶段交付即此报告，等待确认，不直接开展后续代码修改。
- 确认删除冲突政策、AI 删除确认体验、合法数值契约和历史非 UUID 兼容策略。先在副本做异常/碰撞/孤儿只读盘点，不改真实用户数据。
- 先把 C09 测试环境隔离，再将探针转成永久回归，防止验证修复本身污染用户数据。

### 阶段 1：数据丢失与安全边界，小范围逐项修复

建议顺序：C09 → C01/C04/C06 → C02/C03/C05 → C07/C08，并验证 R01/R04。每个问题独立、可评审，避免跨端大重构。

- C01/C07/C10 先落共享契约样本，后端与客户端逐步收敛；新增读取校验不得把旧数据默默丢掉。
- C02/C03 先以三端收敛回归固定规则，再修改合并器；删除标记保留，照片删除保持可解释。
- C05/C06 先保证目标版本和提交原子性，再改界面回执；取消/失败注入必须覆盖。
- C08 修 Web 字段投影，真实后端端到端验证；不放开任意可写字段。
- R01/R04 验证后按实际结果升级为已确认问题；敏感路径不等待性能优化完成。

验收：对应新增失败用例先能复现基线，修复后通过；Python、50 项 JVM、18 个 Swift 程序及新增真实 Web 契约检查通过；没有协议破坏、没有批改用户数据。测试通过仍需人工检查故障恢复与权限边界。

### 阶段 2：完整性、图片、重复写入和恢复能力

处理 C10–C18、C20 和 R02/R05/R06。先完成照片引用台账与待上传持久队列，再设计 GC；先扫描、提供预览及备份，再允许清理。UUID 冲突映射与迁移需单独评审，禁止自动覆盖。

验收：历史发布 schema 副本升级/失败重试/恢复演练，双设备离线多轮同步、12 图部分失败、磁盘满、提交后断网、退出切换账号均保持数据一致；坏记录可定位和修正。

### 阶段 3：性能、测试门禁与维护整理

- 按第 5 节测量后局部减少 EAV 重写、N+1 查询、主线程 IO、重复下载/汇总。保留旧快照协议，增量同步另行设计和确认。
- 补齐测试依赖安装说明/锁定、CI 与独立模拟器测试；发布日志区分 mock、集成、设备、线上只读验证及未验证项。
- 最后处理 C19 的死代码、过时文档和重复页面；保留迁移及既有联动功能，不引入无关依赖。

验收：记录优化前后数据规模与 P95、写入量、内存/FD、主线程耗时及耗电条件；不仅比较平均请求时间。构建、功能、跨端协议和错误恢复无退化。

### 后续变更约束

- 所有修复必须附对应回归测试及数据兼容说明；报告列出的测试是待实施验收要求，不是本阶段已经加入的代码。
- 不删除已有功能，不为“去重复”删除兼容实体，不把缓存清理当作用户附件清理。
- 不把“SQLite integrity_check 为 ok”“单元测试全部通过”或“AI 返回 JSON”当成业务数据正确、权限安全或生产就绪的证明。
- 后续实施、迁移、清理、部署均需在本阶段审查确认之后；本次没有提交或推送 Git。
