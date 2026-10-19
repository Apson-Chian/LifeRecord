# Android 发布签名保管

从 2026-10-19 的 beta.4（build 8）开始，普通版和默认 AI 版固定使用同一证书：

`c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a`

该证书不同于 beta.3 及以前的公测包，因此 beta.3 需要迁移后重装；后续使用此私钥且 versionCode 不降低的版本可覆盖 beta.4。普通版和默认 AI 版共用应用 ID，互相覆盖会切换版本。

## 本机保存

- 主密钥库：`~/.android/liferecord-signing/release.p12`
- 第二份本机备份：`~/Library/Application Support/LifeRecord/Signing Backup/release.p12`
- 格式：PKCS12，别名：`liferecord-release`。
- 密钥库使用随机强密码加密，密码保存在 macOS 登录钥匙串。项目名称为「LifeRecord Android 发布签名」，服务为 `ltd.apsonchian.liferecord.android-signing`，账号为 `release`。
- 两个目录权限为 700，密钥库权限为 600；私钥和密码不写入 Git、公开附件或聊天。保存位置旁有「保存与恢复说明.md」和证书信息。

两份文件仍在同一台 Mac。换机或抹盘前，将加密密钥库复制到离线盘，并通过钥匙串访问查看密码、单独保存到密码管理器；只有密钥库没有密码不能恢复。此说明不包含密码或私钥。

## 后续签名

先构建未签名的 Release APK，再执行：

```sh
python3 Android/scripts/sign-release.py \
  Android/app/build/outputs/apk/release/app-release-unsigned.apk \
  /path/to/LifeRecord-release.apk
```

脚本默认读取上述持久密钥库和登录钥匙串，支持 `--keystore`、`--build-tools`、`JAVA_HOME` 和 `ANDROID_SDK_ROOT`。在其他机器上可交互输入密码，自动化环境可使用安全注入的 `LIFERECORD_SIGNING_PASSWORD`；不要把密码写入命令、源码或日志。

脚本在签名前核对证书 SHA-256、校验 APK 对齐，签名后再次验证签名及证书；缺失密钥或指纹不符会停止。禁止为发布临时生成替代证书，也不要再用自动重建的 `debug.keystore` 签发更新。此次密钥已通过导出公钥、备份字节一致性及实际 APK 签名验证。
