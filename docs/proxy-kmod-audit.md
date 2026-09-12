# 代理软件包 kmod 依赖审计

目标环境（已在本仓库确认）：
- `openwrt/` 检出 = `openwrt/openwrt` main，`.upstream-describe` = `d6f8e7b`（= `d6f8e7b7bef8307011b7fb58e68370a4ac5e4663`）
- `openwrt/target/linux/mediatek/Makefile:11` → `KERNEL_PATCHVER:=6.18`
- 包管理器 = apk（`.config:676` `CONFIG_PACKAGE_apk-mbedtls=y`）
- feeds：`feeds.conf.default` 用 **openwrt/packages**，**不是** immortalwrt/packages

所有 kmod 包定义均在本仓库内复核过（可与下面的上游 URL 对照）。

---

## 1. HomeProxy — `immortalwrt/homeproxy`

- 默认分支：**`master`**
- 审计 commit：`edece28a0085f36d469ec82c8d45f562f602db53`
- 唯一 Makefile：仓库根 `Makefile`（无 `Config.in`）

来源：
- https://github.com/immortalwrt/homeproxy/blob/edece28a0085f36d469ec82c8d45f562f602db53/Makefile#L9-L13

```
LUCI_DEPENDS:= \
	+sing-box \
	+firewall4 \
	+kmod-nft-tproxy \
	+ucode-mod-digest
```

**kmod 依赖（确定）：**
- `kmod-nft-tproxy`

**运行时软依赖（不是包依赖）：**
- `kmod-tun` — 只出现在 UI 文案里，没有写进 `LUCI_DEPENDS`：
  - `htdocs/luci-static/resources/view/homeproxy/client.js:292` — "To enable Tun support, you need to install `ip-full` and `kmod-tun`"
  - `po/zh_Hans/homeproxy.po:2711` — 同义中文
- 内核模块探测是**运行时**做的，佐证 `kmod-nft-tproxy` 是硬需求：
  - `root/usr/share/rpcd/ucode/luci.homeproxy:17-18` `function hasKernelModule(kmod)`
  - `root/usr/share/rpcd/ucode/luci.homeproxy:227` `features.hp_has_tproxy = hasKernelModule('nft_tproxy.ko') || access('/etc/modules.d/nft-tproxy')`

**非 kmod 关键依赖：** `sing-box`、`firewall4`、`ucode-mod-digest`

**备注：** TUN 模式要用户自己 `apk add kmod-tun ip-full`。若希望开箱可用，建议把 `kmod-tun` 也编进仓库（见第 6 节，其它项目已把它列为硬依赖）。

---

## 1b. HomeProxy 变体 — `VIKINGYFY`（回退源）

**⚠️ `VIKINGYFY/homeproxy` 这个仓库不存在**，GitHub API 返回 HTTP 404（`gh api repos/VIKINGYFY/homeproxy` → `Not Found`）。也没有 `gh api "search/repositories?q=user:VIKINGYFY+homeproxy"` 结果。

真正的回退源是 **`VIKINGYFY/packages`** 里的 `luci-app-homeproxy` 目录：
- 默认分支：**`main`**
- 审计 commit：`53bae7ce1990ad9bb6093fe0edc461e8574fffe7`
- 路径：`luci-app-homeproxy/Makefile`

来源：
- https://github.com/VIKINGYFY/packages/blob/53bae7ce1990ad9bb6093fe0edc461e8574fffe7/luci-app-homeproxy/Makefile#L8-L18

```
LUCI_DEPENDS:= \
	+luci-base \
	+sing-box \
	+firewall4 \
	+kmod-tun \
	+kmod-nft-queue \
	+curl +flock +unzip \
	+ucode-mod-digest +ucode-mod-math
LUCI_EXTRA_DEPENDS:=sing-box (>=1.14.0)
```

**kmod 依赖（确定）：**
- `kmod-tun`（这里是硬依赖）
- `kmod-nft-queue` ← **只有这个变体需要**

