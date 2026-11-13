# Flutter 第一版

用户于2026-11-09确认：迁移到Flutter，优先Android；只做课表与今日速览；认证采用学校官方页面，不保存密码，失效后由本人重新登录。

## 工程与迁移边界

`mobile/`是独立Flutter工程，旧根目录仍保留轻量Java原型及其构建脚本。新包名为`cn.bucm.campus_schedule`，与旧原型并存；不会覆盖旧课表或读取旧应用会话，新应用需要本人重新登录、导入。第一版未提供手工新增课程入口。

```text
mobile/lib/
  application/       Riverpod状态管理，校验后保存再发布状态
  data/              本机JSON原子替换存储、明确标记的合成示例
  domain/            课程、教学周、分段授课与日历展开
  platform/          学校接入接口与HTTPS域名校验
  ui/                今日、周/日课表、详情、导入与设置
mobile/android/      Android宿主与过渡XLS适配器
```

界面、日历计算、模型与存储使用Dart。Riverpod负责状态；`flutter_inappwebview`承载可见的官方页面。无需开发者后端，不实现密码自动登录、后台隐式WebView、提醒或其他模块。附带需求文档中的持久化Cookie文件、密码保险箱、全局明文HTTP配置均不采用。

**当前不宣称纯Dart或95%跨平台完成。** 学校官方格式是二进制XLS，暂通过Android方法通道复用已测试的Java HSSF、排课和时间规则。只传导出地址、课表候选和结构化课程；Cookie由Android下载器在内存中使用，不返回Dart、不写日志或独立Cookie文件。iOS/Windows还需要对应XLS及会话下载适配器；这两个平台尚未生成宿主、构建或验收。Flutter插件内部的原生实现与过渡适配层已明确隔离。

## 配置与构建

Android构建自动从本地Git读取HEAD与工作区状态，写入只读资源供项目信息显示；不需要手工传入SHA。干净工作区对应精确提交，存在未提交/未跟踪文件时显示“含未提交修改”，无Git归档构建显示未知。构建类型由Flutter实际模式确定，版本仍读取安装包。准备验收/发布包时先提交源码再构建；含未提交修改的包不能仅凭其HEAD声称源码完全一致。

已使用Flutter 3.47.9、Dart 3.13.7准备工程；实际依赖见`mobile/pubspec.lock`。Android宿主使用Gradle 9.5.0、AGP 8.11.1、Kotlin 2.3.21、JDK 17+（本机Android Studio JBR 25）；插件运行要求Android 8以上。稳定版WebView插件尚不兼容AGP9，暂固定此兼容组合；Flutter会提示未来升级AGP，目前未绕过版本检查。Gradle分发SHA-256已固定。Maven镜像只用于公开构建依赖，与学校请求无关。

首次需要Flutter SDK、Android SDK与联网获取公开依赖：

```powershell
python scripts/dependencies.py
python scripts/prepare_flutter.py
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d emulator-5554
```

本机SDK位于被忽略的`build/toolchain/flutter`。若Flutter未加入PATH，可在`mobile`中使用`..\build\toolchain\flutter\bin\flutter.bat`。当前网络使用Flutter文档列出的中国镜像：

```powershell
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:PUB_CACHE='C:\studentsAPP\build\pub-cache'
$env:JAVA_HOME='D:\AndroidStudio\jbr'
```

`prepare_flutter.py`只同步公开JS、6个解析Java源文件、SHA-256验证过的HSSF依赖和第三方许可；生成文件不入Git。解析器唯一维护源仍在根`src/`。修改它们后先运行`python scripts/check.py`，再重新prepare。Flutter应用依赖锁文件、宿主和Gradle wrapper应提交，SDK、缓存、JAR、密钥和APK不提交。

