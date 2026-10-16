# LifeRecord（生活记录）

安卓安装：[1.4.0-beta.3 Release 下载](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.3) · [更新与验证](Docs/android-release-1.4-beta3.md)。在 Assets 下载 APK，可覆盖安装旧测试版。

API 设置更新：预设仅保留 DeepSeek 和 GLM，三端支持新增、保存与切换多个自定义配置。[配置说明与本机 Dots 设置步骤](Docs/api-settings.md)。

1.4 公开邀请测试版本：独立用户、结构化 SQLite 迁移、更自由的 API 兼容参数与外观设置。新安装从空白记录开始。[测试分发与安全说明](Docs/public-beta.md)。

截至 2026 年 10 月 13 日，网页与后端已更新到[现有网站](https://apsonchian.ltd/liferecord/)，Android 1.4.0-beta 安装包已提供测试下载，iOS 1.4（build 5）工程已交付并通过模拟器构建，尚未发布到 TestFlight。网页已补齐设置面板、自定义 API、训练编辑、删除确认、历史分页和 ETag 条件刷新；AI 数据范围保持原样。

查看[跨平台验证记录](Docs/public-beta-validation.md)与[网页优化交付记录](Docs/web-optimization.md)。测试凭据、用户数据、服务器环境文件和本机分发包不进入仓库。当前仍采用邀请测试，公开注册、密码找回、自动备份与告警尚未实现；真实计费 AI、完整渗透测试和并发压测尚未验证。

本地优先的健身记录项目。Android 和 iOS 使用独立的原生工程、界面、存储与构建工具，通过同一私有同步后端与 Web 交换餐食、身体数据、训练、每日目标和删除标记。

## 仓库结构

```text
LifeRecord/
├── Android/                      # Kotlin + Jetpack Compose，Android 8.0+
│   ├── app/                      # 应用源码、单元测试和设备测试
│   ├── gradle/                   # Gradle Wrapper
│   ├── screenshots/              # 安卓界面与 iOS 对照预览
│   └── README.md
├── iOS/                          # SwiftUI + SwiftData，iOS 17+
│   ├── LifeRecord/               # 应用源码、资源与隐私声明
│   ├── LifeRecord.xcodeproj/      # Xcode 工程与共享 Scheme
│   ├── Configuration/            # Info.plist 与 Entitlements
│   ├── Tests/                    # Swift 回归程序与运行脚本
│   └── README.md
├── Backend/                      # Python / SQLite 私有同步与照片服务
├── Web/                          # 响应式记录管理后台
├── Tests/                        # 后端、Web 与跨平台协议回归
└── Docs/                         # 统计口径与历史设计参考
```

| 平台 | 打开方式 | 说明 |
| --- | --- | --- |
| Android | Android Studio 打开 `Android/` | [运行、功能与界面预览](Android/README.md) · [验证记录](Android/VALIDATION.md) |
| iOS | Xcode 打开 `iOS/LifeRecord.xcodeproj` | [运行、功能与平台配置](iOS/README.md) |
| Web / 后端 | 部署 `Web/` 与 `Backend/` | 下方说明与现有服务配置 |

安卓客户端使用实际 iOS 页面校准的大标题、圆环、分组设置、教练输入与趋势卡片，并用 Compose 实现浮动玻璃导航，不包含 LifeTrack 联动；原有苹果版本的功能和 LifeTrack 配置保留在 `iOS/`。两端可分别开发、构建和安装，均可离线记录。界面变化、系统效果支持与剩余差异见[安卓与 iOS 对齐记录](Docs/android-ios-parity.md)。

## 快速构建

以下命令在仓库根目录执行。Android 需要 JDK 17、SDK 35；iOS 需要 Xcode，真机运行时在工程中选择自己的签名团队。

```sh
# 安卓调试 APK 与核心检查
cd Android
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
cd ..

# iOS 模拟器构建（无需配置真机签名）
xcodebuild -project iOS/LifeRecord.xcodeproj -scheme LifeRecord \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/LifeRecordDerivedData CODE_SIGNING_ALLOWED=NO build

# 原有 iOS Swift 回归检查
./iOS/Tests/run.sh
```

安卓 APK 生成于 `Android/app/build/outputs/apk/debug/app-debug.apk`。构建缓存、安装包、本机 SDK 路径和签名密钥均被 Git 忽略。API Key 与同步密钥由用户在各端设置中录入，不写入仓库。

## DeepSeek 配置与 401 修复

两端官方接口均使用 `https://api.deepseek.com/chat/completions`、`Authorization: Bearer`，预设模型更新为 `deepseek-flash`。发送时自动纠正旧认证选项，清理密钥粘贴中的 Bearer / Authorization 前缀和外围空白，阻止隐藏或包含不可见字符的密钥进入网络请求。密钥继续按服务商独立存储。

更新 App 后，在「设置 → AI 接口」选择 DeepSeek，复制[开放平台的完整 API Key](https://platform.deepseek.com/api_keys)，保存并测试。不要使用网页登录凭证或第三方服务的密钥。401 表示鉴权失败，402 表示 API 余额不足；错误提示不回显密钥。若新版仍返回 401，请重新创建官方密钥。已有失效密钥无法通过修改客户端恢复。[官方配置](https://api-docs.deepseek.com/)、[错误码说明](https://api-docs.deepseek.com/quick_start/error_codes/)。

`deepseek-flash` 支持图片；新预设开启图片能力，已有关闭设置继续保留，可手动开启。模型别名 `deepseek-v4-flash` 仍受官方支持，模型名更新并非 401 的原因。自动回归使用模拟响应检查实际请求头和错误处理，未使用用户密钥进行真实连通性验证。

## Web 页面

`Web/` 是采用侧栏导航、指标卡与餐食数据表格的响应式管理后台，可新增、编辑和删除带照片的餐食及身体数据，编辑每日目标，查看三层营养圆环、每日圆环与带绿点的月历，并导出完整 JSON。宽屏端还提供日期快捷切换、手动同步、营养概览、跨全部历史的餐食搜索与筛选，以及 `N` / `W` / `/` 键盘快捷操作。数据由 `Backend/` 中的鉴权 SQLite 服务持久化，与 iOS、Android App 每 15 秒及页面重新聚焦时自动双向同步；浏览器只在 Local Storage 中保存当前选择日期等界面偏好。

首次使用时，在 App 的“设置 → App 与浏览器同步”及网页中各粘贴一次相同的同步密钥。网页验证成功后使用 `Secure + HttpOnly + SameSite=Strict` Cookie，不会把密钥写进前端源码或 GitHub。

线上地址：<https://apsonchian.ltd/liferecord/>

AI 营养结果会在保存前保持可编辑；它仅用于日常记录参考，不构成医疗建议。

## 共享回归检查

```sh
python3 Tests/sync-edit.py
python3 Tests/admin-api.py
# 先运行安卓单元测试，生成真实 Kotlin 协议样本
python3 Tests/android-sync.py
# 安装 Playwright 并确保 Chrome 可用后
node Tests/web-smoke.cjs
```

上述检查使用临时数据库或模拟 API，不访问真实健康记录。Swift 测试与安卓设备测试分别位于 `iOS/Tests/` 和 `Android/app/src/androidTest/`；具体命令见各平台文档。

[身体趋势统计口径](Docs/body-trends.md)描述 iOS 与 Android 的中位数和指数平滑规则；[历史网页设计参考](Docs/DesignReferences/qianwen.html)只作参考，实际 Web 入口为 `Web/index.html`。
