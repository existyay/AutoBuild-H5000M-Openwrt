#!/usr/bin/env bash
#
# verify-upstream-integration.sh — 上游一动，本仓库的补丁与集成还成立吗？
#
# 为什么需要这个脚本：本工程把 fullcone 的四层支持、一个 fan 策略补丁，以及
# Nikki-RS 的三处 IPv6 绕过默认值，全部作为**补丁/改写**打在 mainline 上。
# 它们成立与否取决于上游那十几个文件当前的形状，而 mainline 每天都在动。
#
# 失效有两种形态，都不等于"构建失败"那么简单：
#
#   1. 上下文对不上 → patch 报 FAILED → 构建在 2–3 小时后变红，原因要翻日志
#      才知道是哪个包的第几个 hunk。
#   2. **更坏的一种**：补丁的 `+` 行已经出现在目标文件里（上游自己加了同一段
#      代码），patch 判定为 "Reversed (or previously applied)" 并把**整个 hunk
#      丢掉**。补丁看起来"打过"了，而常量没有定义、默认值没有写入，故障推迟到
#      编译期（`undeclared`），或者更安静地变成"某个安全控制项其实不存在"。
#      上游 libnftnl 1.3.2 把 `nftnl_expr_set_imm` 加进 `include/libnftnl/expr.h`
#      时，本仓库的 libnftnl 补丁正是被这样整块丢掉的 —— 而丢掉的那一块里还
#      包括 `NFTNL_EXPR_FULLCONE_*` 的定义，于是 nftables 的编译会失败。
#
# 所以这个脚本把"补丁还成不成立"变成一条可自动跑的断言：它按 mainline 当前
# **真正会构建的那些版本**下载源码（nftables / libnftnl 的官方 tarball、
# firewall4 / mt76 的 git 快照），用 `patch -F0 --dry-run` 逐条试；再把 Nikki-RS
# 依赖的三处锚点、clash-rs 钉住版本的资产哈希一起核对。
#
# 退出码刻意分成两种，因为"补丁坏了"和"没能查到"必须能被区分开：
#
#   0  全部通过
#   1  上游漂移（真问题，要改本仓库的补丁/锚点）
#   2  无法验证（网络/工具缺失 —— 不要把它读成补丁坏了）
#
# Usage:
#   scripts/verify-upstream-integration.sh [--ref <sha|branch>] [--keep] [仓库根目录]
#   scripts/verify-upstream-integration.sh --self-test
#
# --self-test 完全离线：它造一个恰好含三种形态（适用 / 上下文对不上 / 已被上游
# 应用）的临时树，然后要求本脚本的判定**如实**区分它们。一条抓不到缺陷的门禁
# 比没有门禁更坏。
#
# 面向 Linux（CI 就是这个环境）。在 Windows 的 Git Bash 下也能跑，但 firewall4
# 与 mt76 的快照里含符号链接，而 Windows 默认不许普通用户创建符号链接，于是这两
# 项会以退出码 2（"没能验证"，不是"漂移"）报出来 —— 那是环境限制，不是补丁问题。
#
set -Eeuo pipefail

EXIT_DRIFT=1
EXIT_UNVERIFIED=2

ROOT_DIR=""
REF=""
KEEP=0
SELF_TEST=0

usage() {
	sed -n '2,/^set -Eeuo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--ref)
			[ "$#" -ge 2 ] || {
				echo "--ref 需要一个参数" >&2
				exit 2
			}
			REF="$2"
			shift 2
			;;
		--keep)
			KEEP=1
			shift
			;;
		--self-test)
			SELF_TEST=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		-*)
			echo "未知参数：$1" >&2
			exit 2
			;;
		*)
			ROOT_DIR="$1"
			shift
			;;
	esac
done

ROOT_DIR="$(cd "${ROOT_DIR:-"$(dirname "${BASH_SOURCE[0]}")/.."}" && pwd)"
cd "$ROOT_DIR"

