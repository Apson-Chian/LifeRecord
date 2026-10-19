# Android 1.4.0-beta.4：趋势日期修复与当前 iOS 体验对齐

2026-10-19。普通版来自 `main`，默认 AI 版来自 `codex/default-ai-service`。两种 APK 的 versionCode 均为 8。签名发布状态见下文。

## 本次更新

- 修复 iOS 每日热量与训练柱状图的日期分桶和刻度不对齐：柱体、日期标签及点击检查使用同一套本地日历日；末日完整显示，单日不会重复日期，跨月、跨年和夏令时使用正确边界。热量图保留所选时间范围，点击缺测日期显示未记录，不映射到相邻记录。
- 安卓补齐训练时长柱状图；每日热量不再固定 14 天，按 7 天、30 天或全部显示。两种图表均提供日期/数值轴、目标线（适用时）、按日点选与前后日查看，空白日不当作零记录。
- 安卓数据详情增加身体总览、近 30 天记录日历和宏量营养均值；身体总览包含趋势体重、今日中位数、7/30 天变化、趋势速度及同次测量估算的身体组成。缺测不补零，示例和未来记录不参与。
- 安卓教练输入栏增加独立收起键盘按钮，保留草稿且不触发发送；返回前台回到最新消息。失败后可重新生成最近一次问题，复用原问题、原照片与原发送时间，不重复插入提问。
- 生成状态持久化。重启后将未完成请求恢复为可重试；若在处理写入时中断，先提示核对记录，不提供直接重放。停止、删除对话和销毁 ViewModel 会取消底层请求，迟到响应不能恢复已删除对话或继续写入。网络请求超时后可手动重试。
- 本版同时包含上一轮尚未打包发布的双端删除确认及新增记录时间默认值优化：新增使用打开页时的当前时分，补记保留所选日期，编辑保留原时间。

## 候选发布

- [普通版 Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.4) · [普通版 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.4/LifeRecord-Android-1.4.0-beta.4.apk)
- [默认 AI 版 Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-default-v1.4.0-beta.4) · [默认 AI 版 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-default-v1.4.0-beta.4/LifeRecord-Android-1.4.0-default-beta.4.apk)

默认 AI 版仍通过独立同步账号使用服务器代理，上游密钥不进入 APK。已有接口选择与本机记录由原安装保留；换签名重装需先自行同步或导出。

## 验证

普通版与默认 AI 版分别验证构建和测试，最终结果随发布更新。iOS 两分支模拟器构建与 Swift 回归通过，新增检查覆盖单日、缺测、末日、跨年和夏令时；安卓新增检查覆盖日期轴、身体总览、失败恢复、原消息/照片/时间保留和禁止自动重放写入。

设备验证使用全新 Android 35 模拟器与独立 `.instrumented` 包：验证包不含 INTERNET 权限，使用本机模拟网络和合成记录。检查图表选择、身体总览、实际软键盘收起、原图重试、重启恢复、新增/编辑时间、删除取消；未访问真实账号、健康记录或计费 AI。普通签名包仅用于这台一次性模拟器上的覆盖安装检查。

iOS 本次发布为代码更新，尚未上架 TestFlight；安卓附件为未启用调试的预发布 Release 包。系统终止应用后不会继续生成，恢复后的请求由用户决定是否重试。本轮不部署服务端。

## 签名与发布状态

发现 beta.3 的签名证书与当前本机 `~/.android/debug.keystore` 不一致。历史发布记录指向临时目录 `/private/tmp/liferecord-android-user/debug.keystore`，该文件现已不存在，常规本机位置未找到备份。原证书摘要为 `217a683e9e34047e07205651ae92575f206db141f42fb1c1b48523a3e32103e5`，当前候选证书为 `c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`。

发布暂保留草稿，等待确认是否启用新证书。新证书不能直接覆盖 beta.3；必须先同步或导出需要保留的记录，再卸载重装。本机对话、常用餐食照片等并不全部参与同步，应另外保留。私钥不得上传到 Git 或 Release；两种新候选包使用相同证书。

截图：[训练柱状图](../Android/screenshots/training-beta4.png) · [每日热量](../Android/screenshots/calories-beta4.png) · [身体总览](../Android/screenshots/body-beta4.png) · [收起键盘](../Android/screenshots/keyboard-beta4.png) · [重试](../Android/screenshots/retry-beta4.png) · [删除确认](../Android/screenshots/delete-beta4.png)。截图均为合成测试数据。
