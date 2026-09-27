#!/usr/bin/env bash
#
# check-action-inputs.sh — 校验每个 `with:` 键都是该 action 真正声明的输入。
#
# 为什么需要这个脚本：给 action 传一个它没声明的输入时，GitHub **不会**报错，
# 只在运行页面留一条 `warning` 注释：
#
#     Unexpected input(s) 'pull-request-title-pattern', valid inputs are [...]
#
# 工作流照常运行、检查照常变绿，所以这种「死配置」会一直躺着，还会让读到它的
# 人以为设置已经生效。本仓库真实发生过一次：release-please.yml 里的
# `pull-request-title-pattern` 被当成「让发布提交合法」的手段写进注释，实际上
# 该 action 从来不读它——发布 PR 的标题依旧是 `chore(master): release 1.1.4`，
# 真正兜住 commitlint 的是 commitlint.config.mjs 里的 ignores 例外。
#
# 同一形状的第二类故障：action 被弃用（或它声明的某个输入被弃用）。这类问题
# 同样只留一条 `warning` 注释，检查照常变绿。本仓库在 run 36282274537 上同时
# 出现了两条：
#
#   * `tool-cache`（free-disk-space）已改名为 `preinstalled-runtimes`；
#   * `actions/attest-sbom` 整体弃用，只剩一层打印告警再转发的包装。
#
# 两者的公告都写在 action 自己的元数据里，所以这里在**已经取下来的** action.yml
# 上顺带核对，不额外发网络请求：输入级弃用看 `deprecationMessage`，整体/改名
# 弃用看清单里那条 `::warning::` 公告文本。
#
# 覆盖范围：
#   * 工作流与本地复合 action 里的所有 `with:`；
#   * 本地 action（`./...`）从工作树里读 action.yml；
#   * 远程 action 按**已钉住的 SHA** 取 action.yml —— SHA 不可变，所以答案稳定；
#   * `docker://` 与 `./` 之外的无法解析者一律报错，不静默放过。
#
# 网络不可用时**失败**而不是跳过：这个脚本存在的意义就是不产生假通过。
#
# Usage: scripts/check-action-inputs.sh [仓库根目录]
#
set -Eeuo pipefail

ROOT_DIR="$(cd "${1:-"$(dirname "${BASH_SOURCE[0]}")/.."}" && pwd)"
cd "$ROOT_DIR"

command -v python3 >/dev/null 2>&1 || {
	echo "需要 python3" >&2
	exit 2
}

python3 - "$ROOT_DIR" <<'PY'
import concurrent.futures
import pathlib
import re
import sys
import urllib.error
import urllib.request

import yaml

root = pathlib.Path(sys.argv[1])
wf_dir = root / ".github" / "workflows"
act_dir = root / ".github" / "actions"

problems: list[str] = []
could_not_verify: list[str] = []


def load(path: pathlib.Path):
    """YAML 1.1 会把裸 `on:` 解析成布尔 True，因此要转回字符串键。"""
    data = yaml.safe_load(path.read_text())
    if not isinstance(data, dict):
        return {}
    if True in data and "on" not in data:
        data["on"] = data.pop(True)
    return data


def steps_of(path: pathlib.Path):
    """工作流走 jobs.*.steps；复合 action 视为单个隐式 job。"""
    data = load(path)
    if "runs" in data:
        for step in (data.get("runs") or {}).get("steps") or []:
            if isinstance(step, dict):
                yield step
        return
    for job in (data.get("jobs") or {}).values():
        if isinstance(job, dict):
            for step in job.get("steps") or []:
                if isinstance(step, dict):
                    yield step