# 颜色只在真正连到终端时输出，否则 CI 日志里全是转义序列。
if [ -t 2 ]; then
	C_RED=$'\033[31m'
	C_YEL=$'\033[33m'
	C_OFF=$'\033[0m'
else
	C_RED=""
	C_YEL=""
	C_OFF=""
fi

log() { printf '  %s\n' "$*"; }
warn() { printf '%s警告%s: %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die() {
	printf '%s错误%s: %s\n' "$C_RED" "$C_OFF" "$*" >&2
	exit "$EXIT_UNVERIFIED"
}

DRIFT_REASONS=()
UNVERIFIED_REASONS=()

drift() { DRIFT_REASONS+=("$*"); }
unverified() { UNVERIFIED_REASONS+=("$*"); }

need() {
	command -v "$1" >/dev/null 2>&1 || die "缺少命令 $1"
}

CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-20}"

# 令牌通过数组传入。写成 ${TOKEN:+-H "..."} 是不行的：bash 不会把展开结果里的
# 引号再解释一次，那会变成一个带引号的畸形容器参数。
#
# 两个变量名都认：CI 里本仓库用的是 `GH_TOKEN: ${{ github.token }}`（gh 的口径），
# 而本地习惯是 GITHUB_TOKEN。读不到也没什么 —— 匿名配额 60 次/小时足够本次运行
# 的那一次 API 调用，只是并发跑多个 workflow 时容易撞上限。
curl_retry() {
	local -a auth=()
	local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
	if [ -n "$token" ]; then
		auth=(-H "Authorization: Bearer ${token}")
	fi
	curl -fsSL --connect-timeout "$CONNECT_TIMEOUT" --retry 4 --retry-delay 3 \
		--retry-all-errors "${auth[@]}" "$@"
}

# ---------------------------------------------------------------------------
# 上游文件的取用
# ---------------------------------------------------------------------------
# RAW 指向 openwrt 主仓库，用于读包 Makefile —— 它才决定"这次构建用哪个版本"。
RAW="https://raw.githubusercontent.com/openwrt/openwrt"
API="https://api.github.com"

# fetch_raw <openwrt 树内路径> <目标文件>
fetch_raw() {
	curl_retry "$RAW/$REF/$1" -o "$2"
}

# pkgvar <openwrt 树内 Makefile 路径> <变量名>
pkgvar() {
	curl_retry "$RAW/$REF/$1" | sed -n "s/^$2:=//p" | head -n1
}

# ---------------------------------------------------------------------------
# 补丁适用性：这是本脚本的核心断言
# ---------------------------------------------------------------------------
# 用 `patch -F0 --dry-run --forward`，而不是 `git apply`：openwrt 打**包内**
# 补丁用的就是 patch(1)，fuzz 与 "reversed" 两种判定都要照它的口径来。
#
# 为什么必须钉住 -F0：默认最多容忍 2 行 fuzz，而 fuzz 命中意味着补丁**打进去了
# 但落点靠猜**。这一次猜对了不代表文件形状是对的，上游再挪几行就会变成静默
# 错位 —— 那正是本项目最不想留下的失败模式。
verify_patches() {
	local dir="$1"
	shift
	local p out rc

	for p in "$@"; do
		rc=0
		out="$(cd "$dir" && patch -p1 -F0 --dry-run --forward --batch <"$p" 2>&1)" || rc=$?
		if [ "$rc" -eq 0 ]; then
			log "OK    $(basename "$p")"
			continue
		fi
		printf '%s\n' "$out" | sed 's/^/        /' >&2
		if printf '%s' "$out" | grep -q 'Reversed (or previously applied)'; then
			drift "$(basename "$p") 对 ${dir##*/}：patch 判定为 Reversed (or previously applied) 并丢弃整个 hunk —— 上游自己加了同一段代码。补丁会静默少打一块，故障推迟到编译期或变成一个缺失的默认值。"
		else
			drift "$(basename "$p") 对 ${dir##*/}：上下文对不上，patch 报 FAILED —— 上游改了它碰的文件。"
		fi
	done
	return 0
}

