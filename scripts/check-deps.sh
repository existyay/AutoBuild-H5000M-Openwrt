#!/usr/bin/env bash
#
# check-deps.sh — verify the host can build mainline OpenWrt.
#
# Reports missing tools instead of installing them; `local-build.sh
# --install-deps` does the installation.  Exit code is the number of missing
# required tools, so CI can gate on it.
#
set -uo pipefail

REQUIRED=(git make gcc g++ python3 patch gawk unzip wget curl zstd find)
CONFIG_ONLY_REQUIRED=(git make gcc g++ python3 patch gawk find tar zstd)
RECOMMENDED=(rsync ccache timeout flock dtc fastjar gperf swig)
SWAP_HINT_GB=8
DISK_HINT_GB=30

missing_required=()
missing_recommended=()

for cmd in "${REQUIRED[@]}"; do
	command -v "$cmd" >/dev/null 2>&1 || missing_required+=("$cmd")
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

if [ "${#missing_required[@]}" -gt 0 ]; then
	echo
	echo "Run 'scripts/local-build.sh --install-deps' on Debian/Ubuntu, or install the equivalent packages."
	exit "${#missing_required[@]}"
fi

echo
echo "OK — host looks ready."
exit 0
