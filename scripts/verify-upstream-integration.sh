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
#   3. **最安静的一种**：补丁打得进去、也真的打上了，但打完的代码编不过。
#      上游 libnftnl 1.3.2 给 `struct expr_ops.set` 加了第 5 个参数
#      （`uint32_t byteorder`），而补丁里 fullcone.c 的 set 仍是 4 个参数：
#      上下文一行不差，`patch` 报 OK，`--dry-run` 也报 OK —— 只有编译器会说话，
#      而它的声音出现在固件构建跑到 libnftnl 的那一刻（v1.1.10 就是这样失败的，
#      一轮 75 分钟）。
#
# 所以这个脚本把"补丁还成不成立"变成一条可自动跑的断言：它按 mainline 当前
# **真正会构建的那些版本**下载源码（nftables / libnftnl 的官方 tarball、
# firewall4 / mt76 的 git 快照），用 `patch -F0 --dry-run` 逐条试；再把 Nikki-RS
# 依赖的三处锚点、clash-rs 钉住版本的资产哈希一起核对。带 `--compile` 时还会把
# 打过补丁的 libnftnl 与 nftables 按**固件自己用的那套 configure 参数**真编一遍；
# 带 `--ebpf-config` 时会把 feed 真正写进 config.yaml 的 ebpf 段喂给钉住的
# clash-rs 核心，用 --strict-config 解析一遍。
#
# 退出码刻意分成两种，因为"补丁坏了"和"没能查到"必须能被区分开：
#
#   0  全部通过
#   1  上游漂移（真问题，要改本仓库的补丁/锚点）
#   2  无法验证（网络/工具缺失 —— 不要把它读成补丁坏了）
#
# Usage:
#   scripts/verify-upstream-integration.sh [--ref <sha|branch>] [--keep] [--compile] [--ebpf-config] [仓库根目录]
#   scripts/verify-upstream-integration.sh --self-test
#
# --compile 需要 gcc / make / pkg-config / flex / bison 与 libmnl、libjansson 的
# 开发头文件。缺件时它报退出码 2（没能验证）而**不是** 0：要求了编译却因缺件
# 静默跳过，正是这个脚本最不想制造的那种假通过。
#
# --ebpf-config 在 Linux x86_64 以外没有意义（钉住的那批资产里只有 x86_64-musl 能
# 在宿主上跑，固件用的 aarch64 跑不了），别处报退出码 2。它在**执行**下载来的
# 二进制之前先核对 sha256 是否等于 pin_clash_rs() 里写死的值 —— 这道检查必须在 CI
# 里跑一个第三方二进制，哈希对不上就不跑。
#
# --self-test 完全离线：它造一个恰好含三种形态（适用 / 上下文对不上 / 已被上游
# 应用）的临时树，然后要求本脚本的判定**如实**区分它们；再复刻上游 22aa500 删掉
# package/network/utils/nftables/patches/ 之后的目录形态，跑一遍 scripts/local-build.sh
# 里的真安装器，要求三层补丁仍然装得进去。一条抓不到缺陷的门禁比没有门禁更坏。
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
COMPILE=0
EBPF_CONFIG=0

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
		--compile)
			COMPILE=1
			shift
			;;
		--ebpf-config)
			EBPF_CONFIG=1
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
	#
	# 退出码三分，因为"哈希不一致"和"根本没比成"必须能被区分开：0 一致、1 漂移、
	# 3 没能验证。实测踩过：Git Bash 里的 python3 会解析到 Windows 商店的"应用
	# 执行别名"桩 —— 它存在、不输出、退出码非 0，于是这里原本会把"检查器没跑起来"
	# 报成"资产哈希与 pin 不一致"，把一次环境问题说成上游换过二进制。
	local rc=0
	python3 -X utf8 - "$WORK/clash-rs-$tag.json" "$WORK/clash-rs-pairs.txt" "$tag" <<'PY' || rc=$?
import json
import sys

release_path, pairs_path, tag = sys.argv[1], sys.argv[2], sys.argv[3]

def cannot_verify(msg):
    print("  ??    %s" % msg)
    sys.exit(3)

try:
    release = json.load(open(release_path, encoding="utf-8"))