应用版本从根`AndroidManifest.xml`读取；prepare同步pubspec，Android构建也直接读取根版本。用户最新指定Android显示版本`0.27`、内部code递增为11；pubspec为满足SemVer规范写作`0.27.0+11`。新增`v0.27`预发布标签，已有`v0.1`、`v0.2`、`v0.25`、`v0.26`及Java历史标签不修改，实际发布状态见STATUS。

0.27正常APK使用`flutter build apk --release --dart-define=CAMPUS_DIRECT_CATALOG=true --dart-define=CAMPUS_TEST_DIAGNOSTICS=false`，debug改为`--debug`及诊断true；两包顺序构建且来源相同。release启用构建优化；构建时重新生成release模式插件注册表，避免此前测试注册表残留。为兼容已安装的同签名预览，仍使用本机既有开发签名。发布包标记为预发布，不将开发密钥提交到Git或Release附件。其他机器的开发密钥不同，不能保证覆盖安装；正式生产发布仍需单独配置签名。

release压缩规则仅保留解析边界、HSSF反射记录和Log4j服务发现；对未使用的桌面绘图、OSGi与编译期注解设置精确的缺类规则，不关闭全部R8检查，也不关闭压缩。读取仅使用原始字符串/数值单元格，不调用桌面绘图和格式化。

R8后的二进制XLS解析用独立测试包验证，避免测试安装/清理影响本人应用数据：

```powershell
cd mobile/android
.\gradlew.bat connectedReleaseAndroidTest -PcampusReleaseParserTest=true
```

该命令仅针对合成工作簿，应用ID为`cn.bucm.campus_schedule.releasetest`；任务在未指定隔离参数时拒绝执行。测试后重新运行普通`flutter build apk --release`得到正式包名的发布附件。测试工作簿由`tests/ReleaseFixture.java`生成，只打包进测试APK。不要并发运行修改插件注册表的Flutter命令和release构建。

## 导入与数据规则

1. 本人在可见学校页面登录，点击自动导入；自动导航选择学期理论课表与全部周次，接收官方XLS。
2. 下载最多4MiB，正常TLS校验，逐跳校验学校HTTPS域名，不保存原始文件。
3. 整批解析、教学周、节次、作息校验和完全重复去重通过后，才替换同学期自动导入数据；保留其他学期。失败不发布新状态。支持同一时段多门课程，不做语义合并。
4. 新学期首次设置第1周周一，之后按课程保存；2026-2027-1沿用用户已确认的2026-09-07。
5. DOM备用路径要求确认学期理论课表中存在已选择的“全部”选项，避免直接用当前周覆盖整学期。这仍是页面控件证据，不是完整学期准确性证明。
6. 白天授课按实际分段展示；全部晚间组合统一18:00–20:25，第12节不延长。周末线上标记来自用户说明；原地点不改写。
7. “无课表课程”只在摘要提示，不猜测时间，不排入日历。
8. 本机私有目录保存结构化课表JSON，临时文件flush后rename替换；损坏文件保留并提示重试。清空课程需确认。会话清除与课表删除为独立操作。

界面随系统切换深色模式。合成示例仅内存展示，始终显示标记；退出示例恢复本人课表。课程详情展示教师原文，缺失时明确提示，不从其他字段猜测教师。

界面已按用户要求更新为`flutter_miuix 1.3.0`，最低Dart版本随组件要求提高至3.12.2。主页面使用MIUIX可折叠大标题、卡片、按钮、标签和分组偏好设置。底栏为Apple风格的自定义悬浮玻璃胶囊；顶栏和底栏都仅对身后内容做有界模糊。列表保留可滚动安全间距，高对比度时改用不透明栏，减少动画时立即切换指示器；设计与参考来源见`DESIGN.md`。

课程与“下一节课”判断固定使用北京时间（UTC+8），不采用设备本地时区；周次日期使用日历天计算，避免设备夏令时影响排课日。

## 验证与隐私

### 原生合成媒体检查

