# Changelog

## [1.4.3](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.4.2...v1.4.3) (2026-11-27)


### Bug Fixes

* **build:** 没有 fwtool 元数据的镜像一律不许发版 ([#109](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/109)) ([aa937fd](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/aa937fde5567c49a4f3e95f3da2d789735d5a811))

## [1.4.2](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.4.1...v1.4.2) (2026-11-25)


### Bug Fixes

* **build:** BUILD-INFO 里那句注释不再是 shell 命令 ([#104](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/104)) ([c1e258d](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/c1e258d80c8309670e2f42f8fbab159ea55d40f3))

## [1.4.1](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.4.0...v1.4.1) (2026-11-25)


### Bug Fixes

* **build:** BUILD-INFO 不再把 feeds/base 与 feeds/*.tmp 当成 feed ([#99](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/99)) ([a2299a5](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/a2299a57c943051cd57f0aa241fd7b3721eb5c3d))
* **ci:** ccache 的上限与报告步骤终于指的是同一个数 ([#102](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/102)) ([cae679b](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/cae679bbfa9244dd31f96351f435672b137fe433))
* **release:** 发布那次派发必须自己钉住 revision ([#103](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/103)) ([3c21312](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/3c213127326e7435c5e9a5dddeda6d5689ec2ddf))

## [1.4.0](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.3.0...v1.4.0) (2026-11-25)


### Features

* **build:** BUILD-INFO 记下每个 feed 的 HEAD ([#90](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/90)) ([b426fc4](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/b426fc478117ea865e4669888843440937d2e547))
* **build:** 按解析出的 revision 编译，并让 pin 可覆盖验证 ([#81](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/81)) ([39fd484](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/39fd484a5914ab54ec8e72b91218554db3751b74))


### Bug Fixes

* **accel:** 让 BBR 活过重启，而不是只在当前内核里生效 ([#85](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/85)) ([f8ee399](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/f8ee399564b22a6d74ef8baa9532c27ece5997e6))
* **build:** 运行期枚举的 MT5700M 补一次 network reload ([#80](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/80)) ([28ae754](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/28ae75476d2b62cf2911540bb2d452c424207ff2))
* **ci:** oras 走 HTTP/1.1，规避 9-16 GB blob 的 HTTP/2 断流 ([#75](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/75)) ([f2088d1](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/f2088d1ff709339efb78ca9e5764d2d5ce6de06b))
* **ci:** Pages artifact 名字带上 run_attempt，重跑不再撞重名 ([#87](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/87)) ([88c2188](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/88c2188dce9e415883bdd9e13338330381f2b11c))
* **ci:** Pages 部署读不到 artifact 时再试一次，并留下证据 ([#89](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/89)) ([073dbba](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/073dbba6723356d0dcf4942f326ecc8c6ab7ee55))
* **ci:** Pages 部署重试在 job 级 continue-on-error 下从未触发 ([#93](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/93)) ([4f827d0](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/4f827d04a7290c13cc1d3f2c328f209cd87384c6))
* **ci:** 不再写死默认分支与版本钉，PR 分支不再跑注定失败的部署 ([#97](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/97)) ([b968f9c](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/b968f9cb75a39f6251679e3bf98b84795e1fa6b3))
* **ci:** 修掉门禁里的四处「判断失效但退出码正常」 ([2d173c2](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/2d173c22d56172444ffd25ff4e3c49e3a6e7e108)), closes [#84](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/84)
* **ci:** 权限子集门禁不再把「显式空 permissions」当成「没写」 ([#91](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/91)) ([6856b7a](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/6856b7a040b0b6bef14f9197c35f4d98e43a2aa1))
* **ci:** 解包后删掉 24.8 GB 的 build cache 归档，缓存保存不再因磁盘满失败 ([#72](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/72)) ([545ae71](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/545ae7114d93cbf0f895340ed258d0ff559a77b6))
* **ci:** 让提交信息门禁接受 dependabot 的 deps-dev scope ([#70](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/70)) ([8903d9e](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/8903d9eb10dfe0496497d4f5fe6082bc4a55d0d5))
* **ci:** 部署重试要等得住抖动，诊断步骤要能找到 action.yml ([#94](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/94)) ([694667f](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/694667fa93f6641553a20615cd26ed86d54c44ec))
* **release:** 版本号去掉 -r&lt;revision&gt; 后缀，一个版本一条 release ([#74](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/74)) ([932cdd1](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/932cdd1a4f285965e6f82755bd111427c2883580))

## [1.3.0](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.2.0...v1.3.0) (2026-11-17)


### Features

* **release:** 产物带版本号，滚动线改成正式发布；修缓存恢复与 ccache 键 ([#68](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/68)) ([c724a91](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/c724a910ad7c9ac374ad233ead92bf431a3dadce))


### Bug Fixes

* **build:** 无仓库构建时，不要断言只有仓库才有的包名 ([#66](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/66)) ([7421300](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/7421300e61eeeefd514753965b68d86023dc582b))


### Performance Improvements

* **ci:** 手动派发可只出固件，编译时间约减半，默认行为不变 ([#65](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/65)) ([cde2eec](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/cde2eec6a656a28db882f54031e7bd7c733077d2))
* **ci:** 把三处缓存 Save 移到产出之后，构建缓存才真正闭环 ([#63](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/63)) ([8fdd049](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/8fdd049103b90780e1e244eb60f173ea5f323f5a))

## [1.2.0](https://github.com/existyay/AutoBuild-H5000M-Openwrt/compare/v1.1.11...v1.2.0) (2026-10-30)


### Features

* **ci:** 把 feed 的 ebpf 段喂给钉住的核心，用 --strict-config 验字段 ([#46](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/46)) ([c0b1d64](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/c0b1d64ad16c3f7db5c0df6b4a27c4dd74e51102))
* **ci:** 门禁先重放上游自己的包内补丁，再验本仓库那一层 ([#59](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/59)) ([d9dfb3c](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/d9dfb3c13de0a3ea261b5124ce9f24d9e45cc6f7))


### Bug Fixes

* **build:** clash-rs 核心升到 v0.20.23-alpha，BUILD-INFO 记全代理开关 ([#49](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/49)) ([4211ad8](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/4211ad8f3136f7e1afdcd7e9391822953570c450))
* **patches:** 重做被上游 10-29 版本移动打断的两个补丁 ([#52](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/52)) ([85bb2ac](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/85bb2ac7274398793ef4f24150e56a656e6d050a))
* **release:** 发布收成两条线，正文固定字段并附 SHA256SUMS ([#60](https://github.com/existyay/AutoBuild-H5000M-Openwrt/issues/60)) ([cf471f9](https://github.com/existyay/AutoBuild-H5000M-Openwrt/commit/cf471f90b8fa9a05bd858c0ebe941a9b5c7cd883))

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
