# 架构与公共能力索引

更新：2026-11-15，按0.3主线源码核对。需求见[PROJECT_BRIEF](PROJECT_BRIEF.md)，交互见[DESIGN](../DESIGN.md)，验证见[STATUS](STATUS.md)。本页描述已有实现；拟拆分与删除见[工程优化计划](MAINTENANCE_PLAN.md)。

## 分层与入口

```text
mobile/lib/main.dart → AppShell（今日 / 课表 / 设置）
  design/         固定色板、基础/语义/组件视觉令牌
  ui/             页面、组件、手势、路由；部分课堂流程仍在页面内
  application/    Riverpod状态、导入收集与任务、本机续播生命周期
  domain/         课程、日历、匹配、分页模型与校验
  data/           本机文件、目录归档、展示时间线、合成示例
  platform/       官方页面访问、受限桥接、播放通道、短时会话、诊断
  mobile/android/ Android宿主、HSSF导入桥、Media3播放组与受限数据源
  src/.../        共享Java核心唯一维护源，以及尚未清理的旧原型
```

页面调用应用状态、模型和平台接口；纯计算不依赖页面。现有目录不是严格依赖隔离：例如外观文件仓库仍与application控制器同文件，课堂协调仍在UI中；后续逐项迁移，不能据目录名宣称拆分完成。

## 业务链路与数据所有权

| 链路 | 入口与处理 | 提交/失败边界 |
|---|---|---|
| 课表导入 | `ui/import_page.dart` → 官方页面导航/导出 → `SchoolAdapter` → Android `MainActivity` → Java XLS/作息核心 | `ScheduleController`先保存再发布状态；整批有效才替换同学期，失败保留旧数据 |
| 录播导入 | `classroom_import_page.dart` / `ClassroomCoursePage` → 官方上下文 → `ClassroomApiReader`或DOM路径 → `ClassroomImportCollection` | `ClassroomArchive`校验所有来源完整分页，`ClassroomLibrary`整组保存；目录可读不代表认证有效 |
| 播放 | 时间线保留来源课程ID、录播ID及原分页 → 官方页面当次权限与媒体准备 → `ClassroomPlayback` → `ClassroomPlayerGroup` | 原生层拥有媒体描述、Cookie和解码器；Dart只接收纹理、显示配置和受限播放状态 |
| 退出会话 | `SchoolAdapter.clearSession`清除诊断、页面缓存、目录、续播及原生WebView会话 | 缓存/存储revision和任务generation阻止旧回调写回；离线课表保留 |
| 外观与语录 | `AppearanceController`、`QuoteService` → 主题及今日展示 | 外观独立存储；在线语录默认关闭，失败回退本地 |

认证由用户在可见官方页面完成，App不额外保存凭据。下载Cookie仅在原生内存中按验证后的目标使用，不返回Dart。学校导出、主文档、认证和媒体分别校验用途/域名/端口/路径，不能合并为宽泛白名单。真实数据不进入测试或Git。

## 开发前先复用的能力

下表代码路径相对于`mobile/lib/`，测试相对于`mobile/test/`。新增计算先检索此表及源码；页面不重复实现已登记的规则。

