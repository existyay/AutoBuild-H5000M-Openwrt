#!/usr/bin/env bash
#
# coverage-test.sh — run several ENABLE_* profiles through --config-only to
# catch configuration regressions without paying for a full firmware build.
#
# This is the migrated equivalent of Auto-H5000M-BIN's coverage-test.sh: the
# point is that every switch combination the workflow offers still produces a
# .config that satisfies verify_config(), not that the firmware boots.
#
# Usage:
#   scripts/coverage-test.sh quick     # default + the two modem stacks
#   scripts/coverage-test.sh full      # everything below
#
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_SET="${1:-quick}"
SOURCE_DIR="${SOURCE_DIR:-openwrt}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-artifacts-coverage}"

export SOURCE_DIR ARTIFACTS_DIR

pass=0
fail=0
failed_profiles=()

run_profile() {
	local name="$1"
	shift
	local log="${ROOT_DIR}/coverage-${name}.log"

	printf '\n\033[1;36m== profile: %s ==\033[0m\n' "$name"

	prune_clones

	# Feeds are identical across profiles — only the first run pays for them.
	if PREPARE_ONLY=false SKIP_FEEDS_UPDATE="${SKIP_FEEDS_UPDATE:-false}" \
		THREADS="${THREADS:-$(nproc)}" "$@" \
		bash "${ROOT_DIR}/scripts/local-build.sh" --config-only >"$log" 2>&1; then
		printf '   \033[1;32mPASS\033[0m (%s)\n' "$log"
		pass=$((pass + 1))
	else
		printf '   \033[1;31mFAIL\033[0m — tail of %s:\n' "$log"
		tail -25 "$log" | sed 's/^/     /'
		fail=$((fail + 1))
		failed_profiles+=("$name")
	fi

	# Every later profile reuses the feed checkout.
	export SKIP_FEEDS_UPDATE=true
}

# Every profile runs against the same openwrt/ checkout, and prepare_source does a
# `git reset --hard` but deliberately no `git clean` — so a tree that an earlier
# profile cloned into package/ is still there when a later profile turns its
# ENABLE_* switch off.  The `no-repo-packages` and `no-easymesh` profiles would
# then verify the "switch off" path in a tree that still contains what the switch
# is supposed to leave out: its config symbols still exist, so verify_config's
# "emitted package survived defconfig" check passes, and a configuration that
# only works WITH those trees present is never noticed.  Removing them first is
# what makes those two profiles mean anything.
#
# Safe to be this blunt: a clone is the only thing under package/ that carries
# its own .git (upstream's own packages are tracked by the OpenWrt repo), and
# install_local_packages/stage_directory strip .git from the local-packages
# copies, so those are never matched.  The next profile re-clones what it needs.
prune_clones() {
	local gitdir
	[ -d "${ROOT_DIR}/${SOURCE_DIR}/package" ] || return 0
	while IFS= read -r -d '' gitdir; do
		rm -rf "$(dirname "$gitdir")"
	done < <(find "${ROOT_DIR}/${SOURCE_DIR}/package" -mindepth 2 -maxdepth 2 -name .git -type d -print0 2>/dev/null)
	return 0
}

# quick: the three board-stack permutations the README documents, plus a profile
# that turns every optional switch on at once.
#
# `all-optional` is in the quick set on purpose.  Every ENABLE_* switch is a
# separate code path — its own clone URL, its own config symbols — and a switch
# that is never exercised in CI is a switch nobody has run.  That is not
# hypothetical: ENABLE_ADGUARDHOME pointed at a repository that does not exist,
# and because the failing clone ran under `set -e` it aborted the whole run.
# The `services` and `proxy-stack` profiles below would have caught it, but they
# live in `full`, which is not what CI runs on push.  One combined profile is
# cheap (all switches on once) and covers every switch individually.
run_profile default env
run_profile mt5700m env ENABLE_WWAND=false ENABLE_MT5700M=true
run_profile minimal env ENABLE_UPNP=false ENABLE_ADBLOCK=false ENABLE_FANCONTROL=false ENABLE_NETMODE=false
run_profile all-optional env ENABLE_DOCKERMAN=true ENABLE_NIKKI=true ENABLE_EBPF_PROXY_KERNEL=true ENABLE_OPENCLASH=true ENABLE_MOSDNS=true ENABLE_HOMEPROXY=true ENABLE_ADGUARDHOME=true ENABLE_ADBLOCK=true

if [ "$PROFILE_SET" = "full" ]; then
	run_profile services env ENABLE_DOCKERMAN=true ENABLE_ADGUARDHOME=true
	# adblock and adblock-fast share the DNS backends (dnsmasq-full + ipset) the
	# default profiles already carry; this exercises the ENABLE_ADBLOCK image path
	# and its classic-adblock dependency set.
	run_profile adblock env ENABLE_ADBLOCK=true
	run_profile proxy-stack env ENABLE_NIKKI=true ENABLE_OPENCLASH=true ENABLE_MOSDNS=true ENABLE_HOMEPROXY=true ENABLE_ADGUARDHOME=true
	# The eBPF kernel options are a separate code path (the CONFIG_KERNEL_*
	# writes and verify_config's live check), so the off case is exercised too.
	run_profile no-ebpf-kernel env ENABLE_EBPF_PROXY_KERNEL=false
	run_profile no-dialer env ENABLE_WWAND=false ENABLE_MT5700M=false
	run_profile no-argon env ENABLE_THEME_ARGON=false
	# `ENABLE_REPO_PACKAGES=false` was never exercised, although it is the switch
	# that keeps the three proxy trees out of package/ — a config that only works
	# with them present would not be noticed until a user turned them off.
	run_profile no-repo-packages env ENABLE_REPO_PACKAGES=false
	# Same for the easymesh feed (IPTV block in the config) and the optional
	# passwall/nikki/hijpass trees: both are off in the `minimal` profile but
	# that profile also drops upnp/adblock/fancontrol, so the off-path of the
	# easymesh stack on its own was untested.
	run_profile no-easymesh env ENABLE_EASYMESH=false
fi

printf '\n\033[1m== coverage summary ==\033[0m\n'
printf '  passed: %s\n  failed: %s\n' "$pass" "$fail"

if [ "$fail" -gt 0 ]; then
	printf '  failing profiles: %s\n' "${failed_profiles[*]}"
	exit 1
fi

echo "  all profiles produced a valid configuration"
