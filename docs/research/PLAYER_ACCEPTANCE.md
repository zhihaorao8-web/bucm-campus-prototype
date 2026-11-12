# 播放器检查与完整课时验收

更新：2026-11-12。实现、Flutter合成检查、原生合成解码、真实学校短时播放、完整课时听音/同步及发布包分别记录，不互相替代。当前结果以[STATUS](../STATUS.md)为准；此表不补造实际观察。

## 可重复的本机合成检查

1. `flutter test`检查Flutter交互、复合录播身份、续播持久化/清理与生命周期命令。
2. `python scripts/check.py`检查学校脚本与Java媒体路径、TLS/跳转、错误脱敏等纯逻辑，不使用真实会话。
3. `scripts/check_native_media.py`用本机FFmpeg从`lavfi testsrc2`与低音量440Hz正弦波生成约60秒H264 baseline/AAC HLS。仅相对TS资产，按文件生成SHA-256清单；设备端再次核对。视频、音频和清单均在忽略的构建目录，不取自学校或第三方视频。

```powershell
$env:PUB_CACHE='C:\studentsAPP\build\pub-cache'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:JAVA_HOME='D:\AndroidStudio\jbr'
python scripts/check_native_media.py --ffmpeg 'C:\tools\ffmpeg.exe' --device emulator-5554
```

FFmpeg路径替换为本机文件。去掉`--device`只生成素材。运行时必须仅连接指定模拟器；脚本拒绝物理设备，不自动启动/清除设备。Android目标包名固定为`cn.bucm.campus_schedule.mediatest`，测试源码/资产与release解析测试分开；直接运行Gradle时也必须指定`-PcampusMediaTest=true`并仅选择`:app:connectedDebugAndroidTest`，不运行插件自身的测试。正常应用、学校会话和本人课表不作为测试目标。

原生检查直接使用正式应用的播放组、Media3解码器及Flutter纹理生产者。正式入口仍逐个验证学校描述并使用`ClassroomDataSource`；隔离检查仅传入`AssetDataSource`，不会请求学校、搭建代理、伪造官方认证或放宽HTTP/TLS/域名边界。未增加Flutter可调用的测试播放入口。

| 原生检查 | 可观察证据 | 不代表 |
|---|---|---|
| 双流实际解码/播放 | 两路`onRenderedFirstFrame`、READY及播放位置推进 | 学校HLS可达、肉眼画质或长时同步 |
| 暂停、统一跳转和倍速 | 各路位置误差界限、0/末尾夹紧、实际Media3速度参数 | 已完成人工听音、倍速听感和完整课时漂移观察 |
| 单路音频配置 | 只有主时钟一路音量非零 | 已验证真实设备扬声器/耳机听感或来电焦点切换 |
| 临时音频焦点 | 请求系统临时焦点，实际抑制期间双流暂停/状态准确，归还后恢复，主动暂停后不自动恢复 | 真实来电、蓝牙或听感已验收 |
| 关闭/恢复/画面交换 | 原生流集合、保留位置、复用流、移除播放器IDLE及最终集合清空 | Flutter触控已在真实学校视频上验收 |
| 不同时长的双流 | 48秒PPT与60秒教师合成流，关闭/切换/恢复及重开后保持初始共同总时长 | 完整真实课时或未知时长来源已经验收 |
| 资源错误 | 缺失本地资产错误码、暂停且不继续播放 | 学校认证/证书/网络错误已逐一真实复现 |

测试完成后运行正常`flutter build apk --debug`，重新得到正常包名并检查测试HLS未进入应用包；要发布时另外按[发布规范](../VERSIONING.md)重新验证实际release包。不得用隔离包、debug或旧CI结果替代发布提交检查。运行中日志在本机构建输出保存，退出码不经管道掩盖；设备JUnit报告在`mobile/build/app/outputs/androidTest-results/connected/debug/`，不会据此自动宣称远程CI通过。

## 真实学校完整课时检查

### 本机基础音频对照（显式手动）

隔离源集`AudioListeningProbe`默认跳过，只有显式传入`campusListen=true`才执行。目标包必须为`.mediatest`；直接生成48kHz单声道PCM，440Hz低音量音调每秒响0.7秒/静0.3秒，共30秒，边缘渐变。绕过学校、网络及Media3；写入成功只证明AudioTrack接收，听感需要本人单独确认。

先以`-PcampusMediaTest=true`构建并安装隔离debug及androidTest两个APK，然后仅运行：

```text
adb shell am instrument -w -e class cn.bucm.campus_schedule.AudioListeningProbe -e campusListen true cn.bucm.campus_schedule.mediatest.test/androidx.test.runner.AndroidJUnitRunner
```

基础PCM清楚后，可显式运行正式播放组的双流合成HLS/AAC听音对照（同样只在`.mediatest`内，不请求学校）：

```text
adb shell am instrument -w -e class cn.bucm.campus_schedule.MediaListeningProbe#continuousAacThroughProductionGroup -e campusListen true cn.bucm.campus_schedule.mediatest.test/androidx.test.runner.AndroidJUnitRunner
```