原生播放组已与WebView认证协调分离，正式入口继续校验学校描述并只使用受限`ClassroomDataSource`。设备检查使用独立`cn.bucm.campus_schedule.mediatest`包及测试APK中的合成H264/AAC HLS，通过`AssetDataSource`读取，不访问学校或修改本人应用数据。

在项目根目录执行（FFmpeg路径替换为本机可执行文件）：

```powershell
python scripts/check_native_media.py --ffmpeg 'C:\tools\ffmpeg.exe' --device emulator-5554
```

沿用上方`JAVA_HOME`/`PUB_CACHE`配置及既有Android SDK。脚本只接受唯一在线的指定模拟器，生成素材/SHA清单到忽略的`mobile/build/app/generated/synthetic-media/`，仅执行`:app:connectedDebugAndroidTest -PcampusMediaTest=true`，要求三项新鲜JUnit检查齐全通过，并核对执行期间原生源码未改变。汇总为本地`build/native-media-summary.json`，不提交设备日志或生成的媒体。

测试运行器版本对齐仅作用于隔离目标；正常应用和release解析检查不增加这些debug运行依赖。素材只属于媒体仪器测试源集，不打包进普通应用。检查结束后重新执行普通`flutter build apk --debug`恢复正常包名产物，安装前验证包名与素材排除；发布另按release检查，不用隔离/debug结果替代。

实际覆盖范围与完整课时/听音/水印检查见[播放器验收清单](research/PLAYER_ACCEPTANCE.md)。本机模拟器通过不代表远程CI或真实学校全链路通过。

外观偏好位于独立`appearance-v1.json`（schema 1），以临时文件flush/rename原子保存并串行处理修改；清空课程不删除外观偏好，退出学校会话不删除离线课表。应用主题、Material 3风格/对比度、顶/底栏模糊、悬浮/普通底栏、玻璃高光、主页面横滑与80%–120%整体缩放均读取该状态。系统字号在整体缩放之外继续生效。系统Monet种子通过只读原生通道读取Android 12及以上动态强调色，无动态色时提供手动选择；不读取壁纸图像。子页面的预测性返回动画要求Android 14及以上及系统手势支持，左边缘返回仅作用于新增设置子页，不拦截学校WebView的网页手势。

项目信息版本来自Android实际包信息（最终由根Manifest构建），不从Dart写死版本。`prepare_flutter.py`同步`design/branding/`下的应用图标与GitHub开发者头像到被忽略的Flutter资产目录；头像离线显示，不需要运行时网络请求。开发者显示名Muzhi、账号zhihaorao8-web，外部主页/仓库以固定HTTPS地址交给浏览器，原生通道拒绝未知链接目标，不扩大学校下载域名白名单。预览与测试需等待两张图片实际解码后检查，避免把空占位误认为成功绘制。

`python scripts/check.py`检查旧解析器及新增教师原文、DOM范围控件；`flutter test`检查单双周、分段、冲突布局、同学期替换、重复批次拒绝、本机缓存重读、写入失败状态保留、域名、小屏大字与深浅色。全部用合成数据，不访问学校。

`flutter test integration_test/school_adapter_test.dart -d emulator-5554`在Android上实际验证方法通道，仍只使用合成课程，不打开学校页面。可选预览测试`flutter test test/preview_capture_test.dart --dart-define=CAPTURE_PREVIEW=true`使用本机Windows中文字体和SDK图标字体渲染合成PNG到`dist/flutter-preview/`，默认在普通测试与CI跳过；不会捕获真实学校页面。

插件调试事件日志已关闭，避免导航URL或网页消息进入日志；不启用WebView调试，不记录密码、验证码、Cookie或令牌。学校会话仅由本机WebView管理，保留会话与额外导出会话文件是不同操作。

**旧Java原型的真实学校验证记录不能直接算作Flutter版本通过。** Flutter新应用的官方认证、WebVPN、弹窗导出和全学期逐条准确性必须在本人授权会话中另行验证，不进入CI。最新执行结果见`docs/STATUS.md`。
