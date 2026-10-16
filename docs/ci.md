# CI/CD 规范与门禁（GitHub Actions 治理 / 供应链安全）

本文是**已生效门禁**的说明，不是提案。每一项都指向仓库里真实存在的文件与
设置，并解释它在这个 H5000M 固件项目里解决什么问题。

一个前提：本项目产出的是**要刷进路由器的固件**和**设备 `apk add` 的软件源**。
威胁模型与普通 Web 项目不同，三条真实风险决定了下面所有取舍：

1. 构建作业持有 `contents: write` 与**签名密钥**，同时下载约 150 个上游
   tarball 和十几个第三方 git 树。被投毒的 action 或上游会继承这一切。
2. 发布出去的 apk 索引是设备信任的根。若它可被替换，所有装包设备都被接管。
3. workflow 自身是攻击面（模板注入、凭据持久化、权限过宽）。

---

## 一、代码规范与提交规约

| 术语 | 落地位置 | 在本项目的作用 |
| --- | --- | --- |
| **Conventional Commits** | `commitlint.config.mjs` | 提交日志在本项目**就是发布日志**：Release Please 由它推导版本号与 changelog，`build.yml` 又用 tag 命名固件。类型写错 → release note 写错。 |
| **Commitlint** | `commitlint.config.mjs` + `checks.yml::commitlint` | CI 门禁（Required Check）。含本项目 **17 个 scope 枚举**（`kmods`/`ebpf`/`fullcone`/`wwan`/`wifi`/`fan`/`accel` 等），scope 自由填写会在一周内漂移、失去可检索性。校验 PR 的**整个提交区间**而非仅 HEAD。 |
| **Release Please** | `.github/workflows/release-please.yml` | 维护 release PR + `CHANGELOG.md`，合并后才打 tag。`release-type: simple`，因为产物不是 npm/pypi 包；tag 与 `build.yml` 的 `v*` 触发对齐。 |
| **pre-commit** | `.pre-commit-config.yaml` | 6 个 hook，**每个都镜像一条已存在的 CI 检查**。规则：CI 不跑的 hook 不加——否则等于训练人绕过 CI。含 `check-added-large-files`（防固件/构建树被提交，本仓库必须保持纯源码）。 |
| **actionlint** | pre-commit hook + 本地 | 校验 GitHub 特有 schema。本轮它抓出了 **3 个真实缺陷**：`workflow_dispatch` 输入超 10 个上限、`uses` 与 `run` 冲突、注释吞掉 `- name:` 导致解析失败——这些 PyYAML 全部看不到。 |
| **zizmor** | `.github/zizmor.yml` + `security.yml::zizmor` | 专门审计 workflow 自身：未钉 action、**模板注入**、凭据持久化、权限过宽、已知 pwn-request。SARIF 上报 code scanning。按版本 pip 安装而非用浮动 action——审计器自身也要守同样的供应链纪律。 |

## 二、质量门禁（Ruleset 已真实生效）

Ruleset `master-protection`，**id `23816928`**，`current_user_can_bypass: never`。

| 规则 | 配置 | 为什么 |
| --- | --- | --- |
| **Required Status Checks** | 5 条，`strict`（要求分支最新） | 见下表。**刻意不含** `Build firmware`：完整固件构建 2–3 小时，不适合每个 PR。 |
| **Required Linear History** | 启用 | 固件按 commit 溯源，线性历史让 `git bisect` 与发布对应关系成立。 |
| **Pull Request** | 必需、必须解决全部 review thread、仅允许 squash/rebase | 保证每个进入 master 的提交都过了门禁。 |
| **Deletion / Non-fast-forward** | 禁止 | 防止误删 master 或强推覆盖历史。 |
| **Required Signatures** | ✅ 已启用 | 签名密钥已注册在 GitHub（实测 master 上的 squash 提交 `verified=true, reason=valid`）。**合并方式收窄为 squash-only**——见下方说明。 |

