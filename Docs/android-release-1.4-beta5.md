# Android 1.4.0-beta.5

2026-10-19，基于 `main`。versionCode 9，最低支持 Android 8.0。

[Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.5) · [下载 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.5/LifeRecord-Android-1.4.0-beta.5.apk)

## 本次更新

- 默认 AI 服务并入主线，后续统一维护一个版本。新安装连接自己的同步账号即可使用服务器提供的服务，无需填写上游 API Key；已有接口选择保留，也可以继续使用自定义接口。
- 每日热量图恢复橙色柱形、浅蓝目标虚线和数值/日期坐标。最新或选中日期加深显示，支持点击查看；保留正确的日期分桶、时间范围和缺测提示。
- 延续 beta.4 的训练柱状图、身体总览、记录日历、教练失败恢复、键盘收起、删除确认和新增记录默认当前时间的优化。
- 仓库首页补充 iOS 真机首页截图。iOS 默认服务与图表更新已合入源码，本次未上传 TestFlight。

## 升级

beta.5 使用与 beta.4 相同的固定签名，versionCode 提升至 9；beta.4 普通版和原默认服务版均可直接覆盖升级，保留本机记录、对话和设置，无需卸载。系统仍会校验安装来源和签名。

beta.3 及更早版本使用旧签名，不能直接覆盖。先核对同步数据并另存需要的本机内容，再卸载重装；JSON 目前没有安卓导入入口，对话及部分照片不参与同步。[迁移步骤](android-release-1.4-beta4.md#签名与发布状态)

## 验证

从干净的 `main` 发布工作树构建未启用调试的 Release APK，使用持久密钥库签名，核对证书和 APK 完整性；附件同时提供 `SHA256SUMS.txt`。

发布构建、63 项安卓 JVM 回归和 Lint 通过。默认服务鉴权、额度、敏感配置不下发、自定义接口回退、同步、网页回归、Swift 回归与 iOS 模拟器构建已在合并时验证；图表深浅色、7/30 天切换和缺测详情通过独立无网络验证包检查。测试使用临时数据库、模拟服务和合成记录，未访问真实健康记录或计费 AI。

在全新一次性模拟器安装公开 beta.4，录入合成测量后直接覆盖 beta.5；冷启动验证测量和引导状态保留。旧普通版与默认服务版的包名、证书和版本号均已核对。

证书 SHA-256：`c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`。[签名保管说明](android-signing.md)
