#!/usr/bin/env bash
#
# check-workflow-contracts.sh — 校验复用工作流的调用契约。
#
# 为什么需要这个脚本：有一种 CI 故障是**完全静默**的。当 build.yml 以
# `uses: ./.github/workflows/x.yml` 调用另一个工作流时，若被调用方声明的
# 权限**超出**调用方已授予的权限，GitHub 会在**启动期**直接拒绝整个工作流：
#
#     构建 H5000M 主线 OpenWrt 固件   completed/startup_failure
#
# 没有 job、没有步骤、没有错误文本，Actions 页面只有一句结论。这个仓库因此
# 在 PR #1 之后的一段时间里**固件构建完全无法启动**，而 build.yml 只在
# schedule / tag / dispatch 时运行，所以任何 PR 门禁都不会暴露它——是靠人工
# 逐个二分才定位到的。
#
# 同类问题还有：调用方 `with:` 传了被调用方未声明的输入；被调用方文件不存在；
# 表达式里对含连字符的标识符用点号访问（`inputs.artifact-name` 会被解析成
# `inputs.artifact - name`，同样是启动期失败）。
#
# 这个脚本把上述契约变成可自动检查的断言，本地与 CI 都能跑。
#
# Usage: scripts/check-workflow-contracts.sh [仓库根目录]
#
set -Eeuo pipefail

ROOT_DIR="$(cd "${1:-"$(dirname "${BASH_SOURCE[0]}")/.."}" && pwd)"
cd "$ROOT_DIR"

command -v python3 >/dev/null 2>&1 || {
	echo "需要 python3" >&2
	exit 2
}

# 交给 python 的 bash 必须是**真正在跑这个脚本的那一个**。Windows 上 `bash`
# 这个名字会先被 System32 的 WSL 启动器抢到：它退出码 1，把 UTF-16 的
# "没有已安装的分发版" 写到 stdout，stderr 是空的 —— 于是每个 run 块看起来都
# "语法错误"，而真正的问题是被换了个 shell 去解析。cygpath 把 MSYS 路径转成
# Windows 路径，Windows 的 python 才 spawn 得动同一个 bash。
if command -v cygpath >/dev/null 2>&1; then
	H5000M_BASH="$(cygpath -w "$(command -v bash)")"
else
	H5000M_BASH="$(command -v bash)"
fi
export H5000M_BASH

python3 - "$ROOT_DIR" <<'PY'
import os
import pathlib
import re
import shutil
import subprocess
import sys

import yaml

bash_bin = os.environ.get("H5000M_BASH") or "bash"

root = pathlib.Path(sys.argv[1])
wf_dir = root / ".github" / "workflows"
act_dir = root / ".github" / "actions"

problems: list[str] = []
checked_calls = 0
# 权限子集没法静态判断的次数（例如调用方没写 permissions、显式减过权）。
# 计数的目的是让「没核对」在输出里露头，而不是静默地算通过。
perm_unchecked = 0


def rel(p: pathlib.Path) -> str:
    """报告里的路径一律用正斜杠。

    `Path.relative_to()` 在 Windows 上给反斜杠，于是同一条报错在本地和 CI 里
    长得不一样 —— 而照着报错去改文件的人只需要一种写法。
    """
    return p.relative_to(root).as_posix()


def load(path: pathlib.Path):
    """YAML 1.1 会把裸 `on:` 解析成布尔 True，因此要转回字符串键。"""
    # encoding 必须显式给 UTF-8：这些文件里有中文注释，而 pathlib.read_text()
    # 默认用系统区域编码。在 Linux CI（UTF-8 locale）上一直没问题，在 Windows
    # 上直接 `UnicodeDecodeError: 'gbk' codec can't decode`，本地就跑不了这个门禁。
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return {}
    if True in data and "on" not in data:
        data["on"] = data.pop(True)
    return data


def as_set(mapping) -> set:
    return set((mapping or {}).keys())


