#!/usr/bin/env bash
#
# local-build.sh — build mainline OpenWrt for the Hiveton H5000M.
#
# This is the migrated successor of existyay/Auto-H5000M-BIN's local-build.sh.
# The pipeline, the CLI, the ENABLE_* switch names and the artifact layout are
# kept deliberately familiar; what changed is the upstream (ImmortalWrt ->
# openwrt/openwrt) and the H5000M feature stack (QModem/ModemManager ->
# ddimension/wwand, luci-app-Airpifanctrl -> luci-app-h5000m-fancontrol).
#
# Usage: see `scripts/local-build.sh --help`.
#
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Upstream baseline (repo, branch, pinned revision, target triple).
# shellcheck source=../configs/upstream.env
. "${ROOT_DIR}/configs/upstream.env"

# ---------------------------------------------------------------- knobs ------
REPO_URL="${REPO_URL:-${OPENWRT_REPO_URL}}"
REPO_BRANCH="${REPO_BRANCH:-${OPENWRT_REPO_BRANCH}}"
SOURCE_DIR="${SOURCE_DIR:-openwrt}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-artifacts}"
THREADS="${THREADS:-$(nproc 2>/dev/null || echo 2)}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-300}"

TARGET_BOARD="${OPENWRT_TARGET}"
TARGET_SUBTARGET="${OPENWRT_SUBTARGET}"
TARGET_PROFILE="${OPENWRT_PROFILE}"
TARGET_ARCH="${OPENWRT_ARCH}"
IMAGE_PREFIX="${OPENWRT_IMAGE_PREFIX}"

# Upstream tracking: `latest` follows the branch head (the point of a scheduled
# auto-build); `pinned` builds the revision this harness was validated against.
OPENWRT_TRACK="${OPENWRT_TRACK:-latest}"

GIT_TIMEOUT="${GIT_TIMEOUT:-1800}"
FEEDS_TIMEOUT="${FEEDS_TIMEOUT:-3600}"
CONFIG_TIMEOUT="${CONFIG_TIMEOUT:-1800}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-7200}"
TOOLCHAIN_TIMEOUT="${TOOLCHAIN_TIMEOUT:-7200}"
COMPILE_TIMEOUT="${COMPILE_TIMEOUT:-28800}"

# Download accelerators — the same defaults the previous harness used; they are
# harmless outside mainland China and can be overridden to the empty string.
GOPROXY="${GOPROXY:-https://goproxy.cn,https://proxy.golang.org,direct}"
GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"
DOWNLOAD_MIRROR="${DOWNLOAD_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/openwrt/sources;https://mirrors.ustc.edu.cn/openwrt/sources;https://mirrors.bfsu.edu.cn/openwrt/sources}"
export GOPROXY GOSUMDB DOWNLOAD_MIRROR
export MAKEFLAGS="-j${THREADS}"

# ----------------------------------------------------------- H5000M stack ----
# Fan control — luci-app-h5000m-fancontrol (userspace PWM policy; the tree
# patch in patches/ removes the three kernel cooling maps that would race it).
ENABLE_FANCONTROL="${ENABLE_FANCONTROL:-true}"

# Egress priority — luci-app-h5000m-netmode arbitrates wired WAN vs cellular.
ENABLE_NETMODE="${ENABLE_NETMODE:-true}"

# WWAN dialer — ddimension/wwand.  The H5000M's built-in TD Tech MT5700M
# (3466:3301, cdc_ncm) is dialled by wwand-ncm; the other backends cover QMI,
# MBIM and PCIe/MHI modules in the USB and M.2 slots.
ENABLE_WWAND="${ENABLE_WWAND:-true}"

# luci-app-mt5700m — FAN789's panel + NCM/DHCP dialer for the same module.
# MUTUALLY EXCLUSIVE with wwand on the data path: both would drive the MT5700M's
# cdc_ncm data interface and both want to own network.MT5700M.  Enabling it
# turns wwand off (see resolve_modem_stack).  It is also the only source of the
# modem temperature cache luci-app-h5000m-fancontrol reads, so a box that wants
# module temperature in the fan curve should pick this and give up wwand.
ENABLE_MT5700M="${ENABLE_MT5700M:-false}"

# ------------------------------------------------------- optional services ---
ENABLE_UPNP="${ENABLE_UPNP:-true}"
ENABLE_ADBLOCK="${ENABLE_ADBLOCK:-true}"
ENABLE_DOCKERMAN="${ENABLE_DOCKERMAN:-false}"
ENABLE_NIKKI="${ENABLE_NIKKI:-false}"
ENABLE_OPENCLASH="${ENABLE_OPENCLASH:-false}"
# Built into the image by default, matching the workflow.  A default that
# differs between a local build and CI produces two different firmwares from the
# same commit, which is worse than either choice on its own.
ENABLE_MOSDNS="${ENABLE_MOSDNS:-true}"
# Built into the image by default.  Unlike the other proxy front-ends, which are
# compiled into the apk repository as =m so a user can install them later, this
# one is on: it needs no separate core package to be useful and is the front-end
# this device is expected to ship with.
ENABLE_HOMEPROXY="${ENABLE_HOMEPROXY:-true}"

# Mesh.  lean's luci-app-easymesh is not the OpenWrt easymesh daemon — mainline
# dropped that package.  Its LUCI_DEPENDS are kmod-cfg80211, batctl-default,
# kmod-batman-adv and dawn, i.e. a DAWN + batman-adv mesh, all of which ARE in
# the official feeds.  So this is a front-end to software mainline already has,
# not a port of something removed.
ENABLE_EASYMESH="${ENABLE_EASYMESH:-true}"
ENABLE_ADGUARDHOME="${ENABLE_ADGUARDHOME:-false}"

# Build the service packages into the apk repository even when they are not
# installed into the image.  On by default: the whole point is that a user can
# `apk add luci-app-dockerman` on the running router instead of having every
# option baked into the firmware.  Turn it off for a fast iteration build — it
# costs real time, because the Docker and proxy stacks are large Go programs.
ENABLE_REPO_PACKAGES="${ENABLE_REPO_PACKAGES:-true}"

# Clone and build the third-party proxy frontends (PassWall, PassWall2, Momo,
# fcshark, NeKoBox, luci-xray, Daed, HiJpass) alongside the ones already handled.
# They are built into the apk repository as =m, never installed into the image.
# Turn off together with ENABLE_REPO_PACKAGES for a fast iteration build — these
# pull in a lot of Go compilation.
ENABLE_PROXY_REPOS="${ENABLE_PROXY_REPOS:-true}"

# ------------------------------------------------- first-boot product setup ---
# Applied once by /usr/sbin/h5000m-firstboot (uci-defaults + ieee80211 hotplug)
# and written into the image as /etc/h5000m-defaults.conf.
#
# WiFi: a freshly flashed OpenWrt leaves every radio disabled until someone logs
# in and picks a country, which reads as "WiFi does not work" on a 5G CPE.  The
# defaults below turn both radios on with one shared SSID.  CHANGE THE KEY
# before flashing anything you care about.
H5000M_WIFI_SSID="${H5000M_WIFI_SSID:-openwrt}"
# No password by default.  Encryption is `none` and there is no key, so the
# first boot brings up an open network: a fresh device is reachable without
# anyone having to know a credential that is printed nowhere.  Owners are
# expected to set their own; the first-boot script never overwrites an SSID that
# has already been changed.
H5000M_WIFI_KEY="${H5000M_WIFI_KEY:-}"
H5000M_WIFI_COUNTRY="${H5000M_WIFI_COUNTRY:-CN}"
H5000M_WIFI_ENCRYPTION="${H5000M_WIFI_ENCRYPTION:-none}"
H5000M_WIFI_HTMODE_2G="${H5000M_WIFI_HTMODE_2G:-EHT40}"
H5000M_WIFI_HTMODE_5G="${H5000M_WIFI_HTMODE_5G:-EHT160}"

# Hardware acceleration.  On mainline this is the netfilter flowtable offload
# driving the MTK PPE — the same hardware the vendor's TurboACC/hnat panel
# controls, reached through a different interface.  fw4 defaults both options to
# "0" and the stock firewall config sets neither, so nothing happens until they
# are turned on.  flow_offloading is software, flow_offloading_hw is the PPE.
H5000M_FLOW_OFFLOAD="${H5000M_FLOW_OFFLOAD:-1}"
H5000M_FLOW_OFFLOAD_HW="${H5000M_FLOW_OFFLOAD_HW:-1}"

# Base URL of this project's own apk repository, published as the apk-repo/
# build artifact.  It is baked into the firmware as
# /etc/apk/repositories.d/50-h5000m.list so the service packages (built as =m,
# not installed) and every kmod can be installed on the running router.
#
# Empty by default, and that default is deliberate.  An earlier revision derived
# a GitHub Pages URL from the repository name and baked it in unconditionally;
# the repository did not exist, so every device shipped with a source entry that
# 404'd and `apk update` reported "wget: exited with error 8" against it.  A
# source that cannot be reached is worse than no source at all: it makes the
# package manager look broken and hides the entries that do work.
#
# scripts/serve-apk-repo.sh serves artifacts/apk-repo/ over HTTP and prints the
# exact value to build with, which is the quickest way to a working setup.
H5000M_APK_REPO_URL="${H5000M_APK_REPO_URL:-}"

# --------------------------------------------------------------------- UI ----
# Argon is the theme the H5000M builds in the wild use, and it is not in any
# mainline feed, so it has to be cloned in.  Installing it is sufficient to make
# it the active theme: the package ships
# root/etc/uci-defaults/30_luci-theme-argon, which sets luci.main.mediaurlbase.
# luci-app-argon-config is its settings page and is useless without the theme.
ENABLE_THEME_ARGON="${ENABLE_THEME_ARGON:-true}"
ARGON_THEME_REPO_URL="${ARGON_THEME_REPO_URL:-https://github.com/jerrykuku/luci-theme-argon.git}"
ARGON_THEME_REPO_BRANCH="${ARGON_THEME_REPO_BRANCH:-master}"
ARGON_CONFIG_REPO_URL="${ARGON_CONFIG_REPO_URL:-https://github.com/jerrykuku/luci-app-argon-config.git}"
ARGON_CONFIG_REPO_BRANCH="${ARGON_CONFIG_REPO_BRANCH:-master}"

# ------------------------------------------------------------- run modes -----
INSTALL_DEPS=false
PREPARE_ONLY="${PREPARE_ONLY:-false}"
CONFIG_ONLY="${CONFIG_ONLY:-false}"
SKIP_TOOLCHAIN="${SKIP_TOOLCHAIN:-false}"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"
SKIP_FEEDS_UPDATE="${SKIP_FEEDS_UPDATE:-false}"
FORCE_PINNED=false

SRC="${ROOT_DIR}/${SOURCE_DIR}"
ART="${ROOT_DIR}/${ARTIFACTS_DIR}"
LOG_FILE="${ROOT_DIR}/build.log"

usage() {
	cat <<'EOF'
Usage: scripts/local-build.sh [options]

Builds mainline OpenWrt (openwrt/openwrt, branch `main`) for the
Hiveton H5000M (mediatek/filogic, profile hiveton_h5000m).

Options:
  --install-deps        Install build dependencies (apt-get, or pacman on Arch).
  --prepare-only        Clone/update source, feeds, patches and local packages, then stop.
  --config-only         Additionally run defconfig and verify the package set, then stop.
  --pinned              Build OPENWRT_PINNED_REVISION instead of the branch head.
  --skip-toolchain      Skip the explicit `make toolchain/install` prebuild step.
  --skip-download       Skip `make download` prefetch.
  --skip-feeds-update   Reuse the existing feeds checkout (no ./scripts/feeds update).
  -h, --help            Show this help.

Feature switches are environment variables, e.g.

  ENABLE_MT5700M=true ENABLE_WWAND=false THREADS=8 scripts/local-build.sh
  ENABLE_NIKKI=true ENABLE_ADBLOCK=false scripts/local-build.sh

Board stack (defaults):
  ENABLE_FANCONTROL=true   luci-app-h5000m-fancontrol + userspace fan DTS patch
  ENABLE_NETMODE=true      luci-app-h5000m-netmode (wired WAN / 5G priority)
  ENABLE_WWAND=true        ddimension/wwand dialer (QMI/MBIM/NCM/MHI)
  ENABLE_MT5700M=false     luci-app-mt5700m instead of wwand (mutually exclusive)

Optional services (defaults):
  ENABLE_UPNP=true ENABLE_ADBLOCK=true
  ENABLE_DOCKERMAN=false
  ENABLE_NIKKI=false ENABLE_OPENCLASH=false ENABLE_MOSDNS=false
  ENABLE_HOMEPROXY=false ENABLE_ADGUARDHOME=false
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--install-deps) INSTALL_DEPS=true ;;
		--prepare-only) PREPARE_ONLY=true ;;
		--config-only) CONFIG_ONLY=true ;;
		--pinned) FORCE_PINNED=true; OPENWRT_TRACK=pinned ;;
		--skip-toolchain) SKIP_TOOLCHAIN=true ;;
		--skip-download) SKIP_DOWNLOAD=true ;;
		--skip-feeds-update) SKIP_FEEDS_UPDATE=true ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
	esac
	shift