except Exception as exc:  # noqa: BLE001
    cannot_verify("读不了 release JSON（%s）" % exc)

assets = {a["name"]: a for a in release.get("assets", [])}
if not assets:
    cannot_verify("%s 的资产清单是空的" % tag)

expected = []
for line in open(pairs_path, encoding="utf-8"):
    line = line.strip()
    if not line or "=" not in line:
        continue
    name, digest = line.split("=", 1)
    expected.append((name, digest))

if not expected:
    cannot_verify("没从 pin_clash_rs() 里解析出任何期望哈希")

bad = 0
for name, want in expected:
    asset = assets.get(name)
    if asset is None:
        print("  FAIL  %s 不在 %s 的资产清单里（release 被撤下或资产改名）" % (name, tag))
        bad += 1
        continue
    got = (asset.get("digest") or "").removeprefix("sha256:")
    if not got:
        # 这个字段是 API 后来才加的，老资产可能没有。没有它就无从比对，
        # 那是"没能验证"，不是"哈希不一致"。
        cannot_verify("%s 在 API 里没有 digest" % name)
    if got != want:
        print("  FAIL  %s\n        期望 sha256:%s\n        实际 sha256:%s" % (name, want, got))
        bad += 1
        continue
    print("  OK    %s sha256 与 pin_clash_rs() 一致" % name)

sys.exit(1 if bad else 0)
PY
	case "$rc" in
	0) : ;;
	1) drift "clash-rs ${tag} 的资产哈希与 pin_clash_rs() 里写死的不一致（详见上方逐条输出）。" ;;
	*) unverified "clash-rs 的资产核对没跑起来（python3 退出码 $rc）—— 这不是哈希不一致，别读成漂移。" ;;
	esac
	return 0
}

