# 文档

| 文件 | 内容 |
| --- | --- |
| `proxy-kmod-audit.md` | 代理软件包 kmod 依赖审计的原始记录：逐个仓库的 Makefile 路径、行号、审计时的 commit，以及若干**已经失效的仓库地址**（如 `xiaorouji/openwrt-passwall` 已 404，现为 `Openwrt-Passwall/openwrt-passwall`）。 |

审计结论已进入主 README 的 [七.9](../README.md)；这份原始记录保留下来，是因为
"当初为什么把这个 kmod 放进列表"这类问题，只有逐包的证据能回答，而结论本身会被后来人
当成断言接受。审计基于 GitHub 上的上游 Makefile，**不是**基于本仓库的构建日志；每个包的
审计 commit 都写在文件里，上游变动后请以文件中的方法复核。