此项复用合成资产摘要校验/纹理及资源清理；首帧/实际单路音频格式就绪后推进30秒，检查实际播放状态与至少28秒进度。素材为连续低音量音调，区别于PCM的每秒停顿；音量太小导致无法判断时不能记人工通过，可仅调整测试设备媒体音量后重放。默认六项检查只选择`MediaPlaybackTest`，不会自动执行手动听音子类。

若合成音也异常，继续核对模拟器/宿主输出；若合成音清楚，再对照合成AAC与真实媒体。不能仅凭其中一项把原因定为学校素材或播放器。检查结束仍需重建正常debug，保持本人应用数据，不把隔离包当交付包。

2026-11-12人工结果：模拟器PCM异常，Windows原生SoundPlayer播放同参数WAV清楚稳定。DirectSound仅部分改善，延迟配置及关闭AVD麦克风均未解决；默认配置已恢复。麦克风对照依据Android官方[蓝牙音质排查](https://developer.android.com/studio/run/emulator-troubleshooting#bluetooth-audio)，本机结果未证实它是本次根因。测试未真正播放或启动崩溃不计入听感样本；详见STATUS。

仅在本人授权会话、当前课程当次权限有效且媒体可达时执行。未登录、学校不可达或缺少开启水印的样本时记为阻塞/未测，不重复要求认证来掩盖网络故障。真实课程名、截图、水印身份、HAR、地址和凭据只留本机，不进入仓库。

先记录：精确源码SHA、构建类型、实际版本/code、APK SHA-256、系统/WebView版本、直连或WebVPN、是否有前台访问、录播为单流/双流、时长及水印开启/关闭。设备只记类别，仓库不记录设备标识；样本用本机代号关联，不写真实课程/教师。

| 检查点 | 操作和需记录结果 | 当前待采样 |
|---|---|---|
| 当次权限 | 从原课程/日期进入，实际取得媒体；不能只看离线目录 | 2026-11-12既有Android模拟器、WebVPN、双流样本实际取得媒体；不代表其他来源 |
| 开始5分钟 | 人工听音；确认PPT/教师画面和实际声音，仅一路音频 | 待测 |
| 10/20/30分钟及结课 | 实际持续时间、声画/双画面对齐、卡顿/漂移类别；按录播全长完成 | 待测 |
| ±10秒与进度拖动 | 前后跳转、0/末尾、暂停拖动后统一位置及音画恢复 | 2026-11-12单教师画面暂停时±10秒精确变化10000ms并保持暂停；其余待测 |
| 倍速 | 0.75/1/1.25/1.5/2倍，听感和画面恢复后再观察 | 待测 |
| 小窗 | 拖动/捏合不误交换，关闭恢复、教师/学生切换、旋转和控制栏显隐 | 待测 |
| 水印开启 | 实际官方配置显示、缩放/拖动后不遮挡；未取得开启样本不能算通过 | 待测 |
| 中断/返回 | 后台、锁屏、音频焦点中断后暂停，不出现背景播放；返回停止并恢复系统方向/UI | 待测 |
| 本机续播 | 正常退出/重开实际同一来源录播，先权限核对后选择继续/从头；源/学期不串用 | 2026-11-12时长修复中间包真实原来源重开显示14:53并恢复播放；跨来源/清理及最终包完整真实复测仍待测，详见STATUS |
| 清理/重登 | 退出会话后清理目录及进度，离线课表保留；旧进度不能归给新会话 | 待测 |
| 另一设备 | 独立认证→目录→当次媒体→上述操作，结果单列 | 待测 |

2026-11-12短时检查基线源码`92ea6f49b86e4a6a8177999ce4bb8df333eb0d92`、正常debug、0.25/code9，安装包SHA-256为`1277176b6358af5e38008053d1ce4f9ea55aa2f1817ae8641309239ac8f0a659`。同一样本全屏暂停保持控制栏、播放空闲后隐藏、轻点恢复及返回先退出全屏已观察；方向切换会暂停，不算持续播放或完整课时通过。样本官方水印开关关闭，视频本身文字不算应用开启水印验收。

用户通过UU远程收听并反馈无声/异常，音频验收未通过。只读诊断确认Android媒体音量5/15、教师AAC双声道48kHz、播放器及音频输出音量1、PCM持续写出；Windows模拟器会话与主音量100且未静音，输出为虚拟音频设备。尚未独立确定媒体内容、模拟器宿主或远程传声中的原因，不将解码/写出等同于实际可听。

该基线在关闭较短PPT后总时长从5986494ms变为5998219ms，重开未出现续播选择；已定位为可见流决定时长与2秒续播校验冲突。修复及复测见STATUS，旧基线不标记续播通过。

最终结论只写实际覆盖的设备/构建/样本和观察时长。学校观看记录不在本机续播验收内；未经协议核实和另行确认，不实现上报或隐藏官方播放器补报。

焦点处理参考Android官方[音频焦点](https://developer.android.com/media/optimize/audio-focus)及Media3 [Player状态](https://developer.android.com/reference/androidx/media3/common/Player)：播放意图与实际播放/系统抑制分别判断。人工听音暂缓时继续保留异常结论，不将此项状态修复作为底噪修复。