def perm_map(value):
    """权限声明的三种形态必须区分开，否则子集判断会静默失效。

    * 没写（None）—— 继承上一级；
    * 写成 map —— 精确集合。**空 map 是「什么都不给」，不是「没写」**；
    * `read-all` / `write-all` 简写 —— 只能按语义近似比较。

    以前这里写的是 `as_set(x) or 上一级`：`permissions: {}` 是空集、假值，于是
    回退到工作流级，子集永远成立 —— 门禁在最该响的那一条上聋了（而这条规则
    失效的表现就是整个工作流 startup_failure，没有 job、没有日志）。字符串
    简写更坑：`set("read-all")` 是 `{'r','e','a','d','-'}`。
    """
    if value is None:
        return None
    if isinstance(value, dict):
        return {str(k): str(v) for k, v in value.items()}
    if isinstance(value, str):
        shorthand = value.strip().lower()
        if shorthand in ("read-all", "write-all"):
            return shorthand
    return "unknown"


def missing_permissions(granted, wanted):
    """返回 `wanted` 里 `granted` 没给的权限名；`None` = 静态判断不了。

    判不了的情况一律记成 unchecked 并打进摘要，而不是默认通过：这条规则的
    代价是整条流水线起不来，宁可在输出里留一行「未能核对」。
    """
    if wanted is None or granted is None:
        return None
    if "unknown" in (granted, wanted):
        return None
    if granted == "write-all":
        return set()
    if wanted == "write-all":
        return None
    if granted == "read-all":
        if wanted == "read-all":
            return set()
        return {k for k, v in wanted.items() if str(v).lower() != "read"}
    if wanted == "read-all":
        reads_only = all(str(v).lower() == "read" for v in granted.values())
        return set() if reads_only else None
    return {k for k in wanted if k not in granted}


# ---------------------------------------------------------------------------
# 1) 表达式里对含连字符的标识符用点号访问
# ---------------------------------------------------------------------------
# `${{ inputs.artifact-name }}` 被解析为减法，表达式编译失败。被复用工作流
# 引用时，故障上抛为调用方的 startup_failure。
DOTTED_HYPHEN = re.compile(
    r"\$\{\{[^}]*\b(inputs|steps|needs|jobs|secrets|matrix|env)"
    r"\.[A-Za-z0-9_]+-[A-Za-z0-9_]"
)

for path in sorted(list(wf_dir.glob("*.yml")) + list(act_dir.rglob("action.yml"))):
    text = path.read_text(encoding="utf-8")
    for i, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        if DOTTED_HYPHEN.search(line):
            problems.append(
                f"{rel(path)}:{i}: 表达式里对含连字符的标识符用了点号访问；"
                f"`-` 会被当作减法，导致启动期失败。请改用 snake_case 标识符或方括号写法。"
            )

# ---------------------------------------------------------------------------
# 2) 复用工作流调用契约
# ---------------------------------------------------------------------------
for path in sorted(wf_dir.glob("*.yml")):
    data = load(path)
    jobs = data.get("jobs") or {}
    caller_top = perm_map(data.get("permissions"))

    for job_id, job in jobs.items():
        if not isinstance(job, dict):
            continue
        uses = job.get("uses")
        if not isinstance(uses, str) or not uses.startswith("./"):
            continue
        checked_calls += 1

        target = (root / uses).resolve()  # 相对仓库根；直接 join，lstrip("./") 会吃掉 .github 的点
        if not target.exists():
            problems.append(
                f"{rel(path)}: job {job_id} 引用了不存在的 {uses}"
            )
            continue

        callee = load(target)
        wc = (callee.get("on") or {}).get("workflow_call")
        if wc is None:
            problems.append(
                f"{rel(path)}: job {job_id} 调用了 {uses}，"
                f"但它没有声明 on.workflow_call"
            )
            continue

        # 2a) with: 的键必须是被调用方声明的输入
        declared = as_set(wc.get("inputs"))
        for key in as_set(job.get("with")):
            if key not in declared:
                problems.append(
                    f"{rel(path)}: job {job_id} 传给 {uses} 的输入 "
                    f"`{key}` 未在被调用方声明（已声明：{sorted(declared)}）"
                )
        # 必填输入必须传
        for key, spec in (wc.get("inputs") or {}).items():
            if isinstance(spec, dict) and spec.get("required") and key not in as_set(job.get("with")):
                problems.append(
                    f"{rel(path)}: job {job_id} 未传必填输入 `{key}` 给 {uses}"
                )

        # 2b) 权限子集：被调用方 job 申请的权限必须是调用方已授予的子集。
        #     这就是让 build.yml 完全无法启动的那条规则。
        job_perm = perm_map(job.get("permissions"))
        caller_granted = job_perm if job_perm is not None else caller_top
        for cj_id, cj in (callee.get("jobs") or {}).items():
            if not isinstance(cj, dict):
                continue
            callee_wants = perm_map(cj.get("permissions"))
            if callee_wants is None:
                callee_wants = perm_map(callee.get("permissions"))
            missing = missing_permissions(caller_granted, callee_wants)
            if missing is None:
                perm_unchecked += 1
                continue
            if missing:
                problems.append(
                    f"{rel(path)}: job {job_id} 调用 {uses}，"
                    f"而被调用方 job {cj_id} 申请了调用方未授予的权限 "
                    f"{sorted(missing)}（调用方授予 {caller_granted}）——"
                    f"GitHub 会在启动期拒绝整个工作流（startup_failure）"
                )

