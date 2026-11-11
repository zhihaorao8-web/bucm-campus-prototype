# 轻新课堂内置播放器选型

调研日期：2026-11-11。用户因学校播放器界面杂乱，明确改为应用内置播放器，并授权参考公开项目、要求标明来源。本文是公开源码调研与实施设计，不是学校媒体已在原生播放器播放通过的证明。

## 结论与候选

优先验证 **Android Media3 / ExoPlayer + Flutter自绘控制界面 + 学校专用媒体请求适配**。当前只交付Android；现有课程关联和原生录播列表继续复用。最终依赖版本在接入时结合项目Gradle、SDK、锁文件和实际构建确定，不直接跟随上游main。

| 参考项目 | 已核对能力及许可证 | 本项目使用方式 |
|---|---|---|
| [AndroidX Media3](https://github.com/androidx/media)，[LICENSE](https://github.com/androidx/media/blob/release/LICENSE) | Apache-2.0；官方HLS模块支持MPEG-TS，提供可替换DataSource | 首选播放内核候选；自行实现学校请求边界，控制层采用App现有MIUIX风格 |
| [Flutter video_player](https://github.com/flutter/packages/tree/main/packages/video_player)，[LICENSE](https://github.com/flutter/packages/blob/main/packages/video_player/video_player/LICENSE) | BSD-3-Clause；Android底层使用Media3 | 参考纹理渲染、生命周期与Flutter桥接的结构；不直接照搬网络默认设置 |
| [media_kit](https://github.com/media-kit/media-kit)，[LICENSE](https://github.com/media-kit/media-kit/blob/main/LICENSE) | Dart层MIT；公开API可传HTTP请求头，视频接入另含原生库包 | 备选；需另核对所选原生二进制及传递依赖许可证、包体和网络约束，不能将所有原生依赖都标为MIT |
| [Chewie](https://github.com/fluttercommunity/chewie)，[LICENSE](https://github.com/fluttercommunity/chewie/blob/master/LICENSE) | MIT；基于video_player的控制界面 | 参考控制显隐、播放状态与全屏组织；不引入完整皮肤或投屏等无关功能 |

当前学校专用Java传输与桥接代码为本项目自行实现，已固定引入Media3 ExoPlayer/HLS 1.11.1，保留原始许可证随包；其余项目仅参考设计/API，尚未复制代码或安装依赖。后续若复制/修改代码，须在具体文件说明来源、保留原版权/许可，并将随包依赖的LICENSE/NOTICE纳入应用许可展示及构建产物。

## 为什么需要学校专用网络层

- Media3的[HLS文档](https://developer.android.com/media/media3/exoplayer/hls)与[扩展文档](https://developer.android.com/media/media3/exoplayer/customization)表明可接HLS与自定义数据源；这是能力依据，学校会话兼容仍待实测。
- 查阅时Flutter插件的[HttpVideoAsset.java](https://github.com/flutter/packages/blob/main/packages/video_player/video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/HttpVideoAsset.java)设置了`setAllowCrossProtocolRedirects(true)`，并设置固定请求头；其默认行为不能直接满足本项目逐跳校验与凭据隔离要求。该观察针对上游当前源码，不代表所有历史或未来版本。
- Media3的[DefaultHttpDataSource.java](https://github.com/androidx/media/blob/release/libraries/datasource/src/main/java/androidx/media3/datasource/DefaultHttpDataSource.java)默认禁止跨协议跳转，但这仍不等于自动限制每一跳域名或自动共享WebView登录。
- 所以需要检查清单、子清单、分片、密钥及重定向的每个请求；正常TLS、HTTPS、明确主机/端口和WebVPN资源路径边界。只验证入口URL的现有`classroomMedia`不足以证明整个播放链安全可用。

拟采用Android内部按目标URL读取WebView CookieManager会话、仅在当前请求内使用的方式，与现有课表下载原则一致；不返回Cookie/Token给Dart，不写独立凭据文件，不把固定Cookie请求头附给所有分片。是否还需WebVPN路径改写、Referer与其他学校要求，必须在授权会话验证，不猜测媒体地址、不把校外媒体静默改成直连。若学校必须显式Token，先核实能否在原生边界内完成，不扩大凭据导出范围。

播放描述只按当前获准观看课次临时解析，Dart控制层尽量仅接收不透明播放句柄、可用画面与状态；销毁即清理，不记录含参数地址，错误仅返回分类。媒体层不得启用含URL的诊断日志或磁盘视频缓存。

## 页面与媒体行为

- 保留课表 → 课程二级页 → 原生录播列表；已发布且当前账号可观看的录播才能启动解析。
- 用户已确认主画面＋可切换小窗，默认PPT为主、教师为小窗，学生画面可切换。教师/PPT/学生是独立画面源，不能把HLS自适应码率选择当作三路课堂切换。缺失画面隐藏对应选项，不伪造视频。
- 已接入播放/暂停、拖动进度、倍速、画面切换与横屏全屏控制；同屏时单一音源，统一暂停/跳转/倍速，返回释放解码器。用户后续要求关闭小窗采用独立按钮，已从画面菜单移除关闭项；关闭后提供独立恢复按钮。
- 学校水印按官方配置继续呈现；如含身份信息，仅当前会话显示，不落日志/测试/缓存。自绘播放器不会自动继承官方网页水印。
- 本地断点与学校观看记录分开设计。官方观看时长接口不能因使用新内核而宣称自动兼容，也不能用隐藏官方播放器补报或双重播放。仅基于真实播放状态、经学校协议核实后接入；未验证时明确写未验证。
- 直播入口保持“未开放”，预留复用播放层的能力，不在没有实播样本时请求直播或宣称直播支持通过。

## 实施顺序与验收

1. 画面布局已确认；更新生效需求与设计。公开调研已独立提交同步。
2. 先建立受限媒体描述/请求适配与原生播放桥接，使用合成响应验证清单嵌套、跨域/降级跳转、Cookie按目标隔离、取消、过期及错误脱敏；不在CI连接学校。
3. 接入一条获准HLS，在本人完成官方登录后验证直连与WebVPN各自可达性、实际解码与音频。桌面网页成功不能替代原生媒体成功。
4. 按确认布局接入控制界面、多路同步、水印及必要记录适配；分项检查、提交、推送。退出/后台暂停、全屏与返回、缺失画面及缓冲错误分别验收。
5. 回归课表导入、离线课表、课程关联与账号切换；记录静态检查、合成测试、Android构建和真实学校播放的独立结果。版本仍为0.2/code 8，不自动发布。

当前状态：Flutter播放页已接入原生录播条目，Android授权WebVPN样本已出现PPT主画面、教师小窗并播放推进超过一分钟，切换学生小窗及暂停已实际核对。两台观察到的媒体节点为qxkt2/qxkt4的HTTPS 8880及各自精确WebVPN前缀；保留学校URL中的空路径段，继续拒绝路径穿越/未知目标。样本水印配置关闭，开启水印、人工听音、长时同步、服务器观看记录仍需独立验证，不能用初始播放成功代替。此前分析info已随旧探针移除，最终检查见STATUS。