done

# ------------------------------------------------------------- logging -------
log()  { printf '\033[1;34m[h5000m]\033[0m %s\n' "$*" | tee -a "$LOG_FILE"; }
warn() { printf '\033[1;33m[h5000m:warn]\033[0m %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
die()  { printf '\033[1;31m[h5000m:error]\033[0m %s\n' "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

is_true() {
	case "${1,,}" in
		1|true|yes|y|on) return 0 ;;
		*) return 1 ;;
	esac
}

run_with_timeout() {
	local timeout_s="$1"; shift
	if command -v timeout >/dev/null 2>&1; then
		timeout --foreground -k 30 "$timeout_s" "$@"
	else
		"$@"
	fi
}

# --------------------------------------------------------------- network -----
github_url_candidates() {
	local url="$1" prefix
	printf '%s\n' "$url"
	for prefix in ${GITHUB_PROXY_PREFIXES:-}; do
		printf '%s%s\n' "$prefix" "$url"
	done
}

git_clone_retry() {
	local url="$1" branch="$2" dest="$3" candidate

	for candidate in $(github_url_candidates "$url"); do
		if run_with_timeout "$GIT_TIMEOUT" \
			git clone --depth 1 --branch "$branch" "$candidate" "$dest"; then
			return 0
		fi
		warn "clone failed, trying next mirror: $candidate"
		rm -rf "$dest"
	done

	return 1
}

# --------------------------------------------------------- dependencies ------
install_deps() {
	if command -v apt-get >/dev/null 2>&1; then
		log "Installing build dependencies with apt-get"

		# Non-interactive, or apt hangs.  `-y` answers apt's own questions but
		# not debconf's, so a package that wants an answer (tzdata's zone, a
		# service restart, a config-file conflict) blocks for ever on a runner
		# with no terminal.  Observed exactly that in CI: the install step sat
		# in_progress for over thirty minutes on an install that normally takes
		# five.  The dpkg options then make the remaining decisions instead of
		# asking: keep existing config files, and do not use a pty.
		export DEBIAN_FRONTEND=noninteractive
		export DEBCONF_NONINTERACTIVE_SEEN=true
		# The timeouts matter as much as the non-interactive flags.  Without
		# them a stalled connection — most often an IPv6 route that accepts the
		# SYN and then goes nowhere — makes apt wait indefinitely rather than
		# fail, which is what turned a five-minute install into a 30+ minute
		# hang in CI.  ForceIPv4 removes the cause; the timeouts bound it if it
		# happens anyway.
		local apt_opts=(
			-o Dpkg::Options::=--force-confold
			-o Dpkg::Options::=--force-confdef
			-o Dpkg::Use-Pty=0
			-o Acquire::Retries=3
			-o Acquire::ForceIPv4=true
			-o Acquire::http::Timeout=30
			-o Acquire::https::Timeout=30
		)
		sudo -E apt-get "${apt_opts[@]}" update
		# Installed in groups, with a line printed before each.  When the CI
		# install hung, the only thing the log could say was "still running" —
		# there was no way to tell which package was responsible.  Now the last
		# line printed before a timeout names the group, and a group can be
		# bisected further without another blind 20-minute run.
		local apt_groups=(
			"build-essential ccache python3 python3-pyelftools"
			"libncurses-dev libssl-dev libgmp3-dev libmbedtls-dev zlib1g-dev libelf-dev"
			"autoconf automake libtool patch gawk gettext"
			"unzip file wget curl rsync zstd git"
			"bison flex gperf haveged"
			"libltdl-dev libmpc-dev libmpfr-dev libreadline-dev"
			"ninja-build p7zip pkgconf python3-ply python3-setuptools"
			"lld llvm clang re2c scons squashfs-tools"
			"qemu-utils subversion swig texinfo uglifyjs upx-ucl"
			"vim xmlto xxd device-tree-compiler fastjar time"
		)
		local group
		for group in "${apt_groups[@]}"; do
			log "apt: installing ${group}"
			# shellcheck disable=SC2086
			sudo -E apt-get "${apt_opts[@]}" install -y --no-install-recommends $group \
				|| die "apt-get failed for: ${group}"
			done
		return 0
	fi

	if command -v pacman >/dev/null 2>&1; then
		log "Installing build dependencies with pacman"
		# Only packages that live in the official Arch repositories.  `fastjar`
		# and `uglify-js` are AUR-only and `qemu-utils` is a Debian name — the
		# Arch equivalent for the image tools is qemu-img.  The AUR extras are
		# reported below rather than silently skipped.
		sudo pacman -S --needed --noconfirm \
			base-devel ccache python python-pyelftools ncurses openssl gmp mbedtls zlib \
			autoconf automake libtool patch gawk gettext unzip file wget curl rsync zstd \
			git bison flex gperf haveged libelf dtc time qemu-img re2c scons \
			squashfs-tools subversion swig texinfo upx ninja p7zip pkgconf \
			python-ply python-setuptools vim xmlto llvm lld clang cpio

		local aur_missing=()
		for cmd in fastjar uglifyjs; do
			command -v "$cmd" >/dev/null 2>&1 || aur_missing+=("$cmd")
		done
		if [ "${#aur_missing[@]}" -gt 0 ]; then
			warn "Still missing (AUR-only on Arch): ${aur_missing[*]}"
			warn "Install them with your AUR helper if a package you enabled needs them, e.g. 'yay -S fastjar uglify-js'."
		fi
		return 0
	fi

	die "No supported package manager found (apt-get / pacman). Install the OpenWrt build deps manually."
}

# Tools the configuration stage needs.  Kept deliberately small: configuring a
# tree (feeds + defconfig) must not demand the full cross-build toolchain, or
# nobody could lint a config change without provisioning a build host.
CONFIG_TOOLS=(git make gcc g++ python3 patch gawk find tar zstd)

# Tools the download/compile stage additionally needs.
BUILD_TOOLS=(unzip rsync flex bison gperf dtc fastjar)

check_environment() {
	local tools=("${CONFIG_TOOLS[@]}") missing=() cmd

	if ! is_true "$CONFIG_ONLY" && ! is_true "$PREPARE_ONLY"; then
		tools+=("${BUILD_TOOLS[@]}")
	fi

	for cmd in "${tools[@]}"; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done

	command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || missing+=("wget|curl")

	if [ "${#missing[@]}" -gt 0 ]; then
		if is_true "$CONFIG_ONLY" || is_true "$PREPARE_ONLY"; then
			die "Missing tools for the configuration stage: ${missing[*]}. Re-run with --install-deps."
		fi
		die "Missing build tools: ${missing[*]}. Re-run with --install-deps."
	fi

	if ! command -v rsync >/dev/null 2>&1; then
		warn "rsync not found; falling back to cp for package staging"
	fi

	if is_true "$CONFIG_ONLY" || is_true "$PREPARE_ONLY"; then
		log "Build host: $(uname -srm), ${THREADS} jobs (configuration stage — full build tools not checked)"
	else
		log "Build host: $(uname -srm), ${THREADS} jobs"
	fi
}

show_features() {
	log "Upstream      : ${REPO_URL} (${REPO_BRANCH}, track=${OPENWRT_TRACK})"
	log "Target        : ${TARGET_BOARD}/${TARGET_SUBTARGET} profile=${TARGET_PROFILE}"
	log "Board stack   : fancontrol=${ENABLE_FANCONTROL} netmode=${ENABLE_NETMODE} wwand=${ENABLE_WWAND} mt5700m=${ENABLE_MT5700M}"
	log "UI            : argon=${ENABLE_THEME_ARGON}"
	# Say plainly whether the default network is open — "encryption=none" is
	# easy to miss in a build log and this is a security-relevant default.
	if [ "${H5000M_WIFI_ENCRYPTION}" = 'none' ]; then
		log "First boot    : wifi=${H5000M_WIFI_SSID}/${H5000M_WIFI_COUNTRY} OPEN NETWORK (no password) offload=sw:${H5000M_FLOW_OFFLOAD}/hw:${H5000M_FLOW_OFFLOAD_HW}"
	else
		log "First boot    : wifi=${H5000M_WIFI_SSID}/${H5000M_WIFI_COUNTRY} ${H5000M_WIFI_ENCRYPTION} offload=sw:${H5000M_FLOW_OFFLOAD}/hw:${H5000M_FLOW_OFFLOAD_HW}"
	fi
	log "apk source    : ${H5000M_APK_REPO_URL:-(none)}"
	log "Optional      : upnp=${ENABLE_UPNP} adblock=${ENABLE_ADBLOCK} dockerman=${ENABLE_DOCKERMAN}"
	log "Repo extras   : build=${ENABLE_REPO_PACKAGES} (services are =m unless their switch is on)"
	log "Proxy/DNS     : nikki=${ENABLE_NIKKI} openclash=${ENABLE_OPENCLASH} mosdns=${ENABLE_MOSDNS} homeproxy=${ENABLE_HOMEPROXY} adguardhome=${ENABLE_ADGUARDHOME}"
}

resolve_modem_stack() {
	# wwand and luci-app-mt5700m both dial the same MT5700M cdc_ncm interface
	# and both want to own network.MT5700M.  The previous harness enforced the
	# same rule for QModem vs luci-app-modem; keep the loud, automatic
	# resolution so a mis-set environment never produces a box with two
	# dialers racing for one modem.
	if is_true "$ENABLE_WWAND" && is_true "$ENABLE_MT5700M"; then
		warn "ENABLE_WWAND and ENABLE_MT5700M are mutually exclusive (one cdc_ncm data path, one network.MT5700M)."
		warn "Keeping wwand (the WWAN dialer) and DISABLING luci-app-mt5700m."
		ENABLE_MT5700M=false
	fi

	if ! is_true "$ENABLE_WWAND" && ! is_true "$ENABLE_MT5700M"; then
		warn "Neither ENABLE_WWAND nor ENABLE_MT5700M is set: the image will have no cellular dialer,"
		warn "and luci-app-h5000m-netmode will have no modem interface to arbitrate."
	fi
}

