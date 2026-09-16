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

可安装的包括 **PassWall、PassWall2、HomeProxy、MosDNS、Nikki、Momo、NeKoBox、
v2rayA、OpenClash、SSR-Plus** 以及各自的中文语言包。内核模块与固件同一次构建产出，
所以 ABI 天然匹配，不必担心装不上。

代理面板运行需要的内核侧依赖已经**装进固件本身**，不需要用户再补：

| 已内置 | 作用 |
| --- | --- |
| `kmod-tun` / `ip-full` | TUN 模式（面板提示的 "需要安装 ip-full 和 kmod-tun" 已是过去式） |
| `kmod-nft-socket` / `kmod-nft-tproxy` / `kmod-nft-fullcone` | 透明代理与 FullCone |
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
| Argon 主题 | LuCI 主题 |
| UPnP IGD / ttyd | 端口映射 / 网页终端 |

硬件加速用的是**主线自己的 PPE 卸载**（fw4 的 `flow_offloading_hw`），首次启动已自动
开启。它与 ImmortalWrt 上的 TurboACC / MTK HNAT 是**两套不同的东西**，后者在主线这个
SoC 上并不存在。

## 自己编译

### 云编译

Fork 本仓库，在 **Actions → 构建 H5000M 主线 OpenWrt 固件 → Run workflow** 手动触发。
构建完成后固件自动发布为 Release，软件包仓库自动发布到 GitHub Pages。

大部分组件已固定为默认内置，界面上只保留确实需要选择的开关（5G 拨号器、Docker、
各代理前端等）。

### 本地编译

```sh
# 装依赖（Debian/Ubuntu 用 apt，Arch 用 pacman）
./scripts/local-build.sh --install-deps

# 全量编译
./scripts/local-build.sh
```

产物在 `artifacts/`：sysupgrade 镜像、rootfs、manifest，以及可供设备安装的 apk 仓库。

常用环境变量：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `H5000M_WIFI_SSID` | `openwrt` | 首启 SSID |
| `H5000M_WIFI_KEY` / `_ENCRYPTION` | 空 / `none` | 默认开放网络 |
| `H5000M_APK_REPO_URL` | 空 | 软件源基址；留空则固件不带额外源 |
| `ENABLE_ADBLOCK` / `ENABLE_HOMEPROXY` | `false` | 关闭时编进软件源（`=m`），打开时装进固件（`=y`） |
| `ENABLE_DOCKERMAN` / `ENABLE_NIKKI` / `ENABLE_OPENCLASH` / `ENABLE_ADGUARDHOME` | `false` | 可选服务 |
| `THREADS` | CPU 核数 | 并行度 |

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
- **不要盲目 `apk upgrade`**：镜像里保留了官方 snapshot 源，而那些版本比本工程的构建新
  —— `apk` 取最高版本，升级会把钉住的 `sing-box` 换成 1.13+（HomeProxy / PassWall2 会
  因此起不来），也可能换上与内核不匹配的 kmod。装包用 `apk add <包名>` 就好。
- 需要**本项目没有编译进去的 kmod** 的包装不上：kmod 必须与内核 vermagic 一致，官方
  源里的对不上。遇到这种包，得把它加进构建配置重新编译。

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

它会只配置指定的源，用构建出的 `apk` 建一个临时数据库，逐条断言：14 个面板都在、
核与守护进程都在、18 个 kmod 都在、`sing-box` 是钉住的 1.12.25，以及**每个面板都能
解析出它需要的核**。`--with-official-feeds` 还会显示 `apk policy`，把"官方源里更新的
版本会被优先选中"这件事直接摆出来。

## 许可证

见 [LICENSE](LICENSE)。
