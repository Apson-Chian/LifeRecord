# 共享与跨平台回归

以下命令在仓库根目录执行，使用临时数据库或模拟 API。

- `python3 Tests/public-beta.py`：私人数据库迁移、用户和照片隔离、会话到期/退出、跨站请求防护和账号删除。
- `python3 Tests/sync-edit.py`：餐食、训练、照片编号、删除标记、旧客户端字段保留与更新冲突。
- `python3 Tests/admin-api.py`：后台编辑与 AI 操作协议。
- `python3 Tests/web-optimizations.py`：自定义 API 的公网 HTTPS、DNS 与认证头防护、禁止重定向、生成参数和按用户鉴权的 ETag 条件读取；不调用真实计费接口。
- `python3 Tests/android-sync.py`：验证 Kotlin 实际生成的同步 JSON 与后端兼容；先在 `Android/` 运行 `./gradlew :app:testDebugUnitTest`。
- `node Tests/web-smoke.cjs`：需要 Playwright 与 Chrome，检查 Web 编辑、AI 复核、搜索和响应式布局。

Swift 回归已移至 `iOS/Tests/`，运行 `./iOS/Tests/run.sh`；安卓单元与设备测试位于 `Android/app/src/test/`、`Android/app/src/androidTest/`。
