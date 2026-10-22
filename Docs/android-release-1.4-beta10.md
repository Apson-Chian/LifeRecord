# Android 1.4.0-beta.10

2026-10-22，versionCode 14，Android 8.0+。

[下载 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.10/LifeRecord-Android-1.4.0-beta.10.apk) · [Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.10) · [校验文件](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.10/SHA256SUMS.txt)

## 目标记录可以逐条纠错

进入“设置 → 目标历史”，在需要修正的记录下点“编辑此记录”。

- 可以修改健身方向、起始/目标体重、每周变化、热量、蛋白质、碳水和脂肪；普通记录还可以用日期选择器纠正生效日期。
- 最初保留的目标也能改数值，其日期范围保持为历史基准。
- 保存后重算该条记录从生效日起、下一条目标生效前的圆环和达标统计，其他日期继续使用各自目标。修正当前生效的记录也会更新当前个人目标。
- 生效日期不允许选未来，同一天已有其他记录时提示编辑那一条；无效输入和过期草稿保留在编辑页，未保存退出有放弃提示。
- 同步使用稳定记录 ID 与修订标记，防止旧快照恢复错误数值或重新出现移走的日期。配套后端已上线并完成公网验收。

包含 beta.9 的按日期保留圆环，以及 beta.8 的跟手弹簧、Android 12 模糊更新修复、空白收键盘、字体/卡片/教练布局和完整示例改进。

## 升级与验证

beta.4–9 可以直接覆盖升级并保留数据；beta.3 及更早版本先看[签名迁移](android-release-1.4-beta4.md#签名与发布状态)。多端都应升级，以正确处理历史修订。iOS 源码已补齐同样编辑能力，需重新构建安装，未发行 IPA/TestFlight；线上 Web 静态页面未替换。

- Debug / Release 各 79 项 JVM 测试通过；Android 12 / API 31 与 Android 15 / API 35 各完整 68 项设备测试通过。
- 构建和 Lint 通过：Release 0 错误 / 16 警告，Sandbox 0 错误 / 15 警告。仅使用独立离线设备包、合成数据和模拟 AI。
- iOS 构建、Swift 回归和实际设置写入用例通过；包括纠正目标、重载、立即再次保存、非法值与过期草稿保护。模拟器坐标点击工具在本轮返回 `noWindowsAvailable`，未完成新增编辑页的原生点击验收，不沿用 beta.9 界面验收作为本轮结果。
- 服务器 Python 3.10 九项隔离脚本和公网一次性账号验收通过；已验证基准纠错、移动日期、当前目标修正与旧快照重放，合成账号清理和数据库完整性通过。[实现与截图](goal-history.md) · [后端上线](goal-history-edit-deployment-2026-10-22.md)
- APK 正式包名、14 / beta.10、API 26–35、非调试属性、v2/v3 签名和固定证书已核验。真我/vivo 真机仍需实测。

证书 SHA-256：`c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`

APK SHA-256：`fd2c1764864990514b8ef2c8a0ecb90e8d2e0fc56e2083525013b12e531d16b9`