# ---------------------------------------------------------------- source -----
prepare_source() {
	local rev staging

	if [ ! -d "${SRC}/.git" ]; then
		log "Cloning ${REPO_URL} (${REPO_BRANCH})"

		# Clone beside the target and merge, rather than cloning into it.  CI
		# restores its caches before this runs, and two of them live inside the
		# source tree — openwrt/dl and openwrt/.ccache — so $SRC already exists
		# and is not empty.  `git clone` refuses that destination outright:
		#
		#   fatal: destination path '.../openwrt' already exists and is not an
		#   empty directory.
		#
		# which is why the very first CI build worked and every later one failed:
		# only the first had no cache to restore.  Merging keeps the caches.
		staging="${SRC}.clone.$$"
		rm -rf "$staging"
		git_clone_retry "$REPO_URL" "$REPO_BRANCH" "$staging" \
			|| die "Unable to clone ${REPO_URL}"

		mkdir -p "$SRC"
		( cd "$staging" && tar -cf - . ) | ( cd "$SRC" && tar -xf - ) \
			|| die "Could not move the fresh checkout into ${SRC}"
		rm -rf "$staging"
	fi

	if [ "${OPENWRT_TRACK}" = "pinned" ]; then
		rev="${OPENWRT_PINNED_REVISION}"
		log "Fetching pinned revision ${rev}"
		run_with_timeout "$GIT_TIMEOUT" git -C "$SRC" fetch --depth 1 origin "$rev" \
			|| die "Cannot fetch pinned revision ${rev}"
		git -C "$SRC" checkout -f FETCH_HEAD
	else
		log "Updating ${REPO_BRANCH} to the current upstream head"
		run_with_timeout "$GIT_TIMEOUT" git -C "$SRC" fetch --depth 1 origin "$REPO_BRANCH" \
			|| die "Cannot fetch ${REPO_BRANCH}"
		git -C "$SRC" checkout -f FETCH_HEAD
	fi

	# A previous run may have applied tree patches; restore tracked files so
	# patch application stays deterministic.  Deliberately NOT `git clean`:
	# feeds/, package/, dl/, build_dir/, staging_dir/ and bin/ must survive to
	# keep incremental builds and ccache useful.
	git -C "$SRC" reset --hard HEAD >/dev/null 2>&1 || true

	local head
	head="$(git -C "$SRC" rev-parse HEAD)"
	log "Source at $(git -C "$SRC" log --oneline -1)"
	printf '%s\n' "$head" > "${ROOT_DIR}/.upstream-revision"

	local desc
	desc="$(git -C "$SRC" describe --tags --always 2>/dev/null || echo "$head")"
	printf '%s\n' "$desc" > "${ROOT_DIR}/.upstream-describe"
}

write_feeds_conf() {
	# The base feeds are always present.  The qmodem feed is *conditional*:
	# luci-app-mt5700m hard-depends on ubus-at-daemon and sms-tool_q, and those
	# two packages exist only there.  QModem is a whole competing modem stack
	# (its own drivers and its own LuCI panel), so it must not be dragged into a
	# wwand build — and on the wwand path nothing needs it.
	{
		cat "${ROOT_DIR}/feeds.conf.default"
		if is_true "$ENABLE_MT5700M"; then
			printf '\n# Added because ENABLE_MT5700M=true. luci-app-mt5700m hard-depends on\n'
			printf '# ubus-at-daemon and sms-tool_q, which are only packaged here.\n'
			printf 'src-git qmodem %s;%s\n' "$QMODEM_REPO_URL" "$QMODEM_REPO_BRANCH"
		fi
	} > "$SRC/feeds.conf.default"
}

