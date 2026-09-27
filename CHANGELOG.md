# Changelog

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