# download_and_extract <url> <目录> <tar 参数...>
download_and_extract() {
	local url="$1" dir="$2"
	shift 2
	local tgz
	tgz="$WORK/$(basename "$url")"

	if ! curl_retry "$url" -o "$tgz"; then
		unverified "下载失败：$url"
		return 1
	fi
	mkdir -p "$dir"
	# 把 tar 自己的理由带进结论，而且取**第一行**：tar 先打印具体原因，最后一行
	# 永远是 "Exiting with failure status due to previous errors" —— 那是最没有信息
	# 量的一句。此前这里固定写"缺 xz-utils？"，而在 Windows 上真正的原因通常是
	# "没有创建符号链接的权限"。一条把原因指错的诊断比没有诊断更浪费时间。
	if ! tar "$@" -xf "$tgz" -C "$dir" 2>"$WORK/tar.err"; then
		local why
		why="$(head -n1 "$WORK/tar.err" 2>/dev/null || true)"
		[ -n "$why" ] || why="tar 退出码非 0，但没有输出原因"
		unverified "解包失败：$(basename "$tgz") —— $why"
		return 1
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 1) fullcone 用户态两层：nftables 与 libnftnl
# ---------------------------------------------------------------------------
check_fullcone_userspace() {
	local name="$1" mkpath="$2" tarbase="$3" patchdir="$4"
	local ver want_hash dir tgz

	ver="$(pkgvar "$mkpath" PKG_VERSION)"
	if [ -z "$ver" ]; then
		unverified "读不到 $mkpath 的 PKG_VERSION"
		return 0
	fi
	want_hash="$(pkgvar "$mkpath" PKG_HASH)"

	printf '\n== %s %s\n' "$name" "$ver"

	dir="$WORK/$name"
	if ! download_and_extract "$tarbase-$ver.tar.xz" "$dir" --strip-components=1 -J; then
		return 0
	fi

	# 校验 tarball 就是 openwrt 会构建的那一份。若上游的 PKG_HASH 与我们下载的
	# 不一致，说明比对的对象本身就不是构建对象，这时"补丁通过"没有意义。
	if [ -n "$want_hash" ]; then
		tgz="$WORK/$(basename "$tarbase-$ver.tar.xz")"
		if [ "$(sha256sum "$tgz" | cut -d' ' -f1)" != "$want_hash" ]; then
			unverified "$name-$ver.tar.xz 的 sha256 与 $mkpath 的 PKG_HASH 不一致"
			return 0
		fi
		log "tarball sha256 与 PKG_HASH 一致"
	fi

	shopt -s nullglob
	local patches=("$ROOT_DIR/$patchdir"/*.patch)
	shopt -u nullglob
	if [ "${#patches[@]}" -eq 0 ]; then
		log "没有补丁，跳过"
		return 0
	fi
	verify_patches "$dir" "${patches[@]}"
	return 0
}

# ---------------------------------------------------------------------------
# 2) firewall4 与 mt76：git 拉取的源码
# ---------------------------------------------------------------------------
check_git_packages() {
	local name="$1" mkpath="$2" urlbase="$3" patchdir="$4"
	local rev dir

	rev="$(pkgvar "$mkpath" PKG_SOURCE_VERSION)"
	if [ -z "$rev" ]; then
		unverified "读不到 $mkpath 的 PKG_SOURCE_VERSION"
		return 0
	fi

	printf '\n== %s %s\n' "$name" "$rev"

	dir="$WORK/$name"
	if ! download_and_extract "$urlbase/archive/$rev.tar.gz" "$dir" --strip-components=1 -z; then
		return 0
	fi

	shopt -s nullglob
	local patches=("$ROOT_DIR/$patchdir"/*.patch)
	shopt -u nullglob
	if [ "${#patches[@]}" -eq 0 ]; then
		log "没有补丁，跳过"
		return 0
	fi
	verify_patches "$dir" "${patches[@]}"
	return 0
}

# ---------------------------------------------------------------------------
# 3) 顶层 patches/：打在 openwrt 检出树上的补丁
# ---------------------------------------------------------------------------
# 只取补丁碰到的那些文件，而不是 clone 整棵树：apply_patches() 的判定是
# `git apply --check`，它只需要被碰文件的内容，因此这里几 KB 就够，而完整
# clone 是 1–2 GB。
check_tree_patches() {
	printf '\n== patches/（顶层树补丁，判定用 git apply --check）\n'

	shopt -s nullglob
	local patches=("$ROOT_DIR"/patches/*.patch)
	shopt -u nullglob
	if [ "${#patches[@]}" -eq 0 ]; then
		log "没有顶层补丁"
		return 0
	fi

	local tree="$WORK/owrt-shadow" p path
	mkdir -p "$tree"

	for p in "${patches[@]}"; do
		# `--- a/...` 侧的文件必须已存在，且内容与补丁的 a 侧逐字相同。
		while IFS= read -r path; do
			[ -n "$path" ] || continue
			mkdir -p "$tree/$(dirname "$path")"
			if [ ! -f "$tree/$path" ]; then
				fetch_raw "$path" "$tree/$path" || unverified "取不到 ${REF} 的 $path"
			fi
		done < <(sed -n 's|^--- a/||p' "$p" | sort -u)

		# `+++ b/...` 侧可能是新建文件，只需要父目录存在。
		while IFS= read -r path; do
			[ -n "$path" ] || continue
			mkdir -p "$tree/$(dirname "$path")"
		done < <(sed -n 's|^+++ b/||p' "$p" | sort -u)
	done

	for p in "${patches[@]}"; do
		if (cd "$tree" && git apply --check "$p" 2>"$WORK/ga.err"); then
			log "OK    $(basename "$p")"
			continue
		fi
		sed 's/^/        /' "$WORK/ga.err" >&2
		drift "$(basename "$p")：git apply --check 失败 —— 它碰的树内文件已被上游改动。"
	done
	return 0
}

# ---------------------------------------------------------------------------
# 4) Nikki-RS：本项目改写的三处默认值还找得到锚点吗
# ---------------------------------------------------------------------------
NIKKI_RAW="https://raw.githubusercontent.com/CHKayanami/OpenWrt-nikki-rs/main"

# assert_upstream_file <上游仓库内路径> <必须存在的字符串> <必须不存在的字符串>
assert_upstream_file() {
	local path="$1" want="$2" absent="${3:-}"
	local dst
	dst="$WORK/nikki/$(printf '%s' "$path" | tr '/' '_')"

	mkdir -p "$WORK/nikki"
	if ! curl_retry "$NIKKI_RAW/$path" -o "$dst"; then
		unverified "取不到 Nikki-RS 的 $path"
		return 0
	fi
	if ! grep -qF -- "$want" "$dst"; then
		drift "Nikki-RS 的 $path 里找不到锚点：${want} —— patch_nikki_ebpf_bypass_defaults 会 die。"
		return 0
	fi
	if [ -n "$absent" ] && grep -qF -- "$absent" "$dst"; then
		drift "Nikki-RS 的 $path 里已经出现${absent} —— 上游自己补上了这一项，本仓库那一段改写应当删除。"
		return 0
	fi
	log "OK    $path"
	return 0
}

check_nikki_anchors() {
	printf '\n== Nikki-RS 锚点（CHKayanami/OpenWrt-nikki-rs@main）\n'

	# 三处默认值来自同一个上游事实：eBPF 的 bypass_dst_ips 不含 fc00::/7。
	# insert_after_anchor / insert_in_default_block 都以这些字符串为锚；锚没了
	# 脚本会 die（不是静默），这里提前把它变成一条 CI 结论。
	assert_upstream_file \
		'nikki-rs/files/nikki-rs.conf' \
		"list bypass_dst_ips 'fe80::/10'" \
		"list bypass_dst_ips 'fc00::/7'"
	assert_upstream_file \
		'nikki-rs/files/uci-defaults/migrate.sh' \
		"uci add_list nikki-rs.ebpf.bypass_dst_ips='fe80::/10'" \
		"uci add_list nikki-rs.ebpf.bypass_dst_ips='fc00::/7'"
	assert_upstream_file \
		'luci-app-nikki-rs/htdocs/luci-static/resources/view/nikki-rs/ebpf.js' \
		"'ff00::/8'" \
		"'fc00::/7',"

	# pin_clash_rs 的前置条件：上游 Makefile 必须仍是"每架构一行 CLASH_HASH"。
	assert_upstream_file 'clash-rs/Makefile' '  CLASH_HASH:=' ''
	return 0
}

# ---------------------------------------------------------------------------
# 5) clash-rs 的钉住版本：资产还在吗，哈希还对吗
# ---------------------------------------------------------------------------
# 钉住一个上游 release 的最大风险不是"有更新版"，而是**那个 release 被撤掉**：
# 那时构建会在下载 clash-rs 的 tarball 时失败，而失败信息只说 404。这里直接问
# release 的资产清单，并把 digest 与 pin_clash_rs 里写死的哈希逐条比对。
check_clash_rs_pin() {
	printf '\n== clash-rs 钉住版本\n'

	local body want_url tag
	body="$(sed -n '/^pin_clash_rs()/,/^}/p' "$ROOT_DIR/scripts/local-build.sh")"
	want_url="$(printf '%s\n' "$body" | sed -n 's/.*local want_url="\([^"]*\)".*/\1/p' | head -n1)"
	if [ -z "$want_url" ]; then
		unverified "从 local-build.sh 的 pin_clash_rs() 里读不出 want_url"
		return 0
	fi
	tag="$(basename "$want_url")"
	log "本仓库钉住：$tag"

	if ! curl_retry "$API/repos/CHKayanami/clash-rs/releases/tags/$tag" -o "$WORK/clash-rs-$tag.json"; then
		drift "clash-rs 的 release ${tag} 已经取不到 —— 资产可能被撤下，pin_clash_rs 会 404。"
		return 0
	fi

	# 资产名 → 本仓库写死的哈希。映射来自 clash-rs/Makefile 的 CLASH_TARGET。
	local pairs="" spec h
	for spec in \
		'aarch64_h:clash-rs-minimal-aarch64-unknown-linux-musl.tar.gz' \
		'x86_64_h:clash-rs-minimal-x86_64-unknown-linux-musl.tar.gz' \
		'armv7_h:clash-rs-minimal-armv7-unknown-linux-musleabihf.tar.gz' \
		'riscv64_h:clash-rs-minimal-riscv64gc-unknown-linux-musl.tar.gz' \
		'i686_h:clash-rs-minimal-i686-unknown-linux-musl.tar.gz'; do
		# 单引号里嵌 `"` 是安全的；直接在双引号里写 `"` 会把字符串提前结束，
		# 于是整个脚本在后面某一行报出与真正原因无关的语法错误。
		h="$(printf '%s\n' "$body" | sed -n 's/.*local '"${spec%%:*}"'="\([^"]*\)".*/\1/p' | head -n1)"
		[ -n "$h" ] || continue
		pairs="${pairs}${spec#*:}=${h}"$'\n'
	done

	if [ -z "$pairs" ]; then
		unverified "从 pin_clash_rs() 里读不出任何 *_h 哈希变量"
		return 0
	fi

	printf '%s' "$pairs" >"$WORK/clash-rs-pairs.txt"
	# -X utf8：这段输出是中文（下面每行都有 OK/FAIL），而 python 的 stdout 编码
	# 取决于宿主的 locale。在 C/POSIX locale 的 runner 上不显式指定，就会变成
	# 一串问号或 mojibake —— 日志里最关键的一行反而不可读。
	if ! python3 -X utf8 - "$WORK/clash-rs-$tag.json" "$WORK/clash-rs-pairs.txt" "$tag" <<'PY'
import json
import sys

release_path, pairs_path, tag = sys.argv[1], sys.argv[2], sys.argv[3]
release = json.load(open(release_path, encoding="utf-8"))
assets = {a["name"]: a for a in release.get("assets", [])}

expected = []
for line in open(pairs_path, encoding="utf-8"):
    line = line.strip()
    if not line or "=" not in line:
        continue
    name, digest = line.split("=", 1)
    expected.append((name, digest))

if not expected:
    print("  FAIL  没解析出任何期望哈希")
    sys.exit(1)

bad = 0
for name, want in expected:
    asset = assets.get(name)
    if asset is None:
        print("  FAIL  %s 不在 %s 的资产清单里（release 被撤下或资产改名）" % (name, tag))
        bad += 1
        continue
    got = (asset.get("digest") or "").removeprefix("sha256:")
    if got != want:
        print("  FAIL  %s\n        期望 sha256:%s\n        实际 sha256:%s" % (name, want, got or "(API 未提供 digest)"))
        bad += 1
        continue
    print("  OK    %s sha256 与 pin_clash_rs() 一致" % name)

sys.exit(1 if bad else 0)
PY
	then
		drift "clash-rs ${tag} 的资产哈希与 pin_clash_rs() 里写死的不一致（详见上方逐条输出）。"
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 自检：本脚本真的能抓到漂移吗
# ---------------------------------------------------------------------------
# 这个项目对 check-action-inputs.sh / check-workflow-contracts.sh 都做了同一件
# 事 —— 造一个恰好含该缺陷的临时树，然后要求门禁**失败**。这里照做，且离线。
self_test() {
	local fix="$WORK/self-test"
	local fails=0

	printf '== 自检：verify_patches 能否区分三种形态\n'

	mkdir -p "$fix/src"
	printf 'alpha\nbeta\ngamma\n' >"$fix/src/f.txt"
	printf 'alpha\ninserted\nbeta\ngamma\n' >"$fix/src/applied.txt"

	# (a) 上下文逐字对得上 —— 必须通过
	cat >"$fix/good.patch" <<'EOF'
--- a/src/f.txt
+++ b/src/f.txt
@@ -1,3 +1,4 @@
 alpha
+inserted
 beta
 gamma
EOF

	# (b) 上游挪了行 —— 必须失败
	cat >"$fix/stale.patch" <<'EOF'
--- a/src/f.txt
+++ b/src/f.txt
@@ -1,3 +1,4 @@
 alpha
 beta
+inserted
 delta
EOF

	# (c) 上游自己加了同一行 —— 必须被判为 Reversed，这是最隐蔽的一种
	cat >"$fix/reversed.patch" <<'EOF'
--- a/src/applied.txt
+++ b/src/applied.txt
@@ -1,3 +1,4 @@
 alpha
+inserted
 beta
 gamma
EOF

	DRIFT_REASONS=()
	verify_patches "$fix" "$fix/good.patch" >/dev/null 2>&1
	if [ "${#DRIFT_REASONS[@]}" -ne 0 ]; then
		printf '  FAIL  一个完全适用的补丁被判成了漂移：%s\n' "${DRIFT_REASONS[0]}" >&2
		fails=$((fails + 1))
	else
		printf '  OK    适用的补丁判为通过\n'
	fi

	DRIFT_REASONS=()
	verify_patches "$fix" "$fix/stale.patch" >/dev/null 2>&1
	if [ "${#DRIFT_REASONS[@]}" -ne 1 ]; then
		printf '  FAIL  上下文对不上的补丁没有被抓到\n' >&2
		fails=$((fails + 1))
	else
		printf '  OK    上下文对不上 → 判为漂移\n'
	fi

	DRIFT_REASONS=()
	verify_patches "$fix" "$fix/reversed.patch" >/dev/null 2>&1
	if [ "${#DRIFT_REASONS[@]}" -ne 1 ]; then
		printf '  FAIL  Reversed 形态没有被抓到（这正是 libnftnl 1.3.2 的形态）\n' >&2
		fails=$((fails + 1))
	elif ! printf '%s' "${DRIFT_REASONS[0]}" | grep -q 'Reversed'; then
		printf '  FAIL  抓到了，但归因错了：%s\n' "${DRIFT_REASONS[0]}" >&2
		fails=$((fails + 1))
	else
		printf '  OK    Reversed → 判为漂移且归因正确\n'
	fi

	if [ "$fails" -ne 0 ]; then
		printf '\n自检失败：%d 项 —— 门禁本身坏了，比没有门禁更坏\n' "$fails" >&2
		return 1
	fi
	printf '\n自检通过\n'
	return 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
WORK="$(mktemp -d)"
cleanup() {
	if [ "$KEEP" -eq 1 ]; then
		printf '保留工作目录：%s\n' "$WORK" >&2
	else
		rm -rf "$WORK"
	fi
}
trap cleanup EXIT

# 自检先跑，且只依赖 patch(1)：它必须能在"什么都没有"的环境里执行，否则
# "门禁本身坏了"这件事就只能在完整环境里才看得出来。
if [ "$SELF_TEST" -eq 1 ]; then
	need patch
	self_test
	exit $?
fi

for c in curl tar patch git sha256sum python3; do need "$c"; done

# REF 必须是本项目真正会对齐的那个上游 head。默认直接问远端，而不是读
# configs/upstream.env 里的 pin：pin 可能落后，而"最新的上游有没有新东西"正是
# 这个脚本要回答的问题。
if [ -z "$REF" ]; then
	# shellcheck disable=SC1091
	. "$ROOT_DIR/configs/upstream.env"
	REF="$(git ls-remote "${OPENWRT_REPO_URL:-https://github.com/openwrt/openwrt.git}" refs/heads/main 2>/dev/null | cut -f1 | head -n1)"
	[ -n "$REF" ] || die "无法解析 openwrt main 的 head（网络？）"
fi

printf '上游参考版本：%s\n' "$REF"
printf '工作目录：%s\n' "$WORK"

check_fullcone_userspace nftables \
	package/network/utils/nftables/Makefile \
	https://netfilter.org/projects/nftables/files/nftables \
	nftables-patches
check_fullcone_userspace libnftnl \
	package/libs/libnftnl/Makefile \
	https://netfilter.org/projects/libnftnl/files/libnftnl \
	libnftnl-patches

check_git_packages firewall4 \
	package/network/config/firewall4/Makefile \
	https://github.com/openwrt/firewall4 \
	firewall4-patches
check_git_packages mt76 \
	package/kernel/mt76/Makefile \
	https://github.com/openwrt/mt76 \
	mt76-patches

check_tree_patches
check_nikki_anchors
check_clash_rs_pin

printf '\n'
if [ "${#DRIFT_REASONS[@]}" -gt 0 ]; then
	printf '%s上游漂移：%d 项%s\n' "$C_RED" "${#DRIFT_REASONS[@]}" "$C_OFF" >&2
	i=0
	for r in "${DRIFT_REASONS[@]}"; do
		i=$((i + 1))
		printf '  %d) %s\n' "$i" "$r" >&2
	done
	printf '\n处置：按上面每条指出的文件重新生成补丁，见 docs/engineering.md 的"上游对齐"一节。\n' >&2
	exit "$EXIT_DRIFT"
fi

if [ "${#UNVERIFIED_REASONS[@]}" -gt 0 ]; then
	printf '%s没能验证：%d 项%s（这不是补丁坏了）\n' "$C_YEL" "${#UNVERIFIED_REASONS[@]}" "$C_OFF" >&2
	for r in "${UNVERIFIED_REASONS[@]}"; do
		printf '  - %s\n' "$r" >&2
	done
	exit "$EXIT_UNVERIFIED"
fi

printf '全部通过：补丁仍适用于上游当前构建的版本，Nikki-RS 锚点与 clash-rs 钉住版本都还在。\n'