# ---------------------------------------------------------------------------
# 6) feed 会写的 eBPF 字段，钉住的核心都认得吗
# ---------------------------------------------------------------------------
# 文本级核对看得见"钉住了哪个版本"，看不见"那个版本听不听得懂 feed 说的话"。
# feed 的 nikki-rs/files/ucode/mixin.uc 在 ebpf 开启时会把一整段 ebpf.* 写进
# config.yaml，而 clash-rs 默认**静默忽略**不认识的字段（它自己的 --help 就写着：
# 为了让别的客户端共享的配置也能加载）。于是"feed 加了字段、钉住的核心还不认识"
# 在设备上的表现是"配了但不生效"，不是报错 —— 最难查的那一类。
#
# 这里把 feed 的 ebpf 段抓下来，喂给钉住的二进制用 --strict-config 解析一遍。
# 两个细节不能省：
#   * 值不按 feed 原样给。这道检查只问字段名认不认识，而 enable: true 会连带
#     触发端口/MAC 之类的取值校验 —— 那是另一件事，也是假漂移的来源。
#   * 必须有反向对照：同一份配置再加一个编造字段，要求它**被拒绝**。否则万一
#     strict 模式没生效，这道检查会永远通过，而永远通过的检查比没有检查更糟。
check_clash_rs_ebpf_fields() {
	printf '\n== clash-rs 的 eBPF 字段\n'

	if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
		unverified "eBPF 字段核对要 Linux x86_64（本机 $(uname -s)/$(uname -m)）：钉住的这批资产里只有 x86_64-musl 能在宿主上跑"
		return 0
	fi

	local body want_url tag asset want
	body="$(sed -n '/^pin_clash_rs()/,/^}/p' "$ROOT_DIR/scripts/local-build.sh")"
	want_url="$(printf '%s\n' "$body" | sed -n 's/.*local want_url="\([^"]*\)".*/\1/p' | head -n1)"
	if [ -z "$want_url" ]; then
		unverified "从 pin_clash_rs() 里读不出 want_url"
		return 0
	fi
	tag="$(basename "$want_url")"
	asset="clash-rs-minimal-x86_64-unknown-linux-musl.tar.gz"
	want="$(printf '%s\n' "$body" | sed -n 's/.*local x86_64_h="\([^"]*\)".*/\1/p' | head -n1)"
	if [ -z "$want" ]; then
		unverified "从 pin_clash_rs() 里读不出 x86_64_h"
		return 0
	fi
	log "钉住的核心：${tag} 的 ${asset}"

	if ! curl_retry "https://github.com/CHKayanami/clash-rs/releases/download/$tag/$asset" \
		-o "$WORK/$asset"; then
		drift "取不到 clash-rs ${tag} 的 ${asset} —— 核心无从核对，pin_clash_rs 也会 404。"
		return 0
	fi

	# 执行之前先对哈希：这道检查要在 CI 里跑一个第三方二进制，只有哈希与
	# pin_clash_rs() 里写死的一致才允许跑。
	local got
	got="$(sha256sum "$WORK/$asset" | awk '{print $1}')"
	if [ "$got" != "$want" ]; then
		drift "${asset} 的 sha256 与 pin_clash_rs() 不一致（期望 ${want}，实际 ${got}）—— 不执行它。"
		return 0
	fi

	rm -rf "$WORK/clash-rs"
	mkdir -p "$WORK/clash-rs"
	if ! tar -xzf "$WORK/$asset" -C "$WORK/clash-rs"; then
		unverified "解不开 ${asset}"
		return 0
	fi
	local bin
	bin="$(find "$WORK/clash-rs" -type f -name 'clash-rs' | head -n1)"
	if [ -z "$bin" ]; then
		unverified "${asset} 里找不到 clash-rs 可执行文件"
		return 0
	fi
	chmod +x "$bin"

	# 判据本身要先验一遍：没有 --strict-config 就没有这道检查。
	"$bin" --help >"$WORK/clash-rs-help.txt" 2>&1 || true
	if ! grep -q -- '--strict-config' "$WORK/clash-rs-help.txt"; then
		unverified "钉住的这个版本不认识 --strict-config —— 判据变了，这道检查没法进行"
		return 0
	fi

	if ! curl_retry "$NIKKI_RAW/nikki-rs/files/ucode/mixin.uc" -o "$WORK/mixin.uc"; then
		unverified "取不到 Nikki-RS 的 mixin.uc"
		return 0
	fi

	local rc=0
	python3 -X utf8 - "$WORK/mixin.uc" "$WORK/ebpf.yaml" "$WORK/ebpf-bogus.yaml" \
		"$WORK/ebpf-keys.txt" <<'PY' || rc=$?
import re
import sys

src_path, ok_path, bogus_path, keys_path = sys.argv[1:5]
src = open(src_path, encoding="utf-8").read()

m = re.search(r"config\['ebpf'\]\s*=\s*\{", src)
if not m:
    print("找不到 config['ebpf'] = { ... } 段", file=sys.stderr)
    sys.exit(3)

depth, i = 1, m.end()
while i < len(src) and depth:
    if src[i] == "{":
        depth += 1
    elif src[i] == "}":
        depth -= 1
    i += 1
if depth:
    print("ebpf 段的大括号没配平", file=sys.stderr)
    sys.exit(3)
block = src[m.end():i - 1]


def sample(key, expr):
    """按 feed 用的 uci_* 辅助函数给一个类型正确的占位值。

    只给字段名，不给真实取值：这道检查问的是"认不认识这个字段"。
    """
    if key == "enable":
        return False           # 关掉连带的取值校验，见上面的注释
    if "uci_bool(" in expr:
        return False
    if "uci_int(" in expr:
        return 12345
    if any(h in expr for h in ("uci_ports(", "uci_dscps(", "uci_fwmarks(", "uci_array(")):
        return []
    if "uci.get(" in expr:
        return ""
    return []


root = {}
stack = [root]
names = [""]
paths = []
for line in block.splitlines():
    line = line.strip()
    if not line:
        continue
    mo = re.match(r"^'([A-Za-z0-9_-]+)'\s*:\s*\{\s*$", line)
    if mo:
        child = {}
        stack[-1][mo.group(1)] = child
        stack.append(child)
        names.append(names[-1] + mo.group(1) + ".")
        continue
    if re.match(r"^\},?\s*$", line):
        if len(stack) > 1:
            stack.pop()
            names.pop()
        continue
    mo = re.match(r"^'([A-Za-z0-9_-]+)'\s*:\s*(.+?),?\s*$", line)
    if not mo:
        continue
    key, expr = mo.group(1), mo.group(2)
    stack[-1][key] = sample(key, expr)
    paths.append(names[-1] + key)

if not paths:
    print("ebpf 段里一个字段都没解析出来", file=sys.stderr)
    sys.exit(3)


def emit(d, indent):
    pad = "  " * indent
    out = []
    for k, v in d.items():
        if isinstance(v, dict):
            out.append("%s%s:" % (pad, k))
            out.extend(emit(v, indent + 1))
        elif isinstance(v, bool):
            out.append("%s%s: %s" % (pad, k, "true" if v else "false"))
        elif isinstance(v, int):
            out.append("%s%s: %d" % (pad, k, v))
        elif isinstance(v, str):
            out.append('%s%s: "%s"' % (pad, k, v))
        else:
            out.append("%s%s: []" % (pad, k))
    return out


open(ok_path, "w", encoding="utf-8").write("\n".join(["ebpf:"] + emit(root, 1)) + "\n")

# 反向对照：同一个 ebpf 段里塞一个编造的字段，strict 模式必须拒绝它。
bogus = dict(root)
bogus["__h5000m_must_reject"] = 1
open(bogus_path, "w", encoding="utf-8").write("\n".join(["ebpf:"] + emit(bogus, 1)) + "\n")
open(keys_path, "w", encoding="utf-8").write("\n".join(paths) + "\n")

print("  feed 的 ebpf 段解出 %d 个字段：" % len(paths))
for p in paths:
    print("    - " + p)
PY
	case "$rc" in
	0) : ;;
	*)
		unverified "没能从 mixin.uc 里抽出 ebpf 段（python3 退出码 ${rc}）"
		return 0
		;;
	esac

	if ! "$bin" -t -f "$WORK/ebpf.yaml" --strict-config >"$WORK/ebpf-check.log" 2>&1; then
		drift "feed 写的 eBPF 字段里有钉住的核心不认识的：$(tr '\n' ' ' <"$WORK/ebpf-check.log" | cut -c1-320)"
		return 0
	fi
	log "OK    上面这些字段，钉住的核心在 --strict-config 下全部接受"

	if "$bin" -t -f "$WORK/ebpf-bogus.yaml" --strict-config >"$WORK/ebpf-control.log" 2>&1; then
		unverified "反向对照失败：编造的字段也被接受了，说明 --strict-config 没在把关，这道检查会永远通过"
		return 0
	fi
	log "OK    反向对照：编造的字段被拒绝（strict 模式确实在把关）"
	return 0
}

# ---------------------------------------------------------------------------
# 7) 编译验证：打得进去不等于编得出来
# ---------------------------------------------------------------------------
# 这一节的由来（v1.1.10，run 38984193085）：libnftnl 1.3.2 给 struct expr_ops.set
# 加了第 5 个参数（uint32_t byteorder），而本仓库补丁里 fullcone.c 的 set 还是
# 4 个参数。补丁的上下文一行不差，于是 patch 与 --dry-run 都报 OK —— 唯一会说话
# 的是编译器，而它的话出现在 75 分钟的固件构建末尾。
#
# 这里用宿主 gcc 把那两层真编一遍，configure 参数**照抄固件自己用的那一套**
# （openwrt 的 package/network/utils/nftables/Makefile 与 package/libs/libnftnl/
# Makefile），这样编到的源文件与走到的条件编译分支都尽量贴近真实构建。它不替代
# 固件构建（架构与工具链都不同），但"函数指针类型不匹配""符号未定义"这类错误与
# 架构无关，正是这一节要抓的东西。
#
# 为什么不给这一节写自检：它的判定器是编译器本身，不是本脚本写的启发式。真正要防
# 的是"要求了编译却静默跳过"，所以缺件一律走 unverified（退出码 2），绝不走通过。
compile_userspace() {
	local -a missing=()
	local c

	for c in gcc make pkg-config flex bison; do
		command -v "$c" >/dev/null 2>&1 || missing+=("$c")
	done
	pkg-config --exists libmnl 2>/dev/null || missing+=("libmnl 开发头文件")
	pkg-config --exists jansson 2>/dev/null || missing+=("libjansson 开发头文件")

	if [ "${#missing[@]}" -gt 0 ]; then
		unverified "--compile 需要这些，而环境里没有：${missing[*]}"
		return 0
	fi

	local ver_lb ver_nft
	ver_lb="$(pkgvar package/libs/libnftnl/Makefile PKG_VERSION)"
	ver_nft="$(pkgvar package/network/utils/nftables/Makefile PKG_VERSION)"
	if [ -z "$ver_lb" ] || [ -z "$ver_nft" ]; then
		unverified "读不到 libnftnl / nftables 的 PKG_VERSION，没法决定编哪个版本"
		return 0
	fi

	printf '\n== 编译验证：libnftnl %s 与 nftables %s，打完本仓库的补丁还编得过吗\n' \
		"$ver_lb" "$ver_nft"

	# 两行分开写：同一个 local 里的展开发生在 builtin 执行之前，写成
	# `local base=... prefix="$base/..."` 在 set -u 下会直接以 unbound variable 崩掉。
	local base="$WORK/compile"
	local prefix="$base/prefix"

	compile_layer libnftnl "$base/libnftnl" libnftnl-patches "$prefix" "$WORK/libnftnl" || return 0
	# nftables 要用**打过补丁的** libnftnl：NFTNL_EXPR_FULLCONE_* 就定义在它的
	# 头文件里。先把 libnftnl 装进 prefix，再让 nftables 通过 pkg-config 找到它，
	# 否则编的是 pacify 过的上游头文件，"编过了"毫无意义。
	PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
		LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
		compile_layer nftables "$base/nftables" nftables-patches "$prefix" "$WORK/nftables" || return 0
	return 0
}

# compile_layer <名字> <工作目录> <补丁目录> <prefix> <已解包的 pristine 树>
compile_layer() {
	local name="$1" dir="$2" patchdir="$3" prefix="$4" pristine="$5"
	local p rc n=0 out log="$WORK/$name.build.log"
	local -a patches=() cfg=()

	if [ ! -d "$pristine" ]; then
		unverified "$name 的源码这一次没解包成功，跳过它的编译验证"
		return 0
	fi

	rm -rf "$dir"
	mkdir -p "$dir" "$prefix"
	cp -a "$pristine/." "$dir/"

	shopt -s nullglob
	patches=("$ROOT_DIR/$patchdir"/*.patch)
	shopt -u nullglob
	if [ "${#patches[@]}" -eq 0 ]; then
		unverified "$patchdir 里没有补丁，编译验证无从谈起"
		return 0
	fi

	# 这里必须**真打**：上面 verify_patches 只做了 dry-run，不真改文件就编不到
	# 补丁引入的代码，这一节也就白跑了。
	for p in "${patches[@]}"; do
		rc=0
		out="$(cd "$dir" && patch -p1 -F0 --forward --batch <"$p" 2>&1)" || rc=$?
		if [ "$rc" -ne 0 ]; then
			printf '%s\n' "$out" | sed 's/^/        /' >&2
			drift "$name：$(basename "$p") 在编译验证里打不上 —— 同一棵树刚刚 dry-run 却过了，说明这期间上游动了，或磁盘上的树被改过。"
			return 0
		fi
		n=$((n + 1))
	done

	# 固件自己用的参数（见 openwrt 的两个包 Makefile）。--with-json 是
	# nftables-json=y 那一支；--with-mini-gmp/--without-cli 让宿主不需要
	# libgmp 与 libedit，同时与固件编的是同一批源文件。
	case "$name" in
	libnftnl)
		cfg=(--enable-static --enable-shared)
		;;
	nftables)
		cfg=(--disable-debug --disable-man-doc --with-mini-gmp --without-cli --with-json)
		;;
	esac

	log "$name：真打了 $n 个补丁，按固件的 configure 参数编译"

	if ! (cd "$dir" && ./configure --prefix="$prefix" "${cfg[@]}" >"$log" 2>&1); then
		tail -n 25 "$log" | sed 's/^/        /' >&2
		unverified "$name 的 configure 没跑通（宿主缺依赖？），编译验证没能进行"
		return 0
	fi

	# 补丁改的是 src/scanner.l 与 src/parser_bison.y，打完它们的 mtime 比 tarball
	# 里预生成的 .c 新，make 一定会重新生成解析器 —— 所以 flex/bison 是硬依赖，
	# 而这也顺带把语法本身查了一遍（固件那一次构建同样走了这一步）。
	if ! (cd "$dir" && make -j"$(nproc 2>/dev/null || echo 2)" >>"$log" 2>&1); then
		local errs first
		errs="$(grep -nE ': (error|fatal error):|undefined reference|No rule to make target' "$log" | head -n 12 || true)"
		if [ -n "$errs" ]; then
			printf '%s\n' "$errs" | sed 's/^/        /' >&2
			first="$(printf '%s\n' "$errs" | head -n1 | sed 's/^[0-9]*://' | cut -c1-200)"
			drift "$name：补丁打得上，但打完编不过 —— $first"
		else
			tail -n 25 "$log" | sed 's/^/        /' >&2
			drift "$name：打完补丁 make 失败，而日志里没有一行 error（用 --keep 保留完整日志）"
		fi
		return 0
	fi
	log "$name：编译通过"

	if [ "$name" = libnftnl ]; then
		if ! (cd "$dir" && make install >>"$log" 2>&1); then
			unverified "$name 编译过了，但 make install 失败 —— nftables 那一层要用它打过补丁的头文件"
			return 0
		fi
		log "$name：已装入 $prefix（给 nftables 用）"
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

	printf '\n'
	self_test_installer
	fails=$((fails + INSTALLER_FAILS))

	if [ "$fails" -ne 0 ]; then
		printf '\n自检失败：%d 项 —— 门禁本身坏了，比没有门禁更坏\n' "$fails" >&2
		return 1
	fi
	printf '\n自检通过\n'
	return 0
}

# ---------------------------------------------------------------------------
# 自检：补丁安装器会不会因为上游删掉一个目录就静默什么都不装
# ---------------------------------------------------------------------------
# 这不是假想的形态。上游把 nftables 升到 1.1.7 之后删掉了
# package/network/utils/nftables/patches/，而安装器当时拿这个**上游自己的**目录
# 当开关：
#
#   [ -d "$dir" ] || { warn "No nftables patches directory"; return 0; }
#
# 目录一没，三层补丁（firewall4 / libnftnl / nftables）一个都没装，只留一条
# 警告。1.1.9 的构建于是在它自己的 fullcone 校验上失败：
#
#   FAIL  firewall4 accepts fullcone in its parse_defaults whitelist
#   FAIL  zone-masq.uc emits fullcone instead of masquerade
#   FAIL  ruleset.uc adds the prerouting fullcone rules
#
# 两个构建实际解析到的上游版本就是这条分界线（都在 track=latest 上）：
#
#   a5c93cd  1.1.8  package/network/utils/nftables -> Makefile, patches
#   22aa500  1.1.9  package/network/utils/nftables -> Makefile
#
# 这里跑的是 scripts/local-build.sh 里的**真函数**：把判断逻辑复制一份进自检，
# 它会随实现一起漂移，而这次要防的恰恰是实现本身。
INSTALLER_FAILS=0
self_test_installer() {
	local fix="$WORK/self-test-installer"
	local fn="$fix/install.sh"
	local fake="$fix/root"
	local layer name srcdir dstdir src_n dst_n rc

	# `|| true` 不是防御性写法：这两个计数会去看一个**故意不存在**的目录，而
	# set -Eeuo pipefail 会把 find 的退出码算到赋值头上，静默中断整个自检。
	count_patches() {
		local n
		n=$(find "$1" -maxdepth 1 -name '*.patch' 2>/dev/null | wc -l || true)
		printf '%s' "${n// /}"
	}

	mkdir -p "$fix/src/package/network/utils/nftables" \
		"$fix/src/package/libs/libnftnl" \
		"$fix/src/package/network/config/firewall4"
	printf 'PKG_VERSION:=1.1.7\n' >"$fix/src/package/network/utils/nftables/Makefile"
	printf 'PKG_VERSION:=1.3.2\n' >"$fix/src/package/libs/libnftnl/Makefile"
	printf 'PKG_VERSION:=1\n' >"$fix/src/package/network/config/firewall4/Makefile"

	sed -n '/^install_nftables_patches()/,/^}$/p' "$ROOT_DIR/scripts/local-build.sh" >"$fn"
	if [ ! -s "$fn" ]; then
		printf '  FAIL  没能从 scripts/local-build.sh 取出 install_nftables_patches\n' >&2
		INSTALLER_FAILS=$((INSTALLER_FAILS + 1))
		return 0
	fi

	printf '== 自检：上游没有 patches/ 目录时，三层补丁还装得进去吗\n'
	rc=0
	(
		SRC="$fix/src"
		. "$fn"
		install_nftables_patches
	) >"$fix/install.log" 2>&1 || rc=$?
	if [ "$rc" -ne 0 ]; then
		printf '  FAIL  安装器在上游无 patches/ 时退出 %s：%s\n' \
			"$rc" "$(tail -n1 "$fix/install.log")" >&2
		INSTALLER_FAILS=$((INSTALLER_FAILS + 1))
	fi

	for layer in \
		"firewall4:firewall4-patches:package/network/config/firewall4/patches" \
		"libnftnl:libnftnl-patches:package/libs/libnftnl/patches" \
		"nftables:nftables-patches:package/network/utils/nftables/patches"; do
		name="${layer%%:*}"
		srcdir="${layer#*:}"
		srcdir="${srcdir%%:*}"
		dstdir="${layer##*:}"
		src_n=$(count_patches "$ROOT_DIR/$srcdir")
		dst_n=$(count_patches "$fix/src/$dstdir")
		if [ "$src_n" -gt 0 ] && [ "$dst_n" = "$src_n" ]; then
			printf '  OK    %s：%s 个补丁都装上了\n' "$name" "$dst_n"
		else
			printf '  FAIL  %s：本仓库有 %s 个，目标目录只有 %s 个\n' "$name" "$src_n" "$dst_n" >&2
			INSTALLER_FAILS=$((INSTALLER_FAILS + 1))
		fi
	done

	# 反过来：本仓库自己少了一层补丁时必须**拒绝构建**，而不是装半套就出货。
	mkdir -p "$fake/firewall4-patches" "$fake/libnftnl-patches" "$fake/nftables-patches"
	cp "$ROOT_DIR"/firewall4-patches/*.patch "$fake/firewall4-patches/" 2>/dev/null || true
	cp "$ROOT_DIR"/libnftnl-patches/*.patch "$fake/libnftnl-patches/" 2>/dev/null || true
	rm -rf "$fix/src2"
	cp -r "$fix/src" "$fix/src2"
	rc=0
	(
		SRC="$fix/src2"
		ROOT_DIR="$fake"
		. "$fn"
		install_nftables_patches
	) >"$fix/refuse.log" 2>&1 || rc=$?
	if [ "$rc" -ne 0 ]; then
		printf '  OK    少一层补丁时拒绝构建\n'
	else
		printf '  FAIL  少一层补丁时安装器仍然成功退出，会静默出货\n' >&2
		INSTALLER_FAILS=$((INSTALLER_FAILS + 1))
	fi

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

# 只看 command -v 是不够的：Windows 上 python3 常常解析到 Microsoft Store 的
# "应用执行别名"桩，它存在、没有任何输出、退出码非 0。这样的 python3 会让下面
# 那段校验悄悄不执行，而 if ! 会把它翻成"资产哈希不一致"——一次环境问题被说成
# 上游换过二进制。所以先让它真的算一下。这里走 die（退出码 2）：整轮核对都没法
# 进行时，报"没能验证"才是诚实的。
if ! python3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
	die "python3 存在但不能用（Windows 商店的应用执行别名桩？）—— 换成真的解释器再跑"
fi

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
if [ "$EBPF_CONFIG" -eq 1 ]; then
	check_clash_rs_ebpf_fields
fi

if [ "$COMPILE" -eq 1 ]; then
	compile_userspace
fi

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
