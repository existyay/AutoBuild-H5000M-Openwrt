# 工程记录

本文件保存 README 精简后移出的技术内容：上游选型论证、组件集成细节、实机反馈的
逐条根因分析、参考工程软件包审计、以及仿真测试的实测结论。

面向使用者请读 [README](../README.md)；代理相关内核模块的逐包证据见
[proxy-kmod-audit.md](proxy-kmod-audit.md)。

---

## 一、为什么上游选 `openwrt/openwrt` main（SNAPSHOT）

这是本工程最关键的一个结论，已逐条核对官方发布产物：

1. **H5000M 设备支持是 2026-01-09 才进上游的**：

   ```
   6487cc9a1f  mediatek: add support for Hiveton H5000M
   ```

   落在 `target/linux/mediatek/image/filogic.mk` 的 `Device/hiveton_h5000m`
   （DTS 为 `target/linux/mediatek/dts/mt7987a-hiveton-h5000m.dts`）。

2. **它不在任何已发布的 25.12.x 里**。逐个核对
   `https://downloads.openwrt.org/releases/<ver>/targets/mediatek/filogic/profiles.json`：

   | 版本 | profiles.json 是否含 `hiveton_h5000m` |
   | --- | --- |
   | 25.12.0 / 25.12.1 / 25.12.2 / 25.12.3 / 25.12.4 / 25.12.5 | **否** |
   | snapshots（`r36216-f0d3e332e5`） | **是** |

   `openwrt-25.12` **分支** HEAD 上确实有该设备（在 25.12.5 tag 之后被 cherry-pick），
   但还没有任何一个 25.12.x 发布镜像带着它。

3. 因此 **SNAPSHOT `main` 既是“最新的”、也是当前唯一真正发布 H5000M 镜像的主线上游**。

4. 上游 H5000M 的 `DEVICE_PACKAGES` 已经包含风扇所需的一切：

   ```
   kmod-hwmon-pwmfan kmod-usb3 mt7987-2p5g-phy-firmware kmod-mt7996e kmod-mt7992-23-firmware
   ```

   也就是说 `pwm-fan` 驱动和 MT7992 固件由官方 target 提供，本工程不需要碰内核。

5. 这也正是各插件维护者验证过的基线：

   * `luci-app-h5000m-fancontrol` README：兼容 `OpenWrt SNAPSHOT`；
   * `ddimension` 二进制源同时发布 `stable/snapshot/` 与 `stable/openwrt-25.12/`，
     两者都有 `aarch64_cortex-a53`；
   * `FAN789/openwrt-H5000M` 钉住的回退基线是 snapshot `r35844`。

> 上游 revision、kernel 版本与 **kernel ABI** 会随 snapshot 变化。本工程把它们写进产物
> 的 `BUILD-INFO.txt` —— 预编译插件的 `.apk` 必须与该 ABI 匹配才能装到这块固件上。

参数集中在 `configs/upstream.env`：

```sh
OPENWRT_REPO_URL=https://github.com/openwrt/openwrt.git
OPENWRT_REPO_BRANCH=main
OPENWRT_PINNED_REVISION=f0d3e332e5f839508f77fba8c7420ceeb079ab86
OPENWRT_TRACK=latest          # latest 跟随分支头；pinned 复现指定 revision
OPENWRT_TARGET=mediatek
OPENWRT_SUBTARGET=filogic
OPENWRT_PROFILE=hiveton_h5000m
```

等 25.12.6 带上该设备后，把 `OPENWRT_REPO_BRANCH` 改成 `openwrt-25.12` 即可切到稳定分支。

---

---

## 二、三个 H5000M 组件

### 1. 风扇管理 — `luci-app-h5000m-fancontrol`

* 来源：<https://github.com/FAN789/luci-app-h5000m-fancontrol>（当前 2.1.0）
* 提供：静音/均衡/性能/自定义四条温度曲线、手动 PWM、滞回、降速延迟、启动助推、
  传感器故障安全模式，简体中文界面。
* 依赖 `kmod-hwmon-pwmfan` —— 官方 H5000M profile 已经带上。

**必须同时打设备树补丁**：`mt7987.dtsi` 给 `cpu-thermal` 定义了四张 cooling map，
其中三张会与用户态控制器抢同一个 PWM 通道。`patches/0001-h5000m-userspace-fan-control.patch`
（从该插件 2.1.0 的 `openwrt-patches/` 原样导入）删掉 `cpu-active-high` / `cpu-active-low` /
`cpu-passive`，**保留 `cpu-active-hot`**，所以内核的 CPU 降频、高温与临界关机保护不受影响。

已验证该补丁对 `OPENWRT_PINNED_REVISION` 上的树 `git apply --check` 通过。

### 2. 出口优先级 — `luci-app-h5000m-netmode`

* 来源：<https://github.com/FAN789/luci-app-h5000m-netmode>（当前 1.3.1）
* 提供：有线 WAN 优先 / 5G 优先 / 仅有线 / 仅 5G 四种策略，接口 hotplug 自动重算，
  切换出口时自动重载已安装的代理服务，并约束 IPv6 出口。
* 状态：只读查询与策略写入分权（普通监控账号改不了出口策略）。

### 3. 5G 拨号 — `ddimension/wwand`