**备注（重要差异）：** 此变体（"Powered by Sing-Box/TUN/AI Edition"）**不需要 `kmod-nft-tproxy`**，改用 `kmod-nft-queue`。两个 HomeProxy 源的 kmod 集合是**不同**的，若你两个都要支持，并集必须同时包含 `kmod-nft-tproxy` 和 `kmod-nft-queue`。

---

## 2. Nikki — `nikkinikki-org/OpenWrt-nikki`

- 默认分支：**`main`**
- 审计 commit：`3799926b147d7065ac98508f16951f8714e53659`

来源（四个 Makefile）：

| 包 | 文件 | 行 |
|---|---|---|
| `luci-app-nikki` | `luci-app-nikki/Makefile` | L6 `LUCI_DEPENDS:=+luci-base +nikki` |
| `nikki` | `nikki/Makefile` | L17 |
| `mihomo-meta` | `mihomo-meta/Makefile` | L38 |
| `mihomo-alpha` | `mihomo-alpha/Makefile` | L38 |

- https://github.com/nikkinikki-org/OpenWrt-nikki/blob/3799926b147d7065ac98508f16951f8714e53659/nikki/Makefile#L17
- https://github.com/nikkinikki-org/OpenWrt-nikki/blob/3799926b147d7065ac98508f16951f8714e53659/mihomo-meta/Makefile#L38
- https://github.com/nikkinikki-org/OpenWrt-nikki/blob/3799926b147d7065ac98508f16951f8714e53659/mihomo-alpha/Makefile#L38

`nikki/Makefile:17`：
```
DEPENDS:=+ca-bundle +curl +yq firewall4 +ip-full +kmod-inet-diag +kmod-nft-socket \
         +kmod-nft-tproxy +kmod-tun +kmod-dummy +mihomo
```

`mihomo-meta/Makefile:38` 与 `mihomo-alpha/Makefile:38`（两者完全相同）：
```
DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +ip-full +kmod-inet-diag +kmod-tun
```

**kmod 依赖（确定）：**
- `kmod-inet-diag`
- `kmod-nft-socket`
- `kmod-nft-tproxy`
- `kmod-tun`
- `kmod-dummy`

**非 kmod 关键依赖：** `ca-bundle`、`curl`、`yq`、`firewall4`、`ip-full`、`mihomo`（由 `mihomo-meta` **或** `mihomo-alpha` 提供，二者 `PROVIDES:=mihomo` 且互相 `CONFLICTS`）
- `luci-app-nikki`：`luci-base` + `nikki`（无 kmod）

**备注：**
- `mihomo-meta` 与 `mihomo-alpha` 是二选一变体（`VARIANT:=meta` / `alpha`，`CONFLICTS` 互斥），kmood 依赖相同。
- 仓库 README（`README.md:95-99`）的依赖列表与 Makefile 完全一致，互相印证。
- ⚠️ **`kmod-br-netfilter` 不是依赖。** 它只出现在 init 脚本的兼容性注释里：
  - `nikki/files/nikki.init:387-388` 与 `:501` — 当 `kmod-br-netfilter` 已加载时把 `bridge-nf-call-iptables` 置 0 的 workaround（`lsmod | grep -q br_netfilter` 运行时判断）。不要误当作依赖编进仓库。

---

## 3. Momo — `nikkinikki-org/OpenWrt-momo`

**仓库确认：** 你说的 "momo" 就是 **`nikkinikki-org/OpenWrt-momo`**（与 Nikki 同组织）。
- `gh api "search/repositories?q=openwrt+momo"` 首位结果：`nikkinikki-org/OpenWrt-momo`，803 stars，"Transparent Proxy with sing-box on OpenWrt."
- `gh api "search/repositories?q=luci-app-momo"` 同样只返回它。
- 包名是 `momo` 和 `luci-app-momo`。

- 默认分支：**`main`**
- 审计 commit：`72f5c46b5b65ad95f8f786f024c98204e47cd3dd`

来源：

