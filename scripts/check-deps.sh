#!/usr/bin/env bash
#
# check-deps.sh — verify the host can build mainline OpenWrt.
#
# Reports missing tools instead of installing them; `local-build.sh
# --install-deps` does the installation.  Exit code is the number of missing
# required tools, so CI can gate on it.
#
set -uo pipefail

REQUIRED=(git make gcc g++ python3 patch gawk unzip wget curl zstd find tar)
CONFIG_ONLY_REQUIRED=(git make gcc g++ python3 patch gawk find tar zstd)
# Libraries without which configure fails, not compile — checked through
# pkg-config because a bare `command -v` cannot see them.  These are the ones
# `local-build.sh --install-deps` installs and this script used to stay silent
# about: on a host missing libncurses-dev it printed "OK — host looks ready"
# and the build then died in `make menuconfig`'s toolchain probe twenty
# minutes later.  bison/flex are here for the same reason (the kernel and the
# kmods regenerate parsers).
REQUIRED_PC=(ncurses:libncurses-dev openssl:libssl-dev libelf:libelf-dev gmp:libgmp-dev)
REQUIRED_TOOLS_FULL=(bison flex pkg-config)
RECOMMENDED=(rsync ccache timeout flock dtc fastjar gperf swig)
SWAP_HINT_GB=8
DISK_HINT_GB=30

missing_required=()
missing_full=()
missing_recommended=()

for cmd in "${REQUIRED[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || missing_required+=("$cmd")
done

for cmd in "${REQUIRED_TOOLS_FULL[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || missing_full+=("$cmd")
done

# pkg-config itself may be the very thing that is missing, in which case the
# library names are what has to be reported.  `--exists` prints nothing and is
# exactly the question worth asking: "is the .pc file there", i.e. is the -dev
# package installed rather than just the runtime library.
for entry in "${REQUIRED_PC[@]}"; do
	pc="${entry%%:*}"
	pkg="${entry#*:}"
	if command -v pkg-config >/dev/null 2>&1; then
		pkg-config --exists "$pc" >/dev/null 2>&1 || missing_full+=("$pkg")
	else
		missing_full+=("$pkg")
	fi
done

for cmd in "${RECOMMENDED[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || missing_recommended+=("$cmd")
done

echo "== configuration stage (feeds + defconfig) =="
missing_config=()
for cmd in "${CONFIG_ONLY_REQUIRED[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || missing_config+=("$cmd")
done
if [ "${#missing_config[@]}" -eq 0 ]; then
	echo "  ready — 'local-build.sh --config-only' can run"
else
	printf '  MISSING: %s\n' "${missing_config[*]}"
fi

echo
echo "== full firmware build =="
if [ "${#missing_required[@]}" -eq 0 ]; then
	echo "  all present (${REQUIRED[*]})"
else
	printf '  MISSING: %s\n' "${missing_required[*]}"
fi
if [ "${#missing_full[@]}" -eq 0 ]; then
	echo "  libraries present (ncurses, openssl, libelf, gmp + bison/flex/pkg-config)"
else
	printf '  MISSING: %s\n' "${missing_full[*]}"
	echo "  these fail 'configure', not the tool lookup, so they are counted below"
fi

echo
echo "== recommended tools =="
if [ "${#missing_recommended[@]}" -eq 0 ]; then
	echo "  all present (${RECOMMENDED[*]})"
else
	printf '  missing (not fatal): %s\n' "${missing_recommended[*]}"
fi

echo
echo "== host resources =="
awk -v hint="$DISK_HINT_GB" '
	/^MemTotal:/  { printf "  RAM : %.1f GiB\n", $2/1048576 }
	/^SwapTotal:/ { printf "  swap: %.1f GiB%s\n", $2/1048576, ($2/1048576 < hint ? "  (a small swap is normal on CI)" : "") }
' /proc/meminfo 2>/dev/null || true

avail_kb="$(df -Pk . 2>/dev/null | awk 'NR==2 { print $4 }')"
if [ -n "${avail_kb:-}" ]; then
	avail_gb=$((avail_kb / 1024 / 1024))
	printf '  disk: %s GiB free in the build directory (>= %s GiB recommended)\n' "$avail_gb" "$DISK_HINT_GB"
	if [ "$avail_gb" -lt "$DISK_HINT_GB" ]; then
		echo "  WARNING: a full toolchain + target build needs roughly ${DISK_HINT_GB} GiB"
	fi
fi

echo
printf '  jobs: %s\n' "$(nproc 2>/dev/null || echo '?')"

if [ "${#missing_required[@]}" -gt 0 ] || [ "${#missing_full[@]}" -gt 0 ]; then
	echo
	echo "Run 'scripts/local-build.sh --install-deps' on Debian/Ubuntu, or install the equivalent packages."
	exit "$(( ${#missing_required[@]} + ${#missing_full[@]} ))"
fi

echo
echo "OK — host looks ready."
exit 0
