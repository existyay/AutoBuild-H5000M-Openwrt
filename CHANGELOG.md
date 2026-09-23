# Changelog

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
