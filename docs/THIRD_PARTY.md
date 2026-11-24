# 依赖、素材与许可

2026-11-24 液态玻璃 Shader 的圆角距离场及边缘折射衰减参考并改写自 [bilalgursen/liquid-glass](https://github.com/bilalgursen/liquid-glass) 的 `src/components/liquid-glass/engine.ts`，固定参考提交 `c2a6aade68fd655771cb98cce21100bbdbd258f3`。MIT，Copyright (c) 2026 Bilal Abdullah Gürşen。完整许可保存在 `assets/third-party/liquid-glass/LICENSE`，由 prepare 脚本随 Android 原生资产打包。Flutter 实现使用 SDK Shader API。

2026-11-14标题艺术字说明：“今日”与“课表”顶部艺术标题由项目自研矢量路径脚本 `scripts/generate_macintosh_hello_glyphs.py` 生成（`mobile/lib/ui/macintosh_hello_glyphs.g.dart`），灵感源自 Apple `Macintosh Skeletal` 手写风与 `npwitk/Macintosh-Skeletal-Filled` 圆管柔融合构形原理，未引入或分发第三方专有字库文件。

2026-11-13图标：新增IconMCP公开服务提供的离线SVG（首批43个，2026-11-20阶段7A同来源新增6个，共49个），MIT（Copyright (c) 2026 UI8），手形参考源的Phosphor/Tabler MIT及Lucide ISC通知一并保留于`design/icons/iconmcp/`并随包注册许可。新增`flutter_svg 2.4.0`及锁定渲染依赖，包自身许可由Flutter注册；具体来源、参数与实际接入状态见[图标系统](ICON_SYSTEM.md)。

轻新课堂内置播放器的公开参考项目、来源链接、许可证及实际使用状态另见[播放器选型与来源](PLAYER.md)。当前已引入下述Media3依赖并随包保留许可；其余列出的播放器项目仅作设计/API参考，未复制上游代码。

2026-11-11后续播放桥接已固定引入`androidx.media3:media3-exoplayer:1.11.1`及`media3-exoplayer-hls:1.11.1`（Apache-2.0）；[上游该版本LICENSE](https://github.com/androidx/media/blob/1.11.1/LICENSE)原文保存在`assets/third-party/Media3-1.11.1/LICENSE`，准备脚本随包复制至原生资产。播放桥接、学校传输和元数据脚本为本项目自行实现；Flutter video_player、Chewie及media_kit目前仅设计/API参考，未复制其代码或安装其播放器包。

mobile/使用Flutter/Gradle，通过Android适配层复用根Java核心及下表依赖；旧原型构建器已移除。学校实际导出为BIFF/OLE二进制XLS，使用Apache POI HSSF，不包含OOXML模块。POI固定5.5.1，共享核心合成检查保留Java 8目标，Android宿主使用Java 17；不自动升级依赖。Flutter版本/摘要见mobile/pubspec.lock，插件许可由Flutter注册，HSSF原始许可随APK保留。

公开依赖从Maven Central获取，版本和SHA-256锁定在`dependencies.lock.json`，缓存于`build/deps/`，不提交二进制JAR。构建与离线检查每次验证摘要。CI只获取公开依赖和使用合成工作簿，不访问学校。

| 组件 | 版本 | 许可 |
|---|---|---|
| Apache POI | 5.5.1 | Apache-2.0 |
| Apache Commons Codec | 1.20.0 | Apache-2.0 |
| Apache Commons Collections | 4.5.0 | Apache-2.0 |
| Apache Commons Math | 3.6.1 | Apache-2.0 |
| Apache Commons IO | 2.21.0 | Apache-2.0 |
| SparseBitSet | 1.3 | Apache-2.0 |
| Apache Log4j API（不包含Core） | 2.24.3 | Apache-2.0 |

JAR中的原始LICENSE/NOTICE随构建加入APK的`assets/third-party/`。SparseBitSet的JAR没有附许可文件，因此单独保留[上游LICENSE](https://github.com/brettwooldridge/SparseBitSet/blob/master/LICENSE)。

参考：[POI HSSF说明](https://poi.apache.org/components/spreadsheet/)、[POI依赖说明](https://poi.apache.org/components/index.html)、[Maven Central](https://repo.maven.apache.org/maven2/)。
