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
# Only the KERNEL half lives here.  The other three halves are carried as
# patches against mainline's own packages, from this repository:
#
#   * libnftnl-patches/100-fullcone-expression.patch
#     adds NFTNL_EXPR_FULLCONE_* and src/expr/fullcone.c
#   * nftables-patches/100-fullcone-expression.patch
#     adds the `fullcone` keyword, the scanner rule and the parser statement
#   * firewall4-patches/100-fullcone-support.patch
#     makes zone-masq.uc emit `fullcone` instead of `masquerade` when
#     firewall.@defaults[0].fullcone is set, and adds the dstnat rules
#
# They are patches, not forks, because a fork of nftables would mean running a
# patched packet-path binary from an unmaintained tree while upstream ships
# security fixes.  install_nftables_patches in scripts/local-build.sh puts each
# one in place.
#
# Only UDP is affected; every other protocol is ordinary MASQUERADE.
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
  # kmod-nf-conntrack6 is gone from modern kernels — IPv6 conntrack was merged
  # into kmod-nf-conntrack — so depending on it only produced
  # "has a dependency on 'kmod-nf-conntrack6', which does not exist".
  DEPENDS:=@IPV6 +kmod-nft-core +kmod-nf-conntrack
  FILES:=$(PKG_BUILD_DIR)/nft_fullcone.$(LINUX_KMOD_SUFFIX)
  KCONFIG:=CONFIG_NFT_FULLCONE
  AUTOLOAD:=$(call AutoProbe,nft_fullcone)
endef

define KernelPackage/nft-fullcone/description
  Adds the nftables "fullcone" expression, for RFC3489-compatible full cone
  SNAT.  Only UDP is affected; other protocols behave as ordinary MASQUERADE.

  The three userspace halves are patched into mainline's libnftnl, nftables and
  firewall4 by this repository, so installing this package alongside them is
  what makes the feature available.  luci-app-h5000m-accel depends on all four
  and is what switches it on.
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
