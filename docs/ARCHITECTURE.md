# 架构与公共能力索引

更新：2026-11-28，按当前分支源码核对。需求见[PROJECT_BRIEF](PROJECT_BRIEF.md)，交互见[DESIGN](../DESIGN.md)，验证见[STATUS](STATUS.md)。本页描述已有实现；拟拆分与删除见[工程优化计划](MAINTENANCE_PLAN.md)。

课堂连接/目录协议与排查见[CLASSROOM](CLASSROOM.md)，播放所有权/媒体边界与公开来源见[PLAYER](PLAYER.md)；不要从已删除的旧专项计划重新实现功能。

## 分层与入口

```text
mobile/lib/main.dart → AppShell（今日 / 课表 / 图书馆 / 设置）
  config/         业务参数、存储路径、公开资源与桥接标识
  design/         固定色板、基础/语义/组件视觉令牌
  ui/             页面、组件、手势、路由；部分课堂流程仍在页面内
  application/    Riverpod状态、课堂连接/导入/播放准备协调、本机续播生命周期
  domain/         课程、日历、匹配、分页模型与校验
  data/           本机文件、目录归档、展示时间线、合成示例
  platform/       官方页面访问、受限桥接、播放通道、短时会话、诊断
  mobile/android/ Android宿主、HSSF导入桥、Media3播放组与受限数据源
  src/.../        7个共享Java核心唯一维护源；旧原型仅在历史分支保留
```

页面调用应用状态、模型和平台接口；纯计算不依赖页面。现有目录不是严格依赖隔离：例如外观文件仓库仍与application控制器同文件，课堂页面仍管理WebView导航、认证展示和任务队列切换，不能据目录名宣称所有流程均已拆分。

## 业务链路与数据所有权

