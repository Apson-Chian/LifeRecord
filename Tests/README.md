# 共享与跨平台回归

以下命令在仓库根目录执行，使用临时数据库或模拟 API。

- `python3 Tests/sync-edit.py`：餐食、训练、照片编号、删除标记、旧客户端字段保留与更新冲突。
- `python3 Tests/admin-api.py`：后台编辑与 AI 操作协议。
- `python3 Tests/android-sync.py`：验证 Kotlin 实际生成的同步 JSON 与后端兼容；先在 `Android/` 运行 `./gradlew :app:testDebugUnitTest`。
- `node Tests/web-smoke.cjs`：需要 Playwright 与 Chrome，检查 Web 编辑、AI 复核、搜索和响应式布局。

Swift 回归已移至 `iOS/Tests/`，运行 `./iOS/Tests/run.sh`；安卓单元与设备测试位于 `Android/app/src/test/`、`Android/app/src/androidTest/`。
