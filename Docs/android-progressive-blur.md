# Android 导航渐进模糊

2026-10-21；2026-10-22 增补 Android 12 修复。本次调整移除胶囊边缘的明显折射，减轻白色描边、高光和阴影。底部增加覆盖屏幕宽度及系统导航区的渐进模糊，页面内容滚入导航区域时自然变软，导航文字和图标单独绘制，保持清晰。

## 渲染与兼容

- Android 12 及以上：使用系统 RenderEffect，分别生成三档真实高斯模糊，并按纵向位置平滑融合，近似渐进半径。背景输入的宽高各取四分之一，前景图标、文字和原页面维持完整分辨率。扩展采样层显式裁切以限制滤波范围。
- Android 8–11、低内存设备或系统省电模式：渐变背景遮罩和近实色胶囊，避免模糊开销。
- 背景先扩展采样范围、模糊后再裁切，避免把模糊区域上缘的一行像素拉长。绘制按根坐标对齐，支持内容滚动和系统导航栏 inset。
- 只捕获页面内容；渐进模糊、导航、提示均在捕获区域之外，避免反馈。渐进层没有点击或拖动处理器，触摸可传递至内容。
- 键盘弹出时与导航一起隐藏；大字体沿用加高导航尺寸。深浅色使用当前主题的背景与材质色。

参考 [Haze 的渐进模糊与平台分级思路](https://github.com/chrisbanes/haze/blob/main/docs/blur/platforms.md)和 [Android RenderEffect](https://developer.android.com/reference/android/graphics/RenderEffect)。沿用工程现有 GraphicsLayer，无新增依赖或 Compose 版本升级。

## 验证

使用独立 sandbox 包和全新 API 35 模拟器，测试数据为合成条纹和示例记录。设备测试前运行 `Tests/android-isolation.py` 核对独立包名、fake Application 和无 INTERNET 权限。

`GlassRenderingTest` 检查生产渐进材质与多档融合的上缘/底部像素对比度、深浅色、偏移坐标下的背景对齐、源内容变更后的重绘，以及无模糊回退的透明上缘和触摸穿透。Android 12 多档算法在 API 35 上直接运行；API 31 后续已增加对应系统回归；API 26–30 / 32 尚无对应系统设备验证。

最终结果：普通 Debug 与 Sandbox 打包成功，两种构建各 69 项 JVM 测试通过，Lint 无错误；完整 54 项 API 35 设备回归通过。设备检查包含滑动切换标签、键盘弹出时同时隐藏导航与渐进模糊，以及大字体/页面布局流程。条纹夹具还检查了接近物理屏幕底边的采样，防止透明采样暴露未模糊的原图。

- [浅色页面](../Android/screenshots/progressive-blur-light.png)
- [深色页面](../Android/screenshots/progressive-blur-dark.png)
- [渐进模糊采样夹具](../Android/screenshots/progressive-blur-sampling.png)

后续一致性优化中增加模拟器滚动采样与省电回退验证，并将开销偏高的嵌套 AGSL 采样改为系统高斯方案，见[实施记录](android-ios-parity-2026-10-21.md)。尚未做真实低端手机的帧率分析，API 31 的缓存失效与滤镜重建修复及双系统回归见 [beta.8 说明](android-compatibility-beta8.md)，API 26–30 / 32 仍待对应镜像验收。