# `feeds install` symlinks packages into package/feeds/<feed>/ but never removes
# links for a feed that is no longer configured, so a tree that once built the
# mt5700m stack would keep offering all of QModem on a later wwand build.  Drop
# those links so the configured feed set is the only thing in the tree.  Only
# symlinks live under package/feeds, so this cannot delete a checkout.
prune_stale_feeds() {
	local dir name entry fname configured

	[ -d "${SRC}/package/feeds" ] || return 0

	shopt -s nullglob
	for dir in "${SRC}/package/feeds"/*/; do
		name="$(basename "$dir")"
		configured=false
		while read -r entry fname _; do
			case "$entry" in
				src-git|src-link|src-svn|src-hg)
					[ "$fname" = "$name" ] && configured=true
					;;
			esac
		done < "$SRC/feeds.conf.default"

		if [ "$configured" = false ]; then
			log "Removing package links for the now-unconfigured feed ${name}"
			rm -rf "$dir"
		fi
	done
	shopt -u nullglob
}

# A feed named in feeds.conf.default but absent from feeds/ means the feed set
# changed since the last update (e.g. qmodem was just switched on).  Skipping the
# update then would make `feeds install` fail with a confusing error.
feed_tree_is_complete() {
	local entry name
	while read -r entry name _; do
		case "$entry" in
			src-git|src-link|src-svn|src-hg)
				[ -d "${SRC}/feeds/${name}" ] || return 1
				;;
		esac
	done < "$SRC/feeds.conf.default"
	return 0
}

prepare_feeds() {
	cd "$SRC"

	write_feeds_conf
	prune_stale_feeds

	if is_true "$SKIP_FEEDS_UPDATE" && feed_tree_is_complete; then
		log "Skipping feeds update (--skip-feeds-update)"
	else
		if is_true "$SKIP_FEEDS_UPDATE"; then
			warn "--skip-feeds-update was requested, but a configured feed has no local checkout; updating anyway"
		else
			log "Updating feeds"
		fi
		run_with_timeout "$FEEDS_TIMEOUT" ./scripts/feeds update -a \
			|| die "feeds update failed — refusing to build a firmware with missing packages"
	fi

	log "Installing feeds"
	run_with_timeout "$FEEDS_TIMEOUT" ./scripts/feeds install -a \
		|| die "feeds install failed"

	verify_wwand_feed
}

# The ddimension feed is not one directory per package: `wwand/Makefile` alone
# defines wwand plus its qmi/mbim/ncm/mhi/esim/datapath subpackages.  So check
# the package *definitions* where they actually live, and only look for a
# directory for the two LuCI packages that really are separate.
verify_wwand_feed() {
	local feed="${SRC}/feeds/wwand" mk pkg

	if [ ! -d "$feed" ]; then
		warn "wwand feed is not present — ENABLE_WWAND will fail its package check"
		return 0
	fi

	mk="${feed}/wwand/Makefile"
	if [ ! -f "$mk" ]; then
		warn "wwand feed has no wwand/Makefile"
		return 0
	fi

	for pkg in wwand wwand-qmi wwand-ncm wwand-mbim wwand-mhi; do
		grep -q "^define Package/${pkg}\$" "$mk" \
			|| warn "wwand feed no longer defines the ${pkg} package"
	done

	for pkg in luci-app-wwand luci-proto-wwand; do
		[ -d "${feed}/${pkg}" ] || warn "wwand feed is missing ${pkg}"
	done

	return 0
}

# Give every source file an mtime derived from its own content.
#
# OpenWrt decides whether a package needs rebuilding from a hash of each source
# file's PATH AND MTIME — include/depends.mk:14 is
#
#   find_md5 = find ... -printf "%p%T@\n" | sort | $(MKHASH) md5
#
# and that hash ends up in the stamp FILENAME:
#
#   build_dir/target-*/acl-2.3.2/.prepared_207a5f72c3f1e3ec911e99787f4e10bd_6664...
#
# A fresh `git clone` stamps every file with the checkout time, so an identical
# tree hashes differently on every clone, no cached stamp name ever matches, and
# `make` rebuilds all 475 packages.  Measured directly: touching a package
# directory moved its hash from 713e06ce... to 8f65ac22..., and no stamp with the
# new name existed.  This is why caching the build tree has never helped —
# including the toolchain cache, which was 996 MB of dead weight.
#
# Deriving the mtime from the content fixes both directions: identical content
# gives an identical mtime so the cached stamp is found, and changed content
# gives a different mtime so the package rebuilds.  Verified on a throwaway
# package: stable across re-clones, different when a byte changes, and the
# original hash returns when the byte is changed back.
#
# The timestamp is mapped into 2000-2019 so it stays behind the stamps the build
# writes, rather than landing in the future where it would look newer than
# everything.
normalize_source_mtimes() {
	[ -d "$SRC" ] || return 0

	local scope=(
		-not -path '*/.git/*'
		-not -path "${SRC}/build_dir/*"
		-not -path "${SRC}/staging_dir/*"
		-not -path "${SRC}/bin/*"
		-not -path "${SRC}/tmp/*"
		-not -path "${SRC}/dl/*"
	)

	local count
	count="$(find "$SRC" -type f "${scope[@]}" 2>/dev/null | wc -l)"
	[ "$count" -gt 0 ] || return 0

	log "Normalizing mtimes of ${count} source files (content-derived, for cache reuse)"
	find "$SRC" -type f "${scope[@]}" -print0 2>/dev/null \
		| xargs -0 -r -P "$(nproc 2>/dev/null || echo 4)" -n 64 sh -c '
			for f do
				h=$(sha1sum "$f" 2>/dev/null | cut -c1-8) || continue
				[ -n "$h" ] || continue
				# 2000-01-01 + (hash mod 20 years), always in the past.
				touch -d "@$(( 946684800 + 16#$h % 630720000 ))" "$f" 2>/dev/null || true
			done
		' _ || warn "Some source mtimes could not be normalized"

	return 0
}

# Install a fixed apk signing key, if one was handed to us.
#
# OpenWrt signs the package index with $(TOPDIR)/private-key.pem and installs the
# matching public key at /etc/apk/keys/public-key.pem in the image.  Left alone,
# every build generates a FRESH pair, and that breaks the published repository:
# the index on GitHub Pages is overwritten by each build and signed with that
# build's key, so a device flashed from an earlier build sees
#
#   WARNING: updating <url>: UNTRUSTED signature
#
# with the packages then unavailable.  Reproduced against the live Pages index
# with the firmware's own apk.
#
# Given one key for every build, the public key ships in every image and matches
# the index, so any device trusts any build's repository.
install_signing_key() {
	local src="${H5000M_SIGNING_KEY_FILE:-}"

	[ -n "$src" ] || return 0
	[ -f "$src" ] || { warn "H5000M_SIGNING_KEY_FILE=${src} does not exist; signing with a per-build key"; return 0; }

	cp -f "$src" "${SRC}/private-key.pem"
	chmod 0600 "${SRC}/private-key.pem"
	if openssl ec -in "${SRC}/private-key.pem" -pubout -out "${SRC}/public-key.pem" 2>/dev/null; then
		log "Installed the fixed apk signing key (public key derived and shipped in the image)"
	else
		warn "Could not derive the public key; the image would not trust the index"
	fi
	return 0
}

# Restore the cached build tree, if the CI fetched one from GitHub Packages.
#
# This is the part that actually saves hours: build_dir/target-* holds one build
# directory per package along with the .built stamps, so packages whose sources
# did not change are simply not rebuilt.  It only works because
# normalize_source_mtimes runs too — see the note there.
seed_cached_build_state() {
	local archive="${BUILD_CACHE_ARCHIVE:-}"

	[ -n "$archive" ] || return 0

	# If the exact path is missing, look around before giving up.  A cache that
	# is downloaded and then silently unused is the worst outcome: it costs the
	# transfer and saves nothing.  This is how the oras title bug above went
	# unnoticed for a whole run.
	if [ ! -f "$archive" ]; then
		local found
		found="$(find "$(dirname "$archive")" "$(dirname "$(dirname "$archive")")" \
			-name "$(basename "$archive")" -type f 2>/dev/null | head -1)"
		if [ -n "$found" ]; then
			warn "Build cache was not at ${archive}; using ${found}"
			archive="$found"
		else
			log "No cached build state at ${archive}"
			return 0
		fi
	fi

	log "Seeding build state from cache ($(du -h "$archive" | cut -f1))"

	# Test the compressed stream before spending minutes unpacking it into the
	# tree.  A truncated archive fails with "premature end" part-way through,
	# which leaves a half-populated build_dir behind and makes the real cause
	# hard to see.
	if command -v zstd >/dev/null 2>&1; then
		if ! zstd -t "$archive" >/dev/null 2>&1; then
			warn "Cached build state at ${archive} is truncated or corrupt (zstd -t failed); ignoring it"
			return 0
		fi
	fi

	mkdir -p "${SRC}"
	if tar -I zstd -xf "$archive" -C "${SRC}"; then
		log "Build cache applied; unchanged packages should be skipped"
	else
		warn "Could not unpack the cached build state; everything will rebuild"
	fi
	return 0
}

# Restore a previously cached toolchain, if one was handed to us.
#
# The CI caches the toolchain because building it is the longest single phase.
# It arrives as an archive rather than as openwrt/staging_dir directly: caching
# that directory makes the cache restore create openwrt/ before anything else
# runs, and prepare_source's `git clone` then fails with "destination path
# already exists and is not an empty directory".  Extracting after the clone
# avoids that, and the archive is keyed on the upstream revision so a stale
# toolchain is never used.
seed_cached_toolchain() {
	local archive="${TOOLCHAIN_CACHE_ARCHIVE:-}"

	[ -n "$archive" ] || return 0
	[ -f "$archive" ] || { log "No cached toolchain at ${archive}"; return 0; }

	log "Seeding toolchain from cache ($(du -h "$archive" | cut -f1))"
	# Unpacked at the source root: the archive holds build_dir/toolchain-* as
	# well as staging_dir/*, and both are needed.  The stamps that make `make`
	# skip the toolchain live in build_dir, not in staging_dir.
	mkdir -p "${SRC}"
	if tar -I zstd -xf "$archive" -C "${SRC}" 2>/dev/null \
		|| tar -xf "$archive" -C "${SRC}"; then
		log "Toolchain cache applied; the toolchain build should be skipped"
	else
		warn "Could not unpack the cached toolchain; building it from scratch"
	fi
	return 0
}

# --------------------------------------------------------------- patches -----
apply_patches() {
	local patch_file name paths applied=0

	shopt -s nullglob
	for patch_file in "${ROOT_DIR}"/patches/*.patch; do
		name="$(basename "$patch_file")"

		# A patch that only INSERTS lines is not idempotent under `git apply`:
		# the surrounding context still matches afterwards, so a second run
		# inserts a second copy of the block.  0001-h5000m-userspace-fan-control
		# has exactly that shape — applying it twice yields two
		# /delete-node/ blocks in the DTS, which dtc then rejects.
		#
		# The `--reverse --check` test below cannot catch this, so the real
		# protection is prepare_source's `git reset --hard`.  Rather than trust
		# that implicitly, assert it: refuse to apply a patch on top of a tree
		# where the files it touches are already modified.  feeds.conf.default
		# is deliberately excluded by scoping the test to the patch's own
		# paths, because prepare_feeds legitimately rewrites it before this
		# point.
		paths="$(git -C "$SRC" apply --numstat "$patch_file" 2>/dev/null | cut -f3-)"
		if [ -n "$paths" ] \
			&& [ -n "$(git -C "$SRC" status --porcelain --untracked-files=no -- $paths)" ]; then
			die "${name} targets files that are already modified in ${SRC} — the tree was not reset; applying it would duplicate inserted blocks"
		fi

		if git -C "$SRC" apply --check "$patch_file" >/dev/null 2>&1; then
			git -C "$SRC" apply "$patch_file" || die "Failed to apply ${name}"
			log "Applied patch ${name}"
			applied=$((applied + 1))
		elif git -C "$SRC" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
			log "Patch ${name} already applied"
		else
			die "Patch ${name} does not apply to $(git -C "$SRC" log --oneline -1) — upstream DTS changed; refresh patches/"
		fi
	done
	shopt -u nullglob


	if [ "$applied" -gt 0 ]; then
		log "Applied ${applied} tree patch(es)"
	fi
	return 0
}

# --------------------------------------------------------------- staging -----
stage_directory() {
	local from="$1" to="$2"

	mkdir -p "$to"
	if command -v rsync >/dev/null 2>&1; then
		rsync -a --delete-after --exclude '.git' "${from}/" "${to}/"
	else
		rm -rf "$to"
		mkdir -p "$to"
		cp -a "${from}/." "$to/"
		rm -rf "${to}/.git"
	fi
}

install_local_packages() {
	local pkg

	shopt -s nullglob
	for pkg in "${ROOT_DIR}"/local-packages/*/; do
		local name
		name="$(basename "$pkg")"
		log "Staging local package ${name}"
		stage_directory "$pkg" "${SRC}/package/${name}"
	done
	shopt -u nullglob

	write_h5000m_runtime_config
}

# Two files the firmware needs at runtime, generated from build inputs rather
# than committed as constants:
#
#   /etc/h5000m-defaults.conf       the first-boot SSID/key/country and the
#                                   hardware-offload switches
#   /etc/apk/repositories.d/50-h5000m.list
#                                   this project's own apk repository, so the
#                                   service packages (=m) and every kmod can be
#                                   installed on the running router
#
# They are written into the staged package's files/ tree, which is what the
# OpenWrt build copies into the image.  Doing it here keeps the package itself
# free of machine-specific values and keeps a stale file from a previous build
# out of the image — the tree is re-staged from local-packages/ on every run.
write_h5000m_runtime_config() {
	local pkg_dir="${SRC}/package/h5000m-integration"
	local repo_dir="${pkg_dir}/files/etc/apk/repositories.d"
	local conf="${pkg_dir}/files/etc/h5000m-defaults.conf"

	[ -d "$pkg_dir" ] || return 0

	mkdir -p "$repo_dir"

	cat > "$conf" <<EOF
# Generated by scripts/local-build.sh — do not edit; edit the build instead.
H5000M_WIFI_SSID='${H5000M_WIFI_SSID}'
H5000M_WIFI_KEY='${H5000M_WIFI_KEY}'
H5000M_WIFI_COUNTRY='${H5000M_WIFI_COUNTRY}'
H5000M_WIFI_ENCRYPTION='${H5000M_WIFI_ENCRYPTION}'
H5000M_WIFI_HTMODE_2G='${H5000M_WIFI_HTMODE_2G}'
H5000M_WIFI_HTMODE_5G='${H5000M_WIFI_HTMODE_5G}'
H5000M_FLOW_OFFLOAD='${H5000M_FLOW_OFFLOAD}'
H5000M_FLOW_OFFLOAD_HW='${H5000M_FLOW_OFFLOAD_HW}'
EOF

	# Root-only: this file carries the WiFi key in clear text, and the package
	# install copies modes verbatim.
	chmod 0600 "$conf"

	# The stock distfeeds.list points every entry at downloads.openwrt.org, and
	# those kmods carry a DIFFERENT vermagic from this image, so `apk add` of
	# anything with a kmod dependency fails there.  customfeeds.list is the
	# file OpenWrt reserves for additions and explicitly survives sysupgrade.
	if [ -n "${H5000M_APK_REPO_URL:-}" ]; then
		{
			printf '# This project'"'"'s own apk repository: every package from the same\n'
			printf '# build as this firmware, so the kmods match this kernel ABI.\n'
			printf '# The repository is the apk-repo/ artifact; serve that directory\n'
			printf '# over HTTP(S) and point H5000M_APK_REPO_URL at it.\n'
			printf '%s/packages.adb\n' "${H5000M_APK_REPO_URL%/}"
		} > "${repo_dir}/50-h5000m.list"
		log "Firmware apk source: ${H5000M_APK_REPO_URL%/}/packages.adb"
	else
		# No URL configured.  Remove any file a previous run left behind rather
		# than ship entries pointing at a host that does not exist.
		rm -f "${repo_dir}/50-h5000m.list"
		log "Firmware apk source: none configured (set H5000M_APK_REPO_URL to add one)"
	fi

	return 0
}

# clone_external <name> <url> <branch> — pull a third-party package tree into
# package/ the same way the previous harness did.  These projects are not in
# the official feeds and are the user's own risk; they are all opt-in.
clone_external() {
	# Split across two statements on purpose: `local a="$1" b="${a}"` expands
	# every argument before assigning any of them, so `b` would see an unbound
	# `a` under `set -u`.
	local name="$1" url="$2" branch="${3:-main}"
	local dest="${SRC}/package/${name}"

	if [ -d "${dest}/.git" ]; then
		log "Updating external package ${name}"
		if run_with_timeout "$GIT_TIMEOUT" git -C "$dest" fetch --depth 1 origin "$branch" \
			&& git -C "$dest" checkout -f FETCH_HEAD; then
			return 0
		fi
		# A usable checkout already exists; a transient fetch failure should not
		# kill the build.
		warn "Could not update ${name}; keeping the existing checkout"
		return 0
	fi

	log "Cloning external package ${name} (${branch})"
	if ! git_clone_retry "$url" "$branch" "$dest"; then
		warn "Could not clone ${name} from ${url}"
		return 1
	fi
	return 0
}

# The three H5000M board plugins are maintained outside any feed, so they are
# cloned into package/ like the previous harness cloned luci-app-Airpifanctrl
# and luci-app-turboacc-mtk.  They are required packages: if the clone fails the
# build stops rather than shipping an image with no fan control or no egress
# arbitration.
install_board_plugins() {
	local failed=0

	if is_true "$ENABLE_FANCONTROL"; then
		clone_external luci-app-h5000m-fancontrol \
			https://github.com/FAN789/luci-app-h5000m-fancontrol.git main \
			|| failed=1
	fi

	if is_true "$ENABLE_NETMODE"; then
		clone_external luci-app-h5000m-netmode \
			https://github.com/FAN789/luci-app-h5000m-netmode.git main \
			|| failed=1
	fi

	if is_true "$ENABLE_EASYMESH"; then
		# Only this one directory is wanted out of coolsnowwolf/luci.
		clone_only_paths luci-easymesh \
			https://github.com/coolsnowwolf/luci.git master \
			applications/luci-app-easymesh \
			|| failed=1
	fi

	if is_true "$ENABLE_MT5700M"; then
		clone_external luci-app-mt5700m \
			https://github.com/FAN789/luci-app-mt5700m.git main \
			|| failed=1
	fi

	if [ "$failed" -ne 0 ]; then
		die "Could not fetch the H5000M board plugins — refusing to build a firmware without them"
	fi

	return 0
}

# Argon lives in two repositories outside every feed, so it is cloned into
# package/ exactly like the board plugins rather than pulled from a feed.
# Both Makefiles include $(TOPDIR)/feeds/luci/luci.mk, so this has to run after
# the feeds are installed.
#
# The clone failure is fatal rather than a warning: the seed lists
# luci-theme-argon and luci-app-argon-config as required packages, so a silent
# fetch failure would resurface much later as an opaque defconfig complaint
# about an unknown package instead of as a network error here.
install_theme() {
	if ! is_true "$ENABLE_THEME_ARGON"; then
		log "Argon theme disabled (ENABLE_THEME_ARGON=false) — keeping the stock theme"
		return 0
	fi

	clone_external luci-theme-argon "$ARGON_THEME_REPO_URL" "$ARGON_THEME_REPO_BRANCH" \
		|| die "Could not fetch luci-theme-argon from ${ARGON_THEME_REPO_URL}"
	clone_external luci-app-argon-config "$ARGON_CONFIG_REPO_URL" "$ARGON_CONFIG_REPO_BRANCH" \
		|| die "Could not fetch luci-app-argon-config from ${ARGON_CONFIG_REPO_URL}"

	return 0
}

# Clone one optional third-party package on behalf of an ENABLE_* switch.
#
# The switch name is part of the failure message on purpose.  Under `set -e` a
# failing `is_true X && clone_external ...` aborts the whole run, and the only
# thing the user sees is the raw git error ("Repository not found") — which does
# not name the switch to turn off, nor the URL that is wrong.  That is exactly
# how a dead ADGUARDHOME url used to kill `--config-only` with
# ENABLE_ADGUARDHOME=true.
install_optional_external() {
	local switch="$1" name="$2" url="$3" branch="$4"

	clone_external "$name" "$url" "$branch" \
		|| die "ENABLE_${switch} is set but ${name} could not be fetched from ${url}. Fix the URL or pick another source, or turn ENABLE_${switch} off."
	return 0
}

# Clone a third-party package when it is needed in the tree for EITHER reason:
# it is installed into the image (its ENABLE_* switch is on), or it is built into
# the apk repository (ENABLE_REPO_PACKAGES).
#
# The second reason is easy to miss and was a real bug here.  append_optional_config
# emits these packages as `=m` so they land in bin/packages/, but a `=m` symbol
# only exists if the package definition exists.  Gating the clone on the ENABLE_*
# switch alone meant that on a clean checkout — CI, or anyone cloning this repo —
# nothing was cloned, defconfig silently dropped all seven symbols with exit 0, and
# the packages never reached the repository at all.  It stayed hidden locally only
# because earlier runs had left the clones in package/.
clone_for_repo_or_image() {
	local switch_value="$1"; shift

	if is_true "$ENABLE_REPO_PACKAGES" || is_true "$switch_value"; then
		install_optional_external "$@"
	fi
	return 0
}

install_external_packages() {
	clone_for_repo_or_image "$ENABLE_NIKKI"     NIKKI     OpenWrt-nikki   https://github.com/nikkinikki-org/OpenWrt-nikki.git main
	clone_for_repo_or_image "$ENABLE_OPENCLASH" OPENCLASH OpenClash       https://github.com/vernesong/OpenClash.git master
	clone_for_repo_or_image "$ENABLE_MOSDNS"    MOSDNS    luci-app-mosdns https://github.com/sbwml/luci-app-mosdns.git v5
	clone_for_repo_or_image "$ENABLE_HOMEPROXY" HOMEPROXY homeproxy       https://github.com/immortalwrt/homeproxy.git master

	# AdGuardHome deliberately has NO clone here.  Its packages — adguardhome,
	# luci-app-adguardhome and luci-i18n-adguardhome-zh-cn — are all in the
	# official feeds now, so the third-party source the previous harness needed
	# (a prebuilt ipk from sirpdboy/luci-app-adguardhome releases) is obsolete.
	# ENABLE_ADGUARDHOME only selects the config symbols; see append_optional_config.
	return 0
}

# Clone a third-party tree and then drop named subdirectories from it.
#
# openwrt-passwall-packages carries its own xray-core, sing-box and microsocks,
# and the official feeds carry packages with those exact PKG_NAMEs.  Cloning it
# wholesale would introduce duplicate package definitions — this project's tree
# currently has ZERO name collisions across 12757 packages, which is worth
# keeping.  Dropping the duplicates leaves exactly the helpers the official feeds
# lack, and the frontends resolve xray-core/sing-box from the feeds instead.
clone_and_prune() {
	local name="$1" url="$2" branch="$3"; shift 3
	local dest="${SRC}/package/${name}"
	local drop

	install_optional_external "$name" "$name" "$url" "$branch" || return 1

	for drop in "$@"; do
		if [ -e "${dest}/${drop}" ]; then
			rm -rf "${dest}/${drop}"
			log "  pruned ${name}/${drop} (official feeds already provide it)"
		fi
	done
	return 0
}

# Clone a monorepo and keep only the named paths, which are relative to the
# repository root.
#
# luci-app-ssr-plus lives in fw876/helloworld and luci-app-easymesh only in
# coolsnowwolf/luci; neither is published as a standalone repository, and both
# carry far more than we want.
#
# Paths, not bare directory names: coolsnowwolf/luci keeps its apps under
# applications/, so matching on the top-level name alone deleted applications/
# entirely and left a tree with no package in it at all — which is what the
# first version did, silently, because pruning files is not something it does.
clone_only_paths() {
	local name="$1" url="$2" branch="$3"; shift 3
	local dest="${SRC}/package/${name}"
	local entry sub keep found

	install_optional_external "$name" "$name" "$url" "$branch" || return 1

	shopt -s nullglob

	# Level one: which top-level directories survive at all.
	for entry in "${dest}"/*; do
		[ -d "$entry" ] || continue
		found=0
		for keep in "$@"; do
			[ "${keep%%/*}" = "$(basename "$entry")" ] && found=1
		done
		[ "$found" -eq 1 ] || rm -rf "$entry"
	done

	# Level two: inside each survivor, drop the siblings that were not asked for.
	for keep in "$@"; do
		case "$keep" in
			*/*) ;;
			*) continue ;;
		esac
		local parent="${dest}/${keep%%/*}" want="${keep#*/}"
		[ -d "$parent" ] || continue
		for sub in "${parent}"/*; do
			[ -d "$sub" ] || continue
			[ "$(basename "$sub")" = "$want" ] || rm -rf "$sub"
		done
	done

	shopt -u nullglob

	log "  kept in ${name}: $*"
	return 0
}

# Neutralise PKG_MIRROR_HASH on the helloworld cores.
#
# Those packages declare PKG_SOURCE_PROTO:=git with a pinned
# PKG_SOURCE_VERSION, so the tarball is generated locally by
# scripts/dl_github_archive.py from that commit.  Its hash depends on the git,
# tar and xz versions, so the hash upstream recorded never matches here:
#
#   Hash of the local file shadowsocks-libev-3.3.5.tar.xz does not match
#     (file: 9d2293f1..., requested: b3898ad0...)
#
# and the build dies in the download stage.  That is what "shadowsocks-libev
# failed to build" meant in CI — not a compiler error.
#
# The source is already pinned to an exact commit, which is what actually
# guarantees integrity; the mirror hash only validates a locally generated
# archive.  `skip` is the value OpenWrt's download logic tests for.
fix_mirror_hashes() {
	local dir="${SRC}/package/luci-app-ssr-plus"
	local f fixed=0

	[ -d "$dir" ] || return 0

	for f in "$dir"/*/Makefile; do
		[ -f "$f" ] || continue
		grep -q 'PKG_SOURCE_PROTO:=git' "$f" 2>/dev/null || continue
		grep -q '^PKG_MIRROR_HASH:=' "$f" 2>/dev/null || continue
		sed -i 's|^PKG_MIRROR_HASH:=.*|PKG_MIRROR_HASH:=skip|' "$f"
		log "  set PKG_MIRROR_HASH=skip in $(basename "$(dirname "$f")")"
		fixed=$((fixed + 1))
	done

	[ "$fixed" -gt 0 ] && log "Neutralised ${fixed} mirror hash(es); sources stay pinned by PKG_SOURCE_VERSION"
	return 0
}