| 能力 | 当前业务入口/职责 | 代表测试 |
|---|---|---|
| 北京时间/日历天 | `domain/schedule.dart`：`schoolNow`、`dateOnly`、`calendarAdd`、`calendarDays`、`isoDate`、`schoolTimestamp` | `schedule_test.dart`、`schedule_freshness_test.dart` |
| 周次/课程展开 | 同文件：`parseWeeks`、`Course.weekAt/occursOn`、`occurrencesOn`、`nextOccurrences` | `schedule_test.dart` |
| 导入差异/替换 | 同文件：`scheduleDifference`、`ScheduleData.mergeImport`；`application/schedule_controller.dart`保存后更新状态 | `schedule_difference_test.dart`、`schedule_recovery_test.dart` |
| 完整名称匹配 | `domain/classroom.dart`：`classroomName`、`matchingClassroomCourses`；`classroomStoredName`保留旧持久化键语义 | `classroom_matching_test.dart`、`classroom_name_merge_test.dart` |
| 完整分页/来源组 | `application/classroom_import_collection.dart`收集；`data/classroom_library.dart`的`ClassroomArchive`校验完整性 | `classroom_import_collection_test.dart`、`classroom_library_test.dart` |
| 批量任务进度 | `application/classroom_import_progress.dart`按学期/名称分组、状态及失败重试集合 | `classroom_import_progress_test.dart` |
| 录播展示排序 | `data/classroom_timeline.dart`：`classroomTimeline`、`recordingsOnDate`；展示排序不改原始播放身份 | `classroom_timeline_test.dart` |
| 路径探测/连接预算 | `platform/classroom_access.dart`、`classroom_read_progress.dart`；连接展示用`application/classroom_connection_status.dart` | `classroom_access_test.dart`、`classroom_read_progress_test.dart` |
| 页面缓存 | `platform/classroom_session_cache.dart`：独占转移WebView句柄，最多2门/5分钟，clear递增revision | `classroom_session_cache_test.dart` |
| 本机续播 | `data/classroom_playback_progress.dart`校验身份/位置；`application/classroom_playback_progress_session.dart`协调选择、周期保存与清理 | `classroom_playback_progress_test.dart` |
| 相邻错色/冲突布局 | `ui/course_colors.dart`分配色索引；`ui/week_grid.dart`按真实时间分片和层叠 | `course_colors_test.dart`、`week_stack_test.dart` |
| 视觉策略/控件 | `design/app_palette.dart`、`design/app_tokens.dart`；`ui/visual_policy.dart`降级、`ui/app_controls.dart`维护按钮/分段指示器 | `quiet_design_test.dart`、`classroom_ui_polish_test.dart`、`appearance_test.dart` |
| 主题/材质/交互 | `app_theme.dart`、`AcrylicSurface`、`CourseSurface/QuietCard/QuietSheet`、`CoursePressable/CourseCardLink`、`navigation_motion.dart` | `quiet_design_test.dart`、`course_interaction_test.dart`、`navigation_motion_test.dart` |

不得重新按设备时区计算教学周、模糊匹配课程，或仅按录播ID丢弃来源。Java导入校验和Dart缓存校验属于不同信任边界，保持各自防护，以合成契约样本约束一致性。

## 文件、资产与生成边界

| 内容 | 维护源/生命周期 |
|---|---|
| 课表 | `schedule-v1.json`，读取schema 1/2、写schema 2；有效备份、损坏副本及清空规则在`FileScheduleRepository` |
| 外观 | `appearance-v1.json`，schema 1；独立于课表和学校会话 |
| 录播目录 | `classroom-library-v1.json`，读取schema 1/2、写schema 2；账号会话退出清除 |
| 本机进度 | `classroom-progress-v1.json`，schema 1；仅身份、位置、时长、更新时间；退出会话清除 |
| 旧单课程关联 | `classroom-links-v1.json`仍有写入、应用无读取调用；列为待清理，尚未删除 |
| 短时页面/诊断 | `ClassroomSessionCache`和`TestDiagnostics`只在内存；诊断200条，debug硬门控 |
| 公共网页脚本 | 根`assets/`及`scripts/research/recording-api.cjs`为维护源，prepare复制；后者虽在research目录，已是运行时资产 |
| Java共享核心 | `src/cn/bucm/campusprobe/`的`ScheduleParser`、`CourseTimes`、`CourseImportPlan`、`AcademicTerm`、`ExportWorkbook`、`SchoolExport`、`ClassroomMediaTransport`共7个文件 |
| 生成资源 | `scripts/prepare_flutter.py`复制到被忽略的Flutter资产、原生共享源码、libs/许可目录；修改维护源后重新prepare，不编辑副本 |
| 图标/字形 | 图标源与许可在`design/icons/iconmcp/`；`app_icons.g.dart`、`macintosh_hello_glyphs.g.dart`由各自生成工具维护 |

旧原型`src/.../MainActivity.java`不同于当前`mobile/android/.../MainActivity.java`。根构建器不是Flutter构建入口，且`check.py`仍导入其JDK工具函数；清理前必须先解除引用。

## 尚未完成的结构整理

- `ClassroomCoursePage`约2607行，仍拥有连接/认证恢复、任务、播放准备与UI；已抽出的模型不等于控制器拆分完成。
- 多个文件仓库分别实现pending文件、flush/rename和清理；公共原子写工具待抽取，业务备份与revision策略不能一并抹平。
- C阶段已收拢顶栏雾化、材质降级、通用控件与常用视觉参数；续播阈值、分页上限等业务参数仍按D阶段收拢。
- 存储文件名、schema和旧键是兼容契约；移动常量不顺带更名或迁移真实用户数据。