| 包 | 文件 | 行 |
|---|---|---|
| `luci-app-momo` | `luci-app-momo/Makefile` | L6 `LUCI_DEPENDS:=+luci-base +momo` |
| `momo` | `momo/Makefile` | L17 |

- https://github.com/nikkinikki-org/OpenWrt-momo/blob/72f5c46b5b65ad95f8f786f024c98204e47cd3dd/momo/Makefile#L17

`momo/Makefile:17`：
```
DEPENDS:=+ca-bundle +curl firewall4 +ip-full +kmod-inet-diag +kmod-nft-socket \
         +kmod-nft-tproxy +kmod-tun +kmod-dummy +sing-box
```

**kmod 依赖（确定）：**
- `kmod-inet-diag`
- `kmod-nft-socket`
- `kmod-nft-tproxy`
- `kmod-tun`
- `kmod-dummy`

**非 kmod 关键依赖：** `ca-bundle`、`curl`、`firewall4`、`ip-full`、`sing-box`

**备注：** kmod 集合与 `nikki` **完全相同**，只是把 `mihomo` 换成 `sing-box`。同样无 `Config.in`；`kmod-br-netfilter` 也只出现在 `momo/files/momo.init:330-331,444` 的兼容性注释中，**不是依赖**。

---

## 4. OpenClash — `vernesong/OpenClash`

- 默认分支：**`master`**
- 审计 commit：`c3a33c1d3407956fdf8f0e0b7c1a4c52e6ad9593`
- 只有一个包 Makefile：`luci-app-openclash/Makefile`（clash/mihomo 内核是**运行时下载**的，仓库内没有内核包）

来源：
- https://github.com/vernesong/OpenClash/blob/c3a33c1d3407956fdf8f0e0b7c1a4c52e6ad9593/luci-app-openclash/Makefile#L11-L47

**硬依赖 `DEPENDS`（L44-46）：**
```
DEPENDS:=+dnsmasq-full +bash +curl +ca-bundle +ip-full \
	+ruby +ruby-yaml +kmod-tun +unzip
```

**条件 kmod —— `Package/luci-app-openclash/config` 块（L11-35）：**

fw4（nftables）路径：
```
config PACKAGE_kmod-inet-diag
	default y if PACKAGE_luci-app-openclash
config PACKAGE_kmod-nft-tproxy
	default y if PACKAGE_firewall4
config PACKAGE_dnsmasq_full_nftset
	default y if PACKAGE_firewall4
```

fw3（iptables，`!firewall4`）路径：
```
config PACKAGE_kmod-ipt-nat
	default y if ! PACKAGE_firewall4
config PACKAGE_iptables-mod-tproxy
	default y if ! PACKAGE_firewall4
config PACKAGE_iptables-mod-extra
	default y if ! PACKAGE_firewall4
config PACKAGE_dnsmasq_full_ipset
	default y if ! PACKAGE_firewall4
config PACKAGE_ipset
	default y if ! PACKAGE_firewall4
```

**kmod 依赖（确定）：**
- `kmod-tun` — 硬依赖，与 fw3/fw4 无关
- `kmod-inet-diag` — 经 `Package/config`
- `kmod-nft-tproxy` — 经 `Package/config`（fw4）
- `kmod-ipt-nat` — 经 `Package/config`（fw3 路径）
- `kmod-ipt-tproxy` — **间接**：`iptables-mod-tproxy` → `+kmod-ipt-tproxy`（fw3 路径）
- `kmod-ipt-extra` — **间接**：`iptables-mod-extra` → `+kmod-ipt-extra`（fw3 路径）

间接关系证据（OpenWrt 主树）：
- `package/network/utils/iptables/Makefile:425-428` → `define Package/iptables-mod-tproxy` / `$(call Package/iptables/Module, +kmod-ipt-tproxy)`
- `package/network/utils/iptables/Makefile:373-376` → `define Package/iptables-mod-extra` / `$(call Package/iptables/Module, +kmod-ipt-extra)`

