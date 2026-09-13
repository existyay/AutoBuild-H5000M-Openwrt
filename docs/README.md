# 文档

面向使用者的说明在仓库根目录的 [README](../README.md)。这里放的是工程记录。

| 文件 | 内容 |
| --- | --- |
| `engineering.md` | 上游选型论证、组件集成细节、实机问题的逐条根因分析、参考工程软件包审计、仿真测试的实测结论。原本都在 README 里，因为太长而移出 —— README 是给刷机的人看的，这里是给改代码的人看的。 |
| `proxy-kmod-audit.md` | 代理软件包 kmod 依赖审计的原始记录：逐个仓库的 Makefile 路径、行号、审计时的 commit，以及若干**已经失效的仓库地址**（如 `xiaorouji/openwrt-passwall` 已 404，现为 `Openwrt-Passwall/openwrt-passwall`）。 |

审计结论已进入 [engineering.md](engineering.md) 的「代理软件的 kmod 依赖」一节；这份原始
记录保留下来，是因为"当初为什么把这个 kmod 放进列表"这类问题，只有逐包的证据能回答，
而结论本身会被后来人当成断言接受。审计基于 GitHub 上的上游 Makefile，**不是**基于本仓库
的构建日志；每个包的审计 commit 都写在文件里，上游变动后请以文件中的方法复核。