| 链路 | 入口与处理 | 提交/失败边界 |
|---|---|---|
| 课表导入 | `ui/import_page.dart` → 官方页面导航/导出 → `SchoolAdapter` → Android `MainActivity` → Java XLS/作息核心。DOM 备用由 `assets/coverage-check.js` 校验已加载的官方筛选文档，再于同一脚本调用 `assets/extract.js` 提取该文档。认证往返保留所选入口和操作 | 当前页面加载到对应学校服务后消费待恢复操作一次。取消、再遇认证、会话清除或超时停止恢复。DOM 选项变化尚未对应到新文档时保留旧课表。`ScheduleController` 先保存再发布状态；整批有效才替换同学期 |
| 校园账号登录 | 设置或课表导入或图书馆 → `openCampusLogin` → `CampusLoginPage` → `CampusLoginContent`（隔离覆盖层下保持官方 WebView 存活）+ `CampusPasswordForm` / `CampusSmsForm`（`ui/campus_login_forms.dart`）；`platform/campus_login_navigation.dart` 管理各入口的 HTTPS 主文档域名、CAS 标签、`upgradeSameHostHttps`（教务 `:80` 跳回有界升级 HTTPS/:443）与同步/异步就绪判定；`platform/campus_native_login.dart`（`CampusNativeLogin`）管理同源顶层 CAS 表单探测/提交、服务票据（`ST-`）校验、分类错误/脱敏手机号解析、串行代次队列及 `cn.bucm.campus/credentials` 通道 → Android `CampusCredentialStore` / `MainActivity`（`credentialGeneration` 防竞态） | 已有有效会话可跳过凭据保存；仅主动勾选「保存账号密码」、完成学校全部验证（含短信二次验证）且确认 `ST-` 回跳和目标就绪后才按未变更代次本机加密保存；短信验证码离开即清，阶段 2 通道不向 Dart 暴露 `read`；未知页面/异常退回官方 WebView；发起方只接收目标可用或取消，自己保留业务上下文 |
| 录播导入 | `classroom_import_page.dart` / `ClassroomCoursePage` → 官方上下文 → `ClassroomImportCoordinator`协调API或DOM收集结果 | `ClassroomArchive`校验所有来源完整分页，协调器按捕获的revision调用`ClassroomLibrary`整组保存；目录可读不代表认证有效 |
| 播放 | 时间线保留来源课程ID、录播ID及原分页 → `ClassroomPlaybackPreparation` → 原生`ClassroomPlayback` / `ClassroomPlayerGroup`。`ClassroomCoursePage` 复用 `openCampusLogin` 处理直连和 WebVPN 门户认证，门户就绪后 `assets/classroom-entry.js` 跟随校方当前教学资源入口。隧道内教学平台自己的 CAS 表单在原官方 WebView 继续，由本人认证；`/cc/` 加载停滞走既有有界恢复。 | 一次点播最多打开一次独立认证页。认证完成后重新读取原来源与分页，播放脚本校验学期、来源、页码、公开状态与唯一录播 ID，原生准备仍执行当次访问检查。取消或切换账号即丢弃请求，准备器负责移交前的原生会话释放。 |
| 退出会话 | `ui/privacy_data_page.dart`（`PrivacyDataPage`）承载「隐私与数据」独立子页；各自确认后分别调用 `SchoolAdapter.clearSession`（经 `CampusNativeLogin.clearWithSession` 递增凭据代次并清除 Android 凭据/Cookies/WebStorage 及录播目录/进度，保留离线课表）、`CampusNativeLogin.clear()`（仅清除本机加密保存账密，保留会话与课表）或 `scheduleProvider.notifier.clear()`（清空本地课程，不影响会话与账密） | 缓存/存储/凭据 revision 与 Android `credentialGeneration` 阻止迟到回调写回；三项清理操作相互独立确认 |
| 图书馆座位预约 | 底部“图书馆”一级页直接进入 `ui/library_seat_query_page.dart`（一级页切入后惰性加载，合成示例模式下隔离）；三级空间选座视图与转场在 `ui/library_floor_overview.dart`（`LibraryFloorListView`、`LibraryFloorSchematicView`、楼层分组、`2F` 专绘与 `3F–5F` 区域方位模型、`LibrarySpatialLevelTransition`、`LibrarySeatViewModeTransition`）；具体区域选座双视图与骨架在 `ui/library_seat_map.dart`，区域/时段轴/预约与取消确认 `QuietSheet` 在 `ui/library_seat_sheets.dart`，“我的预约”焦点票卡与历史分层在 `ui/library_seat_bookings.dart`；`LibrarySeatQueries` 协调查询、预约确认和取消 | L1/L2 仅通过 `/ic-web/seatMenu` 拉取楼层与区域目录，进入 L3 具体区域后才按需拉取座位清单。需要认证时「登录校园账号」先调用 `LibrarySeatReader.tryReuseCampusSession`（无界面受限 WebView 检查是否可复用有效 CAS 会话并在 `/ic-web/seatMenu` 就绪后无弹窗返回，见 `CampusLoginTarget.library`），需要本人认证时进入自动关闭的 `CampusLoginPage`，完成后均由 `showAppNotice` 提示登录成功并仅作只读刷新（0 次自动写重试）；`LibrarySeatPage` 继续作为显式「打开学校预约网页」手动回退。退出会话或离页丢弃迟到响应与个人数据 |
| 外观与语录 | `AppearanceController`、`QuoteService` → 主题及今日展示 | 外观独立存储；在线语录默认关闭，失败回退本地 |

认证由用户在可见官方页面或阶段 2 直连原生表单完成；仅在本人主动勾选并完成全部验证后由 Android Keystore 本机加密保存一组账密（阶段 2 方法通道不向 Dart 暴露 `read`）。下载Cookie仅在原生内存中按验证后的目标使用，不返回Dart。学校导出、主文档、认证和媒体分别校验用途/域名/端口/路径，不能合并为宽泛白名单。真实数据不进入测试或Git。

## 开发前先复用的能力

下表代码路径相对于`mobile/lib/`，测试相对于`mobile/test/`。新增计算先检索此表及源码；页面不重复实现已登记的规则。

