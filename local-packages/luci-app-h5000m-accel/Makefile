include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-h5000m-accel
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=AutoBuild-H5000M-Openwrt

LUCI_TITLE:=H5000M network acceleration (mainline flow offload)
# firewall4 and nftables are hard dependencies, not conveniences: the page's
# fullcone switch writes `firewall.@defaults[0].fullcone`, and that only changes
# anything because firewall4's zone-masq.uc reads it back and emits the
# `fullcone` statement in place of `masquerade`.  kmod-nft-fullcone is the
# expression that statement resolves to, so without it the switch would appear
# to work and silently do nothing.
#
# kmod-sched-core / kmod-sched-bpf carry the TC half of the eBPF proxy fast
# path (the clsact qdisc, cls_bpf and act_bpf).  The page loads them and reports
# whether they are available, so a standalone build gets them too.  The cgroup
# half is a kernel option (CONFIG_CGROUP_BPF), not a package, and the page
# reports it rather than pretending it can install it.
LUCI_DEPENDS:=+luci-base +firewall4 +nftables +kmod-nft-fullcone \
	+kmod-tcp-bbr +kmod-nf-flow +kmod-nft-offload \
	+kmod-sched-core +kmod-sched-bpf
LUCI_PKGARCH:=all

define Package/luci-app-h5000m-accel/conffiles
/etc/config/h5000m_accel
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