运行时核对（佐证上面的清单是完整且准确的）：
- `luci-app-openclash/root/usr/share/openclash/openclash_update.sh:372`
  `packages_to_check="luci-compat kmod-inet-diag kmod-nft-tproxy kmod-ipt-nat iptables-mod-tproxy iptables-mod-extra ipset"`
- `luci-app-openclash/root/etc/init.d/openclash:682-699` `check_mod()`，调用点：`:721` `check_mod "tun"`（仅 TUN 模式）、`:1426/:1468/:1958` `check_mod "nft_tproxy"`、`:2276/:2317/:2812` `check_mod "xt_TPROXY"`
- `luci-app-openclash/root/usr/share/openclash/openclash_debug.sh:194-209` 依赖诊断表同时列 `kmod-tun`/`kmod-inet-diag`/`kmod-nft-tproxy`/`kmod-ipt-tproxy`/`kmod-ipt-extra`/`kmod-ipt-nat`

**非 kmod 关键依赖：** `dnsmasq-full`、`bash`、`curl`、`ca-bundle`、`ip-full`、`ruby`、`ruby-yaml`、`unzip`；以及 `luci-compat`、`ipset`（fw3）

**备注（机制说明，已查证）：**
- `Package/xxx/config` 块并不是"声明依赖"，而是向 menuconfig 注入额外默认值。`scripts/package-metadata.pl:378` 是把它**原样**打印到生成的 Config.in 中的（`$pkg->{config} and print $pkg->{config}."\n";`），**没有**包在 `if PACKAGE_luci-app-openclash` 里。所以 OpenClash 的 `default y if PACKAGE_firewall4` 是按 **firewall4** 求值，而不是 openclash。这是 OpenWrt 常见的"隐式带上 kmod"写法，但严格程度上弱于 `DEPENDS`。
- 因此：**唯一写在 `DEPENDS` 里的 kmod 是 `kmod-tun`**；其余靠 config 默认值带上。若你的构建流程只按 `DEPENDS` 收集 kmod，会**漏掉** `kmod-inet-diag` / `kmod-nft-tproxy`。建议把它们显式编进仓库。
- 你的固件用 fw4，所以实际需要的是 fw4 那一组；fw3 那组（iptables）可以只要 `kmod-ipt-*` + `iptables-mod-*` 以防用户切换。

---

## 5. Daed

存在**两个**候选仓库，`DEPENDS` 的 kmod 部分**完全一致**（互相印证）：

### 5a. `QiuSimons/luci-app-daed`

- 默认分支：**`kix`**（注意不是 master）
- 审计 commit：`bc9a40e08b3c926a4d324f87911cba5e85dce8e6`
- 文件：`daed/Makefile`、`luci-app-daed/Makefile`

- https://github.com/QiuSimons/luci-app-daed/blob/bc9a40e08b3c926a4d324f87911cba5e85dce8e6/daed/Makefile#L63-L71

```
DEPENDS:=$(GO_ARCH_DEPENDS) \
    +ca-bundle +kmod-sched-core +kmod-sched-bpf \
    +kmod-veth +v2ray-geoip +v2ray-geosite \
    +@KERNEL_XDP_SOCKETS \
    +DAED_USE_VMLINUX_BTF:vmlinux-btf
```

`luci-app-daed/Makefile:9`：`LUCI_DEPENDS:=+daed +zoneinfo-asia +luci-compat`

### 5b. `kenzok8/openwrt-daede`

- 默认分支：**`main`**
- 审计 commit：`7b1daf3e6d0787df204576aa0c696aa9452d5361`
- 文件：`daed/Makefile`（L63-71）、`dae/Makefile`（L64-66）、`luci-app-daede/Makefile`

- https://github.com/kenzok8/openwrt-daede/blob/7b1daf3e6d0787df204576aa0c696aa9452d5361/daed/Makefile#L63-L71

同一条 `DEPENDS`（kmod 部分逐字相同）。

