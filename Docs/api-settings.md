# API 设置与自定义配置

2026-10-13：Android、iOS 和网页仅展示 DeepSeek、GLM 两个预设及自定义入口。旧 Dots 选择迁移为自定义配置，既有地址与密钥绑定保留。三端均可另存多个命名配置、切换、更新及删除；保存配置不包含 API Key。网页密钥只留在页面内存，刷新后重新填写；移动端密钥保存在本机安全存储。删除配置不会删除健康记录。

## 在你的设备上添加 Dots

进入设置 → AI 助手（网页为设置 → API），服务商选“自定义”，填写：

| 设置 | 值 |
| --- | --- |
| 接口地址 | `https://note3-prev-api.askdiandian.com/v1/chat/completions` |
| 模型 | `dots3-note-prev` |
| 认证方式 | `api-key` 请求头，直接填写 Key，不加 Bearer |
| 支持图片 | 开启（移动端） |
| 图片 detail | `medium`（移动端的接口兼容性设置） |
| JSON 格式参数 | 关闭 |
| 输出 Token 参数 | `max_tokens` |
| 最大输出 Token | 建议从 `4096` 开始 |
| 额外请求参数 | `{"chat_template_kwargs":{"enable_thinking":false}}` |

配置名称可自行填写，例如“我的视觉接口”，点击“另存为新配置”。Android 在当前表单填写 API Key；iOS 点击 API Key 保存到钥匙串；网页在当前页填写密钥。重新选择已保存配置可恢复模型、地址和兼容参数。移动端“保存并测试连接”会发起真实 AI 请求；网页“检查地址与参数”仅检查配置，不验证实际模型与密钥。

以上地址和模型沿用已使用的配置；如平台调整，按 [Dots 官方接口文档](https://dots.ai/platform/docs)更新你保存的自定义配置。不要把 API Key 放在额外参数、配置名称、反馈或仓库中。

## 验证与分支

`main` 的提交说明为“优化api设置”。网页回归覆盖配置新增、更新、删除、页面刷新恢复及密钥不持久化；iOS 回归覆盖配置切换、重启恢复、旧预设迁移及清除本机数据；Android 回归覆盖旧预设迁移与兼容参数。iOS 模拟器构建、Swift 回归、Android Debug 构建/单元测试/lint 和网页回归通过。未调用真实计费 AI。本次更新以仓库源码为交付，默认服务分支的部署需要单独切换服务端版本。

主网站 API 设置优化与手机配置按钮样式已上线：https://apsonchian.ltd/liferecord/ 。不要求用户提供 AI Key 的独立版本已在 `codex/default-ai-service` 分支提供，并部署到 https://apsonchian.ltd/liferecord-default/ 。默认服务的私有配置、额度、真实请求验证及分发记录见[分支交付说明](https://github.com/Apson-Chian/LifeRecord/blob/codex/default-ai-service/Docs/default-ai-service.md)。服务器当前运行该分支的兼容后端，同时支持两个网页版本；重部署 main 后端会移除默认服务路由，部署时需保留默认服务模块。