五个 Required Status Checks 及其归属。**第三列是 job 的 `id`，Ruleset 里要填的
是第二列 job 的 `name:` 字面值**（包括中文与全角括号）——`docs/conventions.md`
把这条写成了硬规则：`required_status_checks.context` 匹配 `name:` 而不是 `id:`。
写错不会报错，只会让那条检查永远停在 `Expected`。

| Ruleset 里的 `context` | 来源（workflow::job id） | 耗时 |
| --- | --- | --- |
| `仓库与主机检查` | `checks.yml::check` | 分钟级 |
| `提交信息规约` | `checks.yml::commitlint` | 分钟级 |
| `配置覆盖测试` | `coverage.yml::coverage` | ~4 分钟 |
| `工作流静态审计（zizmor）` | `security.yml::zizmor` | 分钟级 |
| `依赖审查` | `security.yml::dependency-review` | 分钟级 |

> 本文此前把这五条写成了英文（`Repository and host checks`、`Conventional
> Commits` 等）。那是**文档漂移**：job 的 `name:` 是中文，而 Ruleset 比的是
> `name:`，所以照这份文档去核对 Ruleset 只会得出"配置错了"的结论。判定依据是
> 真实 check run 的名字，不是这份文档：
>
> ```sh
> gh api repos/<owner>/<repo>/commits/master/check-runs \
>   --jq '.check_runs[].name' | sort -u
> ```
>
> 反证也很直接：若 Ruleset 里真的填了英文名，PR 会因为那五条检查永远
> `Expected` 而**永久 blocked**，但 #27–#30 都正常合并了。

> 注意：一个 Ruleset 只能要求 **PR 上真的会跑**的检查。这三个 workflow 原先
> 没有 `pull_request` 触发器，导致 Required Checks 永不可能通过、PR 永久
> `blocked`——这是本轮修掉的真实缺陷（`checks.yml`/`coverage.yml` 已补）。

> `checks.yml::upstream`（`上游集成校验`）**刻意不进** Required Checks，见第五节。

| 术语 | 落地 | 作用 |
| --- | --- | --- |
| **Rulesets** | API 创建，id 23816928 | 比旧 Branch Protection 更强、可导出、可审计，且能设 bypass 名单。 |
| **Merge Queue** | 未启用（单人仓库） | 多人协作时它保证"PR 通过检查"与"合并后 master 仍通过"一致。单维护者场景收益低于复杂度，故暂缓；Ruleset 的 `strict` 已覆盖主要风险。 |
| **CODEOWNERS** | `.github/CODEOWNERS` | 标注**决定"什么被签进固件"的路径**：`/.github/`、`/configs/`、`/patches/`、fullcone 四层补丁、`local-packages/`（设备上以 root 运行的脚本）。 |
| **Concurrency Groups** | 5 个 workflow | 防重复运行互相抢 ghcr.io 缓存 tag 与 Release。`build` 在 **tag 上不取消**（release 必须跑完），其余按 ref 取消旧运行。 |

## 三、供应链安全

