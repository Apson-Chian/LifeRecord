# Android 1.4.0-beta.3：补齐训练部位模块

2026-10-16。移植 iOS 的专用训练部位分类、对话复核和管理界面，保留上一版日历、教练自定义、拍照和玻璃导航。

| Before | After | Why |
| --- | --- | --- |
| 训练详情进入通用数据列表 | 独立训练明细，可切换训练记录/按部位、点时间轴选择并编辑历史记录 | 与 iOS 的训练路径一致 |
| 仅手动编辑部位或通过通用教练修改 | 专用 AI 分类；按当前范围或单个部位对话，逐条展示旧部位 → 新部位，确认才保存 | 补齐遗漏的专用分类与复核流程 |
| 只有预置和临时自定义标签 | 持久可选部位目录；新增、全局改名、移除及恢复历史部位 | 保持编辑器、历史和动作库的名称一致 |
| 历史手臂标签需要逐条修正 | 手臂细分与历史修复预览；否定、计划、疑问或历史提及不推断为本次训练 | 保留真实记录，避免关键词误归类 |

全局改名在同一 SQLite 事务更新可选目录、全部历史训练的对应标签、动作里的部位及动作库；时间、备注和每组数值保持原样。移除仅影响以后选择，不删除历史。AI 复核只接受清单内准确 ID、无重复且合法的标签；整批应用前检查记录是否已变化、删除或离开当前分组，任一不符则整批不写入。分类分批获取结果，再校验全部结果并一次提交，避免部分成功后混合写入。

普通版：[Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-v1.4.0-beta.3)。默认服务版：[Release](https://github.com/Apson-Chian/LifeRecord/releases/tag/android-default-v1.4.0-beta.3)，源码位于 `default-ai-service`。两种安装包沿用原测试签名，versionCode 同为 7，支持覆盖旧版和相互覆盖。默认服务版使用服务器代理，上游 API Key 仅存服务器环境配置，不放入 APK、源码或客户端响应；使用各人的同步账号密钥鉴权。已有安装保留原接口选择，可在“接口与模型”切换默认 AI 服务。

## 验证与截图

普通版 Debug / Release 构建成功，48 项 JVM 与 26 项 API 35 设备测试全部通过，无失败或跳过。Debug / Release Lint 均为 0 错误、16 警告。新增回归覆盖全局改名保留逐组数据、删除仅影响可选目录、AI 预览确认写入、过期预览整批拦截、35 条历史修复及目录和记录事务回滚。已检查以下三张真实运行截图，共享同步协议与编辑回归通过。专用模拟器验证旧 beta.2 → 普通 beta.3 → 默认 beta.3 → 普通 beta.3 的覆盖安装与冷启动，均成功，无崩溃。

普通版 APK SHA-256：`366fd09d76e3bf7567f9aede466ee2274b9ba72f7459813a90af988cb6096414`。v2/v3 签名验证通过，Release 未启用应用调试；沿用原证书以兼容覆盖安装。默认服务版单独构建验证见 [默认服务说明](https://github.com/Apson-Chian/LifeRecord/blob/default-ai-service/Docs/default-ai-service.md)。

截图：[按部位](../Android/screenshots/workout-parts.png) · [部位管理](../Android/screenshots/workout-part-manager.png) · [AI 修改预览](../Android/screenshots/workout-part-preview.png)。使用合成记录和模拟 AI，不含用户真实健康数据。

玻璃仍为 Android RenderEffect/AGSL 近似；字体、系统选择器与返回手势遵循安卓平台。本轮不重新部署服务器，不读取或变更服务器的实际 API Key。
