# 校园课表 · BUCM

面向北京中医药大学的非官方 Flutter Android 课表与课程录播应用。本人在学校官方页面完成认证，应用在本机导入课表、整理录播目录并播放课程。

**当前版本：0.3 预发布 · Android 8.0 及以上。** 主线工程位于 `mobile/`，默认分支为 `main`。更新内容见 [CHANGELOG](CHANGELOG.md)。

## 下载安装

| 安装包 | 适用场景 | 下载 |
|---|---|---|
| 正常版 release | 日常使用，关闭测试诊断与测试入口 | [0.3 正常版 APK](https://github.com/zhihaorao8-web/bucm-campus-prototype/releases/download/v0.3/campus-schedule-0.3-android-release.apk) |
| 测试版 debug | 问题排查，内置可复制、可清空的白名单诊断 | [0.3 测试版 APK](https://github.com/zhihaorao8-web/bucm-campus-prototype/releases/download/v0.3/campus-schedule-0.3-android-debug.apk) |

[发布说明与 SHA-256 校验文件](https://github.com/zhihaorao8-web/bucm-campus-prototype/releases/tag/v0.3) · [详细版本说明](docs/releases/0.3.md)

两个包来自同一源码，均启用本轮已确认的录播目录直取路径；包名、版本与本机开发签名一致，可以覆盖切换并保留数据。沿用既有 Flutter 预览版升级时无需清数据；与早期 Java 原型的包名不同。当前仍使用开发签名，正式生产签名方案尚未建立。仓库已公开，可通过发布页下载安装包。

## 已有功能

- **课表导入与离线查看**：通过官方页面导出 XLS，整批校验、去除完全重复并保存（兼容课程名全半角括号）；支持今日/下一节授课分段进度、连接时间轴、周视图（全宽层叠冲突 + 底部详情抽屉、可选周末列与周次横滑）、日视图（单层磨砂星期栏）与学期切换。失败保留原课表，提供备份恢复和导入变化摘要。
- **今日语录与艺术标题**：「今日」「课表」大标题采用自研 B1 Macintosh Skeletal Filled 矢量轮廓与 1350ms 逐笔描边入场动效；今日页顶端提供 24 条本地中文语录，并在外观设置中提供默认关闭的“在线一言”可选开关。
- **课程录播与课堂选择页**：统一导入或单课刷新，同学期精确名称匹配全部同名来源，完整分页成功后保存目录；「课程课堂」页采用实时模糊“录播 / 直播”滑动胶囊、合并维护卡与结构化回放来源列表，离线可查看，播放时重新核对学校权限。
- **多画面播放器**：PPT、教师与学生画面按实际来源选择；主小画面交换、小窗拖动/缩放、暂停、倍速、前后10秒和本机续播；点击播放按钮 280ms 圆形扩张过渡。主画面左右滑动与进度条拖动均支持时间预览，松手跳转。
- **沉浸式横屏**：透明进度控件，闲置自动隐藏、轻点恢复；右上角单按钮打开不超过半屏的画面切换侧抽屉。
- **外观与图标**：MIUIX 界面、柔光亚克力浅/深色弥散光场、悬浮玻璃胶囊底栏、Monet 动态配色、字号/缩放/高对比度等偏好；43 个统一的 IconMCP 离线 SVG 功能图标，许可随包提供。

## 使用与数据保护

首次打开学校页面，由本人扫码或输入凭据完成认证，再执行课表导入。课表导出流程保持原有实现；录播可从课程页或设置中的“统一导入录播”进入。自动访问按服务可达性选择学校直连或 WebVPN，保留手动选择，不读取 Wi-Fi 名称。

应用不额外记录密码、验证码、Cookie 或令牌，不通过开发者服务器代理学校凭据；正常校验 TLS、学校域名与媒体路径。本机保存必要课表、录播目录及续播元数据，不下载视频或长期保存媒体 URL。退出学校会话会清理录播上下文与续播，离线课表保留。测试诊断仅含阶段、类别、计数和耗时，不含学校地址、课程或认证内容，不自动上传。

## 验证范围

已有合成测试、Android 构建、模拟器UI验收与早期版本分项实机反馈：官方 XLS 导入保存、自动选择直连后的目录取数、录播画面/声音与续播、滑动进度/横屏侧抽屉、柔光亚克力界面与 B1 艺术标题动效。0.3 的精确检查、构建与发布证据见 [STATUS](docs/STATUS.md) 与 [0.3 发布说明](docs/releases/0.3.md)。

仍待独立验证：完整学期逐项准确性、完整课时与长期会话、开启水印的全部组合、真实认证失效恢复及更多网络/设备。学校 WebVPN 曾返回上游连接拒绝，当前没有恢复成功证据。**本机续播不等于学校观看记录。** 实际直播、学校观看记录上报、图书馆、提醒、社区、视频下载、后台播放及 iOS/Windows 交付均未开放。

## 开发与构建

工程结构：

```text
mobile/                      Flutter Android 主应用与合成测试
src/cn/bucm/campusprobe/      7 个共享 Java XLS/作息/媒体核心
assets/                      受控公开网页脚本与许可
scripts/                     准备、检查与构建工具
design/                      品牌与离线 SVG 素材
AndroidManifest.xml          唯一版本来源
docs/                       生效需求、进度、验证与发布记录
```

Flutter SDK 固定为 `3.47.9` / `c197ca5199e9ee5661e865596c9c07294dfab51c`。根目录**不是 Gradle 工程**；Android 主工程在 `mobile/android/`。旧 Java 页面和原型构建器已移除，Flutter 仍复用根目录的共享核心，不应删除这些源码；根 Manifest 仅保存版本。

```powershell
python scripts/dependencies.py
python scripts/prepare_flutter.py
cd mobile
flutter pub get --enforce-lockfile
cd ..
python scripts/check.py --changed --base origin/main --dry-run
# 按计划选择受影响模块，例如课堂目录
python scripts/check.py --module classroom --direct-catalog
```

发布候选运行`--all`并补专项验证；构建在mobile目录使用`flutter build apk --release --dart-define=CAMPUS_DIRECT_CATALOG=true --dart-define=CAMPUS_TEST_DIAGNOSTICS=false`，测试包改用`--debug`及诊断true。本地依赖源应与锁文件/缓存匹配，Windows pub 缓存与工程放同盘；CI 使用官方源并保留锁定版本和摘要。两个模式顺序构建，避免插件注册表冲突。GitHub Actions 按分支分层检查，仅在 main/发布候选或显式请求时生成两种临时签名预览包，最终升级附件另以可信本机签名构建并验签，见 [Flutter 开发说明](docs/FLUTTER.md) 与 [双包规范](docs/BUILD_VARIANTS.md)。

## 分支与文档

- `main`：当前 Flutter Android 主线，已随 `0.3` 合入 `codex/quiet-ui-refresh` 并接续完整开发历史。
- [`codex/legacy-java-prototype`](https://github.com/zhihaorao8-web/bucm-campus-prototype/tree/codex/legacy-java-prototype)：早期 Java 测试原型，固定保留原主线 `611ec8e`；旧版本标签与附件继续保留。
- 日常开发继续使用独立分支；阶段进展与验证边界见 [当前开发进度](docs/DEVELOPMENT_PLAN.md) 与 [STATUS](docs/STATUS.md)。

[开发入口](docs/DEVELOPMENT.md) · [分层测试](docs/TESTING.md) · [架构与复用索引](docs/ARCHITECTURE.md) · [课堂协议与恢复](docs/CLASSROOM.md) · [播放器与来源](docs/PLAYER.md) · [工程优化计划](docs/MAINTENANCE_PLAN.md) · [生效需求](docs/PROJECT_BRIEF.md) · [开发计划](docs/DEVELOPMENT_PLAN.md) · [验证证据](docs/STATUS.md) · [界面设计](DESIGN.md) · [版本规范](docs/VERSIONING.md) · [第三方许可](docs/THIRD_PARTY.md) · [图标来源](docs/ICON_SYSTEM.md)

本项目为非官方研究与个人使用预发布，不代表学校开放了第三方 API 或正式单点登录接入。仓库与 CI 只允许合成样本，真实课程、截图、HAR、学校会话、设备标识及签名密钥不提交。
