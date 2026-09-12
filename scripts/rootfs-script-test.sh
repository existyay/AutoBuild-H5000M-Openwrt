#!/usr/bin/env bash
#
# rootfs-script-test.sh — run the firmware's own first-boot scripts against the
# REAL aarch64 uci binary, on the host, without root.
#
# Why this exists: the first-boot defaults were written, reviewed, and "verified"
# with a shell mock of uci — and shipped a bug that made both headline features
# silently do nothing.  The script called
#
#     uci -q set "wireless.radio0.disabled='0'"
#
# where the quotes sit INSIDE the double-quoted argument, so uci stores the value
# as the literal `'0'` rather than `0`.  OpenWrt's config_get_bool does not
# recognise `'0'` as false and falls back to the default, so the radio stayed
# disabled while /etc/config/wireless looked correct.  A mock that echoes back
# whatever string it is handed cannot catch that; the real parser can.  Note that
# `uci batch` DOES strip the quotes, so both forms are in use in this tree and
# only one of them is wrong.
#
# How it works: the rootfs tarball is extracted, and the aarch64 uci from that
# rootfs is executed under qemu-aarch64-static with `-c` pointing at a scratch
# config directory.  qemu-user alone would resolve absolute paths against the
# host, and `-L` only fixes the loader, so `-c` is what keeps the test away from
# the host's own /etc — verified: this never writes to the host /etc/config.
#
# Requirements: qemu-aarch64-static on PATH or in $QEMU_AARCH64.
#   curl -sfL -o ~/.local/bin/qemu-aarch64-static \
#     https://github.com/multiarch/qemu-user-static/releases/latest/download/qemu-aarch64-static
#   chmod +x ~/.local/bin/qemu-aarch64-static
#
# Usage: scripts/rootfs-script-test.sh [path/to/rootfs.tar.gz]
#
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_TARBALL="${1:-${ROOT_DIR}/artifacts/openwrt-mediatek-filogic-hiveton_h5000m-rootfs.tar.gz}"
QEMU_AARCH64="${QEMU_AARCH64:-$(command -v qemu-aarch64-static || true)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok()   { printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
check() { # check <description> <expected> <actual>
	if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected [$2], got [$3]"; fi
}

[ -n "$QEMU_AARCH64" ] || { echo "qemu-aarch64-static not found; see the header of this script" >&2; exit 2; }
[ -f "$ROOTFS_TARBALL" ] || { echo "rootfs tarball not found: $ROOTFS_TARBALL" >&2; exit 2; }

echo "== extracting $(basename "$ROOTFS_TARBALL")"
mkdir -p "$WORK/root"
tar -xzf "$ROOTFS_TARBALL" -C "$WORK/root"

UCI="$WORK/root/sbin/uci"
[ -x "$UCI" ] || { echo "no uci in the rootfs" >&2; exit 2; }
file "$UCI" | grep -q aarch64 || { echo "$UCI is not aarch64 — wrong artifact?" >&2; exit 2; }

# The real uci, with -c so it reads and writes our scratch config dir and never
# the host's /etc/config.
mkdir -p "$WORK/bin" "$WORK/config"
cat > "$WORK/bin/uci" <<EOF
#!/bin/sh
exec "${QEMU_AARCH64}" -L "$WORK/root" "$UCI" -c "$WORK/config" "\$@"
EOF
chmod +x "$WORK/bin/uci"
export PATH="$WORK/bin:$PATH"

# The script under test, with its absolute runtime paths redirected.  Only the
# paths change; the uci invocations are exactly what ships.
SCRIPT="$WORK/root/usr/sbin/h5000m-firstboot"
[ -f "$SCRIPT" ] || { echo "h5000m-firstboot missing from the rootfs" >&2; exit 2; }
sed -e "s|/etc/config/|$WORK/config/|g" \
    -e "s|/etc/h5000m-defaults.conf|$WORK/h5000m-defaults.conf|g" \
    -e "s|/etc/h5000m-defaults-applied|$WORK/marker|g" \
    -e 's|^\[ -n "${IPKG_INSTROOT:-}" \]|false|' \
    "$SCRIPT" > "$WORK/firstboot"

# /etc/h5000m-defaults.conf as the package installs it.
cp "$WORK/root/etc/h5000m-defaults.conf" "$WORK/h5000m-defaults.conf"
# shellcheck source=/dev/null
. "$WORK/h5000m-defaults.conf"

seed_wireless() { # seed_wireless <ssid>
	cat > "$WORK/config/wireless" <<EOF
config wifi-device 'radio0'
	option type 'mac80211'
	option band '2g'
	option disabled '1'

config wifi-device 'radio1'
	option type 'mac80211'
	option band '5g'
	option disabled '1'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option mode 'ap'
	option ssid '$1'

config wifi-iface 'default_radio1'
	option device 'radio1'
	option mode 'ap'
	option ssid '$1'
EOF
	printf "config defaults\n\toption input 'REJECT'\n" > "$WORK/config/firewall"
	rm -f "$WORK/marker"
}

echo
echo "== profile: untouched first boot — WiFi must come up and offload turn on"
seed_wireless OpenWrt
sh "$WORK/firstboot"

check "radio0.country"       "$H5000M_WIFI_COUNTRY"  "$(uci -q get wireless.radio0.country)"
check "radio0.disabled"      "0"                     "$(uci -q get wireless.radio0.disabled)"
check "radio0.htmode"        "$H5000M_WIFI_HTMODE_2G" "$(uci -q get wireless.radio0.htmode)"
check "radio1.htmode"        "$H5000M_WIFI_HTMODE_5G" "$(uci -q get wireless.radio1.htmode)"
check "default_radio0.ssid"  "$H5000M_WIFI_SSID"     "$(uci -q get wireless.default_radio0.ssid)"
check "default_radio0.key"   "$H5000M_WIFI_KEY"      "$(uci -q get wireless.default_radio0.key)"
check "default_radio0.enc"   "$H5000M_WIFI_ENCRYPTION" "$(uci -q get wireless.default_radio0.encryption)"
check "flow_offloading"      "$H5000M_FLOW_OFFLOAD"  "$(uci -q get firewall.@defaults[0].flow_offloading)"
check "flow_offloading_hw"   "$H5000M_FLOW_OFFLOAD_HW" "$(uci -q get firewall.@defaults[0].flow_offloading_hw)"

# The bug this test was written for: a value stored with literal quotes still
# reads back looking plausible, so assert on the raw file too.
if grep -q "disabled ''" "$WORK/config/wireless"; then
	bad "wireless config holds quote-wrapped values (uci set \"k='v'\" bug)"
else
	ok "wireless config has no quote-wrapped values"
fi

echo
echo "== profile: owner already changed the SSID — nothing may be touched"
seed_wireless MyOwnWiFi
sh "$WORK/firstboot"
check "ssid preserved"        "MyOwnWiFi" "$(uci -q get wireless.default_radio0.ssid)"
check "radio0.disabled kept"  "1"         "$(uci -q get wireless.radio0.disabled)"
check "offload still applied" "$H5000M_FLOW_OFFLOAD" "$(uci -q get firewall.@defaults[0].flow_offloading)"

echo
echo "== profile: marker present — second boot must be a no-op"
seed_wireless OpenWrt
touch "$WORK/marker"
sh "$WORK/firstboot"
check "radio0.disabled kept"  "1"  "$(uci -q get wireless.radio0.disabled)"
check "offload not applied"   ""   "$(uci -q get firewall.@defaults[0].flow_offloading)"

printf '\n\033[1m== summary ==\033[0m\n  passed: %s\n  failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "  the first-boot scripts behave correctly under the real uci"
