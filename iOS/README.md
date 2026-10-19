# LifeRecord iOS

使用 SwiftUI、SwiftData 和 Swift Charts 构建的原生客户端，最低支持 iOS 17。支持离线记录饮食、训练与身体测量，并通过可选同步服务与 Android、网页端交换记录。

返回[项目介绍](../README.md) · [Android 客户端](../Android/README.md)

## 主要功能

- 今日营养圆环、日期切换与记录日历，快速查看目标和已记录内容。
- 餐食手动录入、多图营养识别、常用餐食复用，保存前可修改识别结果。
- 训练计时、补记、部位分类、动作库与可选的重量、次数和逐组记录。
- 体重、体脂与腰围记录，配合趋势曲线、每日热量、训练柱状图和目标反馈回顾变化。
- 支持图片和多对话的智能教练、独立周报，以及主动授权后的记录操作。
- 深浅色外观、原生材质、明确的键盘收起入口和可编辑的历史记录。

## 运行

1. 使用 Xcode 打开 `LifeRecord.xcodeproj`。
2. 选择可用的 iOS 模拟器，运行 `LifeRecord` Scheme。
3. 真机运行时，在 Signing & Capabilities 中选择自己的签名团队。
4. 从空白记录开始，按需要设置目标、模型接口和同步账号。

在仓库根目录验证模拟器构建：

```sh
xcodebuild -project iOS/LifeRecord.xcodeproj -scheme LifeRecord \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/LifeRecordDerivedData CODE_SIGNING_ALLOWED=NO build
```

项目最低版本与所用 SDK 版本分别配置；真机系统需受本机 Xcode 支持。目前未提供 TestFlight 下载。

## 设置与数据

照片识别、智能教练和周报需要联网并配置服务，支持预设与自定义兼容接口。[接口设置](../Docs/api-settings.md)

记录保存在本机 SwiftData，接口与同步密钥保存在 Keychain。连接同步服务后，餐食、身体数据、训练、目标和删除标记可跨端合并；同步在 App 活跃时运行，离线仍可记录。

聊天、聊天附件、常用餐食照片和部分本机偏好不全部参与同步或导出，卸载前应另行保留。[同步与账号说明](../Docs/public-beta.md)

## 检查与参考

在仓库根目录运行 Swift 回归：

```sh
./iOS/Tests/run.sh
```

- [身体趋势统计口径](../Docs/body-trends.md)
- [当前版本更新说明](../Docs/android-release-1.4-beta4.md)
- [共享回归检查](../Tests/README.md)
