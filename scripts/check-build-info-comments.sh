#!/usr/bin/env bash
# BUILD-INFO.txt 里那句注释，是真的注释吗？
#
# `write_build_info` 用**未加引号**的 heredoc 写产物（`cat >"${dest}/BUILD-INFO.txt"
# <<EOF`）。未加引号的 heredoc 里，反引号是命令替换 —— 在 `#` 注释行上也是。
#
# 这不是假想。`openwrt_revision_source` 上面那段注释把三个取值写成 `latest` /
# `pinned` / `caller`，于是 v1.4.1 发布出去的 BUILD-INFO.txt 是这样：
#
#   # Where openwrt_revision came from:  (the branch head at build time),
#   #  (OPENWRT_PINNED_REVISION) or 3999 ./scripts/local-build.sh (an ...)
#
# latest 与 pinned 当命令跑掉了、什么也没留下，caller 展开成 shell 内建命令的输出
# （`3999 ./scripts/local-build.sh` 是 `caller` 打印的调用栈）。没有任何一步失败：
# heredoc 不会因为“命令找不到”而失败，损坏只出现在已经发布出去的产物里。
#
# 两条断言，因为单独任何一条都能被绕过：
#   1. 全仓扫描 —— 任何未加引号 heredoc 里的 `#` 注释行都不得含反引号；
#   2. 真渲染一遍 —— `write_build_info` 的 stderr 必须干净，产物里必须能读到
#      "latest" / "pinned" / "caller" 这三个词，且不得出现 shell 的输出痕迹。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 解释器从外面传进来。不能指望 python 的 `bash` 就是跑这个脚本的 bash：Windows 上
# `bash` 先命中 System32ash.exe（WSL），它读不到 C:/ 这种路径，于是渲染出 rc=127
# "No such file or directory" —— 看起来像脚本有 bug，其实是找错了 shell。
exec python3 - "$ROOT_DIR" "${BASH:-bash}" <<'PY'
import io
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
bash = sys.argv[2]
problems = []

# ---- 1. 未加引号 heredoc 里的 `#` 注释行不得含反引号 ----------------------
scan_targets = sorted((root / "scripts").glob("*.sh")) + sorted(
    (root / ".github" / "actions").glob("*/action.yml")
)
for path in scan_targets:
    lines = io.open(path, encoding="utf-8").read().splitlines()
    i = 0
    while i < len(lines):
        # 只看**代码行**：注释里提到 `<<EOF` 是为了讲这件事本身，不是 heredoc
        # （这个脚本开头就写了一句，被自己的扫描器逮住过一次）。
        if lines[i].lstrip().startswith("#"):
            i += 1
            continue
        m = re.search(r"<<(-?)\s*([A-Za-z_][A-Za-z0-9_]*)", lines[i])
        if not m:
            i += 1
            continue
        # `<<'EOF'` / `<<"EOF"` 引号化过，体内不做展开，没有这个陷阱。
        rest = lines[i][m.start():]
        quoted = "'" in rest or '"' in rest
        tag = m.group(2)
        j = i + 1
        while j < len(lines) and lines[j].strip() != tag:
            line = lines[j]
            if not quoted and line.lstrip().startswith("#") and "`" in line:
                problems.append(
                    "{}:{}: 未加引号的 heredoc <<{} 里的 `#` 注释行含反引号，"
                    "那是命令替换：{}".format(
                        path.relative_to(root), j + 1, tag, line.strip()[:70]
                    )
                )
            j += 1
        i = j + 1

# ---- 2. 渲染 write_build_info，检查 stderr 与产物文本 ----------------------
src = io.open(root / "scripts" / "local-build.sh", encoding="utf-8").read()
body = re.search(r"^write_build_info\(\) \{.*?^\}\n", src, re.S | re.M)
if not body:
    problems.append("write_build_info 不在了 —— 这条测试要跟着改")
