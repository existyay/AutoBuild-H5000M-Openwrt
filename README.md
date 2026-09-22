# AutoBuild-H5000M-Openwrt

[![构建固件](https://img.shields.io/github/actions/workflow/status/existyay/AutoBuild-H5000M-Openwrt/build.yml?label=build)](https://github.com/existyay/AutoBuild-H5000M-Openwrt/actions/workflows/build.yml)
[![仓库与主机检查](https://img.shields.io/github/actions/workflow/status/existyay/AutoBuild-H5000M-Openwrt/checks.yml?label=checks)](https://github.com/existyay/AutoBuild-H5000M-Openwrt/actions/workflows/checks.yml)
[![配置覆盖测试](https://img.shields.io/github/actions/workflow/status/existyay/AutoBuild-H5000M-Openwrt/coverage.yml?label=coverage)](https://github.com/existyay/AutoBuild-H5000M-Openwrt/actions/workflows/coverage.yml)
[![最新版本](https://img.shields.io/github/v/release/existyay/AutoBuild-H5000M-Openwrt?label=release&color=blue)](https://github.com/existyay/AutoBuild-H5000M-Openwrt/releases/latest)
[![许可证](https://img.shields.io/github/license/existyay/AutoBuild-H5000M-Openwrt?label=license)](https://github.com/existyay/AutoBuild-H5000M-Openwrt/blob/master/LICENSE)

Hiveton H5000M（Airpi H5000M，MT7987A + MT7992）的**主线 OpenWrt** 固件自动编译工程。
上游是 `openwrt/openwrt` main，每周一自动构建，也可手动触发。

## 下载与刷机

到 [Releases](https://github.com/existyay/AutoBuild-H5000M-Openwrt/releases/latest) 下载：

| 文件 | 用途 |
| --- | --- |
| `*-squashfs-sysupgrade.bin` | **刷机用这个** |
| `*-initramfs-kernel.bin` | 恢复镜像，系统起不来时用 |
| `*-targz-rootfs.tar.gz` | 容器 / chroot 使用 |
| `BUILD-INFO.txt` | 上游版本与**内核 ABI** |

在 LuCI 的「系统 → 备份/刷写固件」里刷入 sysupgrade 镜像，或：

```sh
sysupgrade -v /tmp/openwrt-*-sysupgrade.bin
```

> 装内核模块（`kmod-*`）时必须与固件的内核 ABI 一致，具体值见 `BUILD-INFO.txt`
> 或设备上的 `uname -r`。

## 首次启动

无线**开箱即用**，不需要先登录去启用：

| 项目 | 默认值 |
| --- | --- |
| SSID | `openwrt` |
| 密码 | **无（开放网络）** |
| 加密 / 国家 | `none` / `CN` |
| 管理地址 | <http://192.168.1.1> |
| 主机名 | `OpenWrt` |

连上 `openwrt` 后打开 <http://192.168.1.1> 即可，首次登录无密码。

> **默认是开放网络，请尽快在「网络 → 无线」里设置自己的密码。**
> 首启脚本只写入一次，之后不会覆盖你改过的设置。

## 安装更多软件包

固件已内置本项目自己的软件源，代理面板等软件包直接安装即可：

```sh
apk update
apk add luci-app-passwall
```

可安装的包括 **PassWall、PassWall2、HomeProxy、MosDNS、Nikki-RS、Momo、NeKoBox、
v2rayA、OpenClash、SSR-Plus** 以及各自的中文语言包。内核模块与固件同一次构建产出，
所以 ABI 天然匹配，不必担心装不上。

代理面板运行需要的内核侧依赖已经**装进固件本身**，不需要用户再补：

| 已内置 | 作用 |
| --- | --- |
| `kmod-tun` / `ip-full` | TUN 模式（面板提示的 "需要安装 ip-full 和 kmod-tun" 已是过去式） |
| `kmod-nft-socket` / `kmod-nft-tproxy` / `kmod-nft-fullcone` | 透明代理与 FullCone |
| `dnsmasq-full` / `ipset` / `kmod-ipt-ipset` | adblock / adblock-fast 的 `dnsmasq.ipset`、`dnsmasq.nftset` 后端（页面上不会再显示 "dnsmasq.ipset 不支持"） |
| `ucode-mod-math` | HomeProxy 依赖，缺失会导致面板起不来 |
| `sing-box` 1.12.25 | 固定版本，避免被上游快照里的新版顶掉 |

每个面板的**核**（Xray / Mihomo / sing-box）都在软件源里，`apk add` 面板时会自动一起
装上，不需要再手动补 —— 装完直接能用。

> `apk update` 出现 `UNTRUSTED signature` 警告说明索引签名校验失败 —— 正常构建不会
> 出现：索引由本次构建的密钥签名，对应公钥就在固件的 `/etc/apk/keys/`。

## 已内置的功能

| 功能 | 说明 |
| --- | --- |
| **风扇温控** `luci-app-h5000m-fancontrol` | 按温度自动调速，LuCI 可调曲线 |
| **出口优先级** `luci-app-h5000m-netmode` | 有线 / 无线 / 5G 的出口选择与切换 |
| **5G 拨号** `ddimension/wwand` | 5G 模组拨号，带 LuCI 面板 |
| **MosDNS** | 域名分流，开箱已装 |
| HomeProxy / Adblock | 已在软件源中，`apk add luci-app-homeproxy` / `luci-app-adblock` 安装；**默认不装进固件** |
| **Adblock-Fast** | 软件源里也提供 `adblock-fast` + `luci-app-adblock-fast` + 中文包；它推荐但非必需的 `gawk` / `grep` / `sed` / `coreutils-sort` 同样在源里，面板不会再提示缺包 |
| Argon 主题 | LuCI 主题 |
| UPnP IGD / ttyd | 端口映射 / 网页终端 |

硬件加速用的是**主线自己的 PPE 卸载**（fw4 的 `flow_offloading_hw`），首次启动已自动
开启。它与 ImmortalWrt 上的 TurboACC / MTK HNAT 是**两套不同的东西**，后者在主线这个
SoC 上并不存在。

代理侧的加速则是 **Nikki-RS（clash-rs）的 eBPF 快路径**：固件默认编译了 cgroup BPF 与
TC eBPF 所需的全部内核选项（`CONFIG_CGROUP_BPF` 以及 kmod-sched-core / kmod-sched-bpf
带来的 cls_bpf、act_bpf），并把 eBPF 管理器建 datapath 所需的 `kmod-veth` 装进镜像
（它用 netkit/veth 建 `dae0`/`dae0peer` 链路对）。装上 `luci-app-nikki-rs` 后在它的
eBPF 页面打开即可；「网络加速」页面会报告 eBPF 内核支持是否就绪，并可代为开关
（默认「不管理」，由 Nikki-RS 自己的页面决定）。

eBPF 是 **TUN/tproxy/redirect 之外的另一种入站**：内核钩子决定拦截还是放行，不再需要
nftables/iptables 转发规则；打开后 `Proxy Config` 里的 TCP/UDP 模式会被绕过（所以
那里没有、也不需要「eBPF 模式」选项）。本固件已经内置它需要的全部内核侧依赖，
**不需要像社区里那样先装 `dae` 来补依赖**。

关于内核选项，有三件事值得说清楚（上游 README 的依赖清单与我们的配置逐条对过）：

* Nikki-RS 需要的 **`kmod-nft-tproxy`**（以及 `kmod-nft-socket`、`kmod-inet-diag`、
  `kmod-tun`、`kmod-dummy`、`ip-full`、`yq`）**全部已 `=y` 装进镜像**，并在发布前的
  三道门禁里逐条断言，所以不存在"还要自己补内核模块"的情况。
* **`CONFIG_DEBUG_INFO_BTF` 已开启。** 它有两个前置条件，缺一个就会被 defconfig
  静默丢掉：`depends on KERNEL_DEBUG_INFO && !KERNEL_DEBUG_INFO_REDUCED`。树里本来
  就是 `DEBUG_INFO=y`，但 **`DEBUG_INFO_REDUCED` 默认是 `y`**，所以 BTF 一直被丢掉、
  内核实际上没有 BTF。现在这三个符号一起写入、并在 defconfig 之后重新断言。代价是
  gcc 要生成完整 DWARF，再由 `pahole`（`select DWARVES` 会自动构建）转成去重后的
  BTF：vmlinux 会变大、内核编译会变慢，这是本工程有意接受的权衡。
* 我们同时开的是 Nikki-RS 真正需要的 cgroup BPF 一半
  （`CONFIG_KERNEL_CGROUPS` + `CONFIG_KERNEL_CGROUP_BPF`）。`clash-rs` 本身是
  **预编译二进制**（包内 `Build/Compile` 为空，只下载上游 release 的 tarball），
  它的 eBPF 字节码在上游发布流程里就已编译并嵌入二进制；BTF 是给内核侧与
  BTF/CO-RE 类工具（如 Daed）用的。`CONFIG_BPF_EVENTS` / `XDP_SOCKETS` 仍保持关闭。

三点注意：

* eBPF 页的 `Bypass Destination IPs` **必须包含你的内网网段**（默认含 `192.168.0.0/16`），
  否则去往路由器本身的流量也会被拦，直接失去管理入口。
* **第一次调试不要打开 Nikki-RS 的开机自启**（`boot_start`）；确认策略没问题之后再开。
* `dnsmasq.ipset`（adblock）与 eBPF 无关；eBPF 的透明代理端口是它自己的 `tproxy-port`
  （默认 12345），不用去配 Proxy Config 的 tproxy 端口。

## 自己编译

### 在线编译（推荐，也是本项目的默认方式）

在 **Actions → 构建 H5000M 主线 OpenWrt 固件 → Run workflow** 手动触发，或者用命令行：

```sh
gh workflow run build.yml --ref master
```

构建完成后固件自动发布为 Release，软件包仓库自动发布到 GitHub Pages，不需要本机装任何
交叉编译环境。大部分组件已固定为默认内置，界面上只保留确实需要选择的开关（5G 拨号器、
Docker、各代理前端等）。

发布前会跑三道门禁（fullcone 四层链路、代理 kmod 是否真在镜像里、**发布出去的软件源
能否独立满足所有前端**），任何一条不过就不发布。

### 本地编译（只在需要调试时用）

```sh
./scripts/local-build.sh --install-deps    # 装依赖（Debian/Ubuntu 用 apt，Arch 用 pacman）
./scripts/local-build.sh                   # 全量编译
```

产物在 `artifacts/`：sysupgrade 镜像、rootfs、manifest，以及可供设备安装的 apk 仓库。

> **会把源码树和工具链留在本机**：`openwrt/` 编译完约 **70 GB**（含 toolchain 与
> `build_dir`）。本项目不再在本机保留这些产物，用完请删掉：
>
> ```sh
> rm -rf openwrt artifacts artifacts-coverage logs build.log coverage-*.log
> ```
>
> 如果 `/home` 跑在 btrfs 且装了 snapper，空间要等包含这棵树的快照被清掉才会真正释放
> （见下面「已知限制」）。

常用环境变量：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `H5000M_WIFI_SSID` | `openwrt` | 首启 SSID |
| `H5000M_WIFI_KEY` / `_ENCRYPTION` | 空 / `none` | 默认开放网络 |
| `H5000M_APK_REPO_URL` | 空 | 软件源基址；留空则固件不带额外源 |
| `ENABLE_ADBLOCK` / `ENABLE_HOMEPROXY` | `false` | 关闭时编进软件源（`=m`），打开时装进固件（`=y`） |
| `ENABLE_DOCKERMAN` / `ENABLE_NIKKI` / `ENABLE_OPENCLASH` / `ENABLE_ADGUARDHOME` | `false` | 可选服务（`ENABLE_NIKKI` 会克隆并构建 Nikki-RS / clash-rs） |
| `ENABLE_MOSDNS` | `true` | MosDNS 是否直接装进固件（在线构建同样默认内置） |
| `ENABLE_EBPF_PROXY_KERNEL` | `true` | 写入 `CONFIG_KERNEL_CGROUPS` / `CONFIG_KERNEL_CGROUP_BPF`，给 Nikki-RS 的 eBPF 代理补齐 cgroup BPF 内核支持（会改变内核 ABI，关闭则只有 TC 快路径） |
| `THREADS` | CPU 核数 | 并行度 |

其余开关（`ENABLE_WWAND` / `ENABLE_MT5700M` / `ENABLE_EASYMESH` / `ENABLE_THEME_ARGON`
等）及各自默认值以 `scripts/local-build.sh --help` 为准。

想把软件源指向自己的服务器：

```sh
./scripts/serve-apk-repo.sh          # 另开一个终端，会打印出该用的地址
H5000M_APK_REPO_URL=http://<你的地址>:8099 ./scripts/local-build.sh
```

## 已知限制

- **没有 TurboACC / MTK HNAT**：主线不提供，硬件加速走的是 PPE + netfilter flowtable
  这条路。只要 fw4 的 `flow_offloading_hw` 开着就已经生效。
- **无线与 5G 需要真机验证**：仿真能验证脚本与启动流程，但射频、模组附着、风扇曲线
  这类依赖真实硬件的行为，只能上机确认。
- 第三方代理面板由各自上游维护，本项目只负责把它们编译进仓库并保证依赖完整。
- **不要额外添加 `nikki-rs.pages.dev` 源**：本固件的软件源已经包含 `nikki-rs` /
  `clash-rs` / `luci-app-nikki-rs`，无需 nikki-rs 官方的 `feed.sh`。混用外部源会出现
  `WARNING: updating and opening https://nikki-rs.pages.dev/...: UNTRUSTED signature`
  （该源的公钥不在固件里），且可能装上与本固件 ABI/版本不一致的 `clash-rs`。
  已经加过的，删掉 `/etc/apk/repositories.d/` 里指向 `nikki-rs.pages.dev` 的那一行，
  再 `apk update` 即可。
- **不要盲目 `apk upgrade`**：镜像里保留了官方 snapshot 源，而那些版本比本工程的构建新
  —— `apk` 取最高版本，升级会把钉住的 `sing-box` 换成 1.13+（HomeProxy / PassWall2 会
  因此起不来），也可能换上与内核不匹配的 kmod。装包用 `apk add <包名>` 就好。
- 需要**本项目没有编译进去的 kmod** 的包装不上：kmod 必须与内核 vermagic 一致，官方
  源里的对不上。遇到这种包，得把它加进构建配置重新编译。
- **btrfs + snapper 的机器上，删掉本地构建产物不等于立刻回收空间**：本机做过一次全量
  编译后 `openwrt/` 约 70 GB，删掉之后 `df` 可能仍然是满的，因为 snapper 的 timeline
  快照还引用着那棵树。用 `sudo snapper -c home list` 找到构建期间生成的快照并
  `sudo snapper -c home delete <编号>` 才会真正释放；只等 `snapper-cleanup` 的话，
  daily/monthly/yearly 那几档会把它留很久。

## 文档

| 文件 | 内容 |
| --- | --- |
| [docs/engineering.md](docs/engineering.md) | 上游选型论证、组件集成细节、实机问题的逐条根因分析、软件包审计、仿真测试结论 |
| [docs/proxy-kmod-audit.md](docs/proxy-kmod-audit.md) | 各代理软件所需内核模块的逐包证据 |

## 验证软件源

想确认某个固件对应的软件源能不能装，用设备自己的 apk 逻辑查一遍：

```sh
./scripts/verify-apk-repo.sh                       # 查本机刚编译出的 artifacts/apk-repo/
./scripts/verify-apk-repo.sh --with-official-feeds # 再加上官方源，等价于实机环境
./scripts/verify-apk-repo.sh https://<地址>/packages.adb   # 查已经发布的源
```

它会只配置指定的源，用构建出的 `apk` 建一个临时数据库，逐条断言：15 个面板、12 个核
与守护进程、20 个 kmod、12 个中文语言包都在，`sing-box` 是钉住的 1.12.25，以及**每个
面板都能解析出它需要的核**。`--with-official-feeds` 还会显示 `apk policy`，把"官方源里
更新的版本会被优先选中"这件事直接摆出来。

## 许可证

见 [LICENSE](LICENSE)。