# Proxy frontends, plus the cores the official feeds do not carry.  Everything is
# emitted as `=m`: built into the apk repository, not installed into the image, so
# a user picks with `apk add` and the frontend pulls its backend and helpers in.
#
# It is not enough to ship the daemon: each entry here also carries its LuCI app
# and, where upstream has one, the `luci-i18n-<app>-zh-cn` translation, because
# `apk add passwall` without `luci-app-passwall` installs something with no UI.
#
# Repository paths verified against upstream.  Several of the ones in circulation
# are dead: xiaorouji/openwrt-passwall and -passwall2 now 404 and live under the
# Openwrt-Passwall org, v2rayA/openwrt is v2rayA/v2raya-openwrt, and
# QiuSimons/openwrt-xray does not exist at all.
#
# v2rayA needs no clone: v2raya and luci-app-v2raya are in the official feeds.
install_proxy_repos() {
	is_true "$ENABLE_REPO_PACKAGES" || is_true "$ENABLE_PROXY_REPOS" || return 0

	install_optional_external PASSWALL  openwrt-passwall    https://github.com/Openwrt-Passwall/openwrt-passwall.git main
	install_optional_external PASSWALL2 openwrt-passwall2   https://github.com/Openwrt-Passwall/openwrt-passwall2.git main

	# Cores and helpers PassWall/PassWall2/SSR-Plus/HiJpass need that the
	# official feeds do not have.  The three official-feeds duplicates are pruned.
	clone_and_prune openwrt-passwall-packages \
		https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git main \
		xray-core sing-box microsocks

	install_optional_external MOMO    OpenWrt-momo    https://github.com/nikkinikki-org/OpenWrt-momo.git main
	install_optional_external FCHOMO  openwrt-fchomo  https://github.com/fcshark-org/openwrt-fchomo.git master
	# NeKoBox bundles its own sing-box and mihomo.  sing-box duplicates the
	# official feed; mihomo would duplicate fcshark's.  Keep one of each defined
	# in the tree — fcshark's mihomo, the official sing-box — and let NeKoBox
	# depend on them.
	# SSR-Plus.  It is Lua-based, so mainline LuCI needs luci-compat for the page
	# to appear at all; that is emitted below alongside the app.
	#
	# fw876/helloworld is the canonical source (lean uses it too — there is no
	# luci-app-ssr-plus in coolsnowwolf/lede or coolsnowwolf/luci).  The
	# repository is a monorepo of two dozen cores, several of which the official
	# feeds already provide, so the duplicates are pruned by name.
	# SSR-Plus defaults INCLUDE_Http_Proxy to y on aarch64, and that option
	# does `select PACKAGE_3proxy`.  Mainline has no 3proxy at all, so without
	# it the build stops on a missing dependency.  immortalwrt/packages carries
	# it; only that one directory is taken.
	clone_only_paths luci-ssr-plus-3proxy \
		https://github.com/immortalwrt/packages.git master \
		net/3proxy

	# Prune against openwrt-passwall-packages as well as against the official
	# feeds.  Checking only the feeds left nine names defined twice in the tree —
	# chinadns-ng, dns2socks, ipt2socks, naiveproxy, shadow-tls,
	# shadowsocksr-libev, simple-obfs, tcping, v2ray-plugin and xray-plugin all
	# already come from the PassWall checkout — and a tree with two definitions
	# of the same package does not build.
	clone_and_prune luci-app-ssr-plus \
		https://github.com/fw876/helloworld.git dev \
		dnsproxy microsocks v2ray-core xray-core mihomo mosdns v2raya \
		shadowsocks-rust hysteria sing-box \
		chinadns-ng dns2socks ipt2socks naiveproxy shadow-tls \
		shadowsocksr-libev simple-obfs tcping v2ray-plugin xray-plugin

	clone_and_prune openwrt-nekobox \
		https://github.com/Thaolga/openwrt-nekobox.git main \
		sing-box mihomo
	fix_nekobox_release

	install_optional_external LUCIXRAY luci-app-xray  https://github.com/yichya/luci-app-xray.git master
	# Daed is deliberately NOT cloned.  Its daemon declares
	# `PKG_BUILD_DEPENDS:=golang/host bpf-headers` and bpf-headers fails to
	# build against this kernel configuration, which does not enable
	# CONFIG_KERNEL_XDP_SOCKETS / DEBUG_INFO_BTF / BPF_EVENTS.  The failure
	# is not survivable and Daed would not run even if it built, so offering
	# it here would only break every build.  See docs/proxy-kmod-audit.md for
	# the kernel options it needs; enabling them is a separate decision because
	# they change the kernel ABI.
	install_optional_external HIJPass luci-app-hijpass https://github.com/WROIATE/luci-app-hijpass.git main

	return 0
}

# Upstream packaging bug in Thaolga/openwrt-nekobox, worked around rather than
# waited on.
#
# Its Makefile sets `PKG_RELEASE:=rc14`, but luci.mk composes the package version
# as `$(PKG_VERSION)-r$(PKG_RELEASE)` (feeds/luci/luci.mk:185), which yields
# `2.0.9-rrc14`.  apk rejects that -- `-r` must be followed by a number -- and
# the build stops with the unhelpful
#
#   ERROR: failed to create package: package version is invalid
#
# The first look at this looked like a CSS-minification complaint, because
# luci-theme-spectra logs its own message immediately before it; the real error
# only shows up under `make ... V=s`.  A numeric PKG_RELEASE makes the version
# `2.0.9-r1`, which is valid.  The `rc14` marker is cosmetic and is dropped
# rather than encoded as `2.0.9_rc14`, whose underscore form apk's version parser
# would also have to accept.
fix_nekobox_release() {
	local mk="${SRC}/package/openwrt-nekobox/luci-app-nekobox/Makefile"

	[ -f "$mk" ] || return 0
	grep -q '^PKG_RELEASE:=rc14$' "$mk" || return 0

	sed -i 's/^PKG_RELEASE:=rc14$/PKG_RELEASE:=1/' "$mk"
	log "  fixed luci-app-nekobox PKG_RELEASE (upstream rc14 becomes apk-invalid -rrc14)"
	return 0
}

# --------------------------------------------------------------- config ------
config_set_symbol() {
	local symbol="$1" value="$2"

	if grep -q "^${symbol}=" "$SRC/.config" 2>/dev/null; then
		sed -i "s|^${symbol}=.*|${symbol}=${value}|" "$SRC/.config"
	else
		printf '%s=%s\n' "$symbol" "$value" >> "$SRC/.config"
	fi
}

config_enable()  { config_set_symbol "CONFIG_PACKAGE_$1" "y"; }
config_disable() { config_set_symbol "CONFIG_PACKAGE_$1" "n"; }