| 能力 | 当前业务入口/职责 | 代表测试 |
|---|---|---|
| 北京时间/日历天 | `domain/schedule.dart`：`schoolNow`、`dateOnly`、`calendarAdd`、`calendarDays`、`isoDate`、`schoolTimestamp` | `schedule_test.dart`、`schedule_freshness_test.dart` |
| 周次/课程展开 | 同文件：`parseWeeks`、`Course.weekAt/occursOn`、`occurrencesOn`、`nextOccurrences` | `schedule_test.dart` |
| 学期内找课 | `domain/schedule.dart` 的 `searchCourseOccurrences` 按学期及部分课名查找。`ui/schedule_search_page.dart` 与日视图共用 `scheduleDayCourseRows`，按同日完整课表计算卡片颜色与冲突标记 | `schedule_test.dart`、`schedule_search_test.dart` |
| 导入差异/替换 | 同文件：`scheduleDifference`、`ScheduleData.mergeImport`；`application/schedule_controller.dart`保存后更新状态 | `schedule_difference_test.dart`、`schedule_recovery_test.dart` |
| 完整名称匹配 | `domain/classroom.dart`：`classroomName`、`matchingClassroomCourses`；`classroomStoredName`保留旧持久化键语义 | `classroom_matching_test.dart`、`classroom_name_merge_test.dart` |
| 完整分页/来源组 | `application/classroom_import_collection.dart`收集；`data/classroom_library.dart`的`ClassroomArchive`校验完整性 | `classroom_import_collection_test.dart`、`classroom_library_test.dart` |
| 批量任务进度 | `application/classroom_import_progress.dart`按学期/名称分组、状态及失败重试集合 | `classroom_import_progress_test.dart` |
| 目录收集与提交 | `application/classroom_import_coordinator.dart`复用API读取器/来源集合，捕获revision、完整组提交及固定诊断 | `classroom_coordinator_test.dart`、`classroom_direct_import_test.dart`、`classroom_name_merge_test.dart` |
| 录播展示排序 | `data/classroom_timeline.dart`：`classroomTimeline`、`recordingsOnDate`；展示排序不改原始播放身份 | `classroom_timeline_test.dart` |
| 路径探测/连接预算 | `platform/classroom_access.dart`、`classroom_read_progress.dart`；连接展示用`application/classroom_connection_status.dart` | `classroom_access_test.dart`、`classroom_read_progress_test.dart` |
| 连接代次/读轮询 | `application/classroom_connection_coordinator.dart`拒绝迟到路由结果、取消或替换读轮询；页面仍检查生命周期/标签并显示认证 | `classroom_coordinator_test.dart`、`classroom_connection_test.dart`、`classroom_recovery_page_test.dart` |
| 页面脚本桥接 | `platform/classroom_page_scripts.dart`统一资产加载、命令编码、响应容量与直取超时；不读取凭据、请求头或WebView存储 | `classroom_direct_import_test.dart`、`classroom_name_merge_test.dart`、`classroom_recovery_page_test.dart` |
| 原生播放准备 | `application/classroom_playback_preparation.dart`封装begin/play/prepare与错误文案；未handoff由准备器dispose，移交后由播放器拥有会话 | `classroom_preparation_test.dart`、`classroom_player_test.dart` |
| 页面缓存 | `platform/classroom_session_cache.dart`：独占转移WebView句柄，最多2门/5分钟，clear递增revision | `classroom_session_cache_test.dart` |
| WebView 控制器判等 | `platform/webview_identity.dart`：`sameWebViewController`（比对 `.platform` 底层实例，兼容 Android 回调与创建阶段的不同包装器） | `settings_test.dart` |
| 本机续播 | `data/classroom_playback_progress.dart`校验身份/位置；`application/classroom_playback_progress_session.dart`协调选择、周期保存与清理 | `classroom_playback_progress_test.dart` |
| 相邻错色/冲突布局 | `ui/course_colors.dart`分配色索引；`ui/week_grid.dart`按真实时间分片和层叠 | `course_colors_test.dart`、`week_stack_test.dart` |
| 视觉策略/控件 | `design/app_palette.dart`、`design/app_tokens.dart`；`ui/visual_policy.dart`（`AppVisualPolicy` 降级、`isBackdropAnimationActive`、`BackdropSuspensionScope`、`BackdropSuspensionAnimation`、`BackdropTransitionBuilder`）、`ui/app_controls.dart`维护按钮/分段指示器/`showAppNotice`、`ui/app_icon_controls.dart` `AppArrowPreference`（含 `destructive` 语义红变体）、`ui/schedule_sync_card.dart`（支持 `footer` 槽位合卡） | `quiet_design_test.dart`、`liquid_glass_test.dart`、`course_interaction_test.dart`、`classroom_ui_polish_test.dart`、`appearance_test.dart`、`settings_test.dart` |
| 校园登录导航 | `platform/campus_login_navigation.dart`：`CampusLoginTarget`（含 `library`）、`upgradeSameHostHttps`、`campusCasForm` | `settings_test.dart`、`campus_login_native_test.dart` |
| 原生校园登录表单 | `ui/campus_login_forms.dart`：`CampusPasswordForm`（默认不勾选保存、脱敏控制器、保留账号清密码）、`CampusSmsForm`（6 位验证、`onRequestCode` 可空）、`CampusLoginContent`（WebView 保活与隔离覆盖） | `campus_login_forms_test.dart`、`campus_login_native_test.dart` |
| 原生校园登录与凭据 | `platform/campus_native_login.dart`：`CampusNativeLogin`（CAS 顶层表单同调用校验、分类错误与脱敏手机号探测、`ST-` 回跳校验、代次防竞态串行队列与 `cn.bucm.campus/credentials` 通道）、`CampusCredentials`；Android 宿主 `CampusCredentialStore` 与 `MainActivity.credentialGeneration` | `campus_login_native_test.dart`、`settings_test.dart` |
| 主题/材质/交互 | `app_theme.dart`、`AcrylicSurface`、`CourseSurface/QuietCard/QuietSheet`、`CoursePressable/CourseCardLink`、`navigation_motion.dart` | `quiet_design_test.dart`、`course_interaction_test.dart`、`navigation_motion_test.dart` |

