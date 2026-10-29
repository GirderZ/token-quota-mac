# 给安装 Agent 的中文指南

目标：在用户授权的 Mac 上安装 Token额度，不替用户登录账号。

## 安装前

1. 阅读仓库 README 与 `install.sh`，确认来源为 `GirderDog/token-quota-mac`。
2. 检查 macOS ≥13、Apple 芯片；其他系统不要尝试运行 arm64 安装包。
3. 确认用户希望安装。默认目录为 `~/Applications/Token额度.app`，无需管理员权限。
4. 检查是否有可用 Codex CLI 或桌面应用；如果未登录，由用户在官方应用中完成登录，不读取或索取令牌。

## 执行

```bash
curl -fL https://raw.githubusercontent.com/GirderDog/token-quota-mac/main/install.sh -o /tmp/token-quota-install.sh
# 查看脚本后再执行
bash /tmp/token-quota-install.sh
```

安装脚本会读取最新 Release、下载 arm64 ZIP 与 SHA256SUMS.txt，核对哈希、Bundle ID、版本及签名完整性，随后安装。首次打开可能出现 macOS 确认，交给用户完成；不要关闭 Gatekeeper、清除隔离属性或修改账号安全设置。

仅安装而不启动时使用 `--no-open`。自定义位置使用 `--destination /绝对路径/Token额度.app`。

## 升级

相同版本直接复用。不同版本先退出程序，再执行 `bash /tmp/token-quota-install.sh --replace`。目标若不是本应用，脚本会拒绝覆盖。不要删除系统偏好设置；已有设置会继续使用。

## 验证和报告

- 从目标 Info.plist 读取 CFBundleShortVersionString。
- 可运行 `目标路径/Contents/MacOS/CodexBadge --self-test`，不连接账号。
- 用户授权启动后确认菜单栏或悬浮胶囊出现。首次同步可能需要等待。
- 最后报告实际版本、安装位置、是否已启动，以及是否仍需用户处理系统确认或登录。
- 下载、校验或启动失败时说明具体原因，不把“已下载”说成“安装运行成功”。