append_board_stack_config() {
	local out="$1"

	cat >> "$out" <<'EOF'

# --------------------------------------------------- H5000M board stack ------
EOF

	if is_true "$ENABLE_FANCONTROL"; then
		cat >> "$out" <<'EOF'
CONFIG_PACKAGE_luci-app-h5000m-fancontrol=y
CONFIG_PACKAGE_kmod-hwmon-pwmfan=y
CONFIG_PACKAGE_luci-i18n-h5000m-fancontrol-zh-cn=y
EOF
	fi

	if is_true "$ENABLE_NETMODE"; then
		cat >> "$out" <<'EOF'
CONFIG_PACKAGE_luci-app-h5000m-netmode=y
CONFIG_PACKAGE_luci-i18n-h5000m-netmode-zh-cn=y
EOF
	fi

	if is_true "$ENABLE_WWAND"; then
		cat >> "$out" <<'EOF'
CONFIG_PACKAGE_wwand=y
CONFIG_PACKAGE_wwand-qmi=y
CONFIG_PACKAGE_wwand-ncm=y
CONFIG_PACKAGE_wwand-mbim=y
CONFIG_PACKAGE_luci-app-wwand=y
CONFIG_PACKAGE_luci-proto-wwand=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ncm=y
CONFIG_PACKAGE_kmod-usb-net-cdc-mbim=y
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y
CONFIG_PACKAGE_kmod-rmnet=y
EOF
	fi

	if is_true "$ENABLE_MT5700M"; then
		cat >> "$out" <<'EOF'
CONFIG_PACKAGE_luci-app-mt5700m=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ncm=y
EOF
	fi

	cat >> "$out" <<'EOF'
CONFIG_PACKAGE_h5000m-integration=y
CONFIG_PACKAGE_luci-app-h5000m-accel=y
CONFIG_PACKAGE_kmod-tcp-bbr=y

# Transparent-proxy nftables modules.  PassWall2 warns without them:
#   Warning: nftables transparent proxy is missing basic dependency
#   kmod-nft-socket!
# and the redirect/tproxy rules it installs do nothing.  kmod-nft-nat and
# kmod-nft-core are already pulled in by firewall4.
CONFIG_PACKAGE_kmod-nft-socket=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
EOF
}

append_optional_config() {
	local out="$1"

	cat >> "$out" <<'EOF'

# ------------------------------------------------------ optional services ---
EOF

	if is_true "$ENABLE_UPNP"; then
		cat >> "$out" <<'EOF'
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y
CONFIG_PACKAGE_miniupnpd-nftables=y
EOF
	fi

	# Argon theme and its settings page, both cloned into package/ above.
	# Installing the theme is what activates it: it ships
	# root/etc/uci-defaults/30_luci-theme-argon, which points
	# luci.main.mediaurlbase at /luci-static/argon on first boot.
	if is_true "$ENABLE_THEME_ARGON"; then
		cat >> "$out" <<'EOF'
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
EOF
	fi

	if is_true "$ENABLE_ADBLOCK"; then
		cat >> "$out" <<'EOF'
CONFIG_PACKAGE_adblock=y
CONFIG_PACKAGE_luci-app-adblock=y
CONFIG_PACKAGE_luci-i18n-adblock-zh-cn=y
EOF
	fi

	# ------------------------------------------------ services: image or repo ---
	# These are the "extras" — a Docker stack, a proxy stack, AdGuardHome.  They
	# are NOT baked into the image by default: they are large, most owners want
	# only one of them, and every one of them can be installed afterwards from
	# the apk repository this same build publishes.
	#
	# `=m` is the mechanism.  OpenWrt builds a `=m` package and drops its .apk in
	# bin/packages/ without installing it into the rootfs — verified on this tree:
	# CONFIG_PACKAGE_jq=m survived defconfig, `make .../jq/compile` produced
	# bin/packages/aarch64_cortex-a53/packages/jq-1.8.2-r1.apk, and no module was
	# installed into the image.  Runtime dependencies are emitted as `=m` too, so
	# the repository stays self-contained and `apk add` resolves.
	#
	# Turning the matching ENABLE_* switch on upgrades the group to `=y`, i.e.
	# installed into the firmware, for anyone who does want it baked in.
	service_pkg_mode="m"
	is_true "$ENABLE_REPO_PACKAGES" || service_pkg_mode="n"

	# emit_service <switch-value> <package>...
	emit_service() {
		local on="$1"; shift
		local mode="$service_pkg_mode"
		local pkg
		is_true "$on" && mode="y"
		for pkg in "$@"; do
			printf 'CONFIG_PACKAGE_%s=%s\n' "$pkg" "$mode" >> "$out"
		done
	}

	emit_service "$ENABLE_DOCKERMAN" \
		docker dockerd containerd runc docker-compose \
		luci-app-dockerman luci-i18n-dockerman-zh-cn \
		kmod-fs-cifs kmod-nf-nathelper-extra

	emit_service "$ENABLE_NIKKI"     nikki mihomo-meta luci-app-nikki
	emit_service "$ENABLE_OPENCLASH" luci-app-openclash
	emit_service "$ENABLE_MOSDNS"    mosdns luci-app-mosdns
	# ucode-mod-math is a HARD requirement that upstream does not declare.
	# luci-app-homeproxy's LUCI_DEPENDS lists ucode-mod-digest but not math, even
	# though root/etc/homeproxy/scripts/generate_client.uc line 11 does
	# `import { isnan } from 'math'`.  Without it the daemon dies on startup:
	#
	#   Syntax error: Unable to resolve path for module 'math'
	#   Error: failed to generate client configuration.
	#
	# Reported from a real device.  ucode-mod-math has no dependencies of its own,
	# so there is nothing to hold it back.
	#
	# ip-full and kmod-tun are what the LuCI page itself asks for before TUN mode
	# can be switched on ("you need to install ip-full and kmod-tun").  ip-full
	# replaces ip-tiny, which the base image selects; ip-tiny is turned off below
	# so the two do not collide.
	# ip-full conflicts with the ip-tiny the base image pulls in.
	printf 'CONFIG_PACKAGE_ip-tiny=n\n' >> "$out"

	# Mesh: the front-end plus the DAWN / batman-adv stack it drives.  DAWN is a
	# decentralised WiFi controller and batman-adv carries the mesh links; both
	# are in the official feeds.  luci-compat is what lets the Lua-era pages
	# (this one and SSR-Plus) render at all under mainline's JS LuCI.
	emit_service "$ENABLE_EASYMESH" \
		luci-app-easymesh dawn batctl-default kmod-batman-adv kmod-cfg80211 \
		luci-compat

	# Repository only, hence the empty switch — see the note on the block above.
	#
	# SSR-Plus uses `select`, not `depends`, for the cores its INCLUDE_* options
	# cover.  A select forces its target to =y even when the selecting package is
	# only =m, so leaving those options at their aarch64 defaults would install
	# mihomo, 3proxy, chinadns-ng and v2ray-geoip into the image — and
	# dnsmasq-full, which replaces the dnsmasq the base image ships — while the
	# app itself stayed in the repository.  Dependencies in the image and the
	# package that needs them in the repository is the worst of both.
	#
	# They are therefore turned off and the cores are emitted here as =m
	# alongside every other proxy core, so `apk add` finds them all.
	emit_service "" \
		luci-app-ssr-plus luci-i18n-ssr-plus-zh-cn \
		chinadns-ng dns2socks dns2tcp ipt2socks redsocks2 shadowsocksr-libev \
		simple-obfs tcping shadow-tls tuic-client v2ray-plugin xray-plugin \
		gn lua-neturl naiveproxy shadowsocks-libev \
		3proxy v2ray-geoip v2ray-geosite \
		shadowsocksr-libev-ssr-local shadowsocksr-libev-ssr-redir

	# The INCLUDE_* switches themselves.  Off, so the selects above cannot fire.
	printf 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Http_Proxy=n\n' >> "$out"
	printf 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ChinaDNS_NG=n\n' >> "$out"
	printf 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Mihomo=n\n' >> "$out"
	printf 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=n\n' >> "$out"
	printf 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Kcptun=n\n' >> "$out"
	printf 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_GeoData=n\n' >> "$out"

	emit_service "$ENABLE_HOMEPROXY" \
		luci-app-homeproxy sing-box kmod-nft-tproxy \
		ucode-mod-math ip-full kmod-tun

	# AdGuardHome and its LuCI app are in the official feeds, so this needs no
	# clone at all.
	emit_service "$ENABLE_ADGUARDHOME" \
		adguardhome luci-app-adguardhome luci-i18n-adguardhome-zh-cn

	# ------------------------------------------- proxy ecosystem kmod support ---
	# PassWall, PassWall2, SSR-Plus, HomeProxy, OpenClash, Nikki, Momo, FullCombo
	# Shark!, luci-xray, NeKoBox, Daed, HiJpass and v2rayA all redirect traffic
	# through the same handful of kernel facilities: nftables tproxy/socket, the
	# legacy iptables equivalents, tun/inet-diag for the userspace tunnels, and
	# the NAT helper and traffic-control modules for the rest.  A user who
	# `apk add`s one of them gets these pulled from the repository, so they have
	# to be IN the repository — which is what `=m` produces.
	#
	# ONLY modules that are not already built are listed here.  Writing `=m` for
	# a module that something else already pulls in as `=y` is not a no-op: it
	# can demote an installed module to repository-only and remove it from the
	# image, which would break the firewall.  Everything the base system already
	# needs (kmod-nft-*, kmod-nf-conntrack, kmod-nf-nat, kmod-ipt-*, ...) is
	# therefore deliberately absent from this list — it is already present in
	# the image, which is even better than being installable.
	# `kmod-xdp-sockets-diag` is deliberately NOT here even though the wider
	# module list suggests it: it depends on KERNEL_XDP_SOCKETS, which this
	# kernel does not set, so the symbol is dropped by defconfig regardless.
	# Only Daed wants it, and only in its README rather than its Makefile, so
	# `apk add daed` would not pull it either way.  Turning the kernel option on
	# changes the kernel ABI and forces a full rebuild; see
	# ENABLE_EBPF_PROXY_KERNEL below for that decision.
	emit_service "" \
		kmod-netlink-diag \
		kmod-nf-nathelper \
		kmod-macvlan \
		kmod-sched-core \
		kmod-ifb \
		kmod-tcp-bbr

	# Found by auditing the proxy packages' Makefiles rather than by guessing:
	#   kmod-nft-queue            HomeProxy (VIKINGYFY variant) uses nft queue
	#                             rather than tproxy; pulls kmod-nfnetlink-queue
	#   kmod-sched-bpf            Daed traffic shaping
	#   kmod-ipt-tproxy           OpenClash's firewall3 path and the fw3 branch
	#   kmod-ipt-conntrack-extra  of ttimasdf's luci-app-xray
	#   kmod-ipt-filter
	#
	# `kmod-lib-crc32c` is NOT in the list, and two independent audits disagreed
	# about it, so here is the settled answer.  Its Kconfig is
	# `depends on LINUX_6_12`, and this target sets CONFIG_LINUX_6_18, so the
	# symbol cannot be selected at all — defconfig drops it no matter what is
	# asked for.  It is also unnecessary: the kernel is built with
	# CONFIG_NET_CRC32C=y and CONFIG_CRYPTO_CRC32C=y, i.e. CRC32C is already
	# there, and the module package only exists for 6.12 where it evidently is
	# not.  `kmod-nft-core`'s `select PACKAGE_kmod-lib-crc32c if LINUX_6_12`
	# therefore does not fire for this build, which is correct rather than a gap.
	emit_service "" \
		kmod-nft-queue \
		kmod-nfnetlink-queue \
		kmod-sched-bpf \
		kmod-ipt-tproxy \
		kmod-ipt-conntrack-extra \
		kmod-ipt-filter

	# ------------------------------------------- third-party proxy frontends ---
	# Built into the repository, never installed.  Package names are taken from
	# the build system's own tmp/.packageinfo rather than guessed from the
	# Makefiles: these are LuCI apps whose package name comes from the directory,
	# so grepping for `define Package/` finds nothing.
	#
	# The daemon, its LuCI app AND its Chinese translation are all listed.  A user
	# who runs `apk add luci-app-passwall` and gets a UI with no Chinese is the
	# failure this prevents -- upstream ships the translation as its own package
	# and nothing pulls it in automatically.
	emit_service "" \
		luci-app-passwall luci-i18n-passwall-zh-cn \
		luci-app-passwall2 luci-i18n-passwall2-zh-cn \
		luci-app-momo luci-i18n-momo-zh-cn momo \
		luci-app-fchomo luci-i18n-fchomo-zh-cn mihomo \
		luci-app-nekobox luci-theme-spectra \
		luci-app-xray luci-app-xray-geodata luci-app-xray-status \
		luci-app-hijpass luci-i18n-hijpass-zh-cn \
		v2raya luci-app-v2raya

	# Cores and helpers PassWall/PassWall2/HiJpass need that the official feeds do
	# not carry, from the pruned openwrt-passwall-packages checkout.
	emit_service "" \
		chinadns-ng dns2socks geoview hysteria ipt2socks naiveproxy \
		shadow-tls tcping v2ray-plugin xray-plugin \
		shadowsocks-rust-sslocal shadowsocks-rust-ssserver \
		shadowsocksr-libev-ssr-local shadowsocksr-libev-ssr-redir \
		shadowsocksr-libev-ssr-server \
		simple-obfs-client simple-obfs-server

	# Translations for the frontends that were already listed.  Some arrive on
	# their own because luci.mk selects the configured language, but naming them
	# is what turns "the Chinese UI is present" into a checked property.
	emit_service "" \
		luci-i18n-nikki-zh-cn luci-i18n-mosdns-zh-cn luci-i18n-homeproxy-zh-cn

	return 0
}

