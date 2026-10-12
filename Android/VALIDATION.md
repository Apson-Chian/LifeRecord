# 安卓版本验证

2026-10-12，使用 JDK 17、Android SDK 35 和任务专用 Android 15 / API 35 ARM64 模拟器完成以下检查：

- `:app:assembleDebug`：生成调试 APK 成功。
- `:app:testDebugUnitTest`：10 项核心测试通过，无失败。
- `:app:lintDebug`：通过，无错误；剩余为 KTX 用法、同步写入偏好及旧系统图标兼容提示。
- `:app:connectedDebugAndroidTest`：4 项设备测试通过，包括餐食输入/保存/详情删除、训练开始/结束/页面切换、数据库重开及密钥服务商隔离。
- `python3 Tests/android-sync.py`：Kotlin 实际生成的 JSON 经原有后端临时数据库验证，字段完整往返，过期训练快照不能恢复删除记录。
- `python3 Tests/sync-edit.py`：原有餐食、来源、照片编号、训练、逐组数据与旧客户端兼容回归通过。

交互测试使用独立模拟器和模拟数据。真实同步服务器、AI 连通性及照片上传需要用户配置自己的密钥，未访问真实健康数据。最低系统 API 26 由构建配置支持，本次设备验证使用 API 35。

调试安装包位于 `dist/LifeRecord-1.0.0-debug.apk`；构建原始输出位于 `app/build/outputs/apk/debug/app-debug.apk`。调试包和构建缓存不进入 Git；工程源文件、Gradle Wrapper、回归检查和截图保留在项目中。发布签名尚未配置。

同日完成仓库结构调整：Android 工程仍位于 `Android/`，原苹果工程、配置与 Swift 测试迁至 `iOS/`。迁移后重新验证安卓构建、10 项单元测试、Lint、Kotlin/后端协议，以及 iOS 模拟器构建和 11 个 Swift 回归程序，全部通过。原有 iOS 文件与迁移前逐字节一致；共享 `Backend/` 和 `Web/` 的部署目录保持原位。仓库入口见 [README](../README.md)。
