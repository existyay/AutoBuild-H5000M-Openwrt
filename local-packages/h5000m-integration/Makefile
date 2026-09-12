#
# h5000m-integration — board glue for the Hiveton H5000M on mainline OpenWrt.
#
# The H5000M's built-in cellular module is a TD Tech MT5700M (USB 3466:3301)
# which enumerates as a cdc_ncm device with AT side channels.  wwand dials it
# through its NCM backend; luci-app-h5000m-netmode arbitrates between the wired
# WAN (eth1) and that cellular interface.
#
# The two daemons never meet on their own, so this package is the seam:
#
#   * luci-app-h5000m-netmode discovers the 5G side by NAME.  Its
#     discover_modem_interfaces() reads network.MT5700M.device / .ifname and
#     otherwise falls back to a section literally named MT5700M or USB.  Its
#     iface hotplug guard additionally ignores events for any interface that
#     carries neither `modem_config` nor `managed_by mt5700m`.
#
#   * wwand has no /etc/config/wwand — configuration lives in
#     /etc/config/network as `config wwand_modem` + `config interface`
#     with `option proto 'wwand'`.
#
# So the first-boot provisioner creates exactly that shape:
#
#   config wwand_modem 'm0'        option device/path -> the MT5700M
#   config interface 'MT5700M'     proto wwand, modem m0, modem_config set
#
# IPv6 is deliberately NOT given a companion dhcpv6 interface.  wwand's own
# docs (docs/reference.md, "RNDIS IPv6 — the dhcpv6 subinterface") are explicit
# that the `<parent>_6` dhcpv6 subinterface belongs to the **rndis_host**
# datapath, that `extendprefix '1'` applies **only to `pdp_type 'ipv6'`**, and
# that "the `proto wwand` path needs no equivalent — the shim already shares its
# own /64".  The MT5700M is a cdc_ncm modem on the proto wwand path, so a
# companion interface here would be wrong twice over: it would set prefix
# sharing on a dual-stack APN, and because wwand treats a user-defined
# `device '@<parent>'` + proto dhcpv6 section as "the user owns this", it would
# also stop wwand from managing IPv6 at all.
#
# Result: wwand owns the datapath and its own IPv6, netmode sees a first-class
# modem interface, and neither package is forked or patched.  If the module is
# not yet enumerated the provisioner leaves the box alone and wwand's own
# autosetup creates its default `wwan0`/`wwmodem_auto` interface instead.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=h5000m-integration
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=AutoBuild-H5000M-Openwrt <noreply@example.invalid>

include $(INCLUDE_DIR)/package.mk

define Package/h5000m-integration
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=Hiveton H5000M WWAN <-> netmode integration glue
  # Conditional, NOT a hard dependency.  `+wwand` would pull the whole wwand
  # stack into every image, including an ENABLE_MT5700M=true build where wwand
  # must be absent; with this form wwand is required only when it was already
  # selected, and the provisioner no-ops when the proto is missing.
  DEPENDS:=+PACKAGE_wwand:wwand +PACKAGE_wwand:luci-proto-wwand
  DEFAULT:=y if TARGET_mediatek_filogic_DEVICE_hiveton_h5000m
endef

define Package/h5000m-integration/description
  First-boot glue that makes ddimension/wwand the H5000M's WWAN dialer and
  exposes the resulting interface under the name luci-app-h5000m-netmode
  expects, so 5G / wired-WAN egress priority works without patching either
  package.  The MT5700M is provisioned as a single dual-stack wwand interface:
  wwand's proto shim already handles IPv6 including sharing its own /64, and
  its documentation warns that a hand-written companion dhcpv6 interface would
  both mis-set extendprefix and take IPv6 away from wwand.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/h5000m-integration/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/h5000m-wwan-provision $(1)/usr/sbin/h5000m-wwan-provision
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/91-h5000m-wwan $(1)/etc/uci-defaults/91-h5000m-wwan
	$(INSTALL_DIR) $(1)/etc/hotplug.d/usb
	$(INSTALL_BIN) ./files/etc/hotplug.d/usb/50-h5000m-wwan $(1)/etc/hotplug.d/usb/50-h5000m-wwan
endef

$(eval $(call BuildPackage,h5000m-integration))
