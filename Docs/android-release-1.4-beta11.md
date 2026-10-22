# Android 1.4.0-beta.11

2026-10-22，versionCode 15，Android 8.0+。

[下载 APK](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.11/LifeRecord-Android-1.4.0-beta.11.apk) · [Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.11) · [校验文件](https://github.com/Apson-Chian/LifeRecord/releases/download/android-v1.4.0-beta.11/SHA256SUMS.txt)

## 液态玻璃统一重做

- 透明：浮动导航更通透，卡片、表单保留足够底色，去掉厚重紫边；统一首页、设置和教练输入区。
- 折射：Android 13+ 对实际背景做圆角边缘镜片位移；Android 12 使用原生模糊纹理和四层镜片带，保持中心稳定。
- 高光：统一左上光源、柔和面光和细内缘，文字保持锐利。
- 阴影：重做环境与接触阴影，区分卡片、导航、小按钮和弹层的高度。
- 修复跨窗口弹窗可能停留在旧背景的问题；保留 Android 12 残影修复、跟手弹簧和点空白收键盘。

包含此前目标历史逐条编辑、按生效日期保留圆环和完整示例改进。[材质实现与兼容说明](android-liquid-glass.md)

## 升级与校验

beta.4–10 可直接覆盖升级并保留数据。beta.3 及更早版本先看[签名迁移](android-release-1.4-beta4.md#签名与发布状态)。本轮只更新 Android，不需要部署后端或重新构建 iOS。

- Debug / Release 各 79 项 JVM 测试通过；Android 12 / API 31 与 Android 15 / API 35 各完整 72 项设备回归通过。
- 新增四项实际像素检查，覆盖透射、中心稳定/边缘折射、前景清晰、深浅色更新、反复进入、回退阴影和跨窗口弹窗更新；Android 15 显式验证 AGSL 编译成功。
- 首次完整回归定位并修复半展开弹层裁剪导致训练记录无法打开的问题，再跑两版系统完整回归均通过。API 31 有一次收键盘后的空白截图，单独复测未复现持续空白；追加实际文字像素等待断言后，两版系统各五项兼容性回归通过，最终表单截图已检查。
- Sandbox / Release 构建通过。Lint：Release 0 错误 / 16 警告，Sandbox 0 错误 / 15 警告。所有设备测试只安装独立、无 INTERNET 的离线包，使用合成数据与模拟 AI。
- 正式包名、15 / beta.11、API 26–35、非调试属性、v2/v3 签名和 beta.4 起固定证书已核验。真我/vivo 真机、低端机帧率与温升未实测。

证书 SHA-256：`c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`

APK SHA-256：`6a49967b57a3dac864f1729bf1e82fb33faef97f907235cb5926e1d58a0f1962`