`luci-app-daede/Makefile` 的 `DEPENDS:=+luci-base +PACKAGE_luci-app-daede_dae:dae +PACKAGE_luci-app-daede_daed:daed` —— 无 kmod，kmod 由 `dae`/`daed` 带。

**kmod 依赖（确定）：**
- `kmod-sched-core`
- `kmod-sched-bpf`
- `kmod-veth`

**看起来像 kmod 但不是的：**
- `+@KERNEL_XDP_SOCKETS` — 这是**内核 config 符号**（`CONFIG_KERNEL_XDP_SOCKETS=y`），不是包。写进 `DEPENDS` 的意思是"内核不开这个符号，`daed` 在 menuconfig 里根本不可选"。
- `+DAED_USE_VMLINUX_BTF:vmlinux-btf` — 条件依赖，`vmlinux-btf` 是**内核 BTF 数据包**，不是 `kmod-*`。

**额外 kmod（README 要求但不在 `DEPENDS` 里）：**
- `kmod-xdp-sockets-diag` —— **不在 `DEPENDS`**，只写在 README 的 `.config` 片段里
  - `QiuSimons/luci-app-daed README.md:45` `CONFIG_PACKAGE_kmod-xdp-sockets-diag=y`
  - `kenzok8/openwrt-daede README.md:149` 依赖表也列了它
  - 该 kmod 定义确实存在：`package/kernel/linux/modules/netsupport.mk:1495`，且 `DEPENDS:=@KERNEL_XDP_SOCKETS`
  - **结论：`apk add daed` 不会自动装上它**，必须你自己编进仓库/显式选中。

**非 kmod 关键依赖：** `ca-bundle`、`v2ray-geoip`、`v2ray-geosite`
- `luci-app-daed`：`daed`、`zoneinfo-asia`、`luci-compat`
- `luci-app-daede`：`luci-base` + `dae`/`daed`（choice 二选一）

**内核层面的要求（不是 kmod 包，但必须开，否则编不出/跑不起来）：**
`QiuSimons/luci-app-daed README.md:36-45`：
```
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
```
BTF 二选一（`Package/daed/config` choice，`default DAED_USE_KERNEL_BTF`）：
- `DAED_USE_KERNEL_BTF` → 要求 `CONFIG_KERNEL_DEBUG_INFO_BTF=y`
- `DAED_USE_VMLINUX_BTF` → 依赖 `vmlinux-btf` 包（需与内核版本匹配）

**备注（发现的文档/代码不一致）：**
- `kenzok8/openwrt-daede README.md:150` 把 **`kmod-nft-tproxy`** 列为依赖，但 `daed/Makefile` 和 `dae/Makefile` 的 `DEPENDS` **都没有**它；整个仓库除 README 外无任何 `nft-tproxy` 引用（已全仓 grep）。**倾向于 README 过时/多余**；但既然 cost 很低，建议一并编入以求稳。
- Daed 的 kmod 集合与前面四家**完全不重叠**（eBPF 路线 vs nftables TPROXY 路线）。

---

## 6. sing-box（HomeProxy / Momo 的传递依赖）

- 你的 feed 是 **openwrt/packages**（`feeds.conf.default`），不是 immortalwrt/packages。
- 本地实际内容：`openwrt/feeds/packages/net/sing-box/Makefile`，feed commit `16aaa680ddbec779c8f5623d917cfcd32ab1f1a4`
- 来源：`openwrt/feeds/packages/net/sing-box/Makefile:34`

```
define Package/sing-box-default
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +kmod-inet-diag +kmod-tun
```

**kmod 依赖（确定）：** `kmod-inet-diag`、`kmod-tun`（`sing-box` 与 `sing-box-tiny` 共用）

**⚠️ 与 ImmortalWrt 版本的差异：** immortalwrt/packages 的 sing-box 额外依赖 `+kmod-netlink-diag`（`https://github.com/immortalwrt/packages/blob/8509f551edb7beb4a6324afca4d84b2bea404b66/net/sing-box/Makefile#L52-L56`）。**你的 mainline feed 不需要它**，别照抄 ImmortalWrt 的清单。已全目录 grep 确认本地 sing-box 无 `netlink-diag` 引用。