# ---------------------------------------------------------------- 收集调用 ---
# 收集**全部** action 调用，不因为"没写 with:"就跳过：整体弃用与有没有传输入
# 无关，`actions/foo@...` 不带 with: 也照样会打印它的弃用公告。输入检查另在
# 报告阶段按 entry["keys"] 是否为空来收窄。
calls: dict[str, dict] = {}
for path in sorted(list(wf_dir.glob("*.yml")) + list(act_dir.rglob("action.yml"))):
    for step in steps_of(path):
        uses = step.get("uses")
        if not isinstance(uses, str) or uses.startswith("docker://"):
            continue
        entry = calls.setdefault(uses, {"keys": set(), "where": set()})
        entry["keys"] |= set(step.get("with") or {})
        entry["where"].add(f"{path.relative_to(root)}: {step.get('name', '<未命名>')}")


# ------------------------------------------------------------ 声明的输入 ---
RE_USES = re.compile(r"^([^/@]+/[^/@]+)(/[^@]*)?@(.+)$")


def deprecations_in(data: dict) -> dict:
    """从一个 action.yml 里提取会触发的弃用公告。

    只认 action 自己的元数据，分两层：

    * 输入级：`inputs.<k>` 带 `deprecationMessage`。这一层必须带上使用的键再
      判断——action 声明了某个弃用输入、但本仓库从来没传过它，就不该报。
    * 公告级：composite action 的某一步 `run:` 里打印
      `::warning::...deprecat...`。这正是 `actions/attest-sbom` 弃用后的形态：
      一次 `echo` 加一次转发。

    公告再分两种，因为**打印条件**不同，误报与漏报的代价也不同：

    * 无条件（步骤没有 `if:`，且公告不在 shell 条件块里）——必然打印，一律报。
    * 有条件（例如 free-disk-space 的 `if [[ "$TOOL_CACHE" == 'true' ]]`）——
      只有传了那个输入才打印。这种只在公告点名了**我们确实在传**的输入时报，
      否则「没传就不该报」会变成噪音，进而让人关掉整个门禁。

    返回 {"inputs": {键: 消息}, "whole": [必然打印的公告], "conditional": [(公告, 点名的输入)]}。
    """
    out: dict = {"inputs": {}, "whole": [], "conditional": []}
    for key, spec in (data.get("inputs") or {}).items():
        if isinstance(spec, dict) and spec.get("deprecationMessage"):
            out["inputs"][key] = str(spec["deprecationMessage"]).strip()

    # 输入改名的公告惯用措辞：The '<旧名>' input is deprecated ...
    # 只认被抓出来的**旧**名；公告里的替代名（'preinstalled-runtimes'）不算。
    renames = re.compile(r"The '([^']+)' input is deprecated", re.IGNORECASE)

    for step in (data.get("runs") or {}).get("steps") or []:
        if not isinstance(step, dict):
            continue
        run = str(step.get("run") or "")
        for idx, line in enumerate(run.splitlines()):
            if "::warning::" not in line or "deprecat" not in line.lower():
                continue
            msg = line.split("::warning::", 1)[1].strip()
            # 该公告是否处在 shell 条件块内：往前数 `if/while/until/for/case`
            # 是否多于 `fi/done/esac`。缩进不参与判断，只数关键字。
            depth = 0
            for prev in run.splitlines()[:idx]:
                s = prev.strip()
                if not s or s.startswith("#"):
                    continue
                if re.match(r"^(if|while|until|for|case)\b", s):
                    depth += 1
                elif re.match(r"^(fi|done|esac)\b", s):
                    depth -= 1
            conditional = bool(step.get("if")) or depth > 0
            if conditional:
                out["conditional"].append((msg, set(renames.findall(msg))))
            else:
                out["whole"].append(msg)
    return out


def fetch(url: str) -> tuple[dict | None, str | None]:
    """带重试地取一个 action.yml；返回 (数据, 错误)。"""
    last = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                return yaml.safe_load(resp.read().decode("utf8", "replace")), None
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None, "404"
            last = f"HTTP {e.code}"
        except Exception as e:  # noqa: BLE001
            last = f"{type(e).__name__}: {e}"
    return None, last