| 术语 | 落地 | 在本项目的作用 |
| --- | --- | --- |
| **Least Privilege Permissions** | 顶层 `contents: read`，按 job 放宽 | **本轮价值最高的改动**：`build.yml` 顶层原为 `contents: write`，意味着每个 job、每个第三方 action 都能推 master。现仅 `build` job 可写（发 Release），`publish-apk-repo` 仅 Pages。 |
| **OIDC** | attestation / Scorecard 用 `id-token: write` | 签发证明与发布 Scorecard 结果**无需长期密钥**——没有可泄漏、可轮换的签名 secret。 |
| **Dependency Review** | `security.yml::dependency-review` | PR 引入 high 及以上漏洞依赖即失败。带 **Dependency Graph 前置探测**：未启用时明确告警并跳过，启用后自动生效（刻意不用 `continue-on-error`，否则会连真实漏洞一起吞掉）。 |
| **CodeQL** | `security.yml::codeql` | `actions` + `javascript-typescript` 双语言矩阵，`security-extended`。产物在路由器上以 root 运行，值得更严格的查询集。 |
| **Secret Scanning** | 仓库已启用 | provider patterns + **push protection** 均已开启（实测确认），密钥在推送时就被拦下。 |
| **OpenSSF Scorecard** | `security.yml::scorecard` | 独立第三方视角检查仓库卫生（危险 workflow、未钉 action、分支保护）。仅默认分支运行，结果经 OIDC 发布。 |
| **SLSA / Artifact Attestations** | `build.yml::Attest the firmware and the apk repository` | 为 `*squashfs-sysupgrade.bin` 与 `apk-repo/packages.adb` 签发 **build provenance**，任何人事后可验证"这个索引确实由该 commit 的该次运行产出"。 |
| **SBOM** | `security.yml::attest` | 生成 SPDX SBOM 并随证明一起签发、作为 artifact 保留 90 天。 |
| **Action Pinning** | 全部 workflow | **16 个 action 全部钉到 commit SHA**（tag 仅作注释）。已用 API 逐个核验 SHA 可解析回自身。Dependabot 每周分组升级——**SHA 钉定的可持续性依赖它**，否则会变成会腐烂的快照。 |

## 四、复用与编排

| 术语 | 落地 | 选择理由 |
| --- | --- | --- |
| **Reusable Workflows** | `.github/workflows/reusable-script-test.yml`（`workflow_call`）+ `build.yml::script-test` 调用 | 需要**独立 job/runner/权限边界**的单元。用真实 aarch64 `uci`（qemu）跑首启脚本——本仓库已经因此类 bug 被咬过一次（值存成 `'0'` 而非 `0`：配置看似正确、射频始终不启）。调用方**不传 secrets**（`secrets: inherit` 会无谓扩大暴露面）。 |
| **Composite Actions** | `.github/actions/verify-repo/action.yml` | 只需**步骤序列**、不需要独立 runner 的单元，复用 apk 仓库校验。用 reusable workflow 会为 5 秒的检查白起一个 runner。 |
| **Matrix Strategy** | `security.yml::codeql`（`fail-fast: false`） | 两种语言各自独立分析；`fail-fast: false` 保证一个失败不掩盖另一个。 |

## 五、文件结构

```
.github/
├── CODEOWNERS                       # 敏感路径的复核归属
├── dependabot.yml                   # 每周分组升级 actions（含 SHA 更新）
├── zizmor.yml                       # workflow 审计器配置与例外说明
├── actions/
│   └── verify-repo/action.yml       # Composite Action：apk 仓库校验
└── workflows/
    ├── build.yml                    # 固件构建 + 发布 + 证明（3 job）
    ├── checks.yml                   # 仓库/主机检查 + 上游集成校验 + commitlint
    ├── coverage.yml                 # ENABLE_* 配置覆盖矩阵（Required）
    ├── security.yml                 # zizmor / CodeQL / DepReview / Scorecard / attest
    ├── release-please.yml           # release PR + changelog + tag
    └── reusable-script-test.yml     # Reusable Workflow（workflow_call）
scripts/verify-upstream-integration.sh # 上游漂移门禁（补丁 / 锚点 / 钉住版本）
.pre-commit-config.yaml              # 本地钩子（全部镜像 CI 检查）
commitlint.config.mjs                # Conventional Commits 规则与 scope 枚举
docs/ci.md                            # 本文
```

## 六、上游漂移门禁（`上游集成校验`）

这个仓库里其余所有门禁都是**本仓库自身的性质**；只有这一条是
`openwrt/openwrt` 的性质，而它每天都在动。四层 fullcone 补丁里的三层、以及
Nikki-RS 的三处默认值改写都是**上下文补丁**，所以上游的一个 commit 就能让一个
全绿的仓库变成"计划构建跑到 2–3 小时后才红"。

更坏的一种形态值得单独写下来，因为它正是 `libnftnl` 补丁身上发生过的事：