---

## 7. 去重后的 kmod 全集

### 7.1 第一层 —— 各包 Makefile 直接声明（必须编）

| # | kmod 包 | 被谁需要 |
|---|---|---|
| 1 | `kmod-nft-tproxy` | HomeProxy(immortalwrt)、Nikki、Momo、OpenClash(fw4) |
| 2 | `kmod-nft-socket` | Nikki、Momo |
| 3 | `kmod-tun` | Nikki、Momo、mihomo-meta、mihomo-alpha、sing-box、OpenClash(硬依赖)、HomeProxy-VIKINGYFY |
| 4 | `kmod-dummy` | Nikki、Momo |
| 5 | `kmod-inet-diag` | Nikki、Momo、mihomo-meta、mihomo-alpha、sing-box、OpenClash(fw4) |
| 6 | `kmod-nft-queue` | HomeProxy-VIKINGYFY |
| 7 | `kmod-ipt-nat` | OpenClash(fw3) |
| 8 | `kmod-sched-core` | Daed (QiuSimons + kenzok8) |
| 9 | `kmod-sched-bpf` | Daed (QiuSimons + kenzok8) |
| 10 | `kmod-veth` | Daed (QiuSimons + kenzok8) |
| 11 | `kmod-xdp-sockets-diag` | Daed（仅 README / 手动选中，**不在 DEPENDS**） |
| 12 | `kmod-ipt-tproxy` | OpenClash(fw3，经 `iptables-mod-tproxy`) |
| 13 | `kmod-ipt-extra` | OpenClash(fw3，经 `iptables-mod-extra`) |

> 第 6 项与第 1 项属于**不同 HomeProxy 变体**，两边都要支持就必须都编。

### 7.2 第二层 —— 传递依赖（apk 解析时会要，仓库里必须有）

| # | kmod 包 | 来自哪个上层 |
|---|---|---|
| 14 | `kmod-nft-core` | `kmod-nft-tproxy`、`kmod-nft-socket`、`kmod-nft-queue` |
| 15 | `kmod-nf-tproxy` | `kmod-nft-tproxy`、`kmod-ipt-tproxy` |
| 16 | `kmod-nf-conntrack` | `kmod-nft-tproxy`、`kmod-ipt-tproxy` |
| 17 | `kmod-nf-socket` | `kmod-nft-socket` |
| 18 | `kmod-nfnetlink-queue` | `kmod-nft-queue` |
| 19 | `kmod-nfnetlink` | `kmod-nft-core`、`kmod-nfnetlink-queue` |
| 20 | `kmod-nf-reject` | `kmod-nft-core` |
| 21 | `kmod-nf-reject6` | `kmod-nft-core`（`IPV6:` 条件） |
| 22 | `kmod-nf-nat` | `kmod-nft-core`、`kmod-ipt-nat` |
| 23 | `kmod-nf-log` | `kmod-nft-core` |
| 24 | `kmod-nf-log6` | `kmod-nft-core`（`IPV6:` 条件） |
| 25 | `kmod-ipt-core` | `kmod-ipt-nat`、`kmod-ipt-tproxy`、`kmod-ipt-extra`、`kmod-br-netfilter` |