build_required_packages() {
	REQUIRED_PACKAGES=()
	REPO_PACKAGES=(
		luci
		luci-base
		luci-ssl
		luci-mod-admin-full
		luci-app-firewall
		luci-app-package-manager
		luci-i18n-base-zh-cn
	)
	is_true "$ENABLE_FANCONTROL" && REQUIRED_PACKAGES+=(luci-app-h5000m-fancontrol kmod-hwmon-pwmfan)
	is_true "$ENABLE_NETMODE"    && REQUIRED_PACKAGES+=(luci-app-h5000m-netmode)
	is_true "$ENABLE_WWAND"      && REQUIRED_PACKAGES+=(wwand wwand-qmi wwand-ncm wwand-mbim luci-app-wwand luci-proto-wwand)
	is_true "$ENABLE_MT5700M"    && REQUIRED_PACKAGES+=(luci-app-mt5700m ubus-at-daemon sms-tool_q)
	is_true "$ENABLE_THEME_ARGON" && REQUIRED_PACKAGES+=(luci-theme-argon luci-app-argon-config)
	REQUIRED_PACKAGES+=(h5000m-integration luci-app-h5000m-accel kmod-tcp-bbr
		kmod-nft-socket kmod-nft-tproxy)
	is_true "$ENABLE_REPO_PACKAGES" && REPO_PACKAGES+=(luci-app-ssr-plus chinadns-ng)

	# Optional switches are verified too, and for a specific reason: `make
	# defconfig` exits 0 even when a requested package does not exist, it just
	# drops the symbol.  Measured: feeding it the 30 package names the reference
	# harness used but mainline lacks left 20 of them silently absent and
	# produced no diagnostic naming any of them.  Without these entries a typo
	# in a package name, or an upstream package being removed, would ship a
	# firmware that quietly lacks the feature the switch promised.
	is_true "$ENABLE_DOCKERMAN"   && REQUIRED_PACKAGES+=(docker dockerd containerd runc luci-app-dockerman)
	is_true "$ENABLE_NIKKI"       && REQUIRED_PACKAGES+=(nikki mihomo-meta luci-app-nikki)
	is_true "$ENABLE_OPENCLASH"   && REQUIRED_PACKAGES+=(luci-app-openclash)
	is_true "$ENABLE_MOSDNS"      && REQUIRED_PACKAGES+=(mosdns luci-app-mosdns)
	# The ucode module and the two TUN packages are listed here too: a
	# configuration that drops them builds a HomeProxy that cannot start, and
	# `make defconfig` drops requests silently rather than failing.
	is_true "$ENABLE_HOMEPROXY"   && REQUIRED_PACKAGES+=(luci-app-homeproxy ucode-mod-math ip-full kmod-tun)
	# Mesh and SSR-Plus.  Both are Lua-era LuCI apps, so luci-compat is not
	# optional: without it the pages do not render under mainline's JS LuCI.
	is_true "$ENABLE_EASYMESH"    && REQUIRED_PACKAGES+=(luci-app-easymesh dawn batctl-default kmod-batman-adv luci-compat)
	is_true "$ENABLE_ADGUARDHOME" && REQUIRED_PACKAGES+=(adguardhome luci-app-adguardhome)
	is_true "$ENABLE_UPNP"        && REQUIRED_PACKAGES+=(luci-app-upnp miniupnpd-nftables)
	is_true "$ENABLE_ADBLOCK"     && REQUIRED_PACKAGES+=(adblock luci-app-adblock)

	# Required, not cosmetic.  Every line above is `is_true X && ...`, so when
	# the LAST switch is off the final statement returns 1 and — because this
	# function is called as a plain statement under `set -e` — the whole build
	# dies with no message at all.  Before the optional packages were added here
	# the last line was an unconditional `REQUIRED_PACKAGES+=(...)`, which hid
	# the trap.  It surfaced as the `minimal` coverage profile failing right
	# after the second defconfig with a log that simply stopped.
	return 0
}

# Packages that should be there but whose absence is only worth a warning: the
# translation sub-packages generated by luci.mk from a plugin's po/ tree.  Their
# exact name depends on LuCI's language-suffix mapping, so a rename upstream
# must not fail an otherwise good firmware.
build_expected_packages() {
	EXPECTED_PACKAGES=()
	is_true "$ENABLE_FANCONTROL" && EXPECTED_PACKAGES+=(luci-i18n-h5000m-fancontrol-zh-cn)
	is_true "$ENABLE_NETMODE"    && EXPECTED_PACKAGES+=(luci-i18n-h5000m-netmode-zh-cn)
	is_true "$ENABLE_UPNP"       && EXPECTED_PACKAGES+=(luci-i18n-upnp-zh-cn)
	is_true "$ENABLE_ADBLOCK"    && EXPECTED_PACKAGES+=(luci-i18n-adblock-zh-cn)
	return 0
}

configure_build() {
	cd "$SRC"

	prepare_config_stage

	log "Writing .config"
	cp -f "${ROOT_DIR}/configs/h5000m.config" .config
	printf '\n' >> .config
	append_board_stack_config .config
	append_optional_config .config

	log "Running defconfig"
	run_with_timeout "$CONFIG_TIMEOUT" make defconfig \
		|| die "make defconfig failed"

	# defconfig silently drops symbols whose dependencies were not satisfied.
	# Re-assert the ones this image is defined by, then fold the result again.
	#
	# The language gate has to be re-asserted with the packages: every
	# luci-i18n-<app>-zh-cn package defaults to LUCI_LANG_zh_Hans, so if a
	# defconfig pass drops the language the translations silently disappear even
	# though each app is still enabled.
	config_set_symbol "CONFIG_LUCI_LANG_zh_Hans" "y"

	# Re-asserted for the same reason as the language: defconfig regenerates the
	# feed symbols, and losing this one puts a URL that does not exist back into
	# the image's apk sources, where it makes every `apk update` on the device
	# fail.  See the note in configs/h5000m.config.
	config_set_symbol "CONFIG_FEED_wwand" "m"

	build_required_packages
	local pkg
	for pkg in "${REQUIRED_PACKAGES[@]}"; do
		config_enable "$pkg"
	done
	run_with_timeout "$CONFIG_TIMEOUT" make defconfig \
		|| die "second make defconfig failed"

	# ccache last, and after defconfig rather than in the seed, because its
	# Kconfig is `bool "Use ccache" if DEVEL` and defconfig drops it whenever
	# DEVEL is unset.  Turning DEVEL on instead would pull in debug information
	# and cost more build time than the cache saves.  rules.mk only tests
	# `ifneq ($(CONFIG_CCACHE),)`, so a value written after defconfig is enough.
	# That is what makes the CI ccache cache actually fill: without it every run
	# restored an empty directory and rebuilt everything.
	config_set_symbol "CONFIG_CCACHE" "y"

	# SSR-Plus is a repository package, like every other proxy front-end, but
	# defconfig promotes it to =y on its own.  A =y app pulls nothing, so the
	# image would grow by an app whose cores are only in the repository — the
	# front-end installed with no backend, which is the one combination that
	# helps nobody.  Forced back to =m after the final defconfig, the same way
	# the feed and ccache symbols above are.
	config_set_symbol "CONFIG_PACKAGE_luci-app-ssr-plus" "m"
}

# OpenWrt gates .config on $(STAGING_DIR_HOST)/.prereq-build, whose recipe runs
# the *full* host prerequisite check — including tools such as unzip and rsync
# that only a compile needs.  Configuring a tree compiles nothing, so for
# --prepare-only / --config-only we satisfy that stamp directly and let a config
# change be linted on a lightweight host.  A real build always goes through the
# real gate, so a genuinely under-provisioned build host still fails early.
prepare_config_stage() {
	local stamp

	if ! is_true "$CONFIG_ONLY" && ! is_true "$PREPARE_ONLY"; then
		return 0
	fi

	stamp="${SRC}/staging_dir/host/.prereq-build"
	mkdir -p "$(dirname "$stamp")"
	touch "$stamp"

	log "Configuration stage: host prerequisite gate satisfied directly (nothing is compiled)"
}

config_symbol_is_set() {
	grep -q "^CONFIG_PACKAGE_$1=y$" "$SRC/.config"
}

# Repository packages are legitimately =m, so the =y test above would report them
# as dropped.  =m proves the symbol survived defconfig just as well; what it does
# not prove is that the package is installed, which is exactly the distinction
# between the two lists.
config_symbol_present() {
	grep -qE "^CONFIG_PACKAGE_$1=[ym]$" "$SRC/.config"
}

verify_config() {
	local pkg missing=()

	build_required_packages
	for pkg in "${REQUIRED_PACKAGES[@]}"; do
		config_symbol_is_set "$pkg" || missing+=("$pkg")
	done
	for pkg in "${REPO_PACKAGES[@]:-}"; do
		config_symbol_present "$pkg" || missing+=("$pkg")
	done

	if [ "${#missing[@]}" -gt 0 ]; then
		printf '\n' >&2
		for pkg in "${missing[@]}"; do
			warn "required package did not survive defconfig: ${pkg}"
		done
		die "Configuration is missing required packages — refusing to build a firmware without ${missing[*]}"
	fi

	# Board target must be the H5000M, not a generic filogic profile.
	grep -q "^CONFIG_TARGET_${TARGET_BOARD}_${TARGET_SUBTARGET}_DEVICE_${TARGET_PROFILE}=y$" "$SRC/.config" \
		|| die "target profile ${TARGET_PROFILE} is not selected in .config"

	log "Verified ${#REQUIRED_PACKAGES[@]} required packages and target profile ${TARGET_PROFILE}"

	build_expected_packages
	for pkg in "${EXPECTED_PACKAGES[@]}"; do
		config_symbol_is_set "$pkg" || warn "expected package is absent: ${pkg}"
	done
}

dump_enabled_packages() {
	local out="$ART/enabled-packages.txt" n

	mkdir -p "$ART"

	# This file lists .config SYMBOLS, which is not the same set as the packages
	# in the image.  Two differences bite anyone who diffs it against the
	# manifest and concludes that packages went missing:
	#
	#   * ABI-versioned libraries appear under their symbol alias here and under
	#     their real name in the manifest — libubox vs libubox20260721,
	#     libgcc vs libgcc1, jansson vs jansson4.
	#   * Some symbols are build-time knobs, not installable packages at all:
	#     MAC80211_DEBUGFS, TAR_GZIP, trusted-firmware-a-mt7981-ram-ddr3.
	#
	# The authoritative answer to "what is in the image" is the .manifest, which
	# collect_artifacts() copies next to this file.  Say so in the file itself.
	{
		printf '# .config symbols set to =y for this build.\n'
		printf '# NOT the package list of the image: ABI-versioned libraries show their\n'
		printf '# symbol alias here (libubox, libgcc1 -> libgcc) and some entries are\n'
		printf '# build-time knobs rather than packages (MAC80211_DEBUGFS, TAR_GZIP,\n'
		printf '# trusted-firmware-a-*).  For the installed set see the .manifest.\n'
		grep '^CONFIG_PACKAGE_.*=y$' "$SRC/.config" \
			| sed 's/^CONFIG_PACKAGE_//; s/=y$//' | sort
	} > "$out"

	n="$(grep -vc '^#' "$out")"
	log "Wrote ${out} (${n} enabled .config symbols)"
}

