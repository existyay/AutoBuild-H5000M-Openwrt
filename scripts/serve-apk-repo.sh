#!/usr/bin/env bash
#
# serve-apk-repo.sh — serve artifacts/apk-repo/ over HTTP and print the exact
# build command that points a firmware at it.
#
# Why this exists: the package repository this project builds has to be reachable
# from the router for `apk add luci-app-passwall` to work.  There is no hosting
# until someone provides it, and shipping a URL that does not resolve makes
# `apk update` fail on every device — which is exactly the mistake an earlier
# revision of this project made.  Rather than guess a URL, this serves the
# directory from the build host and tells you what to build with.
#
# The device must be able to reach the host's address, so this is for a router on
# the same LAN as the build machine.  For anything permanent, host
# artifacts/apk-repo/ on any static server and pass its URL to
# H5000M_APK_REPO_URL instead — the repository is flat (one packages.adb and the
# .apk files beside it), so any directory-serving host works.
#
# Usage:
#   scripts/serve-apk-repo.sh [port]      # default 8099
#
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${ROOT_DIR}/artifacts/apk-repo"
PORT="${1:-8099}"

if [ ! -f "${REPO_DIR}/packages.adb" ]; then
	echo "No repository at ${REPO_DIR}/packages.adb" >&2
	echo "Build one first:  scripts/local-build.sh" >&2
	exit 2
fi

# Prefer the address that is actually routable to the router.  A VPN or docker
# bridge address is the wrong answer, so ask the routing table which source
# address would be used to reach a public destination.
host_ip() {
	local ip
	ip="$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)"
	[ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
	echo "${ip:-127.0.0.1}"
}

IP="$(host_ip)"
URL="http://${IP}:${PORT}"
COUNT="$(find "$REPO_DIR" -maxdepth 1 -name '*.apk' | wc -l)"

cat <<EOF
Serving ${REPO_DIR}
  ${COUNT} packages + packages.adb

  Rebuild the firmware pointing at this host:

      H5000M_APK_REPO_URL=${URL} scripts/local-build.sh

  Or, on a device that is already flashed, add the line to the file OpenWrt
  reserves for extra sources and refresh:

      echo '${URL}/packages.adb' >> /etc/apk/repositories.d/customfeeds.list
      apk update

  Check it is reachable before flashing:

      curl -sf ${URL}/packages.adb | wc -c

Press Ctrl-C to stop.
EOF

cd "$REPO_DIR"
exec python3 -m http.server "$PORT" --bind 0.0.0.0