依赖边全部在本仓库复核，见 `package/kernel/linux/modules/netfilter.mk`：
- `nft-tproxy`（L1452）→ `DEPENDS:=+kmod-nft-core +kmod-nf-tproxy +kmod-nf-conntrack`
- `nft-socket`（L1441）→ `DEPENDS:=+kmod-nft-core +kmod-nf-socket`
- `nft-queue`（L1430）→ `DEPENDS:=+kmod-nft-core +kmod-nfnetlink-queue`
- `nft-core`（L1309）→ `DEPENDS:=+kmod-nfnetlink +kmod-nf-reject +IPV6:kmod-nf-reject6 +kmod-nf-nat +kmod-nf-log +IPV6:kmod-nf-log6 +LINUX_6_12:kmod-lib-crc32c`
- `nfnetlink-queue`（L1208）→ `$(call AddDepends/nfnetlink)` → `+kmod-nfnetlink`（L1185-1188）
- `ipt-nat`（L526）→ `$(call AddDepends/ipt,+kmod-nf-nat)` → `+kmod-ipt-core +kmod-nf-nat`（L245-248）
- `ipt-tproxy`（L892）→ `DEPENDS+=+kmod-nf-tproxy +kmod-nf-conntrack` + `$(call AddDepends/ipt)`
- `ipt-extra`（L996）→ `$(call AddDepends/ipt)`

### 7.3 第三层 —— 条件项 / 待确认

| # | kmod 包 | 说明 |
|---|---|---|
| 26 | `kmod-lib-crc32c` | `kmod-nft-core` 的 `+LINUX_6_12:kmod-lib-crc32c`。**你的 6.18 目标大概率不需要**——见下方说明。若编 `kmod-nft-core` 时报缺 crc32c，补上它。 |
| 27 | `kmod-br-netfilter` | **仅代码注释提到，不是依赖**（Nikki/Momo 的 init 兼容性 workaround）。如果用户在 Docker 网桥环境下跑 TPROXY 才可能受益。**不建议为它编包**，但知道它存在。 |

**关于 `LINUX_6_12`（已查证机制）：**
- `scripts/target-metadata.pl:69-78` 的 `kver()` 返回"主.次"（如 `6_12`、`6_18`）
- `scripts/target-metadata.pl:411-424` 为每个目标的内核版本生成 `config LINUX_6_18`（bool），并由目标 `select LINUX_$v`
- 即该符号是**精确主次版本**匹配，不是 ">= 6.12"
- `openwrt/target/linux/mediatek/Makefile:11` = `KERNEL_PATCHVER:=6.18` → 选中 `LINUX_6_18`，**不**选中 `LINUX_6_12`
- **结论：在你的 filogic/6.18 目标上，`kmod-nft-core` 的 `kmod-lib-crc32c` 依赖不生效。** 这是"确定查到机制 + 据此推断"，不是直接从构建日志验证的——标记为**推测（高置信）**。

---

## 8. 需要写进 `.config` 的内核选项（非 kmod 包）

只有 Daed 需要，且是**硬性**的：

```
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_DEVEL=y
```

- `CONFIG_KERNEL_XDP_SOCKETS=y` 是 `daed` 包出现的前提（`+@KERNEL_XDP_SOCKETS`）。
- `CONFIG_KERNEL_DEBUG_INFO_BTF=y` 用于 CO-RE eBPF；不开就得改走 `vmlinux-btf` 包路线。注意这会显著增大内核体积。
- 其余四家（HomeProxy/Nikki/Momo/OpenClash）**不需要**任何额外 `CONFIG_KERNEL_*`。

---

## 9. 非 kmod 关键依赖汇总（apk 仓库也要有）

| 项目 | 非 kmod 依赖 |
|---|---|
| HomeProxy (immortalwrt) | `sing-box`、`firewall4`、`ucode-mod-digest` |
| HomeProxy (VIKINGYFY) | `luci-base`、`sing-box(>=1.14.0)`、`firewall4`、`curl`、`flock`、`unzip`、`ucode-mod-digest`、`ucode-mod-math` |
| Nikki | `nikki` + `luci-base`；`nikki`：`ca-bundle`、`curl`、`yq`、`firewall4`、`ip-full`、`mihomo`；`mihomo-*`：`ca-bundle`、`ip-full` |
| Momo | `luci-base`、`momo`；`momo`：`ca-bundle`、`curl`、`firewall4`、`ip-full`、`sing-box` |
| OpenClash | `dnsmasq-full`、`bash`、`curl`、`ca-bundle`、`ip-full`、`ruby`、`ruby-yaml`、`unzip`、`luci-compat`、`ipset`(fw3) |
| Daed | `ca-bundle`、`v2ray-geoip`、`v2ray-geosite`；`luci-app-daed`：`zoneinfo-asia`、`luci-compat`；`vmlinux-btf`（条件） |