# ---------------------------------------------------------------- build ------
prefetch_and_toolchain() {
	cd "$SRC"

	if is_true "$SKIP_DOWNLOAD"; then
		log "Skipping source download (--skip-download)"
	else
		log "Prefetching sources (make download)"
		run_with_timeout "$DOWNLOAD_TIMEOUT" make download -j"${THREADS}" \
			|| warn "make download reported failures; the compile step will retry them"
	fi

	if is_true "$SKIP_TOOLCHAIN"; then
		log "Skipping explicit toolchain prebuild (--skip-toolchain)"
		return 0
	fi

	log "Building toolchain (this is the long part)"
	run_with_timeout "$TOOLCHAIN_TIMEOUT" make toolchain/install -j"${THREADS}" \
		|| die "Toolchain build failed"
}

compile_firmware() {
	cd "$SRC"

	log "Compiling firmware with ${THREADS} jobs — this takes a while"

	local start make_pid heartbeat_pid
	start="$(date +%s)"

	make -j"${THREADS}" &
	make_pid=$!

	# Heartbeat so CI logs show progress instead of going quiet for hours.
	(
		while kill -0 "$make_pid" 2>/dev/null; do
			sleep "$HEARTBEAT_INTERVAL"
			kill -0 "$make_pid" 2>/dev/null || break
			log "still compiling... $(( ($(date +%s) - start) / 60 )) min elapsed"
		done
	) &
	heartbeat_pid=$!

	if ! wait "$make_pid"; then
		kill "$heartbeat_pid" 2>/dev/null || true
		die "Firmware compilation failed"
	fi

	kill "$heartbeat_pid" 2>/dev/null || true
	wait "$heartbeat_pid" 2>/dev/null || true

	log "Compilation finished in $(( ($(date +%s) - start) / 60 )) min"
}

# Assemble a single flat apk repository containing every package this build
# produced, with one freshly generated index.
#
# Why flat rather than OpenWrt's <arch>/<feed>/ tree: the firmware has to be
# told where the repository lives, and that list is written into the image
# BEFORE anything is compiled (install_local_packages runs early), so it cannot
# be derived from which feed directories ended up non-empty.  A flat repository
# needs exactly one URL and one index, which removes that ordering problem
# entirely — and removes the empty-feed problem with it, since there are no
# per-feed directories to be empty.
#
# Both package sets must be present for the repository to be useful:
#   bin/packages/<arch>/<feed>/            architecture-generic packages
#   bin/targets/<board>/<subtarget>/packages/   every kmod
# The kmods are the part a user cannot get anywhere else: the official snapshot
# repository's kmods carry a different vermagic and this kernel refuses them.
build_apk_repository() {
	local dest="$1"
	local repo="${dest}/apk-repo"
	local apk_tool=""
	local count

	mkdir -p "$repo"

	# Collect from both locations.  cp -a on the tree would keep the per-feed
	# directories; this flattens deliberately.
	find "${SRC}/bin/packages/${TARGET_ARCH}" -mindepth 2 -maxdepth 2 -name '*.apk' \
		-exec cp -f {} "$repo/" \; 2>/dev/null || true
	find "${SRC}/bin/targets/${TARGET_BOARD}/${TARGET_SUBTARGET}/packages" -maxdepth 1 -name '*.apk' \
		-exec cp -f {} "$repo/" \; 2>/dev/null || true

	count="$(find "$repo" -maxdepth 1 -name '*.apk' | wc -l)"
	if [ "$count" -eq 0 ]; then
		warn "No .apk files found; the apk repository will be empty"
		return 0
	fi

	# Prefer the host apk built by this tree, so the index format matches the
	# apk the firmware ships.
	if [ -x "${SRC}/staging_dir/host/bin/apk" ]; then
		apk_tool="${SRC}/staging_dir/host/bin/apk"
	elif command -v apk >/dev/null 2>&1; then
		apk_tool="$(command -v apk)"
	fi

	if [ -z "$apk_tool" ]; then
		warn "No apk tool available; shipping packages without an index (apk cannot read it)"
		return 0
	fi

	# Sign the index with this build's key.  Every device built from this tree
	# trusts the matching public key, because OpenWrt installs it at
	# /etc/apk/keys/public-key.pem — and that file is byte-identical to
	# ${SRC}/public-key.pem.  Without this, `apk update` on the device prints
	#
	#   WARNING: updating <url>: UNTRUSTED signature
	#
	# Verified both ways against the firmware's own apk: unsigned gives that
	# warning, signed gives "OK: N distinct packages available".
	#
	# --allow-untrusted still applies to the .apk files themselves, which carry
	# no signature this host trusts; the index is what the target verifies.
	sign_args=()
	if [ -f "${SRC}/private-key.pem" ]; then
		sign_args=(--sign-key "${SRC}/private-key.pem")
	else
		warn "No ${SRC}/private-key.pem; the index will be unsigned and devices will warn about an untrusted signature"
	fi

	# shellcheck disable=SC2046
	"$apk_tool" mkndx --allow-untrusted "${sign_args[@]}" -o "${repo}/packages.adb" $(find "$repo" -maxdepth 1 -name '*.apk') \
		|| die "apk mkndx failed — the repository would be unreadable"

	if [ "${#sign_args[@]}" -gt 0 ]; then
		log "Signed ${repo}/packages.adb with the build key"
	fi

	# Ship the public key with the repository.  The publish job runs on a fresh
	# runner with only this artifact — it has no openwrt/ tree to look in — so
	# the key has to travel inside the artifact.  Devices flashed before the key
	# was fixed fetch it from the same place as the index.
	if [ -f "${SRC}/public-key.pem" ]; then
		cp -f "${SRC}/public-key.pem" "${repo}/public-key.pem"
		log "Repository public key: ${repo}/public-key.pem"
	fi

	log "Built apk repository: ${count} packages, $(du -sh "$repo" | cut -f1)"
	return 0
}

collect_artifacts() {
	local bin_dir="${SRC}/bin/targets/${TARGET_BOARD}/${TARGET_SUBTARGET}"
	local dest="${ART}"

	[ -d "$bin_dir" ] || die "No build output at ${bin_dir}"

	mkdir -p "$dest"

	# Wipe last run's package output first.  These directories are copied into,
	# not replaced, so without this a second build leaves the previous build's
	# .apk files behind — observed as both base-files-1~f0d3e33.apk (the pinned
	# revision) and base-files-1~d0d8c40.apk (the next one) sitting in the same
	# directory, i.e. a published repository mixing two kernel ABIs.
	rm -rf "${dest}/packages" "${dest}/apk-repo"

	log "Collecting artifacts from ${bin_dir}"
	# Images + the metadata needed to install a matching plugin later: the
	# kernel ABI is what ties luci-app-h5000m-* packages to this firmware.
	# The rootfs tarballs are included because this config builds them
	# (CONFIG_TARGET_ROOTFS_TARGZ) and they are the artifact used for a
	# container/chroot or a manual sysupgrade.
	find "$bin_dir" -maxdepth 1 -type f \
		\( -name '*.bin' -o -name '*.itb' -o -name '*.tar.gz' -o -name '*.img.gz' \
		   -o -name '*.manifest' -o -name 'profiles.json' -o -name 'sha256sums' \
		   -o -name 'version.buildinfo' -o -name 'config.buildinfo' -o -name 'feeds.buildinfo' \) \
		-exec cp -f {} "$dest/" \;

	if [ -d "${bin_dir}/packages" ]; then
		mkdir -p "${dest}/packages"
		find "${bin_dir}/packages" -maxdepth 1 -type f -name '*.apk' -exec cp -f {} "${dest}/packages/" \;
	fi

	build_apk_repository "$dest"

	write_build_info "$dest"

	log "Artifacts:"
	ls -la "$dest"
}

write_build_info() {
	local dest="$1" rev desc ver code kver abi
	local profiles="${dest}/profiles.json"

	rev="$(cat "${ROOT_DIR}/.upstream-revision" 2>/dev/null || echo unknown)"
	desc="$(cat "${ROOT_DIR}/.upstream-describe" 2>/dev/null || echo unknown)"

	# The authoritative version/kernel data is the target's profiles.json, which
	# the build writes into bin/targets/<target>/<subtarget>/ and collect_artifacts
	# has already copied here.  version.buildinfo is NOT a key=value file — it is
	# the bare output of scripts/getver.sh — so parsing it for kernel_version
	# silently produced "unknown".
	#
	# linux_kernel.vermagic is the kernel ABI hash: it is what a separately built
	# plugin .apk must match to be installable on this image.
	if [ -f "$profiles" ] && command -v python3 >/dev/null 2>&1; then
		eval "$(python3 - "$profiles" <<'PY'
import json, shlex, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
k = d.get("linux_kernel") or {}
for name, val in (
    ("code", d.get("version_code")),
    ("ver", d.get("version_number")),
    ("kver", k.get("version")),
    ("abi", k.get("vermagic")),
):
    if val:
        print(f"{name}={shlex.quote(str(val))}")
PY
)"
	fi

	# A shallow clone carries no tags, so scripts/getver.sh can only produce
	# `r0-<sha>`: the revision counter is derived from the nearest base tag plus
	# the commit count, and --depth 1 has neither.  When we built exactly the
	# revision this project pins, record the published snapshot id instead of a
	# misleading r0.  Any other revision keeps the tree-derived value, because
	# inventing a snapshot number we did not verify would be worse.
	if [ -n "${OPENWRT_PINNED_SNAPSHOT:-}" ] && [ -n "${OPENWRT_PINNED_REVISION:-}" ] \
		&& [ "$rev" = "$OPENWRT_PINNED_REVISION" ]; then
		code="$OPENWRT_PINNED_SNAPSHOT"
	fi

	cat > "${dest}/BUILD-INFO.txt" <<EOF
project=AutoBuild-H5000M-Openwrt
upstream_url=${REPO_URL}
upstream_branch=${REPO_BRANCH}
upstream_track=${OPENWRT_TRACK}
openwrt_revision=${rev}
openwrt_version_code=${code:-unknown}
openwrt_version_number=${ver:-unknown}
openwrt_describe=${desc}
kernel_version=${kver:-unknown}
kernel_abi=${abi:-unknown}
target=${TARGET_BOARD}/${TARGET_SUBTARGET}
profile=${TARGET_PROFILE}
arch=${TARGET_ARCH}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
enable_fancontrol=${ENABLE_FANCONTROL}
enable_netmode=${ENABLE_NETMODE}
enable_wwand=${ENABLE_WWAND}
enable_mt5700m=${ENABLE_MT5700M}
enable_upnp=${ENABLE_UPNP}
enable_adblock=${ENABLE_ADBLOCK}
enable_dockerman=${ENABLE_DOCKERMAN}
EOF

	log "Wrote ${dest}/BUILD-INFO.txt (kernel ${kver:-?}, abi ${abi:-?})"
}

# ----------------------------------------------------------------- main ------
main() {
	cd "$ROOT_DIR"
	: > "$LOG_FILE"

	if is_true "$INSTALL_DEPS"; then
		install_deps
		check_environment
		log "Build dependencies installed."
		# Stop here.  This used to fall through, so `--install-deps` installed
		# the packages and then carried on into prepare_source, feeds, patches
		# and the whole build — which is why the CI step named "Install build
		# dependencies" was observed running "Building toolchain", and why it
		# took over thirty minutes instead of three.  A flag that says it
		# installs dependencies should do exactly that and return.
		exit 0
	fi
	check_environment
	resolve_modem_stack
	show_features

	prepare_source
	install_signing_key
	seed_cached_toolchain
	seed_cached_build_state
	prepare_feeds
	apply_patches
	install_local_packages
	install_board_plugins
	install_theme
	install_external_packages
	fix_mirror_hashes

	# After every source tree is in place: feeds, board plugins, theme and the
	# external package clones all add directories that the build hashes.
	normalize_source_mtimes
	install_proxy_repos
	configure_build
	verify_config
	dump_enabled_packages

	if is_true "$PREPARE_ONLY"; then
		log "Prepare-only requested; stopping before download/build"
		exit 0
	fi
	if is_true "$CONFIG_ONLY"; then
		log "Config-only requested; stopping before download/build"
		exit 0
	fi

	prefetch_and_toolchain
	compile_firmware
	collect_artifacts

	log "Done."
}

main "$@"
