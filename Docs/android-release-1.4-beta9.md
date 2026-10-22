# Android 1.4.0-beta.9

2026-10-22，versionCode 13，Android 8.0+。

[下载 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.9/LifeRecord-Android-1.4.0-beta.9.apk) · [Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.9) · [SHA-256 校验文件](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.9/SHA256SUMS.txt)

## 目标改变，保留过去的进步

- 修改健身目标从保存当天起生效，更早日期继续使用原目标，避免过去已经合上的圆环因新目标而重新打开。
- 首页、周历和热量/蛋白质达标统计按各自日期计算；营养调整不会重新开始体重阶段。
- 新增“设置 → 目标历史”，查看生效日期与历史目标。同日多次保存使用当天最后一版，仅改称呼或身高不新增目标版本。
- AI 修改目标同样记录历史；同步协议支持离线历史独立合并。iOS 同步补齐这一功能与月历日期计算，**需要重新构建安装 iOS App；本 APK 只更新安卓**。

包含 [beta.8](android-release-1.4-beta8.md) 的全部更新：跟手弹簧动画、Android 12 模糊更新修复、空白处收键盘、字体/教练布局/圆环与卡片比例校准、完整示例及 AI 数据范围说明，以及同一源码里的 iOS 首页身体测量。

## 升级与范围

沿用 beta.4 起固定签名，beta.4–8 可直接覆盖升级，保留本机数据。beta.3 及更早版本先阅读[迁移说明](android-release-1.4-beta4.md#签名与发布状态)。旧示例可在“设置 → 隐私、数据与帮助 → 载入完整示例”更新。

本功能从已有当前目标开始保留版本，**无法自动恢复旧版本未记录、已经丢失的历史目标**。多端都需要升级；完整历史同步还需配套后端更新。配套目标历史后端已部署并通过公网验收；Web 日期适配随源码提供，线上 Web 静态页面未替换。[行为、协议和截图](goal-history.md)

## 验证

- Debug / Release 各 76 项 JVM 测试；Android 12 / API 31 与 Android 15 / API 35 各完整 66 项设备测试通过，使用离线独立包与合成数据。
- Release / Sandbox 构建和 Lint 通过：0 错误，分别 16 / 15 警告。iOS 模拟器构建、Swift 事务与共享协议回归通过，已实际操作修改目标、查看昨日、冷启动及目标历史。
- 临时数据库验证后端目标合并、旧客户端兼容、原子回滚；Kotlin / Swift / 后端 / Web 协议往返通过。
- APK 正式包名、版本 13 / beta.9、API 26–35、非调试属性和固定证书已核验。尚未在真我 Android 12 与 vivo Android 15 真机复测。

证书 SHA-256：`c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`

APK SHA-256：`a39bbddd02804ebc64d273de1f86ef48e1ba55fb1be4cf4d34208742eb29b5b9`
