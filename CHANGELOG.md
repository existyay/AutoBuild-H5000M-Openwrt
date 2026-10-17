# Changelog

## [1.1.11](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.10...v1.1.11) (2026-10-17)


### Bug Fixes

* **fullcone:** libnftnl 1.3.2 的 ops.set 多了 byteorder，补丁打完编不过 ([#43](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/43)) ([fbf6be7](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/fbf6be7fae6eeb418d09eed70b01a02b054f0c46))

## [1.1.10](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.9...v1.1.10) (2026-10-16)


### Bug Fixes

* **ci:** 自动批准那一步先看分支还在不在，别空等 200 秒挡住构建派发 ([#39](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/39)) ([f917aca](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/f917aca1d3158b463e986282613abc8ae6f9d464))
* **fullcone:** 上游删掉 nftables 的 patches/ 后，三层补丁曾一个都没装 ([#41](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/41)) ([1d13ac8](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/1d13ac8929c046c9a71fb41ead41fd8983e0cfb1))

## [1.1.9](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.8...v1.1.9) (2026-10-16)


### Bug Fixes

* **ci:** 自动批准发布 PR 上待批准的检查运行 ([#37](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/37)) ([5d6efbe](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/5d6efbea0d04cc14ce2c3fb442013032bd10d246))
* **fullcone:** 按 nftables 1.1.7 / libnftnl 1.3.2 重新生成补丁，并把上游漂移做成门禁 ([#33](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/33)) ([829426e](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/829426e2bde3ce6cd1a251091a73e7d7ad74140b))

## [1.1.8](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.7...v1.1.8) (2026-09-28)


### Bug Fixes

* **accel:** eBPF 模式下补齐路由器自身 IPv6 的绕过，并修掉清单重复追加 ([#29](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/29)) ([4921683](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/49216839ca78be44543c8eddc4f6a752a110a59b))

## [1.1.7](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.6...v1.1.7) (2026-09-28)


### Bug Fixes

* **ci:** 断言四个 GNU 工具真的装在 adblock-fast 探测的路径上 ([#27](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/27)) ([4b6313a](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/4b6313a9408d05d8ee54a2ac3c95a0971e663f85))

## [1.1.6](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.5...v1.1.6) (2026-09-27)


### Bug Fixes

* **ci:** 弃用门禁改为按值判断，避免报出不成立的结论 ([#24](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/24)) ([398d952](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/398d952fb4fbaa0f6f71235c00cd10b7ce392d85))

## [1.1.5](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.4...v1.1.5) (2026-09-27)


### Bug Fixes

* **ci:** 清除构建日志里 3 条仓库自身产生的 warning，并加门禁防复发 ([#23](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/23)) ([4aad0d0](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/4aad0d0c737aab0bd2eaeb3e4b59c25f11f0c868))
* **ebpf:** 钉住 clash-rs 核心版本，修复 eBPF MAC 白名单被静默丢弃 ([#21](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/21)) ([50cdb3f](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/50cdb3f60c05f6326c8f65fc1124da37dfc41368))

## [1.1.4](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.3...v1.1.4) (2026-09-26)


### Bug Fixes

* **ci:** release-please 派发构建缺 GH_REPO 导致 v1.1.3 无固件产物，并修正 apk 仓库校验的误报 ([#18](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/18)) ([909ef02](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/909ef02ea09f14c87e2b0a145bddb8b73bd06e2f))
* **ci:** 移除 release-please 里被静默忽略的输入，并新增 action 输入门禁 ([#20](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/20)) ([3f2a184](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/3f2a184db80e8a710005110ce1a600027ba91e1c))

## [1.1.3](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.2...v1.1.3) (2026-09-23)


### Bug Fixes

* **ci:** 修复复用工作流里 find -name 用了路径模式，导致设备脚本测试永远失败 ([#16](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/16)) ([9bc97ff](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/9bc97ff20253bf91fad2685b8515ba06bc8b3812))

## [1.1.2](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.1...v1.1.2) (2026-09-23)


### Bug Fixes

* **packages:** 修复 luci-app-nekobox 因 Kconfig 循环依赖被静默丢弃 ([#13](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/13)) ([06a7563](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/06a7563ed512a5530da98a90e8f6f884f14672eb))

## [1.1.1](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.0...v1.1.1) (2026-09-23)


### Bug Fixes

* **ci:** 修复让固件构建自 PR [#1](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/1) 起完全无法启动的缺陷，并加门禁防止复发 ([#10](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/10)) ([fcd640b](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/fcd640b7fd3d7e09051460af6d68c3b3eb515558))

## [1.1.0](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.0.0...v1.1.0) (2026-09-23)


### Features

* **ci:** 失败自动诊断 + CI 状态监控脚本，让红的 run 自己说明原因 ([#6](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/6)) ([ce95b6f](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/ce95b6f1b9ccf8d31628f1ffed5f32482082fd27))


### Bug Fixes

* **ci:** 修复 Release Please 与 commitlint 的冲突（门禁抓到的真实缺陷） ([#9](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/9)) ([ac6b5f6](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/ac6b5f6e10e5cba311bfcca1fd8b8086a562287b))