不得重新按设备时区计算教学周、模糊匹配课程，或仅按录播ID丢弃来源。Java导入校验和Dart缓存校验属于不同信任边界，保持各自防护，以合成契约样本约束一致性。

## 文件、资产与生成边界

| 内容 | 维护源/生命周期 |
|---|---|
| 课表 | `schedule-v1.json`，读取schema 1/2、写schema 2；有效备份、损坏副本及清空规则在`FileScheduleRepository` |
| 外观 | `appearance-v1.json`，schema 1；独立于课表和学校会话 |
| 录播目录 | `classroom-library-v1.json`，读取schema 1/2、写schema 2；账号会话退出清除 |
| 本机进度 | `classroom-progress-v1.json`，schema 1；仅身份、位置、时长、更新时间；退出会话清除 |
| 旧单课程关联 | 已停用读写；`ClassroomLibrary.clear`在清除学校会话/目录时删除固定旧文件及pending，不读取或迁移旧关联 |
| 已保存校园账密 | `campus-login-v1.enc` 于 `noBackupFilesDir`，`AndroidKeyStore`（`AES/GCM/NoPadding`）；仅主动勾选并完整验证后保存，`clear()` 与 `clearSession()` 均同步删密钥与密文，密钥失效重建 |
| 短时页面/诊断 | `ClassroomSessionCache`和`TestDiagnostics`只在内存；诊断200条，debug硬门控 |
| 公共网页脚本 | 根`assets/`为维护源，包括recording-api.cjs；prepare复制到Flutter/原生资产 |
| Java共享核心 | `src/cn/bucm/campusprobe/`的`ScheduleParser`、`CourseTimes`、`CourseImportPlan`、`AcademicTerm`、`ExportWorkbook`、`SchoolExport`、`ClassroomMediaTransport`共7个文件 |
| 生成资源 | `scripts/prepare_flutter.py`复制到被忽略的Flutter资产、原生共享源码、libs/许可目录；修改维护源后重新prepare，不编辑副本 |
| 图标/字形 | 图标源与许可在`design/icons/iconmcp/`；`app_icons.g.dart`、`macintosh_hello_glyphs.g.dart`由各自生成工具维护 |

旧Java页面、提醒接收器、根构建器和专用res已移除，历史保留在codex/legacy-java-prototype；当前宿主在mobile/android。根Manifest仅为版本元数据；检查工具的JDK定位函数在scripts/java_tools.py，不依赖旧构建器。

## 公共文件操作