def declared_for(uses: str) -> tuple[set | None, dict, str | None]:
    """返回 (已声明的输入名, 弃用元数据, 错误)。

    弃用元数据在**同一次** action.yml 读取中顺带算出，所以这两类检查不额外
    花一次网络往返。
    """
    if uses.startswith("./"):
        # 本地 action：从工作树读，不走网络。
        path = root / uses / "action.yml"
        if not path.exists():
            return None, {}, f"本地 {uses}/action.yml 不存在"
        data = load(path)
        return set((data.get("inputs") or {})), deprecations_in(data), None

    m = RE_USES.match(uses)
    if not m:
        return None, {}, "无法解析 uses（缺少 owner/repo@ref）"
    repo, sub, ref = m.group(1), (m.group(2) or "").strip("/"), m.group(3)
    stem = f"{sub}/" if sub else ""
    base = f"https://raw.githubusercontent.com/{repo}/{ref}/"
    saw = ""
    for name in ("action.yml", "action.yaml"):
        data, err = fetch(f"{base}{stem}{name}")
        if data is not None:
            return (
                set((data.get("inputs") or {})),
                deprecations_in(data),
                None,
            )
        saw = err or saw
        if err != "404":
            break
    return None, {}, saw or "该 ref 下没有 action.yml"


with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    futures = {pool.submit(declared_for, u): u for u in calls}
    for fut in concurrent.futures.as_completed(futures):
        uses = futures[fut]
        declared, deprecated, err = fut.result()
        entry = calls[uses]
        if declared is None:
            # 取不到就是取不到 —— 不静默放过，否则又会回到假通过。
            could_not_verify.append(
                f"{uses} —— 无法确认其声明的输入（{err}）；"
                f"出现在 {', '.join(sorted(entry['where']))}"
            )
            continue
        where = ', '.join(sorted(entry["where"]))
        extra = entry["keys"] - declared
        if extra:
            problems.append(
                f"{sorted(extra)} 不是 {uses} 声明的输入。"
                f"GitHub 只会留一条 warning 注释而不会失败，工作流照常变绿，"
                f"于是这条配置是死的、却看起来生效了。"
                f"出现在 {where}；"
                f"该 action 声明了 {sorted(declared)}"
            )

        # 弃用：同样只留 warning 注释，检查照常变绿。
        for key in sorted(entry["keys"] & set(deprecated["inputs"])):
            problems.append(
                f"{uses} 的输入 `{key}` 已被弃用：{deprecated['inputs'][key]}"
                f"出现在 {where}。"
                f"这只会留一条 warning 注释、工作流照常变绿，"
                f"所以请改用公告里指定的替代输入（不要把告警留在日志里）。"
            )
        for msg in deprecated["whole"]:
            problems.append(
                f"{uses} 整个 action 已弃用，其自身会无条件打印：{msg}"
                f"出现在 {where}。"
                f"这只会留一条 warning 注释、工作流照常变绿，"
                f"所以请改为直接调用公告里指定的替代 action。"
            )
        for msg, names in deprecated["conditional"]:
            # 有条件打印：只有传了公告点名的那个输入才会真的告警。
            hit = sorted(entry["keys"] & names)
            if not hit:
                continue
            problems.append(
                f"{uses} 的输入 {hit} 已被弃用，传了它就会打印：{msg}"
                f"出现在 {where}。"
                f"这只会留一条 warning 注释、工作流照常变绿，"
                f"所以请改用公告里指定的替代输入。"
            )

if could_not_verify:
    print(f"\033[31m✗ 有 {len(could_not_verify)} 个 action 无法核对输入：\033[0m\n")
    for c in could_not_verify:
        print(f"  - {c}")
    print()
    print("这个检查宁可失败也不跳过：无法核对时的「通过」就是它要消灭的假象。")
    sys.exit(2)

if problems:
    print(f"\033[31m✗ 发现 {len(problems)} 处 action 输入/弃用问题：\033[0m\n")
    for p in problems:
        print(f"  - {p}\n")
    sys.exit(1)

print(
    f"\033[32m✓ action 输入全部声明正确、且没有已弃用的调用\033[0m"
    f"（核对了 {len(calls)} 个不同的 action 调用）"
)
PY