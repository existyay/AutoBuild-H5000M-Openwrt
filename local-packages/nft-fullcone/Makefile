#
# nftables "fullcone" expression — full-cone NAT for the nftables era.
#
# Mainline OpenWrt has none of this, and the absence is felt as a missing
# feature rather than a bug, so it is worth being precise about what is here.
#
# The original implementation is Chion82/netfilter-full-cone-nat (2019), an
# xtables target.  llccd added IPv6 and ported it to newer kernels; Syrone Wong
# rewrote it as an nftables expression, which is what this packages.  Upstream:
#   https://github.com/sbwml/nft-fullcone            (2022-12, the source used)
#   https://github.com/fullcone-nat-nftables/nft-fullcone  (2023-05, a later fork)
#
# Only the KERNEL half lives here.  The other two halves are deliberately not
# included:
#
#   * nftables userspace must know the `fullcone` expression or `nft` cannot
#     parse a rule that uses it.  Mainline ships nftables 1.1.6; the only
#     patched tree available is a fork of 1.0.2.  Carrying that means the whole
#     system runs a patched nftables, which sits directly in the packet path —
#     a decision, not a detail.
#   * firewall4 has no fullcone option, so nothing emits the rules yet.
#
# So this package is useful on its own only to prove the module compiles and
# loads against the current kernel.  Wiring it up is a separate step.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=nft-fullcone
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=AutoBuild-H5000M-Openwrt

PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define KernelPackage/nft-fullcone
  SUBMENU:=Netfilter Extensions
  TITLE:=nftables fullcone expression support
  DEPENDS:=@IPV6 +kmod-nft-core +kmod-nf-conntrack +kmod-nf-conntrack6
  FILES:=$(PKG_BUILD_DIR)/nft_fullcone.$(LINUX_KMOD_SUFFIX)
  KCONFIG:=CONFIG_NFT_FULLCONE
  AUTOLOAD:=$(call AutoProbe,nft_fullcone)
endef

define KernelPackage/nft-fullcone/description
  Adds the nftables "fullcone" expression, for RFC3489-compatible full cone
  SNAT.  Only UDP is affected; other protocols behave as ordinary MASQUERADE.

  The module is only half of the feature: nftables userspace must also know the
  expression, and firewall4 must emit the rules.  Neither is provided here, so
  installing this alone changes nothing yet.
endef

# Local sources, copied in.  $(CURDIR) is spelled out because a bare ./src is
# resolved against whatever directory make happens to be in, and the first
# attempt copied only three of the five files.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/src/. $(PKG_BUILD_DIR)/
endef

# Spelled out rather than left to KernelPackage's default.  The default ran make
# inside the build directory, where a Kbuild file has no default target, and
# died with "No targets.  Stop."  Invoking the kernel's build system with -C and
# M= is what an out-of-tree module actually needs.
define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C "$(LINUX_DIR)" \
		$(KERNEL_MAKE_FLAGS) \
		M="$(PKG_BUILD_DIR)" \
		CONFIG_NFT_FULLCONE=m \
		modules
endef

$(eval $(call KernelPackage,nft-fullcone))