[data/local_files.dart](../mobile/lib/data/local_files.dart)只负责应用私有文件定位、同目录pending暂存/flush/rename及finally清理。writeAtomicText返回false表示提交前canCommit拒绝替换，不得当作已保存；同一目标由调用仓库串行化。保存成功后仓库才发布状态/通知，失败原数据保留；课表备份/损坏副本、目录完整性和账号revision继续在各仓库校验。对应检查为atomic_file_test及各仓库存储测试。

## 业务配置维护入口

以下文件在mobile/lib/config/，只含公开常量/纯策略，无账号、Cookie或媒体地址。

| 入口 | 管理范围/兼容要求 |
|---|---|
| storage_policy.dart | 四类有效JSON文件名/容量、进度条目上限及旧关联清理名；schema及持久化键仍由各模型负责，修改有效文件名须独立迁移设计 |
| classroom_limits.dart | 字段长度、模型/官方API分页边界、来源/记录上限、短时缓存、页面/桥接超时与阶段预算 |
| playback_policy.dart | 毫秒续播阈值/时长容差、保存/轮询/准备间隔；模型与活动会话复用resumablePosition |
| network_policy.dart | 固定官方入口及WebVPN已知路径、无凭据探测、课表导入等待、可选语录请求；入口不替代用途白名单 |
| runtime_config.dart | AppAssets、AppChannels（含 `credentials`）、AppFeatures、AppLinks；资源源文件仍由prepare复制，原生通道保持相同协议 |

配置按职责维护，不能将媒体/认证/课表导出合成宽泛允许列表。Java/JS与Dart处于不同信任边界，协议页大小等仍有独立校验；涉及这些契约变化时需对应多语言合成测试及必要L3验证，不因集中常量跳过防护。业务配置不得导入UI或视觉令牌。

## 尚未完成的结构整理

公共材质底座 `ui/liquid_glass_surface.dart` 读取现有外观与 `AppVisualPolicy`，共享 FragmentProgram、每实例持有并释放 FragmentShader，`ImageFilter.blur` 统一 `TileMode.clamp`。能力不足、加载中或加载失败使用普通模糊，高对比度或关闭材质使用不透明底；在路由转场、`CourseCardHero` 飞行、`ScheduleModeTransition` 及选座胶囊渐显期间通过 `ui/visual_policy.dart` 的 `BackdropTransitionBuilder`、`BackdropSuspensionScope` 与 `BackdropSuspensionAnimation` 暂停 `BackdropFilter` 与着色器采样，各表面（`GlassNavigation`、`AcrylicSurface`、`ClassroomSectionSwitch`、`QuietSliverAppBar`、`QuietSheet`、主/设置 `MiuixTopAppBar`）采用同层兄弟栈避免 `BackdropFilter` 或 `ClipRRect` 嵌套。输入为有界尺寸、前景 child 与可选 edgeDepth/refraction/blurKey，正文在滤镜之后绘制。调用入口为 `GlassNavigation` 选中透镜、`AppSegmentIndicator` 的可选液态分段层，以及 `AcrylicSurface` 的可选微折射变体。分段层由 `ScheduleModeSwitch`、`ClassroomSectionSwitch` 复用；亚克力变体由今日焦点卡、图书馆当前预约焦点票卡和选座胶囊显式开启，非定位前景决定自然高度，定位背景取得有界尺寸。父级继续拥有标签、焦点与回调。验证入口为 `liquid_glass`、`course_interaction`、`navigation_motion`、`schedule_motion`、`classroom_ui_polish`、`today_focus`、`library_seat_queries` 测试及 `integration_test/liquid_glass_{controls,focus,library}_test.dart`。

- `ClassroomCoursePage`仍约2500行，D3已抽出路由选择/代次/读轮询、目录提交、脚本桥接及原生播放准备。页面继续拥有WebView标签、导航回调、可见认证、来源恢复、批量队列切换和UI；不宣称整个页面状态机已迁出。
- D2已由data/local_files.dart共享文件定位和原子替换；各仓库仍拥有队列、业务备份与revision策略，不能在页面另写一套存储。
- C阶段已收拢顶栏雾化、材质降级、通用控件与常用视觉参数；D1已集中续播阈值、分页上限、常用超时和公开路径；原生/JS边界保持独立验证。
- 存储文件名、schema和旧键是兼容契约；移动常量不顺带更名或迁移真实用户数据。