# ---------------------------------------------------------------------------
# 3) `gh` 调用必须能在没有 checkout 的 job 里定位仓库
# ---------------------------------------------------------------------------
# `gh` 从**当前目录的 git remote** 推断仓库。一个没有 `actions/checkout` 的
# job（典型：release-please 这种纯 API 的容器 action）里，工作区之上根本不存在
# `.git`，于是每个 `gh` 调用都死于：
#
#     failed to run git: fatal: not a git repository ...
#
# 这个故障在 v1.1.3 上真实发生：`gh workflow run` 已经派发成功（派发不需要本地
# 仓库），紧接着用于**确认**派发的 `gh run list` 挂掉，整个 job 失败，tag 因此
# 一个固件产物都没有。派发成功 + 校验崩溃 = 最坏的组合，因为它看起来像失败，
# 而队列里其实躺着一个没人确认的构建。
#
# 检查规则：任何执行 `gh <子命令>` 的步骤，若同一 job 中此前没有 checkout，
# 就必须通过 `GH_REPO` 显式给出仓库（步骤 / job / 工作流级 env 均可）。
GH_SUBCMD = re.compile(
    r"(?:^|[^\w-])gh\s+(?:api|run|release|workflow|pr|repo|auth|issue|label|"
    r"secret|variable|cache|gist|attestation|ruleset|search|status)\b"
)


def gh_invocations(run: str):
    """返回真正**执行** gh 的行。

    纯文本匹配会把诊断用的人话也算进来：diagnose action 里对用户打印的
    ``echo "复现：\\`gh run view ...\\`"`` 并不执行 gh。因此对 echo/printf/cat
    这类纯打印语句，只有在 gh 位于**命令替换**（未转义的 ``$(`` 或反引号）之后时
    才算调用——这样 `echo "$(gh run list)"` 仍会被抓到，而转义反引号里的示例文本
    不会。`gh` 出现在 `if gh ...`、`files=$(gh ...)` 等真实命令位置时照常匹配。
    """
    out = []
    for raw in run.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        candidate = line
        if line.split(None, 1)[0] in ("echo", "printf", "cat"):
            m = re.search(r"\$\(|(?<!\\)`", line)
            if m is None:
                continue
            candidate = line[m.start():]
        if GH_SUBCMD.search(candidate):
            out.append(line)
    return out


for path in sorted(list(wf_dir.glob("*.yml")) + list(act_dir.rglob("action.yml"))):
    data = load(path)
    wf_env = as_set(data.get("env"))
    # 复合 action 没有 job 概念，视为单个 job
    if "runs" in data:
        jobs_iter = [(None, data.get("runs") or {})]
    else:
        jobs_iter = [
            (jid, j) for jid, j in (data.get("jobs") or {}).items() if isinstance(j, dict)
        ]

    for job_id, job in jobs_iter:
        job_env = as_set(job.get("env"))
        has_checkout = False
        for step in job.get("steps") or []:
            if not isinstance(step, dict):
                continue
            # checkout（含本地 path 形式）会让 `.git` 出现在工作区
            uses = step.get("uses")
            if isinstance(uses, str) and uses.startswith("actions/checkout@"):
                has_checkout = True
                continue

            run = step.get("run")
            if not isinstance(run, str):
                continue
            hits = gh_invocations(run)
            if not hits:
                continue
            if has_checkout:
                continue
            step_env = as_set(step.get("env"))
            if "GH_REPO" in (step_env | job_env | wf_env):
                continue
            where = f"job {job_id} " if job_id else ""
            problems.append(
                f"{rel(path)}: {where}步骤 `{step.get('name', '<未命名>')}` "
                f"调用了 gh（{hits[0].strip()[:60]}…），但该 job 中没有 actions/checkout，"
                f"也未设置 GH_REPO。gh 依赖当前目录的 git remote 推断仓库，"
                f"会直接失败（v1.1.3 因此没有产出固件）。"
                f"请加 `GH_REPO: ${{{{ github.repository }}}}`。"
            )