---

## 10. 未解决 / 需你决定

1. **`kmod-xdp-sockets-diag`（Daed）**：README 要求但不在 `DEPENDS`，`apk add daed` 不会带上。需要你显式加入仓库 + 编入固件。
2. **`kmod-nft-tproxy`（kenzok8 Daed）**：README 与 Makefile 冲突，倾向 README 过时。低风险做法是编进去。
3. **HomeProxy 两个变体并存**：两者 kmod 需求不同（`nft-tproxy` vs `nft-queue`），需要决定支持哪个/都支持。
4. **OpenClash 的 config 块**：若你的收集逻辑基于 `DEPENDS` 而非 menuconfig 实际选中，会漏 `kmod-inet-diag`/`kmod-nft-tproxy`。
5. **apk + kmod 的版本锁定**：kmod 包带内核 vermagic，必须与固件内核同一次构建产出，不能跨版本复用。这几个 kmod 都属 `package/kernel/linux/`，在 `CONFIG_ALL_KMODS` 之外时需逐个显式 `=y`（或 `=m` 后进仓库）。

---

## 附：证据文件绝对路径（本地复核用）

上游（固定 commit）：
- HomeProxy: `https://github.com/immortalwrt/homeproxy/blob/edece28a0085f36d469ec82c8d45f562f602db53/Makefile`
- HomeProxy-VIKINGYFY: `https://github.com/VIKINGYFY/packages/blob/53bae7ce1990ad9bb6093fe0edc461e8574fffe7/luci-app-homeproxy/Makefile`
- Nikki: `https://github.com/nikkinikki-org/OpenWrt-nikki/blob/3799926b147d7065ac98508f16951f8714e53659/nikki/Makefile`
- Momo: `https://github.com/nikkinikki-org/OpenWrt-momo/blob/72f5c46b5b65ad95f8f786f024c98204e47cd3dd/momo/Makefile`
- OpenClash: `https://github.com/vernesong/OpenClash/blob/c3a33c1d3407956fdf8f0e0b7c1a4c52e6ad9593/luci-app-openclash/Makefile`
- Daed (QiuSimons, 分支 `kix`): `https://github.com/QiuSimons/luci-app-daed/blob/bc9a40e08b3c926a4d324f87911cba5e85dce8e6/daed/Makefile`
- Daed (kenzok8): `https://github.com/kenzok8/openwrt-daede/blob/7b1daf3e6d0787df204576aa0c696aa9452d5361/daed/Makefile`

本地（与上游 `d6f8e7b` 一致）：
- `openwrt/package/kernel/linux/modules/netsupport.mk`（tun L507 / veth L522 / sched-core L713 / sched-bpf L794 / netlink-diag L1438 / inet-diag L1453 / xdp-sockets-diag L1495）
- `openwrt/package/kernel/linux/modules/netfilter.mk`（nf-conntrack L124 / nf-socket L223 / nf-tproxy L234 / ipt-nat L526 / ipt-tproxy L892 / ipt-extra L996 / br-netfilter L1080 / nfnetlink-queue L1208 / nft-core L1309 / nft-queue L1430 / nft-socket L1441 / nft-tproxy L1452）
- `openwrt/package/kernel/linux/modules/netdevices.mk`（dummy L1769）
- `openwrt/package/network/utils/iptables/Makefile`（iptables-mod-extra L373 / iptables-mod-tproxy L425）
- `openwrt/feeds/packages/net/sing-box/Makefile:34`
- `openwrt/scripts/target-metadata.pl:69-78, 411-424`
- `openwrt/scripts/package-metadata.pl:378`
- `openwrt/target/linux/mediatek/Makefile:11`
