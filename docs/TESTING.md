# 分层测试与排查入口

更新：2026-11-16。统一入口为根目录`scripts/check.py`，纯选择规则在`scripts/check_plan.py`。已有业务计算与职责见[架构](ARCHITECTURE.md)，Android专项操作见[FLUTTER](FLUTTER.md)。本页描述已实现的本地检查调度，CI分流已复用同一计划/Runner，分支职责见VERSIONING。

## 日常命令

在仓库根目录执行；首次准备公开依赖/资产与Flutter环境见[DEVELOPMENT](DEVELOPMENT.md)。脚本不自动下载依赖或运行pub get，缺少环境/锁定依赖直接失败。

```powershell
# 无参数运行离线检查，包括图标、合成样本和已登记的 Java/Node 检查
python scripts/check.py
# 明确模块；可重复--module组合，重叠测试去重
python scripts/check.py --module schedule
python scripts/check.py --module player --module storage
python scripts/check.py --module classroom --direct-catalog
# 具名调试链路：不操作学校或设备
python scripts/check.py --flow auth-recovery --dry-run
python scripts/check.py --flow playback-resume
# 基于与main的共同祖先，包含已提交+已暂存+未暂存+未跟踪改动
python scripts/check.py --changed --base origin/main --dry-run
python scripts/check.py --changed --base origin/main
# --all包含全部宿主检查、静态分析、默认Flutter及开启直取的专项
python scripts/check.py --all
# 文档或检查调度自身的快速验证，不需要Flutter/JDK
python scripts/check.py --module docs --module tooling
```

`--module`、`--flow`、`--changed`、`--all`四选一；无选择时是旧离线检查。`--flutter PATH`可指定Flutter可执行文件，否则先PATH，再找仓库build/toolchain/flutter/bin。dry-run只输出选择理由、测试集合、Flutter命令与设备补验提示，不调用SDK、不创建报告。

## 模块与检查范围

| 模块 | 宿主检查 | Flutter合成测试 |
|---|---|---|
| docs | 仓库已跟踪/未忽略新增Markdown的本地链接目标 | 无；不检查外链与页内锚点 |
| schedule | 周次/教师/作息Java、合成示例标记 | 课程模型、差异/新鲜度、今日焦点、周网格/层叠/星期及相邻错色 |
| storage | 无Java/Node | 原子文件、课表恢复、目录（含旧关联清理）、续播存储、外观；覆盖相应仓库读写与失败保护 |
| classroom | 目录DOM、入口导航、目录API和桥接Node | 课程匹配、分页/来源组、进度、连接/恢复、短时缓存、时间线、提示与诊断 |
| player | 独立媒体传输Java、播放准备Node | 播放控制器、路由、横屏、控件显隐、手势/进度条预览、小窗与续播 |
| ui | 图标资产摘要与许可检查 | 主题、导航、设置、外观、材质/按压、课堂列表、艺术标题、语录及图书馆只读查询页 |
| adapter | 课表解析/XLS/作息/教师Java，导出/DOM范围/缩放Node，图书馆只读/单次写入脚本的字段、防重与 fail-closed 边界 | 课程模型、学校URL/认证边界、图书馆主文档校验、时段状态、会话切换与预约确认/结果核对 |
| tooling | 检查调度Python回归、图标、示例标记 | 无 |

模块是当前测试文件的命名集合，不宣称已拆成独立Dart package，也不宣称每个文件内只有一个测试层级。准确集合以check_plan.py输出为准；新增/删除Flutter或Java/Node测试必须更新注册表，否则立即报错，不默默跳过。预览截图显式排除，见下文。

模块命令默认跑其默认配置；目录直取相关模块用`--direct-catalog`加跑现有直取专项。`--all`总是包括该专项，`--changed`选中目录相关消费者时自动加入；不能把默认跳过的直取用例当作通过。

## 可复用调试场景

所有场景复用check_plan和同一个Runner；报告注明flow及实际步骤/退出码，不另建一套测试框架。

| --flow名称 | 调试链路与范围 |
|---|---|
| schedule-import | Java XLS/DOM导航→课程/时间模型→差异/更新时间→存储恢复；不操作Android或真实导出 |
| classroom-import | 元数据/完整名称→全部来源分页→任务/整组保存；含API及DOM桥，自动跑开启直取专项 |
| auth-recovery | 访问探测→认证等待/门户/超时→取消/迟到回调→恢复导入；自动含直取时序，全部为合成页面 |
| playback-resume | 原生准备/移交→路由→续播选择/保存/清理及控制；仅Java传输/JS准备与Dart模拟，不实际解码或访问学校 |
| storage-recovery | 原子暂存/提交/失败→课表备份→目录旧文件清理→进度/外观；仅合成临时文件 |

