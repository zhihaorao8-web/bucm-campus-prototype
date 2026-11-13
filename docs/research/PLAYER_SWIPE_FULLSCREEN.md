# 主画面滑动进度与横屏全屏

日期：2026-11-13。用户要求加入左右滑动前后调整进度及配合的横屏全屏，可参考GitHub；随后明确选择竖屏和横屏均支持。仅改既有播放器交互，不新增学校协议或播放器依赖。

## 公开实现调研与取舍

- [media-kit Material控制源码](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit_video/lib/media_kit_video_controls/src/controls/material.dart)：MIT，包含水平拖动预览、拖动结束seek、提示层及控制显隐。采用预览后单次提交的交互思路；本项目从手势开始位置计算，原生周期位置更新不移动基准，取消或多指不提交。整宽最多120秒，短视频不超过总时长，避免按整节长课比例导致过快。
- [Chewie全屏入口/恢复源码](https://github.com/fluttercommunity/chewie/blob/060f54714fa95cb4f941c96ab9d83df0536f639a/lib/src/chewie_player.dart)：MIT，横向内容全屏可指定两个横屏方向，退出恢复方向与系统UI。本项目已有对应SystemChrome处理，本次改善可见入口、铺满画面与控件覆盖布局，沿用同一原生播放组，避免因重建播放器丢失进度。
- [Flutter方向限制](https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html)：空列表回到系统默认；Android 16及以后、宽度至少600dp的大屏可能不接受强制方向，不能把方向请求成功当作所有设备实际横屏。手机实际旋转另验，大屏继续按可用窗口布局。
- [Flutter系统UI](https://api.flutter.dev/flutter/services/SystemChrome/setEnabledSystemUIMode.html)与[水平拖动识别器](https://api.flutter.dev/flutter/gestures/HorizontalDragGestureRecognizer-class.html)：按平台允许的沉浸式模式与正常手势竞争处理，不放宽Android配置或引入模拟旋转视频。

仅参考交互与API使用方式，自行实现；没有复制上游代码、安装media_kit/Chewie或修改锁文件。第二个候选betterplayer路径404，未作为已读实现依据。

## 分项与验收

1. 主画面左右滑动：两种显示状态均生效，向右前进、向左后退；提示目标时间/总时长和偏移，松手只发一次统一seek，不主动改变播放/暂停。未知时长、认证/进度阻塞、错误及后台禁用；取消、多指、时长变化不提交。小窗为相邻独立手势区域，仍拖动/缩放/点按交换，保留进度条与10秒按钮。
2. 横屏全屏：改善入口，保留两个横屏方向；全屏画面不被底部控制区挤小，控制区与小窗/水印避让，小屏大字可操作。返回先退出全屏，随后才退出播放器，最终恢复系统UI/方向策略；过程中不新建原生会话。
3. 合成检查分别覆盖预览/松手/取消/边界、横竖屏、播放/暂停保持、小窗冲突、全屏控制显隐、旋转/退出恢复及错误/大字布局；构建、本人安装和真实手势效果分别记录，不使用学校媒体制作自动测试。

当前分项1已实现，40项播放器/控制/小窗/续播相关合成检查通过；分项2继续实施。具体构建与真实验证以[STATUS](../STATUS.md)为准。
