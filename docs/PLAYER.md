# 播放器实现与来源

更新：2026-11-16。当前采用Android Media3 ExoPlayer/HLS 1.11.1、Flutter控件及自行实现的学校数据源。需求见[PROJECT_BRIEF](PROJECT_BRIEF.md)，组件规范见[DESIGN](../DESIGN.md)，验证和手动听音入口见[播放器验收](research/PLAYER_ACCEPTANCE.md)。

## 职责与边界

- 课程页恢复学校课程ID＋录播ID的原来源，核对当次权限；ClassroomPlaybackPreparation统一begin/play/prepare与移交前清理，移交后由播放器拥有会话。不能用离线目录或旧进度跳过准备。
- Android的ClassroomPlayback持有媒体描述/会话，ClassroomPlayerGroup协调Media3播放组；Dart仅接收纹理、可用画面及受限控制状态。Cookie按每个已验证目标在原生内存使用，不回传Dart或固定转发全部节点。
- ClassroomDataSource与共享ClassroomMediaTransport逐资源/逐跳校验TLS、主机、端口、路径、Range及响应类型。直连qxkt1–4仅接受已核实HTTPS:8880；WebVPN仅接受已观察的2/3/4精确映射，1的映射未观察，保持拒绝。保留学校路径中的合法空段，拒绝穿越及未知目标。
- 直连不额外依赖网页跨域预请求；WebVPN通过学校包装取得实际隧道地址，不猜映射或静默转直连。学校水印按官方配置呈现，媒体地址仅本次内存使用，无磁盘视频缓存。
- 同屏一路音轨，统一暂停/跳转/倍速；共同总时长不随可见流变化。播放意图、实际播放及系统焦点抑制分别处理；后台暂停，返回释放。本机续播与学校观看记录分开，未实施观看记录上报。

## 已实现交互

默认PPT主画面、教师小窗，学生画面按实际可用集合切换。小窗独立关闭/恢复、单指拖动、双指缩放、轻点交换，位置/尺寸仅本次保留并避开水印与控制区。

主画面横竖屏均可左右滑动：以开始位置预览目标，整宽最多120秒且不超过短视频总长，松手只提交一次统一seek，保持播放/暂停；取消、多指、后台、时长变化或错误不提交。进度条拖动同步在画面中央显示目标/总时长和“松手跳转”。

横屏底部透明基础控件，右上一个画面入口，抽屉最多占可用区域一半且宽不超过360。播放闲置3秒隐藏，暂停/缓冲/错误/操作/无障碍及抽屉期间常显；返回先退出全屏，再退出播放，沿用同一原生会话。方向请求不保证所有Android大屏实际旋转。

续播按学期＋学校课程＋录播身份隔离，先选继续/从头；阈值与保存间隔在PlaybackPolicy，持久化与清理复用进度仓库/会话。退出学校会话清理并拒绝迟到读写，不能将旧账号进度归给新账号。

## 来源与许可

| 来源 | 使用情况 |
|---|---|
| [AndroidX Media3](https://github.com/androidx/media)、[HLS](https://developer.android.com/media/media3/exoplayer/hls) | 实际播放依赖Apache-2.0；原LICENSE随包，见[THIRD_PARTY](THIRD_PARTY.md) |
| [Flutter video_player](https://github.com/flutter/packages/tree/main/packages/video_player) | BSD-3-Clause；仅参考纹理/桥接/生命周期，未安装或复制；不沿用其宽泛网络默认配置 |
| [media-kit控制实现](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit_video/lib/media_kit_video_controls/src/controls/material.dart) | MIT控制层；仅参考预览后单次seek与显隐。未安装media_kit，不把其全部原生依赖统称MIT |
| [Chewie方向与恢复](https://github.com/fluttercommunity/chewie/blob/060f54714fa95cb4f941c96ab9d83df0536f639a/lib/src/chewie_player.dart) | MIT；仅参考全屏/恢复组织，未安装或复制 |

学校桥接、传输、同步与手势代码自行实现。将来复制上游代码须在对应文件保留来源/版权及许可，不由“参考”一词代替许可证处理。