例如`python scripts/check.py --flow classroom-import`，先加`--dry-run`可看准确集合。场景是显式排查范围，不自动扩展全部消费者；公共接口改动仍先用--changed看影响，发布候选用--all。默认不开启预览、不安装、不创建学校会话、不读取真实数据；L3与手动样本不能由场景通过替代。

## 按变更选择

- base先解析为Git提交，再取merge-base；分支改动、暂存/未暂存及未忽略新增文件取并集。重命名按旧路径删除+新路径新增处理，避免漏测旧消费者。无法解析base或无共同祖先直接失败，不当作无变更。
- Dart按本地import/export/part（含条件URI和测试辅助文件）计算反向传递依赖。只运行受影响的现有测试，源码没有测试消费者或删除路径无法映射时回退全部宿主检查。
- 已知Java/网页脚本映射到对应模块；Java/JS改动额外扩展到Dart接口消费者。学校解析器变更可能影响大部分页面，扩大范围是有意行为。
- 未知文件、共享配置、工具链/依赖锁及原生宿主保守回退全部宿主检查，输出原因；不靠文件名猜测可以跳过。新增/删除测试若未登记则报错要求维护映射。
- Markdown改动只做文档检查；纯文档不触发应用回归。没有改动时输出空计划并成功，但仍执行注册表一致性检查。
- `--module`是开发者明确选择的集合，不自动补齐所有消费者；公共接口或跨模块变更优先用`--changed`查看影响，也可组合模块。

## 分层与触发条件

| 层级 | 场景与最小动作 |
|---|---|
| L0 文档/资产/配置 | 文档链接、图标摘要、测试注册表、静态分析；Flutter分析对涉及Dart的选择运行一次 |
| L1 纯逻辑/存储 | 周次、名称匹配、分页完整性、原子保存/损坏恢复、缓存失效；修改哪个模块运行哪个集合 |
| L2 组件/流程 | 真实拖动/取消、减少动画、大字/小屏、连接失败恢复与迟到结果；使用对应现有widget测试 |
| L3 Android专项 | 方法通道、原生媒体、压缩规则及解析依赖变更，显式执行隔离设备检查；脚本required_manual只提示，不会自动安装 |
| L4 发布/广泛集成 | --all全量宿主回归；另外核验正常包名的双包、R8、签名、版本、精确源码与摘要，详见版本规范 |
| 手动学校/真机 | 官方认证、完整学期/课时、水印、跨天会话与真实性能，单独授权并记录证据，不进入CI |

应用测试只使用合成数据；测试通过不代表学校链路或设备验收。--all也不包含APK构建、安装、仪器测试、学校访问或预览截图。旧无参数命令也不自动增加这些动作。

## 可选合成预览与设备专项

预览：在mobile目录运行`flutter test --no-pub test/preview_capture_test.dart --dart-define=CAPTURE_PREVIEW=true`，需要该测试约定的本机字体，只生成合成图。不会用截图存在代替目检或真机体验。

方法通道：`flutter test integration_test/school_adapter_test.dart -d <指定模拟器>`。R8 XLS使用`connectedReleaseAndroidTest -PcampusReleaseParserTest=true`隔离目标；媒体继续复用`scripts/check_native_media.py`的6项检查。完整参数、设备限制、隔离后重建正常包名规则见FLUTTER，不用通用检查器复制第二套安装流程。

## 输出与失败定位

每次执行在忽略的build/checks/report-<随机ID>.json保存独立报告，含计划、选择理由、已运行步骤、退出码、耗时与补验提示。报告scope固定为synthetic-host-checks；status=passed仅表示选定宿主检查通过，不能据此宣布设备补验通过。dry-run没有报告。

按步骤顺序执行、遇错停止；子进程失败码传回调用方，后续步骤不继续执行，报告保持failed；人工中断返回130。控制台保留原测试输出，报告不收集通用logcat、认证数据或原始异常正文。测试报告与生成文件均不提交。

Windows公共依赖与工程同盘；Flutter命令使用--no-pub，环境准备与检查分开。单次命令只调用一次静态分析，测试集合去重，默认/直取两种配置顺序执行；不要与构建或其他会刷新Flutter插件注册表的命令并发。CI工作分支/PR按变更，main/发布候选全量，双包预览独立受门禁控制；实际远端结果另记精确SHA。
