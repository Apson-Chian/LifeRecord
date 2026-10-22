# Android 液态玻璃重做

2026-10-22，随 Android 1.4.0-beta.11 提供。以现有 iOS 的轻盈、分层和文字清晰为参照，统一首页卡片、设置分组、浮动导航、教练输入区、快捷操作、底部表单和确认弹窗。

## 四项材质变化

- 透明：去掉卡片的厚白底和紫色整圈描边；导航透过更多页面内容，数据卡片和编辑表单保留更高底色。深色使用独立透明度，省电、低内存设备和 Android 8–11 使用接近不透明的清晰回退。
- 折射：Android 13+ 使用 AGSL 对圆角边缘的实际背景像素做位移，中心保持稳定；Android 12 使用同一张原生模糊纹理的四层圆角镜片带，近似边缘放大。不是只叠加渐变模拟折射。
- 高光：统一左上光源；柔和面光位于文字下面，细内缘在最上层，右下有轻微明暗过渡。选中导航和按钮沿用同一照明方向。
- 阴影：宽而轻的环境阴影配合短接触阴影；导航和弹层比普通卡片更浮起，小按钮更贴近页面。

## 采样与兼容

`LiquidMaterial.kt` 管理材质层级，`LiquidOptics.kt` 管理背景采样和镜片折射。页面只捕获背景与内容，不包含浮动导航和弹窗。数据卡片、教练输入栏及页面内按钮只采样环境背景；浮动导航和弹窗采样完整页面。两条单向采样关系避免自我反射、递归模糊和文字发糊。

折射输入使用半分辨率 GraphicsLayer，外围预留模糊与位移区域，避免边缘出现空块。现有上下缘渐进模糊继续使用四分之一分辨率的多带原生模糊。没有引入第三方渲染库、CPU 截图回读或常驻逐帧定时器；不能由这些实现选择推断真机帧率或温升。

Android 12 没有 RuntimeShader，使用原生 RenderEffect 加镜片带。Android 13+ 编译失败时也回退到镜片带。Android 8–11、不支持模糊的设备、省电和低内存策略下保留高光、阴影与可读底色，不运行背景滤镜。API 26–30 / 32 与具体 OEM GPU 未逐一设备验收。[官方 AGSL 示例](https://developer.android.com/develop/ui/views/graphics/agsl/using-agsl) · [官方 RenderEffect API](https://developer.android.com/reference/android/graphics/RenderEffect)

不同窗口使用屏幕坐标对齐。在测试中发现：Android 15 的确认弹窗可能继续显示首次捕获的背景，单独请求重绘不足以更新输入。现在页面记录后会合并请求弹窗重绘，并刷新跨窗口原生滤镜输入绑定；复用已编译 shader，不在每次绘制时重新编译。Android 12 同样刷新原生输入，源和目标在实际状态变化后失效；节点销毁时注销观察者和回调。

底部弹层的玻璃位于 Material3 实际移动的内容层内。完整回归曾发现外层裁剪与半展开位移冲突，画面被裁掉后点击会落到遮罩；已修正层级，训练日历测试增加实际可见性断言，随后验证记录卡片可以打开原训练编辑页。拖动柄保留展开、收起和关闭的无障碍操作。

## 回归与界面

新增四项设备回归：实际条纹像素在边缘位移且中心稳定；深浅色透射背景变化、反复进入无旧色块且前景细线清晰；关闭模糊时底色不采样背景且接触阴影存在；跨窗口弹窗更新背景且确认按钮仍可用。Android 15 还显式断言 AGSL 成功编译，避免把静默降级当作着色器通过。

完整设备检查、截图与发行校验见[本版发布说明](android-release-1.4-beta11.md)。截图使用合成记录，包含浅深色首页、教练、编辑表单、大字体与省电回退。真我 Android 12、vivo Android 15 的实际 GPU 差异仍需用户设备验证。

| 实际界面 | Android 12 / API 31 | Android 15 / API 35 |
| --- | --- | --- |
| 浅色首页 | [截图](../Android/screenshots/liquid-glass-api31/home-light.png) | [截图](../Android/screenshots/liquid-glass-api35/home-light.png) |
| 深色首页 | [截图](../Android/screenshots/liquid-glass-api31/home-dark.png) | [截图](../Android/screenshots/liquid-glass-api35/home-dark.png) |
| 教练输入区 | [截图](../Android/screenshots/liquid-glass-api31/coach-conversation.png) | [截图](../Android/screenshots/liquid-glass-api35/coach-conversation.png) |
| 深色大字体 | [截图](../Android/screenshots/liquid-glass-api31/coach-large-text-dark.png) | [截图](../Android/screenshots/liquid-glass-api35/coach-large-text-dark.png) |
| 编辑表单 | [截图](../Android/screenshots/liquid-glass-api31/record-sheet.png) | [截图](../Android/screenshots/liquid-glass-api35/record-sheet.png) |
| 省电回退 | [截图](../Android/screenshots/liquid-glass-api31/home-power-save.png) | [截图](../Android/screenshots/liquid-glass-api35/home-power-save.png) |