else:
    # as_posix()：这条测试在 Windows checkout 上也要跑，而 mkdtemp() 给出的反斜杠
    # 在 MSYS bash 里是字面字符，重定向会写到别处，渲染看起来“干净”却什么也没产出。
    dest = pathlib.Path(tempfile.mkdtemp()).as_posix()
    preamble = [
        "set -uo pipefail",
        "log() { :; }",
        r'warn() { printf "warn: %s\n" "$*" >&2; }',
        # 真脚本里这些是算出来的；这里只测 heredoc 的文本，值本身无关。
        "derive_project_version() { echo 9.9.9; }",
        "ROOT_DIR=/nonexistent TARGET_PROFILE=p TARGET_ARCH=a",
        "TARGET_BOARD=b TARGET_SUBTARGET=s",
        "REPO_URL=u REPO_BRANCH=main OPENWRT_TRACK=pinned",
    ]
    for knob in (
        "FANCONTROL NETMODE WWAND MT5700M UPNP ADBLOCK DOCKERMAN "
        "NIKKI OPENCLASH MOSDNS HOMEPROXY ADGUARDHOME EBPF_PROXY_KERNEL"
    ).split():
        preamble.append("ENABLE_{}=0".format(knob))
    script = "\n".join(
        preamble + [body.group(0), 'write_build_info "{}"'.format(dest)]
    ) + "\n"
    # 落成文件再执行，不用 `bash -c`：Windows 上命令行会被 MSVCRT 重新引用，
    # 内嵌的 heredoc 会被改坏，报出来的错在这台机器之外不存在。
    runner = pathlib.Path(dest) / "run.sh"
    runner.write_text(script, encoding="utf-8", newline="\n")
    # as_posix() 必须跟到调用处：
    # `str(Path(...))` 在 Windows 上给出反斜杠，bash 会把它们当转义符吃掉，报出
    # "C:Usersissac...run.sh: No such file or directory"。
    proc = subprocess.run([bash, runner.as_posix()], capture_output=True, text=True)
    if proc.returncode != 0 or proc.stderr.strip():
        problems.append(
            "渲染 write_build_info 不干净（rc={}）：\n{}".format(
                proc.returncode, proc.stderr.strip()[:600]
            )
        )

    produced = pathlib.Path(dest) / "BUILD-INFO.txt"
    if not produced.exists():
        problems.append(
            "write_build_info 没在 {} 产出 BUILD-INFO.txt（rc={}）：{}".format(
                dest, proc.returncode, proc.stderr.strip()[:300]
            )
        )
        info = ""
    else:
        info = produced.read_text(encoding="utf-8")

    # 注释里写明的三个取值必须真的出现。被吃掉的那个恰好就是裸词本身。
    for value in ("latest", "pinned", "caller"):
        if '"{}"'.format(value) not in info:
            problems.append(
                'BUILD-INFO.txt 的 openwrt_revision_source 注释里读不到 "{}" —— '
                "注释被 heredoc 吃掉、或被改写后没同步这条测试".format(value)
            )
    # 被吃掉的替换留下的是空位，不是错误信息：`注释里有 "..." 但不是所有词`
    # 这类痕迹表现为冒号后紧跟两个空格。这比按字面找 "3999 " 可靠 ——
    # 后者正是 caller 内建在**这台**机器上的输出，换一台就变。
    # 只查被记录过的那一句。全文件的“冒号后两个空格”会误伤**引用**损坏文本的
    # 修复说明（local-build.sh 里就有一段），而被吃掉的替换只会留下空洞，不会
    # 留下错误信息，所以空洞是唯一能抓住它的痕迹。
    for line in info.splitlines():
        if line.startswith("# Where openwrt_revision came from") and ":  " in line:
            problems.append(
                "BUILD-INFO.txt 里那句取值的注释被吃掉了一半（冒号后两个空格）："
                "{!r}".format(line.strip()[:90])
            )
    if "command not found" in info:
        problems.append("BUILD-INFO.txt 里带着 shell 报错：命令替换漏进了产物")

if problems:
    print("\033[31m✗ 发现 {} 处 BUILD-INFO 注释问题：\033[0m\n".format(len(problems)))
    for p in problems:
        print("  - " + p)
    print()
    sys.exit(1)

print(
    "\033[32m✓ BUILD-INFO 的注释能在 heredoc 里活下来\033[0m"
    "（扫描了 {} 个文件里未加引号 heredoc 的注释行，并真渲染了一遍产物）".format(
        len(scan_targets)
    )
)
PY
