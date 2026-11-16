# 播放器检查与完整课时验收

更新：2026-11-16。当前实现/来源见[PLAYER](../PLAYER.md)，测试分层见[TESTING](../TESTING.md)。历史构建/样本只在[STATUS](../STATUS.md)记录；实现、合成解码、真实短时播放、人工听音和完整课时不互相替代。本页是复用检查入口，不自动授权设备或学校操作。

## 可重复的本机合成检查

1. `python scripts/check.py --module player`检查播放器/续播交互及Java/JS边界；跨目录或存储改动按TESTING组合模块，避免日常全量。
2. 涉及课堂脚本/来源恢复再组合`--module classroom --direct-catalog`；只改播放器控件不必运行课表XLS集合，全部使用合成数据。
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

## 本机基础音频对照（显式手动）

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

## 真实学校人工验收

仅在本人授权、当次权限有效且媒体可达时执行。先记录精确源码/修改标记、模式、版本/code、APK摘要、系统/WebView类别、直连或WebVPN、流组合、时长和水印开关；设备只记类别，不记录标识。真实课程、截图、水印身份、地址和会话不进入仓库。

| 项目 | 已有样本/仍需验证 |
|---|---|
| 当次权限/开播 | Android直连与早期WebVPN均有短样本，不能推广所有来源 |
| 5分钟/完整课时 | 2026-11-13本人对约5分钟任务反馈正常，时长未独立计量；10/20/30分钟与结课听音/漂移仍待测 |
| 跳转/倍速 | 旧模拟器暂停±10秒精确变化10000ms；其余边界、不同倍速听感/恢复仍需真实样本 |
| 手势/全屏 | 4e2ba42包本人确认竖屏滑动、横屏显隐/抽屉/返回；横屏滑动未单独口述，不能用它证明后来滑块中央时间预览实机通过 |
| 小窗 | 合成拖动/捏合/关闭恢复/水印避让通过；真实视频全部手势与组合未覆盖 |
| 续播 | 9185851d包重开选择与合理恢复获本人反馈；跨来源/账号隔离的真实清理仍待验证 |
| 水印/中断 | 开启水印全组合、锁屏/来电/蓝牙焦点及长期同步未完成 |
| 另一设备/网络 | 独立认证→目录→当次媒体及操作须分别记录；学校WebVPN上游拒绝仍有未解决样本 |

旧模拟器PCM/真实媒体听音异常保留失败；全新隔离模拟器PCM/AAC人工通过仅证明该环境合成输出，不能回填旧设备“已修复”。声音太小、未启动或只写入PCM都不算听感通过。学校不可达不等于凭据失效，不反复清会话或要求重登掩盖网络故障。

本机续播不等于学校观看记录；观看记录协议和实现需另行确认，不隐藏官方播放器补报。完整课时、真实性能与学校验证不进入CI。
