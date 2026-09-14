include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-h5000m-accel
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=AutoBuild-H5000M-Openwrt

LUCI_TITLE:=H5000M network acceleration (mainline flow offload)
LUCI_DEPENDS:=+luci-base +firewall4
LUCI_PKGARCH:=all

define Package/luci-app-h5000m-accel/conffiles
/etc/config/h5000m_accel
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
