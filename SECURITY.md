# 安全策略

## 支持的版本

本仓库产出的是**固件镜像**与**设备端 apk 软件源**，不是可持续打补丁的库。
安全修复只针对**最新发布版**：

| 版本 | 支持 |
| --- | --- |
| [最新 Release](https://github.com/existyay/AutoBuild-H5000M-Openwrt/releases/latest) | ✅ |
| 更早的 Release | ❌（请重新刷入最新固件） |

固件的上游是 `openwrt/openwrt` main 分支（SNAPSHOT）。上游自身的漏洞由其
安全团队处理，本仓库负责的是：**把上游的安全修复及时编译进新固件**，以及
**本仓库自身的供应链安全**（见下）。

## 报告漏洞

**请勿为安全问题开公开 issue。**

- 首选：[GitHub 私密漏洞报告](https://github.com/existyay/AutoBuild-H5000M-Openwrt/security/advisories/new)
- 备用：发邮件至仓库所有者（见 profile），主题以 `[SECURITY]` 开头

请包含：受影响的版本或提交 SHA、复现步骤、影响范围，以及（如可能）修复建议。
我们会在 7 天内确认收到，并在修复发布后致谢（除非你要求匿名）。

### 范围

在范围内：

- 本仓库的构建脚本、补丁与 CI 工作流（`scripts/`、`patches/`、
  `local-packages/`、`.github/`）
- 发布出去的 apk 索引与软件包的**完整性**（签名、来源可验证性）
- 固件默认配置的安全问题（例如默认开放无线网络 —— 这是**有意为之**的
  首次启动体验，用户需自行设置密码，不属于漏洞；见 README）

不在范围内：

- 上游 OpenWrt、各代理面板与内核的漏洞 → 请报告给对应上游
- 需要物理接触设备才能利用的问题
- 默认开放 Wi-Fi 这一已知且有文档记录的行为

## 本仓库的供应链安全措施

| 措施 | 位置 |
| --- | --- |
| 全部 Action 钉定到提交 SHA | `.github/workflows/*.yml` |
| 工具下载校验 SHA256（actionlint / syft） | `checks.yml`、`security.yml` |
| Python 依赖 hash 锁定 | `.github/requirements-zizmor.txt` |
| Node 依赖 integrity 锁定 | `package-lock.json` |
| CI 最小权限（顶层 `contents: read`） | 全部 workflow |
| 发布产物签名 + 构建来源证明（SLSA / OIDC） | `build.yml`、`security.yml` |
| 分支保护：必需检查、线性历史、签名提交 | Ruleset `master-protection` |
| 静态审计（zizmor / CodeQL / Scorecard） | `security.yml` |
| 密钥扫描 + 推送保护 | 仓库设置 |
