# Android 1.4.0-beta.13 与网页接口配置更新

2026-11-12 · build 17 · Android 8.0+

[直接下载 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.13/LifeRecord-Android-1.4.0-beta.13.apk) · [Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.13) · [SHA-256 校验文件](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.13/SHA256SUMS.txt)

## 本次内容

- 网页 API Key 持久化到当前浏览器，刷新或重新打开页面后恢复。多个命名配置可保存各自的 Key，即使使用相同接口地址，也能分别切换、更新和删除。
- 网页更换地址或认证方式时隔离原 Key；提供一键清除，退出、更换账号或注销账号时清除保存的 Key。Key 不随健康记录导出或同步。[接口与隐私说明](api-settings.md)
- 合入网页玻璃按钮、开关、Temperature 滑杆和趋势范围切换，支持关闭玻璃效果及减少动态效果。
- README 将最新 APK 直接下载、平台入口和上手步骤前置，用户后台部署说明移至[独立文档](user-admin.md)。

Android APK 基于当前源码重新构建，版本提升为 beta.13，沿用 beta.12 的教练指令、身体趋势与测量明细。上述新接口存储和控件改动位于网页端，Android 已有的接口密钥存储行为保持不变。本次发布源码和 APK，不包含线上网页或后端的重新部署。

## 安装与升级

beta.4–12 可覆盖安装并保留本机数据。beta.3 及更早版本需先同步、导出并另存本机照片与对话，再按[签名迁移说明](android-release-1.4-beta4.md#签名与发布状态)重新安装。

应用 ID：`ltd.apsonchian.liferecord`。沿用 beta.4 起的固定发布证书，SHA-256：

`c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`

## 验证

- Android Release 构建与 80 项发布版 JVM 单元测试通过；lint 无错误，保留 16 条警告。
- 网页 Playwright 回归通过：Key 刷新恢复、相同地址的多配置隔离、更新与删除、一键清除、退出及注销清理、存储失败提示；账号注册与登录回归通过。
- 发布附件包含固定证书签名的 Release APK 与 `SHA256SUMS.txt`，签发脚本检查 APK 对齐、签名及证书指纹。

网页测试使用模拟接口，未调用真实计费 AI。本次未新增 Android 真机或模拟器安装验证。
