# 编写规范（语言、命名、风格）

本文件是**可执行的约定**，不是建议。CI 门禁会检查其中可自动化的部分。

## 一、语言约定：中文标签 + 英文标识符

本项目面向中文使用者（README、docs、提交信息均为中文），但 CI 的**标识符**
参与机器匹配。两条线必须分清：

| 类别 | 语言 | 例子 | 理由 |
| --- | --- | --- | --- |
| **人类可读标签** | **中文** | workflow `name:`、job `name:`、step `name:`、`run-name:` | 出现在 Actions 列表、PR 检查面板、徽章——维护者读的是中文 |
| **机器标识符** | **英文** | job `id:`、step `id:`、input 名、`env` 变量名、文件名、分支/tag | 被 `needs:`、`steps.<id>.outputs`、Ruleset 的 Required Checks、脚本引用 |

**为什么这样切**：混用会让同一处出现两种语言（本项目此前的实际状态：
workflow 名是中文、job 与 step 名是英文），阅读时必须来回切换。
约定按"谁读它"划分，而不是按"文件是哪种语言"划分。

### 关键耦合：改 job 名必须同步 Ruleset

`required_status_checks` 的 `context` 匹配的是 **job 的 `name:`**，不是 `id:`。
所以重命名 job 时：

1. 先在 PR 分支改 workflow —— 该分支跑出新名字的检查；
2. 再用 API 把 Ruleset 的 context 改成新名字；
3. 此时 PR 上**已存在**的新名字检查立即满足规则，自动合并。

若顺序反了（先改 Ruleset）会造成死锁：规则要求一个还不存在的检查。
**无保护窗口为零**——Ruleset 始终至少要求一组真实存在的检查。

## 二、命名规范

| 对象 | 规范 | 示例 |
| --- | --- | --- |
| workflow 文件 | `kebab-case.yml`，一名一职 | `security.yml`、`reusable-script-test.yml` |
| job `id` | 英文 `kebab-case`，语义化 | `build`、`publish-apk-repo`、`dependency-review` |
| job `name` | 中文，简洁说明**做什么** | `构建固件`、`依赖审查` |
| step `id` | 英文，仅在被引用时需要 | `upstream`、`buildcache` |
| step `name` | 中文，动词开头 | `恢复工具链缓存`、`校验发布仓库` |
| input / env | 英文 `SCREAMING_SNAKE_CASE` | `ENABLE_WWAN`、`BUILD_DIR` |
| Reusable workflow | 前缀 `reusable-` | `reusable-script-test.yml` |
| Composite action | 动词短语目录 | `.github/actions/verify-repo/` |

## 三、Shell 风格

- **缩进制表符**，`case` 分支保持缩进（`.editorconfig` + shfmt 默认值）
- `set -euo pipefail`（构建脚本可放宽 `-e`，须在注释说明）
- 变量一律加引号：`"${var}"`
- 断言而非假设：`rm -rf "${DIR:?}/${name:?}"`（SC2115）
- 错误信息写**为什么坏、怎么修**，不只写"失败"
- 中文注释，但命令与参数保持原样

## 四、注释规范

注释解释**为什么**，不解释**是什么**（代码已说明是什么）。有价值的注释：

- 记录一个**实测结果**（"实测：x 为 y 时 z"）
- 说明一个**反直觉的决定**及其代价
- 标注**上游行为**的出处（文件:行号、issue 链接）

反面例子：`# 设置变量`、`# 循环遍历`。

凡引入**门禁或阈值**，注释必须写明：它防的是什么故障、该故障曾如何发生。

## 五、CI 安全规范（与供应链规约一致）

- Action **一律钉 40 位 SHA**，tag 只作注释
- 顶层 `permissions: contents: read`，按 job 放宽
- **外部输入一律经 `env:` 传入**，绝不插值进 `run:`
  （`${{ }}` 在 bash 解析前做文本替换 = 命令注入）
- 工具下载**校验 SHA256**；Python 用 `--require-hashes`；Node 用 `npm ci` + lockfile
- 缓存写操作**仅限受信 ref**（`actions/cache/restore` + `save` 分离）
- **禁止提交二进制**（Scorecard Binary-Artifacts）——工具由 CI 拉取

## 六、提交规范

Conventional Commits，scope 见 `commitlint.config.mjs`。类型与 scope 用英文，
描述可用中文：

```
fix(kmods): kmod-tun 未进镜像导致 TUN 模式无法启用

设备实测：`apk add luci-app-homeproxy` 报
  To enable Tun support, you need to install ip-full and kmod-tun.
kmod 只能来自同内核构建的仓库，故改为 =y 进镜像。
```
