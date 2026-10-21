# Android 1.4.0-beta.7

2026-10-21，基于 `main`。versionCode 11，最低支持 Android 8.0。

[Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.7) · [下载 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.7/LifeRecord-Android-1.4.0-beta.7.apk) · [SHA-256 校验文件](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.7/SHA256SUMS.txt)

## 本次更新

- 重新调整玻璃导航，减轻折射、描边和阴影；底部增加由清晰到模糊的渐进过渡，文字与图标保持清晰。Android 12 及以上使用三档系统高斯模糊，旧系统、低内存设备和省电模式自动回退。
- 编辑草稿支持活动重建后恢复，包括餐食、测量、训练、嵌套逐组数据及常用库；照片以私有文件引用恢复。离开未保存编辑时增加放弃确认，阻止旧草稿重新保存已删除记录。
- 餐食识别补齐“餐盘识别 / 营养成分表 / 配料表”，按模式发送不同指令，结果继续由用户复核并保存。
- 餐食和聊天照片支持同组翻页、页码、保存当前图片、双击/双指缩放；放大时优先平移，还原后支持下滑关闭。
- 首页周历增加每天营养圆环，补齐餐次图例、下拉同步、结果反馈和餐食长按编辑/删除。
- 身体总览同时显示每日中位数与趋势，优先展示今日测量，历史按需展开。长列表与图片按需加载，降低大量记录下的开销。
- 统一卡片材质、选择控件和外观图标，聊天跟随强调色；补齐系统触觉反馈、大字体适配和图表/照片无障碍操作。关闭系统动画时省略按压缩放。

## 升级

沿用 beta.4/5/6 的固定签名，版本号提升至 11，可直接覆盖这些版本，保留本机记录、对话与设置。beta.3 及更早版本签名不同，需按[迁移说明](android-release-1.4-beta4.md#签名与发布状态)先保留数据，再卸载重装。

默认 AI 和账号登录继续使用既有服务，本轮不部署后端，也不修改 iOS 或 Web。自部署服务器的账号要求沿用 beta.6。[账号说明](account-password.md)

## 验证与边界

- Debug、Sandbox 和 Release 构建成功，各变体 69 项 JVM 测试通过；发布变体 Lint 为 0 错误、16 项兼容/代码建议警告。
- API 35 离线隔离测试包完整 54 项设备测试通过，覆盖账号、编辑恢复、三种识别请求、多图手势、图表、千条历史、大字体、渐进模糊像素、存储与隔离。宿主 GPU 滚动采样和省电回退追加检查通过。
- 实际 Kotlin JSON 与后端协议、同步编辑/删除兼容检查通过。测试使用合成数据与模拟 AI，未调用计费服务。
- 最终 APK 校验 v2/v3 签名、固定证书、正式包名、versionCode 11、API 26–35 和非调试属性。设备自动化仅运行独立 `.instrumented` 包，没有在用户设备或正式包执行自动化。
- 已核对深浅色页面、双曲线、恢复的草稿、多图和大字体截图。[实施记录与截图](android-ios-parity-2026-10-21.md) · [渐进模糊实现](android-progressive-blur.md)

仍为测试版。API 26–32 镜像、低端真机帧率/温升和完整 TalkBack 阅读顺序尚待对应设备验收；模拟器采样不代表手机 60fps。系统状态恢复不等于永久草稿库，主动清除数据或移除任务不保证恢复草稿。工程其余审查事项见[修复进度](REPAIR_PROGRESS.md)。

证书 SHA-256：`c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`。[签名保管说明](android-signing.md)

APK SHA-256：`c3a31c59ece7222f34b1c4599762432017ea50adea034d6f668f73ff9b4d4a3a`