* 来源：<https://github.com/ddimension/wwand>，OpenWrt 包定义在
  [`ddimension/openwrt-repo`](https://github.com/ddimension/openwrt-repo) feed（本工程已作为
  `src-git wwand` 引入）。
* H5000M 内置模组是 **TD Tech MT5700M**（USB `3466:3301`），以 **cdc_ncm** 枚举并带 AT 侧信道
  —— 正好由 `wwand` 的 **NCM 后端**原生驱动，不需要 `comgt-ncm`、`ModemManager` 或 `uqmi`。
* 同时启用 `wwand-qmi` / `wwand-mbim`，覆盖 USB 与 M.2 位的 QMI / MBIM 模组；
  `wwand-mhi` 未默认开启（PCIe/MHI 模组才需要）。
* 约 3 MB RSS、正常运行时零进程派生；配置全部在 `/etc/config/network`（WireGuard 风格）。

---

---

## 三、集成缝：wwand ↔ netmode

两个组件默认互不认识，本工程用一个极小的板级胶水包把它们接起来，**不改任何一方源码**：

```
local-packages/h5000m-integration/
├── Makefile
└── files/
    ├── usr/sbin/h5000m-wwan-provision          # 幂等配置器
    ├── etc/uci-defaults/91-h5000m-wwan         # 首启调用
    └── etc/hotplug.d/usb/50-h5000m-wwan        # 模组后枚举时调用
```

冲突点在于 **netmode 靠“名字”找 5G 接口**：它的 `discover_modem_interfaces()` 读
`network.MT5700M.device` / `.ifname`，否则回退到名为 `MT5700M` 或 `USB` 的 section；
而它的 `iface` hotplug 守卫只处理带 `modem_config` 或 `managed_by mt5700m` 的接口。
wwand 那一侧则是 `config wwand_modem` + `option proto 'wwand'`。

因此 `h5000m-wwan-provision` 在首启（或模组后枚举）时写入正好满足双方约定的一小段配置：

```uci
config wwand_modem 'm0'
	option device 'wwan0'      # 实际探测到的 MT5700M 数据 netdev
	option path '1-1'          # 稳定 sysfs 锚点，L3 改名后仍可绑定

config interface 'MT5700M'
	option proto 'wwand'
	option modem 'm0'
	option pdp_type 'ipv4v6'
	option metric '50'
	option managed_by 'wwand'
	option modem_config 'wwand'   # netmode hotplug 守卫标记

config interface 'MT5700Mv6'
	option proto 'dhcpv6'
	option device '@MT5700M'
	option extendprefix '1'
```

结果：wwand 掌管数据面，netmode 看到一个一等公民的 modem 接口，两个上游包都可以原样跟进。
脚本幂等——`network.MT5700M` 一旦存在就完全不动它。若模组尚未枚举，脚本什么都不做，
交给 wwand 自己的 autosetup 建默认 `wwan0`。

### wwand 与 luci-app-mt5700m 互斥

两者都会驱动同一个 cdc_ncm 数据面、都想拥有 `network.MT5700M`。默认取 **wwand**；
若同时打开，`resolve_modem_stack()` 会大声提示并自动关掉 `luci-app-mt5700m`
（沿用参考工程处理 QModem / 原版 modem 互斥的同一套做法）。

需要哪个由用途决定：

| 想要 | 选择 |
| --- | --- |
| 原生 QMI/MBIM/NCM 拨号、eSIM、多模组、~3 MB 内存占用 | `ENABLE_WWAND=true`（默认） |
| 模组温度进风扇曲线（fancontrol 读 mt5700m 的温度缓存）、MT5700M 专用面板 | `ENABLE_MT5700M=true ENABLE_WWAND=false` |

互斥不只是"两个开关不同时打开"，而是三条独立机制各自保证的：

1. `resolve_modem_stack()` 在配置生成前就把两者掰开，wwand 胜出并打印警告。
2. `h5000m-integration` **不硬依赖** wwand，而是写成
   `DEPENDS:=+PACKAGE_wwand:wwand +PACKAGE_wwand:luci-proto-wwand`：只有 wwand 已被选中时
   才要求它。写成 `+wwand` 会把整个 wwand 栈拖进每一个镜像，包括 mt5700m 那条路径。
3. 首启 provisioner 开头就检查 `/lib/netifd/proto/wwand.sh`，不存在直接退出。否则在
   mt5700m 镜像上它会写一个 `proto wwand` 的接口，而那个 proto 根本没装。

另外，`luci-app-mt5700m` 硬依赖 `ubus-at-daemon` 与 `sms-tool_q`，这两个包**只**存在于
[FUjr/QModem](https://github.com/FUjr/QModem) feed 里。所以 `write_feeds_conf()` 只在
`ENABLE_MT5700M=true` 时把它追加进 `feeds.conf.default`——wwand 构建完全看不到 QModem，
因为后者是一整套竞争性的 modem 栈（自带驱动和自带 LuCI 面板）。切换开关后 feeds 集合变了，
`feed_tree_is_complete()` 会忽略 `--skip-feeds-update` 强制更新一次，`prune_stale_feeds()`
则清掉上一次留下的 `package/feeds/<feed>` 软链。

---

---

## 四、目录结构

```
.
├── .github/workflows/build.yml             云编译（周更 + 手动 + tag）
├── configs/
│   ├── upstream.env                        上游仓库/分支/钉住 revision/目标三元组
│   └── h5000m.config                       .config 基线（target、LuCI、中文、工具、IPv6）
├── feeds.conf.default                      OpenWrt 官方 feeds + ddimension(wwand) feed
├── patches/
│   ├── 0001-h5000m-userspace-fan-control.patch   设备树风扇策略补丁
│   └── 0002-h5000m-mt76-txwi-fix.patch           mt76 TXWI 缺陷修复（上游未合并）
├── mt76-patches/
│   └── 100-mt7996-always-fill-txwi.patch    0002 的原始内容（供单独取用/提交上游）
├── local-packages/
│   └── h5000m-integration/                 wwand ↔ netmode 板级胶水
└── scripts/
    ├── local-build.sh                      唯一构建入口（本地与 CI 共用）
    ├── check-deps.sh                       主机依赖与资源检查
    └── coverage-test.sh                    配置覆盖测试（不完整编译）
```

---

---

## 五、本地编译

需要 x86_64 Linux。先看主机是否就绪：

```sh
./scripts/check-deps.sh
```

配置阶段（拉源码 + feeds + 打补丁 + defconfig + 校验包集合，**不编译**）：

```sh
./scripts/local-build.sh --config-only
```

完整编译：

```sh
./scripts/local-build.sh                      # 首次会自动装依赖？不会——先跑下面这条
./scripts/local-build.sh --install-deps       # Debian/Ubuntu 用 apt，Arch 用 pacman
./scripts/local-build.sh
```

常用参数：

| 参数 | 说明 |
| --- | --- |
| `--install-deps` | 安装编译依赖（apt-get 或 pacman） |
| `--prepare-only` | 拉到源码/feeds/补丁/本地包后停止 |
| `--config-only` | 再跑 defconfig 与包校验后停止 |
| `--pinned` | 编译 `OPENWRT_PINNED_REVISION` 而不是分支头 |
| `--skip-toolchain` | 跳过显式 `make toolchain/install` |
| `--skip-download` | 跳过 `make download` |
| `--skip-feeds-update` | 复用已有 feeds（本地迭代提速） |

功能开关（环境变量，沿用参考工程命名）：

```sh
# 板级功能栈
ENABLE_FANCONTROL=true    # luci-app-h5000m-fancontrol + 设备树补丁
ENABLE_NETMODE=true       # luci-app-h5000m-netmode
ENABLE_WWAND=true         # ddimension/wwand 拨号
ENABLE_MT5700M=false      # luci-app-mt5700m（与 wwand 互斥）

# 可选服务
ENABLE_UPNP=true ENABLE_ADBLOCK=true
ENABLE_DOCKERMAN=false
ENABLE_NIKKI=false ENABLE_OPENCLASH=false ENABLE_MOSDNS=false
ENABLE_HOMEPROXY=false ENABLE_ADGUARDHOME=false
```

三个板级插件（`luci-app-h5000m-fancontrol` / `-netmode` / `-mt5700m`）不在任何 feed 里，
构建脚本会把它们从各自上游仓库克隆到 `package/`；**克隆失败会直接中止构建**，不会产出一个
没有风扇控制或没有出口仲裁的固件。其余第三方组件（Nikki / OpenClash / MosDNS / HomeProxy）
同样是克隆，但失败只告警。AdGuardHome 走官方 feeds，不需要克隆。

例：用 mt5700m 面板 + 打开 Nikki：

```sh
ENABLE_WWAND=false ENABLE_MT5700M=true ENABLE_NIKKI=true THREADS=8 ./scripts/local-build.sh
```

配置覆盖测试（每个开关组合都要能生成合法 `.config`，不编译固件）：

```sh
./scripts/coverage-test.sh quick
./scripts/coverage-test.sh full
```

产物在 `artifacts/`：

| 文件 | 说明 |
| --- | --- |
| `openwrt-mediatek-filogic-hiveton_h5000m-squashfs-sysupgrade.bin` | **刷机镜像** |
| `openwrt-mediatek-filogic-hiveton_h5000m-initramfs-kernel.bin` | initramfs 恢复镜像 |
| `*-targz-rootfs.tar.gz` / `*-rootfs.tar.gz` | rootfs 压缩包（本配置 `CONFIG_TARGET_ROOTFS_TARGZ=y`） |
| `*.manifest` | 镜像内实际安装的包清单（约 274 个） |
| `BUILD-INFO.txt` | 本次上游 revision、kernel 版本与 **kernel ABI** |
| `profiles.json` | 上游生成的版本/内核元数据（ABI 的权威来源） |
| `sha256sums` | 校验和 |
| `enabled-packages.txt` | 进入最终 `.config` 的符号清单（约 297 个），见下方说明 |
| `packages/` | 本 target 专有的 `.apk` —— **kmod 都在这里**（含 `kmod-mt7996e`） |
| `apk-repo/` | **与本镜像 ABI 匹配的 apk 仓库**，保留 OpenWrt 原生 `<arch>/<feed>/` 布局（含 `packages.adb` 与 `index.json`），可直接给 apk 用 |

两者不要混淆：**kmod 是 target 专有的**，落在 `packages/`；`apk-repo/` 装的是架构级
feed（base/luci/packages/routing/telephony/video/wwand），没有 kmod。

`apk-repo/` 是刻意收集的：官方 snapshot 仓库的 `vermagic` 与本镜像不同，从那里装的
kmod 会因 ABI 不匹配被拒绝；同一轮构建产出的仓库才是配套的。

### 关于镜像大小

本机实测：sysupgrade **18.3 MB**，而官方 snapshot 同型号是
**11.0 MB** —— 我们比官方**大 66%**，不是小。差别来自本工程在官方最小镜像之上加了
LuCI 全套、中文语言包、argon 主题、三个
板级组件、wwand、AdBlock、UPnP 以及一批诊断工具（htop / nano / ttyd / iperf3 / tmux /
usbutils / pciutils）。

rootfs 解压后 36.5 MB（argon 主题只增加了约 0.5 MB），构成如下：

| 目录 | 占用 |
| --- | --- |
| `usr/lib` | 11.6 MB |
| `lib/modules` | 4.7 MB |
| `usr/bin` | 4.0 MB |
| `usr/share` | 3.6 MB |
| `usr/sbin` | 3.3 MB |
| `lib/firmware`（MT7992 无线固件等） | 2.3 MB |

kmod 并没有缺失：`.config` 里启用的 **94 个 kmod 与镜像内实装的 94 个双向差集为空**。
设备关键的 17 个（`kmod-mt7996e`、`kmod-mt7992-23-firmware`、`kmod-cfg80211`、
`kmod-mac80211`、`kmod-hwmon-pwmfan`、`kmod-usb-net-cdc-ncm/mbim/qmi-wwan`、`kmod-rmnet`、
`kmod-usb3` 等）全部在内。

> 注意不要拿 `enabled-packages.txt` 和 `.manifest` 直接相减。前者是 **`.config` 符号**，
> 后者是**实际包名**：ABI 版本化的库在两边名字不同（`libubox` ↔ `libubox20260721`、
> `libgcc` ↔ `libgcc1`、`jansson` ↔ `jansson4`），而且前者还含 `MAC80211_DEBUGFS`、
> `TAR_GZIP`、`trusted-firmware-a-*` 这类**构建期开关，根本不是包**。判断"镜像里有什么"
> 请只以 `.manifest` 为准。

---

---

## 六、云编译

`.github/workflows/build.yml`：

* **定时**：每周一 04:00 UTC（北京 12:00）自动构建并上传 artifact。
* **手动**：`workflow_dispatch`，所有 `ENABLE_*` 与 `publish_release`、`pinned`、
  `runner_type`（github-hosted / self-hosted）都是输入项。
* **tag**：推送 `openwrt-*` 或 `v*` 触发并发布 Release。

`check` job 在主机构建之前做四件便宜的事，避免跑到一半才发现问题：

1. `check-deps.sh` 主机依赖检查；
2. 所有 `scripts/*.sh` 语法检查，外加 `shellcheck -S error`（只拦真实缺陷，不管风格）；
3. 拉一次上游 `filogic.mk` 确认 `Device/hiveton_h5000m` 仍然存在，
   并对 `patches/*.patch` 做 `git apply --check`；
4. 通过 GitHub API 确认三个板级插件仓库与 ddimension feed 仍然存在 ——
   它们是在构建时才克隆的，被改名或删除不该等到编译中途才暴露。

`coverage` job 与固件编译**并行**跑配置覆盖，配置回归不会卡住发版。

### action 版本与 Node 运行时

action 主版本是**刻意固定**的，不要往下调：

| action | 版本 | 运行时 |
| --- | --- | --- |
| `actions/checkout` | `v7` | node24 |
| `actions/upload-artifact` | `v7` | node24 |
| `actions/cache` | `v6` | node24 |
| `jlumbroso/free-disk-space` | `v1.3.1`（原来跟 `main`） | — |

原先用的是 `checkout@v4` / `upload-artifact@v4` / `cache@v4`，它们声明的是 **node20**，
而 node20 已被 GitHub 弃用。当时靠 workflow 顶层的
`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` 压过去 —— 那是个过渡期的逃生舱，会把只为
node20 测试过的 action 硬塞到 node24 上跑。**升级主版本才是正解，该环境变量已删除，
不要加回来。**

---

---

## 七、实机测试反馈与修复

固件刷入真机后确认可以正常进系统，同时暴露出四个问题。逐条记录现象、查证过程和结论，
把"已修复"和"仅定位到候选原因"分开写清楚。

### 1. 主题没有更新 —— 已修复

参考工程配置了 `luci-theme-argon` + `luci-app-argon-config`，本工程此前完全没处理，
刷出来是主线的默认 `luci-theme-bootstrap`。

两个包都**不在任何主线 feed** 里（`luci-theme-bootstrap` / `footstrap` / `material` /
`openwrt` / `openwrt-2020` 是可选的，argon 不是），所以和板级插件一样从上游仓库克隆：

| 包 | 仓库 | 版本 |
| --- | --- | --- |
| `luci-theme-argon` | `jerrykuku/luci-theme-argon` @ `master` | 2.4.7 |
| `luci-app-argon-config` | `jerrykuku/luci-app-argon-config` @ `master` | 1.0 |

**装上就会生效**，不需要额外写 uci-defaults：主题包自带
`/etc/uci-defaults/30_luci-theme-argon`，它把 `luci.main.mediaurlbase` 指到
`/luci-static/argon`。开关是 `ENABLE_THEME_ARGON`（默认 `true`）。

主题包依赖里有 `+USE_APK:wget-any`，而主线包索引里只有 `wget-ssl` / `wget-nossl`，
看起来像会失败；实测 `--config-only` 全程**没有任何 `wget-any` 警告**，两个符号都正常
进入 `.config`，19 个必需包校验通过。这个依赖由 `wget` 的 `PROVIDES` 解析掉了。

### 2. 无线无法开启 —— 已定位到上游未修复的 mt76 缺陷，已内置修复

先把"不是本工程造成的"证清楚：

| 检查 | 结果 |
| --- | --- |
| 驱动支持 MT7992 | 是，`MT7992_DEVICE_ID` 就在 `mt7996/mac.c` 的 PCI ID 表里 |
| 固件是否齐全 | 齐，`mt7992_{wm,wa,rom_patch,eeprom,dsp}_23.bin` 6 个 + `mt7996e.ko` |
| 无线包集 | 与官方 snapshot **完全一致**（官方 profile 用的也是 `wpad-basic-mbedtls`） |
| DTS 是否被迁移改动 | 否，与 `immortalwrt/immortalwrt` master **逐字节相同** |
| pin 之后上游是否修过该 DTS | 否，`git log` 显示该文件只有添加它的那一条 commit |
| EEPROM nvmem 布局 | `eeprom@0 reg = <0x0 0x1e00>`，与 `gl-be10000`/`gl-mt3600be`/`routerich-be7200`/`tenda-be12-pro` 完全一致；`0x1e00 = 7680 = MT7996_EEPROM_SIZE`，是驱动期望值 |
| wpad 是否缺 11be | 不缺，镜像里的 wpad 二进制含 `ieee80211be` / `eht_bw320_offset` |

所以这不是迁移缺陷，而是主线 H5000M 支持本身的问题。

#### 根因：mt76 的 TXWI 缺陷（已内置修复）

`openwrt/mt76` 的 issue [#1043](https://github.com/openwrt/mt76/issues/1043)
（"NAT performance degradation on WiFi IPv4 download with MT7987A+MT7991A
platform"，至今 **open**）里，**把 H5000M 加进 OpenWrt 的那位开发者 fildunsky**
在 2026-07-02 写道：

> This patch for `mt76` **also fixed my Hiveton H5000M**.

2026-08 他又确认 2.4G "started to work fine after patching mt76 #1043"；
另一位开发者 akorshun 在 2026-08-23 同样确认 "also fixes hiveton h5000m wifi
issue"。同一 issue 里还有 H5000M 用户报告 "working but dmesg shows some panic
message on WiFi driver"。

缺陷本体是 `mt7996/mac.c` 里两处条件判断——主机在 802.3 帧上把 TXWI 留空，
固件就会错误解析：

```c
	/* Transmit non qos data by 802.11 header and need to fill txd by host*/
	if (!is_8023 || pid >= MT_PACKET_ID_FIRST)
		mt7996_mac_write_txwi(dev, txwi_ptr, tx_info->skb, wcid, key,
				      pid, qid, 0, link_id);
```

本工程已把修复作为**默认补丁**内置：`patches/0002-h5000m-mt76-txwi-fix.patch`，
它落到 `package/kernel/mt76/patches/100-mt7996-always-fill-txwi.patch`
（OpenWrt 的 `PATCH_DIR` 机制，`include/quilt.mk:37`），内容是把这两处判断改为
无条件填充 TXWI / 施加 TXD。

三点已验证：

* 我们构建用的 mt76（`2026.09.01~be5ce791`）里 bug 代码**一字不差**存在
* 补丁在该 revision 上 `patch -p1` **干净应用**（无 offset、无 fuzz）
* `openwrt/mt76` master **至今仍带这段 bug 代码**（`mt7996/mac.c:1136` 与 `:1188`），
  即修复没有上游化，只能自己带

#### 另外两件与真机状态有关的事

**(a) factory 分区内容 —— 让它是空的。** 上游合并 commit `6487cc9a1f` 的正文
自己写明：

> Factory `mmcblk0p2` partition is empty... Flashing this eeprom before flashing
> OpenWrt will make OpenWrt read eeprom ... **But it will have wifi issues for
> now. It's better to use OpenWrt fallback eeprom for now.**

作者贴出的**正常工作**日志里就有 `eeprom load fail, use default bin` ——
在这一块板子上**这是正常的**，不是故障。驱动回退链是：nvmem 读到全 0 →
`mt7996_check_eeprom()` 拒绝 → 转 efuse → 再失败才用
`/lib/firmware/mediatek/mt7996/mt7992_eeprom_23.bin`（或 FEM 为 INT 时的
`_23_2i5i.bin`）——**两个文件镜像里都有**，所以空分区本身不会导致起不来。
反过来，刷了 vendor 的 `MT7991_MT7976_EEPROM_BE5040_iPAiLNA.bin` 才会有问题。

所以：**不要刷任何 vendor eeprom**。若曾被刷过，清空即可：

```sh
dd if=/dev/mmcblk0p2 bs=4 count=1 2>/dev/null | od -A n -t x1   # 先看
dd if=/dev/zero of=/dev/mmcblk0p2 bs=1 count=7680 conv=fsync
sync
```

**(b) 若 dmesg 里完全没有固件版本行，则是 MT7992 variant 不匹配。**
`mt7996_variant_type_init()`（`init.c:1208`）按 `MT_PAD_GPIO` strap 决定
`VAR_TYPE_23/44/24`。24 型会请求 `mt7992_*_24.bin`，而这类文件在 mt76
`be5ce791` 的 firmware 目录里**不存在**，OpenWrt 也没有任何包提供。
此项为**基于源码的推断，无第二方证据**，且 strap 由硬件决定，无法从源码判定。

#### 真机诊断顺序

```sh
dmesg | grep -E "mt7996e|mt76"        # ① 有没有 WM/DSP/WA Firmware Version 行
dmesg | grep -i eeprom                # ② "use default bin" 是正常的
lspci -nn                             # ③ 能不能看到 MediaTek 无线设备
iw dev ; ls /sys/class/ieee80211/     # ④ radio 有没有被创建
logread | grep -i hostapd             # ⑤ hostapd 拒绝原因
```

判读：①无固件版本行 → (b)；③看不到设备 → PCIe 枚举问题；④有 phy 无 wlan →
mt76 绑定问题；⑤ 才是配置/加密选项问题。

> 有一类说法**不适用于本固件**：参考工程文档里"无线客户端侧的网络加速把本地流量
> 误卸载导致无线异常"出自 **ImmortalWrt + MTK HNAT** 的语境，而主线**没有 HNAT**
> （见下一节），所以那句话描述的是另一套软件栈的现象。

### 3. 无线网络加速 —— 根因明确：主线这个 SoC 上做不了

参考工程里的 `luci-app-turboacc-mtk` 是 **MTK 私有分支**的面板，它开关的是
`/sys/kernel/debug/hnat/` 下的 HNAT。主线**没有 `mtk_hnat` 驱动**——整个
`target/linux/mediatek` 树里搜不到，所有 feed 里也没有 `luci-app-turboacc` /
`turboacc-mtk`。面板即使硬塞进去也只是个写不存在 sysfs 的死 UI，所以本工程不带它。

参考工程配置里的 `# CONFIG_PACKAGE_kmod-mtk_wed is not set` 同样要说明：那是
**MTK 私有 SDK 的符号**，在 mainline 上既不存在、也不生效。主线对应的开关是
`CONFIG_NET_MEDIATEK_SOC_WED`，它是 `def_bool NET_MEDIATEK_SOC != n`，即随
以太网驱动自动 `=y`，不需要也不应该手动设置。

那主线自己的硬件加速 **WED**（Wireless Ethernet Dispatch）呢？分两层看：

* **以太网侧**有：`mt7987.dtsi` 定义了 `wed0: wed@15010000`，以太网节点引用
  `mediatek,wed = <&wed0>`。
* **PCIe 侧没有**：`mt7987.dtsi` **没有 `wed_pcie` 节点**，也没有
  `mediatek,wed-pcie` phandle。对比 MT7986 的 `mt7986a.dtsi`：那里有
  `wed_pcie: wed-pcie@10003000` 和 `mediatek,wed-pcie = <&wed_pcie>`。
  而 WED 要卸载**无线**流量必须走 PCIe 那条通路。

所以 **MT7987 在设备树层面就无法做 PCIe-WED**，这不是配置能补的。

WED 也不是无线起不来的原因：mt7996e **不依赖** WED——`mmio.c:17`
`static bool wed_enable;`（无初值 → false），`:490` `if (!wed_enable) return 0;`；
即便打开，`:621` `mtk_wed_device_attach()` 失败也只是返回 0 降级，所有 WED 使用点
都被 `mtk_wed_device_active()` 包住。

**结论**：本固件上可用的"网络加速"只有 nftables flowtable 的**软件 offload**，
它的 UI 已经在随固件安装的 `luci-app-firewall` 里（网络 → 防火墙 → 常规设置 →
软件流量分载），默认关闭。

> 网上流传的 `options mt7996e wed_enable=1` 写进 `/etc/modules.conf` 是合法参数
> （不会导致模块加载失败），但在 H5000M 上因为没有 PCIe-WED 通路，**不会有实际
> 效果**。

### 4. IPv6 不太对 —— 本工程的真实 bug，已修复

这个是自己写错了。`h5000m-wwan-provision` 原先额外创建了一个伴生接口：

```
config interface 'MT5700Mv6'    proto dhcpv6, device '@MT5700M', extendprefix 1
```

wwand 自己的文档 `docs/reference.md`（"RNDIS IPv6 — the dhcpv6 subinterface"一节）
把它否掉了，而且是连着三条：

* `<parent>_6` 形式的 dhcpv6 子接口属于 **rndis_host** 数据面；MT5700M 是 **cdc_ncm**。
* `extendprefix '1'` **只能用于 `pdp_type 'ipv6'`**；本工程配的是 `ipv4v6` 双栈。
* 原文："the `proto wwand` path needs no equivalent — the shim already shares its own /64"。

最隐蔽的是第四条：文档说明**用户自己定义的** `option device '@<parent>'` + `proto dhcpv6`
的 section 会让 wwand "writes nothing"——即 wwand 认为 IPv6 已由用户接管。所以我那段代码
不只是多余，它还**把 IPv6 从 wwand 手里拿走了**。

修复：删掉整个 `MT5700Mv6`，只保留单个双栈 wwand 接口，IPv6 交给 `proto wwand` 的 shim。
`IFACE6` 变量、Makefile 描述和 provisioner 头注释里的相关说法一并清理。

### 5. 烧录重启后无线默认关闭 —— 已修复

OpenWrt 出厂把所有 radio 设为 `disabled`，要登录并选国家才启用。在一台 5G CPE 上，
这个默认行为会被理解成"无线坏了"。

新增 `/usr/sbin/h5000m-firstboot`，写入两个入口、共用同一份实现：

| 入口 | 时机 |
| --- | --- |
| `/etc/uci-defaults/92-h5000m-defaults` | 首次启动 |
| `/etc/hotplug.d/ieee80211/20-h5000m-defaults` | 无线 PHY 出现时 |

**为什么是两个入口**：`/etc/config/wireless` **不在镜像里**，它由 `/sbin/wifi config`
生成，而触发它的是镜像自带的 `/etc/hotplug.d/ieee80211/10-wifi-detect`。只写
uci-defaults 有可能在任何 radio 段存在之前就运行、什么都没配上。把 hotplug 脚本编到
`20`（在 `10-wifi-detect` 之后）才能保证顺序。

应用一次后用 `/etc/h5000m-defaults-applied` 标记，并由
`lib/upgrade/keep.d/h5000m-defaults` 让 sysupgrade 保留该标记，所以后续刷机
**不会重置用户改过的设置**。判断条件也很保守：只要任一 AP 的 SSID 已不是默认值，
就完全不碰。

默认值（构建时可覆盖，见下表）：

```
SSID       openwrt
密码       无                ← 默认开放网络，请自行加密
国家/加密  CN / none
htmode     2.4G=EHT40  5G=EHT160
```

**默认是开放网络**：`encryption=none` 且不写 `key`。这样一台刚刷好的设备无需任何凭据即可
连上，凭据不会被印在某个没人看的地方。首启脚本在无密码时**删除** `key` 选项而不是写入
空值，并且**不设置** `ieee80211w` —— 在未加密接口上要求 PMF 会让 hostapd 拒绝整份 AP
配置。构建日志会明确写出 `OPEN NETWORK`。

另外**不写** `bss_transition` —— 官方紧凑版 wpad 不认识该 hostapd 选项，会导致
**整个 AP 配置被拒绝**。

### 6. 硬件加速不能用 —— 根因是控制面不同，已启用主线那条

这里要说清楚一件事：**你要的 TurboACC 面板在主线上一行代码都没有**。

| 检查 | 结果 |
| --- | --- |
| 主线是否有 `mtk_hnat` | 否 |
| 主线是否有 `luci-app-turboacc` / `turboacc-mtk` | 否 |
| 主线是否有 `shortcut-fe` / `fast-classifier` | 否 |

TurboACC 面板开关的是 `/sys/kernel/debug/hnat/` 下的 **厂商 out-of-tree HNAT 驱动**，
主线没有这个驱动，所以那个面板即使硬塞进来也是个写不存在 sysfs 的死 UI。

**但同一块硬件在主线上是有的，只是换了个控制面。** 主线把 HNAT 的能力吸收进了
`mtk_ppe_offload.c`，通过**标准 netfilter flowtable 卸载 API**（`flow_cls_offload`）
暴露，也就是 fw4 的 `flow_offloading_hw`。MT7987 的接线是完整的：

* `mtk_eth_soc.c` 的 `mt7987_data` 声明 `.offload_version = 2`、`.ppe_num = 2`
* `mtk_ppe_init()` 对两个 PPE 都被调用（`mtk_eth_soc.c:5816`）
* `nf_flow_table.ko`、`nf_flow_table_inet.ko`、`nft_flow_offload.ko` 都在镜像里
* 内核 `CONFIG_NFT_FLOW_OFFLOAD=m`、`CONFIG_NF_FLOW_TABLE=m`

**所以它只是没打开**：fw4 把 `flow_offloading` 与 `flow_offloading_hw` 都默认成 `"0"`，
而 stock 的 `/etc/config/firewall` 两个都不写。首启脚本现在把两者都设为 `1`，
并且它们在 LuCI（网络 → 防火墙 → 常规设置）里**依旧可见可改**。

> 也就是说：**同一块 PPE，"硬件加速"在主线上叫 `flow_offloading_hw`，不叫 TurboACC。**

### 7. 代理软件包的源与 kmod 依赖 —— 已修复

两个独立问题：

**(a) 固件里没有任何指向本工程的源。** `distfeeds.list` 全部指向
`downloads.openwrt.org`，而**官方 kmod 与本镜像的 vermagic 不同**，从那里装任何带 kmod
依赖的包都会被拒；同时没有任何一条指向我们自己产出的仓库。

现在 `collect_artifacts` 会装配一个**扁平单索引仓库**，同时收录两处产物：

```
bin/packages/<arch>/<feed>/            架构级包
bin/targets/<board>/<subtarget>/packages/   全部 kmod   ← 别的仓库给不了
```

做成扁平而非 OpenWrt 的 `<arch>/<feed>/` 树，是因为固件必须在**任何东西被编译之前**
（`install_local_packages` 阶段）就知道源地址，那时无法判断哪些 feed 目录最终非空。
单索引只需要一条 URL，从根上消掉了这个顺序问题和空 feed 问题。

**(b) 代理的 kmod 依赖没有完整进入仓库。** 代理栈的 kmod 依赖——
`kmod-tun`、`kmod-nft-tproxy`、`kmod-inet-diag`——**已经编译出来了**，但此前它们只是
散落在 `artifacts/packages/` 里，**没有索引**，所以不是可安装的仓库。现在它们和架构级
包一起进了同一个带索引的仓库。

固件侧：`H5000M_APK_REPO_URL` 会被烘焙成
`/etc/apk/repositories.d/50-h5000m.list`（OpenWrt 为此保留的文件，且 sysupgrade 会保留）。
CI 会自动按运行它的仓库推导地址，并有独立 job 把仓库发布到 Pages。

| 构建变量 | 默认 | 说明 |
| --- | --- | --- |
| `H5000M_APK_REPO_URL` | 空 | 仓库基址；**留空则固件不带额外源**（指向不存在的托管会让 `apk update` 报错） |
| `H5000M_WIFI_SSID` / `_KEY` / `_COUNTRY` / `_ENCRYPTION` | `openwrt` / 空 / `CN` / `none` | 首启无线默认值；默认无密码 |
| `H5000M_FLOW_OFFLOAD` / `_HW` | `1` / `1` | 软件 / PPE 硬件卸载 |

### 8. 调制解调器重复 —— 已修复（只剩一个 wwand）

镜像里只有**一个拨号器**（`wwand` + 它的 3 个后端），没有 `luci-app-mt5700m`、
`comgt`、`ModemManager`、`uqmi`/`umbim`。但存在一条真实的重复路径：

`wwand` 的**零配置 autosetup** 在"完全没有 wwand 配置"时会自建
`config wwand_modem 'wwmodem_auto'` + `config interface 'wwan0'`
（`docs/reference.md`：*"Autosetup never runs when any wwand config exists"*）。
而本工程的 provisioner 建的是 `network.m0` + `network.MT5700M`，**原来的守卫只查
`MT5700M`，检测不到 autosetup 建的那一套**。

启动顺序让这个竞态真实存在：`S10boot`（跑 uci-defaults，provisioner 首次执行）→
`S19wwand`。如果首次执行时 MT5700M 还没枚举完，provisioner 会提前退出；
随后 wwand autosetup 建好配置；等 USB 热插拔再次调用 provisioner 时，它会在
autosetup 的配置**之上**再加一套 —— 一个模组两个拨号接口。

修复两处：

* 守卫改为"**只要存在任何 wwand 配置就不动手**"，匹配 `wwand_modem` 段或任何
  `proto 'wwand'` 接口，因此 autosetup 的命名也能识别
* 成功建立自己的配置**之后**，写
  `config wwand_globals 'globals'` + `option autosetup '0'`，让 wwand 不会再补第二套

"之后才关"是刻意的：如果 provisioner 因为换了 USB ID 不同的模组而无法配置，
autosetup 仍是开启的，机器能自己起来。

### 9. 代理软件的 kmod 依赖 —— 已补齐

代理插件（PassWall / PassWall2 / SSR-Plus / HomeProxy / OpenClash / Nikki / Momo /
FullCombo Shark! / luci-xray / NeKoBox / Daed / HiJpass / v2rayA）重定向流量依赖的是
同一批内核设施：nftables 的 tproxy/socket、对应的 iptables 老接口、用户态隧道用的
tun 与 inet-diag，以及 NAT helper 与流量控制模块。

盘点后发现**基础集已经齐备**（`kmod-nft-tproxy`、`kmod-nft-socket`、`kmod-nft-nat`、
`kmod-nf-tproxy`、`kmod-nf-socket`、`kmod-nf-nat`、`kmod-nf-conntrack`、`kmod-tun`、
`kmod-inet-diag`、`kmod-nf-nathelper-extra`、`kmod-veth`、`kmod-dummy`、
`kmod-br-netfilter` 等），缺的是这 6 个，已补为 `=m` 进入仓库：

```
kmod-netlink-diag  kmod-nf-nathelper  kmod-macvlan
kmod-sched-core    kmod-ifb           kmod-tcp-bbr
```

> **只补"完全没构建"的模块，这是有意的。** 对已经是 `=y` 的模块写 `=m` 不是空操作：
> 它可能把已安装的模块降级成"仅仓库"，从而**从镜像里移除**，把防火墙弄坏。所以
> 基础系统已经需要的那批（`kmod-nft-*`、`kmod-nf-conntrack`、`kmod-nf-nat`、
> `kmod-ipt-*` …）**刻意不列入** —— 它们本来就在镜像里，比"可安装"更好。
>
> `kmod-xdp-sockets-diag` **刻意不加**：它依赖 `KERNEL_XDP_SOCKETS`，而本内核没有开启
> 该选项，符号会被 defconfig 丢掉；代理栈里没有任何东西需要它（那是 `ss` 工具的可选
> 视图），为它打开内核选项会变更 ABI、触发全量重编却不带来收益。

`kmod-tcp-bbr` 顺带把 BBR 拥塞控制也带进了仓库——这在主线上是**真实可用**的加速手段
之一（见 [七.6](#6-硬件加速不能用--根因是控制面不同已启用主线那条)）。

#### 代理前端：本体 + LuCI + 中文翻译，三者缺一不可

只编本体是不够的。`apk add luci-app-passwall` 之后界面没有中文，正是因为**上游把中文
翻译做成独立的包**（`luci-i18n-passwall-zh-cn`），而没有任何东西会自动把它拉进来。
所以下面每个代理都按**三件套**编入仓库：

| 代理 | 本体 / LuCI / 中文包 | 上游仓库 |
| --- | --- | --- |
| PassWall | `luci-app-passwall` + `luci-i18n-passwall-zh-cn` | `Openwrt-Passwall/openwrt-passwall` @ `main` |
| PassWall2 | `luci-app-passwall2` + `luci-i18n-passwall2-zh-cn` | `Openwrt-Passwall/openwrt-passwall2` @ `main` |
| Momo | `momo` + `luci-app-momo` + `luci-i18n-momo-zh-cn` | `nikkinikki-org/OpenWrt-momo` @ `main` |
| fcshark | `mihomo` + `luci-app-fchomo` + `luci-i18n-fchomo-zh-cn` | `fcshark-org/openwrt-fchomo` @ `master` |
| NeKoBox | `luci-app-nekobox`（无中文 po） | `Thaolga/openwrt-nekobox` @ `main` |
| luci-xray | `luci-app-xray` + `-geodata` + `-status`（无中文 po） | `yichya/luci-app-xray` @ `master` |
| Daed | `daed` + `luci-app-daed` + `luci-i18n-daed-zh-cn` | `QiuSimons/luci-app-daed` @ `kix` |
| HiJpass | `luci-app-hijpass` + `luci-i18n-hijpass-zh-cn` | `WROIATE/luci-app-hijpass` @ `main` |
| v2rayA | `v2raya` + `luci-app-v2raya` | **主线 feeds，无需克隆** |
| PassWall 核心群 | `chinadns-ng` `dns2socks` `geoview` `hysteria` `ipt2socks` `naiveproxy` `shadow-tls` `tcping` `v2ray-plugin` `xray-plugin` `shadowsocks-rust-*` `shadowsocksr-libev-*` `simple-obfs-*` | `Openwrt-Passwall/openwrt-passwall-packages` @ `main`（**已裁剪**） |

> **包名取自构建系统自己的 `tmp/.packageinfo`，不是 grep Makefile 猜的。** 这些是 LuCI
> 应用，包名等于目录名，`define Package/` 一个都找不到；猜错的名字会被 `defconfig`
> **一声不响地丢掉**。

**同名冲突用裁剪解决，而不是容忍。** `openwrt-passwall-packages` 自带 `xray-core`、
`sing-box`、`microsocks`；`openwrt-nekobox` 自带 `sing-box` 和 `mihomo`；`fcshark` 也定义
`mihomo`。整仓克隆会让同一个包名出现多个定义——而本工程的树目前 **12757 个包零同名
冲突**，这个性质值得保住。做法是签出后删掉重复目录，让每个名字只剩一个定义，前端从
feeds 解析其余依赖。

**审计覆盖的软件包**：PassWall、PassWall2、SSR-Plus、HomeProxy（`immortalwrt` 与
`VIKINGYFY` 两个变体）、OpenClash、Nikki、Momo、FullCombo Shark!（fchomo）、
luci-xray（`yichya` 与 `ttimasdf`）、NeKoBox、Daed（`QiuSimons` 与 `kenzok8`）、
HiJpass、v2rayA。逐包的 Makefile 路径、行号与审计 commit 见
[`proxy-kmod-audit.md`](proxy-kmod-audit.md)。

**审计顺带查出的、与 kmod 无关但会绊住你的事**：

* **流传的仓库地址大多已失效。** `xiaorouji/openwrt-passwall` 与
  `xiaorouji/openwrt-passwall2` 现在都是 **404**，已转移到
  `Openwrt-Passwall/` 组织；`v2rayA/openwrt` 是 **404**，实为
  `v2rayA/v2raya-openwrt`；**`QiuSimons/openwrt-xray` 根本不存在**
  （该用户下没有任何 xray 仓库）。照抄旧地址的脚本会静默抓不到东西。
* **PassWall / PassWall2 仓库里只有 LuCI 前端**，核心守护进程包在**独立的
  `openwrt-passwall-packages`** 仓库，三个都要加。
* **v2rayA 有两个来源、kmod 结论相反**：`v2rayA/v2raya-openwrt` 的包
  **不声明任何 kmod**（只在 README 里要求手动装 `kmod-nft-tproxy`），会让
  `apk add v2raya` 后 tproxy **静默失败**；`openwrt/packages` 官方 feed 版才有
  硬依赖。
* **代理的非 kmod 依赖大面积缺失。** 例如 `chinadns-ng`、`dns2socks`、`tcping`、
  `geoview`、`shadowsocks-rust-*`、`shadowsocksr-libev-*`、`naiveproxy`、
  `hysteria`、`shadow-tls` 等 14 个包不在本工程的任何 feed 里。
  **本次只解决了 kmod 部分**；要真正 `apk add` 装上这些代理，还需要为它们补第三方
  feed 或把它们一并编进仓库。
* **`xray-core` 会同名冲突**：`openwrt/packages` 与 `openwrt-passwall-packages`
  都提供 `xray-core`，只能留一个。
* **Daed 需要内核选项，不只是 kmod**：`CONFIG_KERNEL_XDP_SOCKETS`、
  `CONFIG_KERNEL_DEBUG_INFO_BTF`、`CONFIG_KERNEL_BPF_EVENTS/CGROUPS/CGROUP_BPF`、
  `CONFIG_BPF_TOOLCHAIN_HOST`。这些**不是包而是内核配置**，开启会变更内核 ABI 并
  触发全量重编，且 BTF 会明显增大镜像。**本次未开启**，因此 Daed 目前装不上；
  需要的话告诉我，我加一个独立开关。

---

## 八、已知限制

* **已完成验证的范围 —— 完整固件已在本机编译成功**（`BUILD_EXIT=0`，6 核，含工具链）：

  | 项目 | 结果 |
  | --- | --- |
  | 上游 revision | `d0d8c40b678c8326551ad37fc8bbecc53cb33217`（`OPENWRT_TRACK=latest`；`--pinned` 可回到固定的 `f0d3e332e5`） |
  | kernel | `6.18.44`，ABI `949e3839f10545b1b342c4acf59c6ba6` |
  | 刷机镜像 | `…-squashfs-sysupgrade.bin`，18,288,902 字节（约 18 MB） |
  | initramfs | `…-initramfs-kernel.bin`，17,248,520 字节 |
  | 镜像内包数 | 274（`manifest`；服务类包为 `=m`，不在其中） |
  | 收集的 apk | target 专有 168 个 + 仓库 221 个（含 16 个服务类包） |

  三个 H5000M 组件确实进入了镜像（取自 `manifest`，非推测）：

  ```
  luci-app-h5000m-fancontrol - 2.1.0-r1
  luci-app-h5000m-netmode    - 1.3.1-r2
  wwand                      - 1.6.6_p22-r1   (+ wwand-ncm, luci-app-wwand, luci-proto-wwand)
  h5000m-integration         - 1.0.0-r1
  kmod-hwmon-pwmfan          - 6.18.44-r1
  kmod-mt7996e               - 6.18.44.2026.09.01~be5ce791-r1
  kmod-mt7992-23-firmware    - 6.18.44.2026.09.01~be5ce791-r1
  ```

  配置覆盖测试三条 profile 全部 PASS：

  | profile | 开关 | 结果 |
  | --- | --- | --- |
  | `default` | 默认（wwand） | PASS，17 个必需包 |
  | `mt5700m` | `ENABLE_WWAND=false ENABLE_MT5700M=true` | PASS，14 个必需包，`.config` 中**无任何 wwand 包** |
  | `minimal` | 关掉 upnp / adblock / fancontrol / netmode | PASS |

  注：本次构建走的是默认的 `OPENWRT_TRACK=latest`，落到当时的 main head
  `d0d8c40`——**已经不是所固定的 `f0d3e332e5` 了**，上游在此期间前进了。这一点顺带验证了
  两件事：两个树补丁（风扇策略、mt76 TXWI）在移动后的 head 上**仍然干净适用**，
  `defconfig` 与全量编译都通过。要构建与文档快照 `r36216-f0d3e332e5` 完全对应的版本，
  用 `scripts/local-build.sh --pinned`。

  另：`--pinned` 之外的构建会得到 `r0-<sha>` 形式的 `openwrt_version_code`，因为浅克隆
  没有 tag、`scripts/getver.sh` 算不出真实计数；脚本只在 revision 正好等于固定值时替换为
  已知的 snapshot id（见下方说明）。
* **实机验证状态**：已刷机，可正常进系统。实测暴露的主题、无线、加速、IPv6 四项见
  [七、实机测试反馈与修复](#七实机测试反馈与修复)。其中**风扇曲线、5G 附着与出口切换
  仍未验证**，需要真机确认。
* `BUILD-INFO.txt` 里的 `openwrt_version_code` 在构建树于 shallow clone 中时会是 `r0-<sha>`
  （`scripts/getver.sh` 需要 tag 才能算出真实计数）。当 revision 正好等于本工程固定值时，
  脚本会改用官方已发布的 snapshot id（如 `r36216-f0d3e332e5`）；其他 revision 则保留
  构建树给出的值，不臆造。
* `wwand` 对 MT5700M 的驱动依赖其 NCM 后端对这颗模组的兼容性。若现场发现 wwand 无法
  附着，`ENABLE_MT5700M=true ENABLE_WWAND=false` 可切回 FAN789 的 NCM/DHCP 拨号路径；
  两条路径不会同时进入固件（`resolve_modem_stack()` 强制互斥）。
* 可选的第三方代理组件（Nikki / OpenClash / MosDNS / HomeProxy）全部默认关闭，且是从
  各自上游仓库直接克隆进 `package/` 的，**不保证**与当前 snapshot 兼容；打开它们属于
  自行承担风险，`coverage-test.sh full` 会校验其配置符号。
* `luci-app-h5000m-*` 与 wwand 的版本会各自前进。插件是源码随固件编译的，所以在
  `package/` 里改一次 commit 或 tag 就等于换版本;二进制单装才需要匹配 kernel ABI。
* 官方 H5000M 端口定义为 `eth0` = LAN、`eth1` = 有线 WAN，MAC / WiFi EEPROM / LED /
  sysupgrade 布局全部沿用 OpenWrt 官方实现。
* **补丁依赖 `git reset --hard`，这是隐式约束，现已改为显式断言。** `patches/0001`
  （风扇策略）是"纯插入"型补丁：它在一段不会被改动的上下文之间插进一个块，所以
  `git apply` **无法**检测出它已应用过——再应用一次会插入第二份 `delete-node`，
  `dtc` 会因此报错。`apply_patches` 里的 `--reverse --check` 对这类补丁是失效的；
  真正保证只应用一次的是 `prepare_source` 的 `git reset --hard`。脚本现在会在应用
  每个补丁前**断言**该补丁触及的文件在树中尚未被修改，否则直接失败而不是默默写坏，
  以免哪天 `prepare_source` 被改动后这个隐式前提悄悄失效。

---

## 九、迁移参考

迁移期间查阅的上游与参考仓库：

| 用途 | 仓库 |
| --- | --- |
| 被迁移的参考脚手架 | `existyay/Auto-H5000M-BIN` |
| 官方 H5000M 基础固件（ImageBuilder 路线，作为交叉参考） | `FAN789/openwrt-H5000M` |
| 风扇管理 | `FAN789/luci-app-h5000m-fancontrol` |
| 出口优先级 | `FAN789/luci-app-h5000m-netmode` |
| MT5700M 面板（可选、与 wwand 互斥） | `FAN789/luci-app-mt5700m` |
| 5G 拨号守护进程 | `ddimension/wwand` |
| 5G 拨号 OpenWrt 包定义 | `ddimension/openwrt-repo` |

---

---

## 十、参考工程软件包可集成性审计

把 `existyay/Auto-H5000M-BIN` 工作流里出现的**每一个**软件包拿来，逐项在主线核对。方法：
从它的 `h5000m.extra.config` 与 `scripts/local-build.sh` 提取全部符号，与主线
`tmp/.config-package.in`（12735 个可选符号）做集合运算，再对每个"主线没有"的项
去上游确认归属。

根因先说清楚：**参考工程用的是 ImmortalWrt feeds**
（`immortalwrt/packages` + `immortalwrt/luci` @ `openwrt-24.10`），本工程用**主线**
（`openwrt/packages` + `openwrt/luci` @ `master`）。大部分差异由此而来，不是"忘了搬"。

### 统计结果

| | 数量 |
| --- | --- |
| 参考工程包总数（去重） | **82** |
| 主线可直接集成 | **52** |
| 主线没有 | **30** |

### 主线没有的 30 个，按原因分类

| 类别 | 数量 | 包 | 说明 |
| --- | --- | --- | --- |
| MTK 私有 `mtwifi` 驱动 | 11 | `kmod-connac_if` `kmod-mt7992` `kmod-mt799a` `kmod-mt_hwifi` `kmod-mtk_pci` `kmod-mtk_wed` `kmod-mt_wifi7` `kmod-mt_wifi_cmn` `mtwifi-cfg` `luci-app-mtwifi-cfg` `luci-i18n-mtwifi-cfg-zh-cn` | MTK 闭源驱动。主线用开源 `mt76`（本工程装 `kmod-mt7996e`），这些符号**在主线根本不存在** |
| HNAT 加速面板 | 1 | `luci-app-turboacc-mtk` | 开关 `/sys/kernel/debug/hnat/`，主线无 `mtk_hnat` 驱动。见 [七.3](#3-无线网络加速--根因明确主线这个-soc-上做不了) |
| 已从主线移除 | 3 | `vlmcsd` `luci-app-vlmcsd` `luci-i18n-vlmcsd-zh-cn` | 主线 `packages`/`luci` 上游 **404 已确认**；ImmortalWrt 仍有 |
| ImmortalWrt 独有 | 1 | `luci-app-ramfree` | 主线 `openwrt/luci` 404，`immortalwrt/luci` 200 |
| 旧 LuCI 遗留 | 3 | `luci-cbi` `luci-lib-cbi` `luci-lib-docker` | 现代 LuCI 已删（改为客户端 JS）。注意主线版 `luci-app-dockerman` 依赖 `luci-base + docker + ttyd + dockerd + docker-compose + ucode-mod-socket`，**不需要** `luci-lib-docker` |
| 已改名换代 | 1 | `luci-app-Airpifanctrl` | → `luci-app-h5000m-fancontrol` |
| 第三方，可克隆集成 | 10 | `luci-app-homeproxy` `luci-i18n-homeproxy-zh-cn` `luci-app-mosdns` `luci-i18n-mosdns-zh-cn` `mosdns` `luci-app-nikki` `luci-i18n-nikki-zh-cn` `nikki` `mihomo-meta` `luci-app-openclash` | 本工程已作为**可选开关**从各自上游克隆，默认关 |

主线可直接集成的 52 个里，有 2 个（`luci-theme-argon`、`luci-app-argon-config`）其实是
**我们自己的克隆**而不是主线原生包，核对时已扣除。

### 实测：照搬参考工程的包列表会怎样

这是本节最重要的结论。把上述 30 个符号直接追加进 `.config` 后跑 `make defconfig`：

```
EXIT=0                          ← 不报错
30 个符号中只有 10 个活下来      ← 其余 20 个被静默丢弃
没有任何警告点名这 20 个符号      ← 日志里那些 WARNING 说的是别的包缺依赖
```

那 10 个"活下来"的是因为我们的克隆恰好提供了它们；真正被丢掉的 20 个正是上表里
私有/已移除的那批。

**也就是说：`defconfig` 对不存在的包名既不失败也不提示，固件能正常编译，
只是静默缺少你自以为启用了的功能。** 这是照搬参考工程配置最容易踩的坑。

针对这一点，本工程加了防线：`build_required_packages()` 现在会把**每个已启用的
可选开关**对应的包也列入必需校验，缺任何一个就直接失败而不是默默出货。全部可选
开关打开时有 **37 个必需包**接受校验（默认配置 23 个）。

### 审计中发现并修复的 3 个 bug

**(1) `ENABLE_ADGUARDHOME=true` 会中止整个构建。** `install_external_packages`
里有一行克隆 `https://github.com/ruigvis/luci-app-adguardhome.git` —— **该仓库
不存在（HTTP 404）**。`set -Eeuo pipefail` 生效时，`is_true X && clone_external ...`
中后者失败会触发 `set -e`，脚本带着一句 git 的 "Repository not found" 直接退出。

而且这个克隆**根本不需要**：`adguardhome`、`luci-app-adguardhome`、
`luci-i18n-adguardhome-zh-cn` 三个包**主线 feeds 都有**。参考工程当年用
`sirpdboy/luci-app-adguardhome` 的预编译 ipk，那是另一条已经过时的路径。
修复：删掉该克隆；同时把可选克隆改为经由 `install_optional_external()`，
失败时报出**是哪个 `ENABLE_*` 开关**和哪个 URL，而不是一句裸的 git 错误。

**(2) `set -e` × `is_true X && ...` 的函数末尾陷阱。** 修复 (1) 时我给
`build_required_packages()` 追加了若干 `is_true "$ENABLE_X" && REQUIRED_PACKAGES+=(...)`
行，最后一行的开关是 `ENABLE_ADBLOCK`。当它为 false 时，函数**最后一条语句返回 1**，
而该函数是在 `set -e` 下作为普通语句调用的 → 整个构建**无任何输出地中止**。
原先最后一行是无条件数组追加（永远返回 0），把这个陷阱掩盖了。

它由覆盖测试抓出来：`minimal` profile（唯一设置 `ENABLE_ADBLOCK=false` 的）
在第二次 defconfig 之后日志突然截断。修复：加显式 `return 0`，并排查了脚本里
所有函数，确认没有同类结尾。

**(3) CI 的默认覆盖档位盖不到可选开关。** 上面两个 bug 都出自可选开关的代码路径，
而 CI 在 push/定时触发时跑的是 `coverage-test.sh quick`，其三个 profile
（default / mt5700m / minimal）**没有一个打开 ADGUARDHOME**；能覆盖到它的
`services` / `proxy-stack` 在 `full` 档里，而 `full` 只在手动触发时才跑。
修复：把 `all-optional`（一次性打开全部可选开关）加进 `quick`，并给 `full`
补了 `no-argon`。

修复后 `quick` 的 4 个 profile 全部 PASS。

### 与厂商 defconfig 的差异对照

参考工程的基线源码是 `padavanonly/immortalwrt-mt798x-24.10`，其默认配置取自
`mt798x-mt799x-6.6-mtwifi` 分支的 `defconfig/mt7987_mt7992.config`（7905 行，
启用 330 个包）。拿它和本工程对照，可以找出"厂商有、主线也有、但我们没装"的项——**91 个**。
逐个核对后只有一项属于真正的缺陷：

| 项 | 状态 | 结论 |
| --- | --- | --- |
| **`luci-app-ttyd`** | **缺陷，已修复** | 本工程装了 `ttyd` 守护进程却**没装它的 LuCI 页面**，Web 终端在界面上根本进不去。FAN789 的构建器与厂商 defconfig **都装了这一对**。已补 `luci-app-ttyd` + `luci-i18n-ttyd-zh-cn` |
| `iwinfo` | 非缺口 | 无线状态页要的是 `rpcd-mod-iwinfo`（`luci-mod-network` 的直接依赖），它和 `libiwinfo` 都已在镜像里。`iwinfo` 只是独立的命令行工具 |
| `dnsmasq-full` | 可选增强 | 厂商用 `dnsmasq-full`（含 `dnsmasq_full_dhcpv6`）。本工程用主线默认的 `dnsmasq` + `odhcpd-ipv6only`，LAN 侧 IPv6 由 odhcpd 负责。换 `dnsmasq-full` 还能带来 DNSSEC 与 nftset（Adblock 的最佳后端） |
| `kmod-tcp-bbr` | 可选增强 | BBR 拥塞控制。这是主线上**真实可用**的加速手段之一（HNAT/WED 都不可用，见 [七.3](#3-无线网络加速--根因明确主线这个-soc-上做不了)） |
| `kmod-nf-nathelper-extra` | 可选增强 | NAT 助手（FTP/SIP/PPTP 等）与全锥形 NAT |
| `kmod-usb-serial-option` `kmod-usb-acm` | 可选增强 | 模组 AT 串口。wwand 走 cdc-wdm 控制通道，不依赖它们；装了便于手工调试 |
| `kmod-usb2` `kmod-usb-ehci` `kmod-usb-ohci` | 一般不需要 | 上游 `DEVICE_PACKAGES` 给的是 `kmod-usb3`；xHCI 本身向下兼容 USB 2.0 设备 |
| `luci-compat` `luci-lib-*` `lua*` `ucode-mod-lua` | 不需要 | Lua 版 LuCI 应用运行时。本工程的应用栈是 JS，用不到 |
| `libqmi` `libmbim` `libqrtr-glib` `kmod-pcie_mhi` `sms-tool` | 不需要 | 私有 mtwifi/ModemManager 栈的配套。wwand 自己实现 QMI/MBIM/AT |
| `opkg` | 不适用 | 主线自 25.12 起用 apk |
| `jq` `bc` `coremark` `mhz` `tc-tiny` `kmod-macvlan` `kmod-ifb` `kmod-usb-storage-extras` 等 | 中性 | 纯工具/功能包，按需加即可 |

### 第三方仓库与主线的冲突分析

这是迁移里最需要证伪的一件事。做了两类检查：

**① 包名碰撞 —— 没有。** 解析 `tmp/.packageinfo` 得到 **12757 个包**，按
`Package:` → `Source-Makefile:` 归并后统计"同名包被多个源定义"：

```
包总数: 12757
同名包（多源）: 0
```

`luci-theme-argon`、`luci-app-argon-config`、`luci-app-h5000m-fancontrol`、
`luci-app-h5000m-netmode`、`luci-app-mt5700m`、`OpenClash`、`OpenWrt-nikki`、
`homeproxy`、`luci-app-mosdns`、`h5000m-integration` 这些克隆进来的目录，
**没有一个与主线 feed 里的包重名**，因此不存在静默覆盖。

**② Kconfig 循环依赖 —— 有 7 处，其中 5 处由第三方引入。** `defconfig` 因此打印
`recursive dependency detected!`，但**仍然 `EXIT=0` 并写出配置**，不影响构建成败。

| 循环链 | 来源 |
| --- | --- |
| `luci-app-homeproxy` → `sing-box-tiny` → `sing-box` → (selected by) `luci-app-homeproxy` | 第三方 `homeproxy` + 主线 `sing-box` 变体机制 |
| `luci-app-wwand` ↔ `luci-proto-wwand` ↔ `wwand` | 第三方 wwand feed |
| `wwand-esim` depends on **itself** | 第三方 wwand feed（该包定义的明显缺陷） |
| `mihomo-alpha` ↔ `mihomo-meta` | 第三方 `OpenWrt-nikki` |
| `libubus-lua`（主线核心）↔ `libubus-lua-async`（wwand feed） | 第三方 wwand feed |
| `librespeed-cli-rust` → `librespeed-cli` → `librespeed-common` | **主线自身**（与本工程无关） |
| `luci-app-librespeed` depends on **itself** | **主线自身**（与本工程无关） |

实际影响评估：唯一可能咬人的是 homeproxy 那条，因为本工程会显式启用 `sing-box`。
核对 `.packageinfo` 里**解析后**的元数据，`luci-app-homeproxy` 的依赖是
`+sing-box +firewall4 +kmod-nft-tproxy +ucode-mod-digest`，**没有 `Conflicts`**，
与显式启用的 `sing-box` 一致，所以循环只停留在变体符号层面，不产生实际冲突。
另两处 wwand 的"依赖自己"是上游包定义的毛病，不影响 `wwand` 本身工作。

**结论：可以集成，无需为冲突做任何规避。**

### 服务类包：编译进仓库，但不装进镜像

按"能后续安装的就先不烧进固件"的原则，Docker 栈、代理栈（nikki / OpenClash /
MosDNS / HomeProxy）与 AdGuardHome **默认不进入镜像**，改为 `=m`：

```
CONFIG_PACKAGE_docker=m
CONFIG_PACKAGE_dockerd=m
CONFIG_PACKAGE_luci-app-dockerman=m
```

`=m` 是 OpenWrt 的标准机制：**编译该包并把 .apk 放进 `bin/packages/`，但不安装进
rootfs**；其运行时依赖同样以 `=m` 产出，所以仓库自洽，用户可以直接
`apk add luci-app-dockerman`。已在本树实测：`CONFIG_PACKAGE_jq=m` 在 defconfig 后
保留，`make .../jq/compile` 产出
`bin/packages/aarch64_cortex-a53/packages/jq-1.8.2-r1.apk`，且没有任何模块进入镜像。

打开对应的 `ENABLE_*` 开关会把该组升级为 `=y`（装进固件），留给确实想烧进去的人。

| 开关 | 默认 | 镜像内 | apk-repo |
| --- | --- | --- | --- |
| `ENABLE_DOCKERMAN` | false | ✗ | ✓（docker/dockerd/containerd/runc/docker-compose + LuCI） |
| `ENABLE_NIKKI` | false | ✗ | ✓（nikki/mihomo-meta + LuCI） |
| `ENABLE_OPENCLASH` | false | ✗ | ✓ |
| `ENABLE_MOSDNS` | false | ✗ | ✓（mosdns + LuCI） |
| `ENABLE_HOMEPROXY` | false | ✗ | ✓（+ sing-box、kmod-nft-tproxy） |
| `ENABLE_ADGUARDHOME` | false | ✗ | ✓（+ 中文语言包） |
| `ENABLE_REPO_PACKAGES` | **true** | — | 关掉可跳过上述编译以加快迭代 |

代价要讲清楚：这会显著拉长构建时间，Docker 与代理栈都是大型 Go 程序。
只想快速验证固件本身时，用 `ENABLE_REPO_PACKAGES=false` 跳过。

---

## 十一、仿真测试

没有真机时能验证到什么程度，实测结论如下。**两条路径的边界完全不同**，值得分开记。

### Renode：能建出平台，但无法引导到用户态

Renode 装在本机（`/opt/renode`），但缺 `dotnet` 运行时。**这一点可以免 root 解决**：
官方 `dotnet-install.sh` 把 .NET 8 装到 `~/.dotnet` 即可，之后 `renode --version`
正常输出 `v1.17.0 / .NET 8.0.31`。

平台也不是死路。Renode 自带 229 个 `.repl` 里**没有任何 MediaTek 平台**，但它配套的
`dts2repl` 可以把设备树转成平台描述。该工具的安装方式被它自己的
`tools/dts2repl-version.sh` 钉死了（且钉死了兼容 commit）：

```
pip install "git+https://github.com/antmicro/dts2repl@<version.sh 给出的 commit>"
```

把已构建的 DTB 反编译后喂给它，**确实生成了一个可用的 MT7987 平台**：4 个
Cortex-A53、GICv3（含 redistributor）、ARM 通用定时器（62.5 MHz）、
256 MB DRAM @ `0x40000000`。再补一个 `UART.NS16550`（`wideRegisters: true`，
对应 MTK 的 32 位寄存器间隔，IRQ 123）就能加载内核：

```
sysbus: Loading block of 17273604 bytes length at 0x40080000.
sysbus: Loading block of 27762 bytes length at 0x4F000000.
```

**但引导到此为止。** 要让 cpu0 从内核入口而不是复位向量 0x0 开始执行，必须先
`cpu0 IsHalted true` → 设 PC → 再解除 halt；即便如此，内核会**立即触发同步异常**
跳到 `0x200`（未初始化的异常向量表）。原因不是配置问题，而是模型缺口：

* MT7987 的**时钟控制器**（`topckgen` / `infracfg` / `apmixedsys`）、pinctrl、
  reset、watchdog 在 Renode 里**没有模型**，而 Linux 的 MTK 平台代码必须先让这些
  驱动 probe 成功，才能建立定时器和串口
* 更根本的是：**MT7992 无线、5G 模组、风扇 PWM、以太网交换芯片在 Renode 里完全
  不存在**。哪怕把平台补到能进用户态，**也无法验证这台机器上真正要验证的任何东西**

要往下走是一个平台开发项目（为 MTK 外设写 Renode 模型），不是配置调整。已探明边界，
没有继续投入。

### qemu-user + 真实 uci：这条路径有效，并且抓到了一个会出货的 bug

`qemu-aarch64-static` 可以预编译二进制取得（无需 root），配合 `-L <rootfs>` 能直接执行
固件里的 aarch64 程序。关键点是 **uci 支持 `-c <path>` 指定配置目录**，所以**根本不需要
proot/chroot/root** —— 而且实测确认它只读写指定目录，**不会碰宿主机的 `/etc/config`**。

`scripts/rootfs-script-test.sh` 就是这条路：解出 rootfs → 用**固件自带的那个 uci 二进制**
跑首启脚本 → 断言配置结果。

**它立刻抓到了一个我和静态审查都没发现的 bug：**

```sh
uci -q set "wireless.radio0.disabled='0'"     # 引号在双引号内 → 值是字面的 '0'
```

`uci` 存进去的是 `'0'` 而不是 `0`。而 OpenWrt 的 `config_get_bool` **不认识** `'0'`，
会回落到默认值 —— 也就是说**无线仍然是关闭的**，而 `/etc/config/wireless` 看起来
完全正常。同样受影响的还有 SSID（客户端会看到一个名字带引号的网络）、国家码、
htmode，以及两个 flow offload 开关（**硬件卸载根本没打开**）。

也就是说：**我上一轮声称"已修复"的无线默认开启与硬件加速，实际都会静默失效。**

`uci batch` **会**剥掉引号，所以用 batch 的 `h5000m-wwan-provision` 本来就是对的；
错的只有命令行 `uci set` 这一种形式。

**为什么之前没抓到**：此前我用 shell mock 验证过同一段逻辑并通过了 —— 但 mock 会把
传进来的字符串原样存下，`'0'` 和 `0` 都能"通过"。**只有真实解析器会拒绝它。**

> 测试脚本还会额外断言配置**原始文件**内容，因为带引号的值读回来仍是"非空"，
> 单看取值会显得合理。
>
> 注意：该脚本验证的是 `artifacts/` 里的 rootfs 打包，所以**在重新构建固件之前，
> 它会对已出货的镜像持续报这个 bug** —— 这正是它应有的行为。

### 四层 fullcone 链路：静态审查全部通过，运行时验证抓出 5 个缺陷

nftables 时代实现 fullcone 需要四层同时正确，缺任何一层都不是"编译失败"，而是**静默
不生效**或**规则集加载失败**：

| 层 | 作用 | 载体 |
| --- | --- | --- |
| ① 内核模块 | 注册 `fullcone` 表达式 | `local-packages/nft-fullcone/`（`nft_fullcone.ko`） |
| ② libnftnl | 常量 `NFTNL_EXPR_FULLCONE_*` + 序列化 | `libnftnl-patches/` |
| ③ nftables | `fullcone` 关键字、语法、netlink 编解码 | `nftables-patches/` |
| ④ firewall4 | 真正把 `masquerade` 换成 `fullcone` | `firewall4-patches/` |

**静态证据一开始全部"通过"**：三份补丁 `patch --dry-run` 干净、`nftables` 编译通过、
`parser_bison.c`（bison 生成物）里确实有 `fullcone` 规则、`config` 校验 37 个符号全绿。
看起来可以出货了。

**运行时验证推翻了其中的两项，并顺带发现了另外三处。** 五处缺陷里**只有一处会导致
编译失败**，其余四处都会安静地做出一个"看起来装好了、实际不工作"的固件：

1. **libnftnl 补丁的新文件块缺 `@@` 头**（`--- /dev/null` 后直接就是内容）。
   `patch` 会**只检查两个已有文件、完全跳过新文件**，并以 `exit 0` 报告成功 —— 所以
   `src/expr/fullcone.c` 从未被创建，而 `--dry-run` 说"通过"。
   *修*：补上 `@@ -0,0 +1,167 @@`。

2. **新文件没有接进构建系统**。*修*：给 `src/Makefile.am` / `src/Makefile.in` 的
   `libnftnl_la_SOURCES` 加项，并给 `am_libnftnl_la_OBJECTS` 加 `expr/fullcone.lo`
   （automake 的对象列表不派生自 SOURCES，缺它就不会编译），再补 dirstamp 依赖行。

3. **`.set` 回调是旧签名**。`fullcone.c` 写的是 5 参数
   `(e, type, data, data_len, byteorder)`，libnftnl 1.3.1 是 4 参数。
   *修*：去掉 `byteorder`。

4. **firewall4 的 `parse_defaults()` 是白名单**。它只拷贝 `spec` 里列出的键，
   其它键仅打印 `specifies unknown option 'fullcone'` 就丢弃。所以
   `fw4.default_option("fullcone")` 恒为 `null`，两个模板**一条规则都不会生成**。
   *修*：在 `fw4.uc` 的 `parse_defaults` 里加 `fullcone: [ "bool", "0" ]`。

5. **`{% else: %}` 是语法错误**。ucode 模板的 `else` **不带冒号**（同目录
   `zone-verdict.uc` / `redirect.uc` 都是 `{% else -%}`）。这一处是唯一会炸的：
   模板编译失败 → `fw4` 起不来 → **整个防火墙不加载**（连带 NAT）。
   *修*：改成 `{% else %}`。

**验证手段与边界**（都无需 root，也无需真机）：

* **①**：`make package/nft-fullcone/compile` → `nft_fullcone.ko`（229 KB），
  `modinfo` 显示 `alias: nft-expr-fullcone`。
* **②**：交叉编译一个探针，**静态**链接目标 `libnftnl.a`，在 `qemu-aarch64-static`
  下跑真实 aarch64 代码：

  ```
  OK    nftnl_expr_alloc("fullcone") succeeded
  OK    NFTNL_EXPR_FULLCONE_FLAGS accepted
  OK    bogus expression name rejected      ← 证明查表是真的，不是恒返回
  ```

  这一步是错误的补丁**唯一**会露馅的地方：修复前后 `libnftables.so` 都能链接成功，
  只是链接时留下一个未定义的 `expr_ops_fullcone`。

* **③**：`nftables` 全量重建通过、`nm -D` 无 `fullcone` 未定义引用、
  库中存在 `fullcone` 字节。**没能做到运行时语法探针** —— 见下面的 qemu 限制。
* **④**：用构建出来的**宿主机 ucode**（`staging_dir/hostpkg/bin/ucode`，注意需要
  `-T` 才是模板模式）直接渲染被补丁改过的模板：

  ```
  fullcone=0 → meta nfproto ip masquerade comment "!fw4: Masquerade ip wan traffic"
  fullcone=1 → meta nfproto ip fullcone    comment "!fw4: Fullcone NAT ip wan traffic"
  ```

  并且断言**关闭态与原模板输出逐字节一致** —— 这排除了补丁引入多余/缺失换行、
  破坏既有规则串接的可能（模板的空格控制 `{%-` `-%}` 很容易在这一步出错）。
  `fw4.uc` 另用 `ucode -c` 做语法编译检查。

**qemu-user 的两条硬边界**（踩到就会浪费很多时间，记下来）：

* **开了 `pack-relative-relocs` 的动态链接目标程序跑不起来**。OpenWrt 的
  `TARGET_LDFLAGS` 默认带 `-z pack-relative-relocs`，产物里有 `DT_RELR` 段，
  qemu-user 下 musl 的加载器报
  `Error relocating /lib/libxxx.so: unsupported relocation type 6`。
  **静态链接可以绕过**（`-static` 后 `qemu-aarch64-static` 直接能跑）；
  此前 `strings src/nft | grep fullcone` 得到 0 也是因为看错了文件 ——
  `src/nft` 只是 libtool 包装脚本，解析器在 `libnftables.so` 里，而那时它是**旧产物**。
* **qemu-user 建不出 `NETLINK_NETFILTER` 套接字**（`socket()` 直接 `EPROTONOSUPPORT`）。
  所以 `libnftables` 的完整路径（parse → evaluate → netlink）无法在仿真下走通，
  ③ 只能停在"语法表里确实有、链接无缺失"这一层。

### 为什么"failed to build"能连着三次都没有原因

同样的 `shadowsocks-libev` 连续失败三次，日志里永远只有一行：

```
ERROR: package/luci-app-ssr-plus/shadowsocks-libev failed to build.
```

根因不是构建本身，而是**三个诊断通路同时断掉**。修的过程比修 bug 本身更值得记：

1. **`build.log` 里没有 make 的输出。** 它只收集脚本自己 `log()` 的行；
   而 `ERROR: ... failed to build.` 是 **make** 打的。诊断步骤 grep 这个文件，
   自然永远找不到 —— 而那一行就明晃晃地印在它上面的控制台里。
   *修*：`compile_firmware` 用 `> >(tee -a "$LOG_FILE") 2>&1` 把 make 输出也接进去。
   用进程替换而不是管道是必须的：`make ... | tee` 会让 `$!` 变成 tee 的 PID，
   `wait` 就会返回 tee 的状态，**失败的构建会被当成成功**。

2. **OpenWrt 本来就有每包日志，但开关被 Kconfig 静默丢掉了。**
   `include/subdir.mk` 会把每个包的完整构建输出 tee 到
   `$(BUILD_LOG_DIR)/<包>/<步骤>.txt`，并把失败目标写进同级的 `error.txt`。
   开关是 `CONFIG_BUILD_LOG`，但它在 `config/Config-devel.in` 里声明为
   `bool "..." if DEVEL` —— 没有 `CONFIG_DEVEL` 时该符号不可见，defconfig 直接丢弃。
   **实测**：种子里写着 `CONFIG_BUILD_LOG=y`，生成的 `.config` 里却只有
   `CONFIG_BUILD_LOG_DIR=""`，没有 `CONFIG_BUILD_LOG`。也就是说这个功能从来没生效过。
   *修*：`scripts/local-build.sh` 直接给 make 传 `BUILD_LOG=1 BUILD_LOG_DIR=...`，
   绕开可见性规则（**不要**用 `CONFIG_DEVEL=y` 去修：它会连带打开整个构建的调试信息）。
   副作用是好的：同一个包的**控制台**输出从 1.9 MB 降到 3.9 KB，而完整的 277 KB
   落进每包日志文件。

3. **诊断步骤在猜包。** 它硬编码 `package/feeds/packages/rust/host/compile` ——
   那是本工程遇到的第一个失败，此后就不是了；于是整个预算都用来反复证明 rust 能编译。
   *修*：先读 `logs/`（`error.txt` 给出失败目标，`<目标>/compile.txt` 给出原因），
   只有拿不到时才重跑，并加了"最后一个被 make 启动的包"作为兜底。

现在的行为：失败当场打印失败包与它的日志尾部；CI 另外把 `logs/` 作为 artifact 上传
（7 天保留）。**再出现失败，原因会直接出现在日志里，而不是再花三小时去猜。**

顺带记两条排查中的教训：

* `make package/X/compile` 在 `CONFIG_PACKAGE_X*` 全都没开时是**静默空转**（0.14 秒，
  exit 0）。我据此一度得出"本地编译通过"，其实什么都没编译 —— 要验证一个包真的能编，
  必须先把它的 config 符号打开，并清掉 `build_dir` 与 `staging_dir/stamp`。
* `nullglob` 只丢弃**匹配不到的模式**，不丢弃**不存在的字面路径**。
  把 `"$DIR"/error.txt` 这种字面量放进数组，即使文件不在也会留在数组里，
  后面的 `read` 就会炸。要么用 `*` 通配，要么显式判存在。

### 结论

| 路径 | 结论 |
| --- | --- |
| Renode 全系统 | 平台能生成，**引导不进用户态**；且关键外设无法仿真 —— 对本项目无实用价值 |
| qemu-user + 真实 uci | **有效**，可验证首启脚本、uci 写入、守卫与幂等性；已抓到一个真实 bug |
| qemu-user + 静态链接的目标库 | **有效**，可直接调用真实 aarch64 代码（本次抓出 libnftnl 三处缺陷） |
| 宿主机 ucode 渲染模板 | **有效**，可逐字节比对模板改动前后的输出（本次抓出 firewall4 两处缺陷） |
| qemu-user + 动态链接 / netlink | **不可用** —— `DT_RELR` 与 `NETLINK_NETFILTER` 都不支持 |
| 真机 | **仍然必需** —— 无线起不起、5G 能否附着、风扇曲线、硬件卸载是否真的生效，只有真机能答 |


---

### 迁移时被调整或去掉的功能

改上游不只是换仓库地址——参考工程里有几块东西是绑在 MTK 私有分支上的，主线没有对应物。
逐条列出来，避免以后有人以为它们“忘了搬”：

| 参考工程功能 | 本工程 | 原因 |
| --- | --- | --- |
| MTWIFI 私有驱动补丁（`mtwifi-apcli-active-only`） | **去掉** | 补的是 MTK 私有 `mtwifi` 驱动。官方 H5000M 用主线 `mt7996e`（mac80211），没有这些代码路径。 |
| MTK HNAT 本地地址补丁（`mtk-hnat-local-dest`） | **去掉** | 同上：官方 `mediatek/filogic` 不带 HNAT offload。 |
| `luci-app-turboacc-mtk`（HNAT/SFE 面板） | **去掉** | 与上面两个补丁配套，开关的是 `/sys/kernel/debug/hnat/`，主线无此驱动。详见 [七.3](#3-无线网络加速--根因明确主线这个-soc-上做不了)。 |
| `luci-app-Airpifanctrl` | → `luci-app-h5000m-fancontrol` | 上游改名并重写（见下文）。 |
| `mwan3` 多 WAN | → `luci-app-h5000m-netmode` | 参考工程本身也已移除 mwan3。 |
| QModem / `luci-app-modem` + ModemManager | → `ddimension/wwand` | 上游换代（见下文）。 |
| **LuCI 主题** | **新增 `luci-theme-argon`** | 参考工程有而本工程初版漏了，刷出来是默认 bootstrap。见 [七.1](#1-主题没有更新--已修复)。 |
| **mt76 TXWI 缺陷** | **新增补丁**（本工程独有） | 上游未修复的 H5000M 无线缺陷，见 [七.2](#2-无线无法开启--已定位到上游未修复的-mt76-缺陷已内置修复)。 |
| `vlmcsd` + `luci-app-vlmcsd` | **去掉** | 已从 OpenWrt 官方 feeds 全部移除（packages / luci / routing / telephony / video 里都没有）。要保留需自行引入第三方 feed。 |
| AdGuardHome 走私有预编译 ipk + 版本降级 hack | **改用官方 feeds** | `adguardhome` 与 `luci-app-adguardhome` 现在都在主线 feeds 里，不再需要下载 ipk、也不再需要 Go 版本兼容补丁。 |
| MosDNS 的 Go 1.24 补丁、`v2dat` 清理、HomeProxy 回退源等 | **去掉** | 这些是针对 ImmortalWrt 24.10 特定版本组合的补丁；主线直接装上游包，`v2ray-geoip` / `v2ray-geosite` / `sing-box` / `kmod-nft-tproxy` 都已由官方 feeds 提供。 |
| Nikki / OpenClash / MosDNS / HomeProxy | 保留为**可选**（默认关），从各自上游仓库克隆 | 它们从来不在官方 feeds 里 |

---

---