* 上游 libnftnl 1.3.2 把 `nftnl_expr_set_imm` 加进了
  `include/libnftnl/expr.h`，而本仓库的补丁要加的正是同一行的下一行；
* `patch(1)` 于是看到自己的 `+` 行已在目标文件里，判定
  `Reversed (or previously applied)`，把**整个 hunk 丢掉**——包括同一个 hunk
  里的 `NFTNL_EXPR_FULLCONE_*` 定义；
* 补丁"打上了"，构建继续跑了很久，最后死在 nftables 里：
  `'NFTNL_EXPR_FULLCONE_FLAGS' undeclared`。

`scripts/verify-upstream-integration.sh` 把这类判断变成一条自动断言：它按
mainline **当前真正会构建的版本**取源码（nftables / libnftnl 的官方 tarball，
并用上游 Makefile 的 `PKG_HASH` 校验 tarball 就是那一份；firewall4 / mt76 取
`PKG_SOURCE_VERSION` 的快照），用 `patch -p1 -F0 --dry-run --forward` 逐条试，
再把 Nikki-RS 的四处锚点与 `clash-rs` 钉住版本的五个资产哈希一起核对。

设计约定：

| 约定 | 理由 |
| --- | --- |
| `-F0`（不允许 fuzz） | fuzz 命中意味着补丁**打进去了但落点靠猜**。这一次猜对了不代表文件形状是对的。 |
| 退出码 `1` = 漂移，`2` = 没能验证 | 网络故障与补丁失效必须在日志里长得不一样，否则一次代理抖动会被读成"补丁坏了"。 |
| 先跑 `--self-test` | 一条抓不到缺陷的门禁比没有门禁更坏。自检离线造出三种形态（适用 / 上下文对不上 / 已被上游应用），要求检测器如实区分。 |
| 刻意不做成 Required Check | 它需要网络。Required Check 因抖动变红会拦住本仓库的每个 PR——那是把"少一道人工审批"换成"多一道随机拦截"。它依然是真实门禁：每周计划运行、每个 PR 都会跑，红了就出现在 PR 的检查列表里。 |
| 与 `build.yml` 无 `needs:` 依赖 | `build.yml` 的注释已经写明"检查都在 `checks.yml`，两个 workflow 各自独立"。加依赖会推翻一个已记录的取舍。 |

## 七、Signed Commits（已启用）

`required_signatures` 已生效，签名密钥已注册在 GitHub 上：

```
GitHub id  1194013   H5000M build machine (commit signing)   ssh-ed25519
实测        master 上的 squash 提交 verified=true, reason=valid
```

**但当前这台机器上没有对应的私钥。** 实测（2026-10-16）：`~/.ssh` 里只有
`known_hosts`；`git config` 的 `gpg.format` / `user.signingkey` / `commit.gpgsign`
三项全部未设置，所以从这里产生的提交是**未签名**的（`git log --format='%G?'` 得到 `N`）。

### 未签名的提交不挡 squash 合并（实测，不是推断）

PR #33 的分支提交 `13ed429` 未签名，5 项必需检查全绿后 squash 合并**成功**；合并结果
`829426e` 在 GitHub 上是 `verified=true, reason=valid` —— GitHub 用 web-flow 密钥
重新签了合并结果本身。

所以"这台机器缺私钥"只影响提交上的徽章，**不影响能否合并**。前提正是下面这条：
合并方式必须是 squash。若放开 rebase，PR 里的未签名提交会被原样落到 master。

### 为什么合并方式必须是 squash-only

squash 合并时 GitHub 用 **web-flow 密钥重新签名**合并结果，所以 master 上的
提交天然是 verified 的；而 **rebase 会把 PR 内的提交原样落到 master**——若其中
有未验证的提交（例如别人在网页上编辑产生的），master 就会混入未签名历史。
因此 Ruleset 的 `allowed_merge_methods` 限定为 `["squash"]`。

### 换机器或密钥失效时