# ---------------------------------------------------------------------------
# 4) `runs-on` 不得使用浮动的 `*-latest` 标签
# ---------------------------------------------------------------------------
# `ubuntu-latest` 不是版本，而是一个**会移动**的指针：GitHub 用它来回切换
# 默认镜像。于是同一个 commit 在不同日子会跑在不同的发行版上——对一个发布
# 固件 / 写 apk 仓库的 job 来说，这是没有 commit 可审的运行环境变更。
#
# 这个仓库因此真实吃到过告警：`publish-apk-repo` 是全仓唯一用 `ubuntu-latest`
# 的 job，run 36282274537 上 GitHub 给它挂了一条注释
#
#     The ubuntu-latest label will migrate to Ubuntu 26 beginning October 19,
#     2026.
#
# 其余 9 个 job 早已钉住 `ubuntu-24.04`，只有这一个漏了。检查规则：`runs-on`
# 里的每个标签都不得以 `-latest` 结尾。矩阵 / 表达式的值不在此处判断（它们
# 由输入决定），只查字面量与列表字面量。
def runner_labels(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for v in value:
            if isinstance(v, str):
                yield v


for path in sorted(wf_dir.glob("*.yml")):
    data = load(path)
    for job_id, job in (data.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        for label in runner_labels(job.get("runs-on")):
            if label.endswith("-latest"):
                problems.append(
                    f"{rel(path)}: job {job_id} 的 runs-on 用了浮动标签 "
                    f"`{label}`。它指向的镜像会随时移动，同一个 commit 会在不同日子"
                    f"跑在不同发行版上（run 36282274537 实测：GitHub 对 "
                    f"ubuntu-latest 挂了 Ubuntu 26 迁移告警）。请钉住具体版本，"
                    f"例如 `ubuntu-24.04`。"
                )


# ---------------------------------------------------------------------------
# 5) `run:` 块里不得出现 `${{ ... }}`
# ---------------------------------------------------------------------------
# 两条互相独立的理由，都在 2026-11-01 的 PR #63 上真实触发过：
#
#   * 正确性：runner 在执行前会把 run 标量里的表达式整个替换掉。写进 run 块的
#     字面量（例如用来做文本变异的模式串）已经不是原来的文本 —— 本仓库新加的
#     缓存门禁自检因此"什么都没改"，只在 CI 暴露，本地抽取脚本跑永远复现不了。
#   * 安全：zizmor 的 template-injection 审计会报 info 级 findings，门禁以
#     exit 11 失败（"steps.upstream.outputs.rev may expand into
#     attacker-controllable code"）。
#
# 正确写法是把值经 `env:` 传入，脚本里用 `$VAR` 读。
GITHUB_EXPR = "$" + "{{"


def walk_runs(node, trail):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "run" and isinstance(value, str) and GITHUB_EXPR in value:
                yield trail, value
            else:
                yield from walk_runs(value, trail + [str(key)])
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_runs(value, trail + [str(index)])


for path in sorted(list(wf_dir.glob("*.yml")) + list(act_dir.rglob("action.yml"))):
    for trail, body in walk_runs(load(path), []):
        first = next(l.strip() for l in body.splitlines() if GITHUB_EXPR in l)
        problems.append(
            f"{rel(path)}: {'/'.join(trail) or 'run'} 的 run 块里出现了表达式 "
            f"`{first[:70]}`。runner 会先替换再交给 shell：字面量被改掉，且 zizmor 会报 "
            f"template-injection。请改用 `env:` 传值。"
        )


# ---------------------------------------------------------------------------
# 6) 构建缓存必须在 make 产出之后保存
# ---------------------------------------------------------------------------
# 2026-11-01 的性能审阅发现三个 Save 步骤全在 Build 前面：冷缓存保存空目录，
# fallback 命中时则只是把旧内容换一个 key 再存一次。本轮新编的 toolchain、下载
# 和 ccache 一个字节都进不了下轮。这不是小优化，而是让整套缓存从未真正闭环。
build_wf = load(wf_dir / "build.yml")
build_steps = ((build_wf.get("jobs") or {}).get("build") or {}).get("steps") or []
step_pos: dict[str, int] = {}
for i, step in enumerate(build_steps):
    if isinstance(step, dict) and isinstance(step.get("name"), str):
        step_pos[step["name"]] = i

required_order = [
    ("Restore toolchain", "Build"),
    ("Restore download cache", "Build"),
    ("Restore ccache", "Build"),
    ("Build", "Save download cache"),
    ("Build", "Save ccache"),
    ("Build", "Pack the toolchain for the cache"),
    ("Pack the toolchain for the cache", "Save toolchain"),
]
for before, after in required_order:
    if before not in step_pos or after not in step_pos:
        problems.append(
            f".github/workflows/build.yml: 缺少缓存时序步骤 `{before}` 或 `{after}`"
        )
    elif step_pos[before] >= step_pos[after]:
        problems.append(
            f".github/workflows/build.yml: `{before}` 必须在 `{after}` 之前；"
            "否则会恢复得太晚或在 make 产出缓存前保存空/旧内容"
        )

# Actions cache is immutable.  The download key must change as upstream moves,
# while restore-keys retains incremental reuse of the prior download set.
dl_restore = next(
    (s for s in build_steps if isinstance(s, dict) and s.get("name") == "Restore download cache"),
    {},
)
dl_key = str(((dl_restore.get("with") or {}).get("key") or ""))
dl_fallback = str(((dl_restore.get("with") or {}).get("restore-keys") or ""))
if "steps.upstream.outputs.rev" not in dl_key:
    problems.append(
        ".github/workflows/build.yml: download cache 的精确 key 必须含 upstream rev；"
        "永久 key 是不可变的，后续新增 tarball 永远写不回（2026-11-01 实测该仓库"
        "一条缓存都没写成，每轮重下约 3 GB）"
    )
if "h5000m-dl-" not in dl_fallback:
    problems.append(
        ".github/workflows/build.yml: download cache 必须保留 h5000m-dl- fallback，"
        "否则每个上游 revision 都会重新下载全部源码"
    )

# ---------------------------------------------------------------------------
# run 块的 shell 语法。
#
# 2026-11-23 的 PR #77 上，checks.yml 里少写了一个引号：
#
#     code="$(curl … "https://api.github.com/repos/${repo}") || {
#
# 外层引号没有闭合，bash 于是把紧随其后的几行注释也当成字符串的一部分，直到下
# 一个 `"` 才结束，最后 `(curl failed)` 落在命令位置 —— CI 报的是
#
#     line 49: syntax error near unexpected token `('
#
# 而 actionlint（只做 YAML 与表达式）与 shellcheck（只检查已提取出来的脚本）
# 都看不见它，于是这个引号一路走到了 master 方向的 CI。这里对每个 bash 的 run
# 块跑一次 `bash -n`，把这一类错误挡在本地。
#
# 只检查 bash：`shell:` 明确写成 pwsh/python 的块用 bash -n 解析没有意义。
shell_checked = 0
shell_bad = 0
scratch = root / ".workflow-shell-scratch"
if scratch.exists():
    import shutil

    shutil.rmtree(scratch)
scratch.mkdir()

# 每个单元是「一份文档 + 它的 step 列表」：工作流的每个 job 各算一份，复合
# action 的 `runs.steps` 也算一份 —— 复合 action 的 run 块同样是 bash（`diagnose`
# 那一百多行取证逻辑就在其中），而此前它一个都没被 `bash -n` 看过。
shell_units = []
for wf in sorted((root / ".github/workflows").glob("*.yml")):
    wf_doc = load(wf) or {}
    for job_name, job in (wf_doc.get("jobs") or {}).items():
        shell_units.append((wf, list((job or {}).get("steps") or [])))
for act in sorted(act_dir.rglob("action.yml")):
    act_doc = load(act) or {}
    shell_units.append((act, list((act_doc.get("runs") or {}).get("steps") or [])))

try:
    for doc, steps in shell_units:
        for idx, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            body = step.get("run")
            if not isinstance(body, str) or not body.strip():
                continue
            if not str(step.get("shell") or "bash").startswith("bash"):
                continue
            shell_checked += 1
            # 写进仓库内的相对路径再交给 bash：Windows 的 python 给出的
            # `C:\Users\…\Temp\x.sh` 到 MSYS 的 bash 手里会把反斜杠当成
            # 转义吃掉，变成不存在的路径，于是每个块都“语法错误”。
            rel = scratch.name + "/" + f"block{shell_checked}.sh"
            (root / rel).write_text(body, encoding="utf-8", newline="\n")
            result = subprocess.run(
                [bash_bin, "-n", rel],
                cwd=str(root),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if result.returncode != 0:
                shell_bad += 1
                lines = (result.stderr or "").strip().splitlines()
                reason = lines[0] if lines else f"bash -n 返回 {result.returncode}"
                step_name = str(step.get("name") or f"step #{idx + 1}")
                problems.append(
                    f"{rel(doc)}: 步骤 `{step_name}` 的 run 块不是合法的"
                    f"shell —— {reason}"
                )
finally:
    import shutil as _shutil

    _shutil.rmtree(scratch, ignore_errors=True)

# ---------------------------------------------------------------------------
# 7) 同一个旋钮在所有步骤里必须看到同一个值
# ---------------------------------------------------------------------------
# 2026-11-25 的构建报告给出了自相矛盾的数字：
#
#     Cache size (GiB): 1.9 / 5.0 (37.25%)
#     Cleanups: 9629
#
# 5.0 GiB 是 ccache 的内建默认天花板 —— `CCACHE_MAXSIZE: 2G` 只写在 Build 步骤
# 自己的 env 里，`Report ccache effectiveness` 完全看不到它。真实状态是
# 1.9 / 2.0：缓存已经顶在天花板上、淘汰过 9629 次，这才是 22.7% 命中率的来源。
# 一份测量别人配置的报告，比没有报告更糟：它让一个已经饱和的缓存显示成“还有
# 38% 空间”，而且这个错误会被当成“ccache 就是这么慢”长期接受下来。
#
# 检查规则：跨步骤共享的旋钮必须写在 job 或 workflow 级 env；步骤级只允许
# 出现与上层相同的值，不允许另立一套。
SHARED_KNOBS = ["CCACHE_MAXSIZE", "CCACHE_COMPRESS"]
build_job = (build_wf.get("jobs") or {}).get("build") or {}
knob_checked = 0


def upper_env(doc, job, knob):
    """(值, 位置) —— 上层 env 里这个旋钮的值，没有就是 (None, None)。"""
    for scope, mapping in (("job", job.get("env")), ("workflow", doc.get("env"))):
        if isinstance(mapping, dict) and knob in mapping:
            return str(mapping[knob]).strip(), scope
    return None, None


for knob in SHARED_KNOBS:
    knob_checked += 1
    top_value, top_scope = upper_env(build_wf, build_job, knob)
    if top_value is None:
        problems.append(
            f".github/workflows/build.yml: `{knob}` 只在步骤级出现 —— "
            "同一个 job 里别的步骤（尤其负责测量它的那个）看不到这个值，"
            "报告就会拿内建默认值去对比一个真实存在的上限"
        )
        continue
    for step in build_steps:
        if not isinstance(step, dict):
            continue
        step_env = step.get("env")
        if not (isinstance(step_env, dict) and knob in step_env):
            continue
        step_value = str(step_env[knob]).strip()
        if step_value != top_value:
            problems.append(
                f".github/workflows/build.yml: 步骤 "
                f"`{step.get('name') or '?'}` 把 `{knob}` 覆盖成 "
                f"`{step_value}`，而 {top_scope} 级是 `{top_value}` —— "
                "同一个 job 里两套值，报告与构建必然对不上"
            )

# ---------------------------------------------------------------------------
if problems:
    print(f"\033[31m✗ 发现 {len(problems)} 处复用工作流契约问题：\033[0m\n")
    for p in problems:
        print(f"  - {p}")
    print()
    sys.exit(1)

print(
    f"\033[32m✓ 复用工作流契约正常\033[0m"
    f"（检查了 {checked_calls} 处 uses: ./ 调用、表达式中的连字符点号访问，"
    f"runs-on 的浮动标签、run 块里的表达式替换、固件缓存的恢复/保存顺序、"
    f"{knob_checked} 个跨步骤旋钮的唯一取值，"
    f"以及 {shell_checked} 个 bash run 块的 shell 语法（含复合 action））"
)
if perm_unchecked:
    # 不失败，但必须露出来：这一条查的就是 startup_failure —— 没核对等于没查。
    print(
        f"\033[33m! {perm_unchecked} 处可复用工作流的权限子集没能静态核对\033[0m"
        "（调用方或其 job 没写 permissions，或用了 read-all/write-all 简写）"
    )
PY
