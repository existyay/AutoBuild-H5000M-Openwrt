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
python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys

import yaml

root = pathlib.Path(sys.argv[1])
wf_dir = root / ".github" / "workflows"
act_dir = root / ".github" / "actions"

problems: list[str] = []
checked_calls = 0


def load(path: pathlib.Path):
    """YAML 1.1 会把裸 `on:` 解析成布尔 True，因此要转回字符串键。"""
    data = yaml.safe_load(path.read_text())
    if not isinstance(data, dict):
        return {}
    if True in data and "on" not in data:
        data["on"] = data.pop(True)
    return data


def as_set(mapping) -> set:
    return set((mapping or {}).keys())


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
    text = path.read_text()
    for i, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        if DOTTED_HYPHEN.search(line):
            problems.append(
                f"{path.relative_to(root)}:{i}: 表达式里对含连字符的标识符用了点号访问；"
                f"`-` 会被当作减法，导致启动期失败。请改用 snake_case 标识符或方括号写法。"
            )

# ---------------------------------------------------------------------------
# 2) 复用工作流调用契约
# ---------------------------------------------------------------------------
for path in sorted(wf_dir.glob("*.yml")):
    data = load(path)
    jobs = data.get("jobs") or {}
    caller_top = as_set(data.get("permissions"))

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
                f"{path.relative_to(root)}: job {job_id} 引用了不存在的 {uses}"
            )
            continue

        callee = load(target)
        wc = (callee.get("on") or {}).get("workflow_call")
        if wc is None:
            problems.append(
                f"{path.relative_to(root)}: job {job_id} 调用了 {uses}，"
                f"但它没有声明 on.workflow_call"
            )
            continue

        # 2a) with: 的键必须是被调用方声明的输入
        declared = as_set(wc.get("inputs"))
        for key in as_set(job.get("with")):
            if key not in declared:
                problems.append(
                    f"{path.relative_to(root)}: job {job_id} 传给 {uses} 的输入 "
                    f"`{key}` 未在被调用方声明（已声明：{sorted(declared)}）"
                )
        # 必填输入必须传
        for key, spec in (wc.get("inputs") or {}).items():
            if isinstance(spec, dict) and spec.get("required") and key not in as_set(job.get("with")):
                problems.append(
                    f"{path.relative_to(root)}: job {job_id} 未传必填输入 `{key}` 给 {uses}"
                )

        # 2b) 权限子集：被调用方 job 请求的权限必须是调用方已授予的子集。
        #     这就是让 build.yml 完全无法启动的那条规则。
        caller_granted = as_set(job.get("permissions")) or caller_top
        for cj_id, cj in (callee.get("jobs") or {}).items():
            if not isinstance(cj, dict):
                continue
            callee_wants = as_set(cj.get("permissions")) or as_set(callee.get("permissions"))
            missing = callee_wants - caller_granted
            if missing:
                problems.append(
                    f"{path.relative_to(root)}: job {job_id} 调用 {uses}，"
                    f"而被调用方 job {cj_id} 申请了调用方未授予的权限 "
                    f"{sorted(missing)}（调用方授予 {sorted(caller_granted)}）——"
                    f"GitHub 会在启动期拒绝整个工作流（startup_failure）"
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
    f"（检查了 {checked_calls} 处 uses: ./ 调用，以及表达式中的连字符点号访问）"
)
PY