```sh
git config gpg.format ssh
git config user.signingkey ~/.ssh/id_ed25519_signing.pub
git config commit.gpgsign true
git config tag.gpgsign true
gh auth refresh -h github.com -s admin:ssh_signing_key
gh ssh-key add ~/.ssh/id_ed25519_signing.pub --type signing --title "H5000M build machine"
```

验证：`git log --format='%h %G?' -1` 应为 `G`；推送到 GitHub 后
`verified` 应为 `true`。

## 八、本地开发

```sh
pipx install pre-commit
pre-commit install --install-hooks
pre-commit install --hook-type commit-msg

./actionlint .github/workflows/*.yml   # GitHub Actions schema 校验
pre-commit run --all-files             # 全部钩子
```

---

## 九、Release PR 的运行批准（已自动化）

把上面这些规则都落实之后，日常 PR 已经不需要任何人点任何按钮：Ruleset 里
`required_approving_review_count` 是 `0`，不需要 review 批准，检查全绿即可 squash 合并。

Release PR 曾是这个结论的唯一例外，因为它的运行不是"人"触发的。Release Please 用
`GITHUB_TOKEN` 推送 `release-please--branches--master`，GitHub 对这类事件创建的
`pull_request` 运行不直接执行，而是停在 `action_required` 等有写权限的人批准——而 5 条
必需检查正是这些运行产生的。实测（2026-10-16，PR #34，head `793d5e87`）：

| 运行 | 状态 |
| --- | --- |
| `仓库与主机检查` | `action_required` |
| `配置覆盖测试` | `action_required` |
| `供应链安全` | `action_required` |

该 head 上因此有 **0 个 check run**，PR 停在 `mergeable_state=blocked`，而 Required
Checks 永远等不到结果。前两个 Release PR（#28 / #30）的 head 上最终都有 11 个
`success`，说明这一步一直被以某种方式补上——但它不写在仓库里，也不会自己发生。

**现在由 `release-please.yml` 里的 `批准发布 PR 上待批准的检查运行` 完成**：它在 Release
Please 推完分支后轮询 `release-please--branches--<默认分支>` 上 `conclusion` 为
`action_required` 的运行，逐个调 `POST /repos/{owner}/{repo}/actions/runs/<id>/approve`。

为什么可以自动化：那次点击批准的是**执行检查**，不是内容。内容决定是合并，而合并仍然由人
决定——发布 PR 上从不开启 auto-merge。

这一步的边界：它只认发布分支上的运行；而且发布 PR 的 diff 只有 `CHANGELOG.md` 一个文件
（实测 1.1.8 的发布提交 `620e12e`，stat 恰好是 `CHANGELOG.md | 7 +++++++`），所以被批准
执行的是 master 自己的工作流，没有被 PR 改动过。

它刻意做成"尽力而为"（`continue-on-error` + `::warning::`）：人工在 Actions 页面点
"Approve and run" 这条路必须保留——`GITHUB_TOKEN` 是否有权批准它自己触发出来的运行
**尚未验证**，而这一步就是那次验证。

### PAT 那条路已经堵死（实测，不是推断）

"让 Release Please 用 PAT 推送"是最直觉的替代方案，但 `release-please.yml` 里已经记录了
它被试过并被迫回退：

| 推送用的 token | 发布提交的 committer | 结果 |
| --- | --- | --- |
| `GITHUB_TOKEN` | `GitHub <noreply@github.com>` | `verified=true` |
| PAT | token 的主人 | `verified=false, reason=unsigned` |

未签名的发布提交会被本仓库的 `required_signatures` 规则拒绝，发布 PR 永远合不了。
release-please-action 自己不能签名（它唯一的签名相关输入就是 `token`），所以"PAT + 已签名
的发布提交"无法兼得。GitHub App token 没有实测过，但它同样不是 web-flow 签名，很可能同样
走不通——如果哪天要试，先用一个一次性 PR 验证提交的 `verification` 字段再决定。

除此之外没有别的路：这是 GitHub 对"机器人用 `GITHUB_TOKEN` 创建 PR"的既定行为，不是本
仓库配置错了。
