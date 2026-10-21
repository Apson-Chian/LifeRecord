默认 AI 服务已并入 `main`，新安装连接自己的同步账号即可使用，也支持自定义接口。当前可下载[beta.7](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.7)。**新签名不能覆盖 beta.3，安装前请阅读[迁移说明](../Docs/android-release-1.4-beta4.md#签名与发布状态)。**

# LifeRecord Android

Android 1.4.0-beta.7（2026-10-21）：编辑草稿恢复、餐盘/营养成分表/配料表识别、多图翻页、周历营养环、下拉同步、身体总览双曲线、按需列表与无障碍适配。见[实施与验证](../Docs/android-ios-parity-2026-10-21.md)，下载和升级见[本版发布说明](../Docs/android-release-1.4-beta7.md)。

「设置 → 账号与同步」支持：用户自主注册、账号密码登录及密码修改，管理员无需分配账号，保留原同步密钥兼容；首页、周历、设置和深浅色视觉已调整。[使用与部署说明](../Docs/account-password.md)。账号与界面更新已包含在 beta.6 客户端；线上账号后端已于 2026-10-20 部署；自部署服务器需升级对应后端，旧密钥连接继续兼容。

Android 1.4.0-beta.6：重做首次导览，补齐 30 天示例、训练与身体图表，并合入账号和数据兼容更新。[更新与验证](../Docs/android-release-1.4-beta6.md)。beta.4/5 可直接覆盖升级；beta.3 及更早版本需先迁移再重装。

设备测试现仅针对独立 `sandbox` 构建，包名 `ltd.apsonchian.liferecord.instrumented`。不要安装普通 Debug/Release 包来执行设备测试，也不要复用真实账号或已有个人数据的设备。使用新建的一次性模拟器：

```sh
./gradlew :app:assembleSandbox :app:assembleSandboxAndroidTest
python3 ../Tests/android-isolation.py app/build/outputs/apk/sandbox/app-sandbox.apk
./gradlew :app:connectedSandboxAndroidTest
```

只有 APK 检查通过后才可运行设备测试。该包使用独立 UID/数据库/密钥存储、内存 fake 网络且移除 INTERNET 权限；误填生产地址也会在传输前被拒绝。历史文档中的 `connectedDebugAndroidTest` 已被替换。正常 Debug/Release 构建、包名和数据保持兼容。验证进度见 [修复进度](../Docs/REPAIR_PROGRESS.md)。

原生 Kotlin + Jetpack Compose 安卓客户端，最低 Android 8.0（API 26）。工程与原有 iOS、Web、后端并列，不包含 LifeTrack App Group、跳转或联动逻辑。

返回[仓库总览](../README.md)，或查看独立的 [iOS 工程](../iOS/README.md)。以下 Gradle 命令在 `Android/` 目录执行。

## 运行与安装

1. 使用支持 Android Gradle Plugin 8.9 的 Android Studio 打开本目录，安装 Android SDK 35 和 Build Tools 35.0.0。
2. 选择 JDK 17，等待 Gradle 同步，运行 `app` 到模拟器或手机。
3. 首次启动可直接开始，或写入 14 天本机示例餐食/测量。示例不会上传或参与真实趋势，设置中可清除。
4. 需要现有 iOS/Web 数据时，在「设置 → 跨设备同步」填写原同步密钥。服务地址与 iOS 一致。
5. 默认 AI 服务使用自己的同步账号；需要自定义接口时，在「设置 → 教练与 AI → 接口与模型」配置模型、端点和服务商密钥。

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

调试 APK 输出：`app/build/outputs/apk/debug/app-debug.apk`。可直接通过 Android Studio 或 `adb install -r app/build/outputs/apk/debug/app-debug.apk` 安装。发布版使用固定持久签名，按[签名保管与签发步骤](../Docs/android-signing.md)执行；本仓库不存放私钥和密码。

构建固定为 AGP 8.9.2、Gradle 8.11.1、Kotlin 2.1.20、Compose BOM 2025.04.01、JDK 17、SDK 35。Gradle Wrapper 带官方分发包 SHA-256 校验。SDK 路径写入本机 `local.properties`，已被 Git 忽略。

## 已实现

- 今日：任意日期切换、周视图、蛋白质/碳水/餐次圆环、热量、最近体重和记录连续性。
- 餐食：新增、编辑、删除、餐次、原始描述、营养、备注；选择多张图片交由 AI 识别，再复核保存；常用餐食填入；编辑时可用 AI 修改营养草稿。
- 训练：开始/结束计时、跨午夜时长、补记、编辑、删除、独立部位、自定义部位、动作库及可选逐组次数/重量/时长。
- 身体：体重、可选体脂/腰围、历史时间和备注。
- 趋势：7 天/30 天/全部范围、体重/体脂每日中位数与指数平滑曲线、时段筛选及逐日查看、按所选范围显示热量与训练柱状图、身体总览及 30 天日历、训练概览、完整目标反馈、版本化记录质量确认、全部历史记录搜索筛选、独立生成与保存的 AI 周报。
- 教练：左侧多对话栏、iOS 同款教练头像、本机聊天照片留存、常用餐食入口、记录上下文、离开页面后继续生成；可提出餐食、测量、训练、动作库和目标操作。AI 写入默认关闭，在输入栏或设置中开启后，按明确要求执行；只有数据库实际提交成功才展示执行回执。无写入权限、无有效操作、数据已变化或任一操作无效时不写入；整批验证通过后一次提交。支持停止生成、不同对话分别生成，以及本机自定义名称和头像。
- 私有同步：兼容现有 Unix 秒时间戳、UUID、营养/身体/训练字段、个人目标和删除标记。前台每 15 秒同步，返回前台立即同步，离线可用。响应按更新时间与**收到响应时**的最新本机数据合并。
- 照片：系统相机或照片选择器，无需整个相册权限；按方向解码并压缩 JPEG。本机离线保存、配置同步后排队上传、远程照片按密钥隔离磁盘缓存、重试、完整图片缩放查看、下滑退出和保存到系统相册。
- 设置：个人档案、营养目标、服务商独立密钥、认证请求头、图片能力、生成参数、自定义指令、常用餐食、动作库、默认关闭的漏记提醒、记录 JSON 导出。
- 安卓适配：Compose 原生渲染、iOS 风格控件、深浅色、边到边布局、系统返回、键盘避让、原生日期与时间选择、通知权限和 WorkManager。

## 玻璃导航与 iOS 对齐

浮动胶囊导航使用真实页面背景模糊、轻量高光和可滑动的选中胶囊，底部新增从清晰到模糊的渐进过渡，覆盖系统手势区域。Android 12 及以上平滑融合三档系统高斯模糊，背景以较低分辨率渲染以减少开销；Android 8–11、低内存设备和省电模式使用渐变遮罩与近实色胶囊。导航图标和文字始终清晰，按钮按压和切换使用弹簧动画；键盘出现时，导航和渐进模糊一起隐藏。实现与验证见[渐进模糊说明](../Docs/android-progressive-blur.md)。

首页顺序、蓝紫主题、蛋白质/碳水/餐次配色、添加菜单、记录日历、餐次分组、照片入口、训练结束后编辑、默认收起的动作组数，以及「问 AI」先填草稿的操作已对齐 iOS。切换标签保留日期、滚动位置、趋势范围、搜索和未发送文字。详细变化与 GitHub 参考见[对齐记录](../Docs/android-ios-parity.md)。

在 [Releases](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.7) 的 Assets 下载 `LifeRecord-Android-1.4.0-beta.7.apk`，在安卓文件管理器中打开并按系统提示安装。beta.4/5/6 用户直接覆盖安装即可。**beta.3 及更早版本的签名不同，不能直接覆盖：先同步记录、导出备份并另外保留本机照片和对话，再卸载旧版安装。**JSON 导出目前没有安卓导入入口，恢复同步记录需使用原账号；详见[迁移说明](../Docs/android-release-1.4-beta4.md#签名与发布状态)。beta.4 后续更新使用固定证书。iOS 更新需要重新构建并安装 iOS App。

照片识别、智能教练与周报需要联网并配置服务。预设和自定义接口的连接、密钥保存与常见错误见[接口设置](../Docs/api-settings.md)。

## 数据与权限

健康记录存储在应用私有 SQLite；API Key 和同步密钥分别使用 Android Keystore 的不可导出 AES-GCM 密钥加密，系统备份已关闭。AI/同步配置中不保存明文密钥。清除应用数据或卸载会删除本机记录和本机密钥；卸载前应先同步或导出。

应用主动申请通知权限；网络、启动恢复和后台工作相关系统权限由应用及 WorkManager 声明。照片使用系统选择器，无需整个相册权限。启用 AI 时，相关记录上下文会发送到用户选择的 AI 接口；照片只随具体图片请求发送。启用私有同步后，真实健康记录和目标上传到原有服务器。动作库、常用餐食、AI 对话留在本机。

提醒通过 WorkManager 每天检查一次当天本机记录，并在工作结束后安排次日。系统省电可能延迟，不申请精确闹钟权限。训练星期可配置；每天最多一条汇总；其他设备的记录需要先同步才能抑制通知。

JSON 导出包含真实记录、目标、删除标记、照片服务器编号、常用餐食与动作库，不包含密钥、本机照片字节、示例和对话。它是数据导出，当前未提供安卓端 JSON 导入入口；跨设备迁移通过私有同步进行。

## 1.2.0：补齐趋势、教练和照片流程

趋势移植 iOS 的每日中位数、按实际日间隔指数平滑、目标方向校验、记录日营养统计、每周一重置的进度与全部七类质量规则。体重和体脂详情可筛选时段、切换平滑、逐日查看，原始测量可打开编辑。质量确认仅隐藏当前记录版本，编辑或同步更新后重新核对。统计不包含示例、未来及无效数值，缺测不补零。

数据详情搜索、测量详情、质量列表和周报留在趋势标签中；去教练后返回会保留位置。周报点击生成才调用 AI，独立保存和阅读，离开页面后继续生成，不创建教练对话。使用生成时的记录快照；旧报告可重生成。

教练使用左侧对话栏及 iOS 头像。未发送文字与照片跨标签保留；已发送附件保存至应用私有目录，重启可查看，删除对话时清理对应文件。请求仅发送角色和消息内容，存储路径不进入 AI 消息字段。照片可完整显示、双击/双指放大、移动，原尺寸时下滑退出；Android 10 / API 29 及以上保存到 `Pictures/LifeRecord`，旧系统使用系统文件保存窗口，不增加相册读取权限。

## 1.3.0：按 iOS 实际画面校准 UI

在专用 iOS 模拟器逐页对照首页、设置和趋势；安卓端重做大标题、周历、带中心餐数与柔和阴影的营养环、热量单位、图标底座、餐食行、分组设置与数字行、教练布局、输入条和趋势坐标。浮动导航缩至 60 dp，采用深色未选图标与灰色选中胶囊；背景、深色控件和反馈统一。设置详情在标签中推入，身体与每日营养目标分开编辑；切换标签清理输入焦点，保留未发送文字。

对照截图来自原生 App，首页使用等值示例，详见 [校准记录](../Docs/android-ios-parity.md#130以实际-ios-页面校准外观)。30 项单元测试、15 项设备测试和 Lint 通过；安装包 versionCode 4，签名与旧版一致，可覆盖安装。

## 当前平台差异

- 玻璃使用 Android RenderEffect 的多级系统模糊；圆环对齐营养配色与进度含义，材质、光照和系统字体仍有平台差异。
- 系统相机、照片选择、日期时间、返回和键盘遵循安卓平台。相机仅获得本次临时照片 URI 的授权，拍照完成或取消后清理临时文件。
- 常用餐食照片、聊天附件、质量确认和周报留在本机，不参与跨设备同步或 JSON 导出；历史聊天照片不会自动附加到后续 AI 请求。
- 训练部位专用分类、对话复核、部位目录管理和历史修复已在 1.4.0-beta.3 提供；目录偏好只保存在本机，训练标签通过原有协议同步。
- 安卓已去除 LifeTrack 联动，iOS 保留原有功能。

`./gradlew :app:connectedSandboxAndroidTest` 在新建的一次性模拟器上检查数据库、密钥与主要记录流程；运行前按文首步骤检查专用 APK。禁止把普通 Debug/Release 用户包作为设备测试目标。

运行安卓单元测试后，回到仓库根目录执行 `python3 Tests/android-sync.py`，会把 Kotlin 实际生成的同步 JSON 送入临时后端数据库验证协议兼容；`python3 Tests/sync-edit.py` 可继续执行原有 iOS/Web 同步回归。

测试覆盖同步删除/覆盖冲突、示例和本机照片路径隔离、AI 部分修改与整批失败原子性、跨午夜训练、逐组输入、缺失日期、连续记录和同日体重中位数。真实同步服务和 AI 需使用用户自己的密钥进行联调；自动测试不访问真实健康数据。

## 界面预览

- [浅色首页](screenshots/today-light.png)
- [深色首页](screenshots/today-dark.png)
- [浅色教练](screenshots/coach-light.png)
- [深色教练](screenshots/coach-dark.png)
- [浅色设置](screenshots/settings-light.png)
- [深色设置](screenshots/settings-dark.png)
- [分组身体与目标](screenshots/profile-light.png)
- [教练键盘避让](screenshots/coach-keyboard.png)
- [趋势曲线](screenshots/trends-light.png)
- [时段筛选与平滑详情](screenshots/measurement-detail.png)
- [质量确认列表](screenshots/quality-review.png)
- [左侧对话栏](screenshots/coach-drawer.png)
- [独立周报](screenshots/weekly-report.png)
- [训练月历](screenshots/workout-calendar.png)
- [当天完整训练](screenshots/workout-calendar-day.png)
- [自定义教练](screenshots/coach-profile.png)
- [名称与头像效果](screenshots/coach-identity.png)

截图来自 Android 15 模拟器；1.3.0 首页使用明确标注、与 iOS 参照数值相同的测试示例，新增趋势/质量/周报截图使用设备测试合成数据，周报文字为保存流程测试夹具，未调用真实 AI。验证记录见 [VALIDATION.md](VALIDATION.md)。

原生参照：[iOS 首页](screenshots/ios-reference/today-light.png) · [iOS 设置](screenshots/ios-reference/settings-light.png) · [iOS 趋势](screenshots/ios-reference/trends-light.png)。两端系统安全区和字体遵循各自平台。

## 2026-10-15：页面精简

- 删除首页健身记录与趋势训练节奏的装饰文案；目标反馈默认展示关键指标，营养明细与说明点击“记录与解读”展开。
- 按近 7 天、近 30 天或全部历史回顾，结束日期为今天，阶段参考按区间内实际测量跨度换算，不显示未来周末或下周计划。
- 教练每次进入和切换对话时定位到最新消息、生成状态或待复核操作；保留未发送草稿。
- 设置首页整合为六个入口：个人与目标、记录与提醒、教练与 AI、外观与个性化、跨设备同步、隐私/数据/帮助。身体和营养目标在同一个表单保存；接口和高级参数按需展开。

## 1.4.0-beta.2：同步当前 iOS 体验并提供 Release 下载

以 2026-10-15 的 iOS 源码为参照，保留已完成的六入口设置、合并个人目标表单、历史目标反馈、最新消息定位与浮动玻璃导航，补齐训练月历和教练资料入口。月历周一开始、支持跨月与返回本月，显示已完成训练量与训练内容；点击日期查看全部动作和逐组数据，再直接编辑原始记录。负重或次数缺失时不估算训练量，跨午夜按开始日归属。

教练名称与头像仅存本机，头像压缩后保留，所有对话使用同一资料；输入栏的写入开关默认关闭。开启后按请求验证并实际保存 AI 操作，再显示应用生成的回执。停止会取消对应网络请求，保留已发送的问题与照片，不执行该次写入。拍照与相册可用于教练和餐食识别。

[Release 发布说明与验证](../Docs/android-release-1.4-beta2.md)。发行附件是 Release 构建，未启用应用调试，沿用旧测试证书以支持覆盖升级；仍是预发布测试版本。APK、证书私钥和本机测试数据不进入源码仓库。

## 1.4.0-beta.3：训练部位专用流程

“趋势 → 训练内容与明细 → 按部位”提供 AI 分类、专用对话修改、时间轴和记录选择、全局部位改名及动作库入口。“设置 → 记录与提醒 → 管理训练部位”可新增、移除、恢复历史部位，并预览修复明确描述的手臂细分。AI 对话修改先预览，点击应用才保存；旧预览遇到记录变化会失效。

[发布与验证说明](../Docs/android-release-1.4-beta3.md)。上游 API Key 不会打入默认服务版 APK，始终由服务器代理持有。

默认 AI 服务版也已同步本版 UI 与功能：[默认版 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-default-v1.4.0-beta.3/LifeRecord-Android-1.4.0-default-beta.3.apk)。上游密钥留在服务器，需要先连接自己的同步账号。

## 首次使用与示例体验

首次使用提供四步导览，可跳过，也能在最后选择近 30 天完整示例。示例覆盖饮食、身体、训练和预写教练对话；设置中可重新载入或清除，不影响真实记录。[导览预览、数据边界与验证](../Docs/onboarding-and-demo.md)。
