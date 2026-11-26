# 界面与交互开发规范

更新：2026-11-27。适用当前Flutter Android课表、录播与图书馆座位预约，保留0.3已验收的MIUIX结构、柔光亚克力和B1标题。本文是当前组件规范；需求见[PROJECT_BRIEF](docs/PROJECT_BRIEF.md)，公共计算见[ARCHITECTURE](docs/ARCHITECTURE.md)，验证证据见[STATUS](docs/STATUS.md)，独有模拟器采样见[UI验证](docs/research/UI_VALIDATION.md)。旧UI计划已精简，不覆盖本文。

## 开发顺序与参数来源

新增/修改页面先确定已有组件和状态，再组合布局。页面不自行复制主题、材质降级、顶栏雾化、路由或分段指示器算法。需要新变体时先在公共组件加入具名参数，再在本文记录用途与验收；不要复制整套组件到另一页面。

| 层次 | 代码入口 | 使用规则 |
|---|---|---|
| 固定配色 | [app_palette.dart](mobile/lib/design/app_palette.dart) / [backdrop_styles.dart](mobile/lib/design/backdrop_styles.dart) | 默认强调色、浅深色fallback、课程/环境光色板与多背景主题四页子样式色板（`BackdropTheme` / `BackdropStyleSpec`）。主题和默认外观引用同一强调色值 |
| 基础/语义参数 | [app_tokens.dart](mobile/lib/design/app_tokens.dart) | AppSpace间距、AppLayout安全布局/触控、AppType字阶、AppRadius圆角、AppMotion时长/曲线 |
| 组件参数 | 同文件AppHeader、AppSurface、AppControl | 顶栏、不同密度材质、维护按钮按用途取值，不以相同数值推断相同用途 |
| 主题语义 | [app_theme.dart](mobile/lib/ui/app_theme.dart) | 正文、表面、主操作、异常优先使用Theme.colorScheme/textTheme；MIUIX经MiuixThemeBridge同步 |
| 系统/偏好策略 | [visual_policy.dart](mobile/lib/ui/visual_policy.dart) | AppVisualPolicy统一高对比度、减少动画、透明材质与底栏模糊条件；不在页面重抄组合判断 |

常用间距为4/8/12/16/24/32，保留已有6/10/20及具名18/22组件内边距；主内容左右24、设置子页16，底部32叠加安全区。字阶正文16、辅助14、标题17/22、普通页标题34/30、今日焦点时间38；窄周表9/10与B1展开标题40有独立用途。系统字号继续生效，不为塞入文字关闭缩放。

固定十六进制配色集中于design目录，UI读取语义颜色/色板；系统Monet、用户选择的颜色和算法扩展课程色可动态生成。绘图控制点、媒体视口比例、文字测量和密集周表几何留在对应实现；不得把这些不同用途的值机械合成全局常量。超时、存储路径、分页和账号状态属于D阶段业务配置，不放进视觉令牌。

## 组件选择与复用

下表代码均在mobile/lib/ui，测试入口以文件名指mobile/test；测试命令见[TESTING](docs/TESTING.md)。

| 场景 | 必须复用的入口 | 交互/布局要求 | 代表验收 |
|---|---|---|---|
| 主页面/背景 | AppShell、QuietBackdrop、GlassNavigation | 今日/课表/图书馆/设置四个目的地；`AppShell` 在 `PageView` 后共享单一 `QuietBackdrop`，切页时经 `AppMotion.ambientChange`（900ms）与 `AppMotion.ambientChangeCurve`（约 200ms 短暂停顿后平滑显色，减少动画下即时切换）过渡背景色板与参数；`QuietBackdrop` 支持「柔和弥散（默认）/ 流光丝绸雾 / 极光柔幕 / 晨昏地平线」4 套主题；非当前页隔离触控/焦点/语义/ticker；B1用于今日/课表/图书馆展开标题，折叠标题及设置用系统字体；图书馆切入后惰性加载 | navigation_motion、atmosphere、ui |
| 设置子页 | SettingsScaffold、settingsGroup、AppArrowPreference、AppearancePage | 顶栏遮挡登记到滚动视口，末项可滚出底栏；保留返回和大字换行；`SettingsScaffold` 传入 `tab: 3` 与设置页子样式对齐；`AppearancePage` 提供「背景主题」选择器及关闭柔光停用逻辑，顶部 `ThemePhonePreview` 实时静帧预览所选主题；`PrivacyDataPage` 复用 `AppArrowPreference(destructive: true)` 区分危险本地删除与中性会话清理 | settings、appearance |
| 课程阅读顶栏 | QuietSliverAppBar | 与主/设置顶栏共享AppHeader计算，不覆盖可见内容或系统栏前景 | atmosphere、settings |
| 焦点大卡 | AcrylicSurface、FocusCourseCard、WavyProgressIndicator | 仅局部裁剪模糊；优先显示此刻/下一节、开始/结束及授课分段波浪进度条（前景可见时轻柔流动，减少动画/不可见/后台保持静态，高对比度保留清晰轨道与语义） | today_focus、quiet_design |
| 普通/课程卡 | QuietCard、CourseSurface、CourseRow | 普通列表与dense周表分别选材质，不逐格加BackdropFilter；完整信息有详情入口 | week_grid、week_stack、course_interaction |
| 课程按压/跳转 | CoursePressable、CourseCardLink、CourseDetailsRoute | 接触反馈；移动/取消释放；同一入口防重复打开；每个可见实例独立Hero身份 | course_interaction |
| 课程信息/冲突抽屉 | showQuietSheet、QuietSheet | 长内容滚动，安全区/关闭/系统返回可用；优先显示仅本次生效，不写回学校课表 | settings、week_stack |
| 维护/连接恢复 | AppActionButton、ClassroomConnectionCard、showAppNotice | 主操作tonal、次操作outline，统一圆角/内边距/48dp最小高度；Wrap允许换行；`showAppNotice` 统一悬浮提示并避让悬浮底栏，成功态带语义图标 | classroom_ui_polish、classroom_connection、settings |
| 校园账号登录 | 设置分组、AppArrowPreference、AppActionButton、官方 WebView | 登录页显示发起原因和学校来源。官方直连 CAS 的三个标签可用时显示原生方式选择器，默认账号密码；WebVPN 沿用官方扫码。教务同域 HTTP 跳转仅在宿主安全层 `upgradeSameHostHttps` 改写为 HTTPS；返回取消，网络失败可重试，目标服务可用后自动关闭并通过 `showAppNotice` 明确提示登录成功 | 设置合成测试覆盖 320 窄屏、大字、方式切换、同域 HTTPS 改写、取消和成功提示；Android 单独核对网页输入与回跳 |
| 图书馆认证后查单 | 图书馆查询页、`showAppNotice`、“我的预约” | 普通查询沿用当时页面。预约中断后认证成功，打开请求日期所在周的“我的预约”；取消中断后刷新原预约列表。用户关闭登录时保留中断提示，恢复过程只读。 | `library_seat_queries` 核对查询范围及预约和取消请求次数 |
| 录播认证后恢复 | `CampusLoginPage`、`ClassroomConnectionCard`、录播时间线 | 用户点播遇到认证时保留原课时并说明登录后继续观看。直连按轻新课堂目录就绪返回，WebVPN 沿用校方扫码。返回后重新读取原来源和课时。取消或权限失效时回到课程并显示原因。 | `classroom_name_merge`、`classroom_preparation` 与 `auth-recovery` |
| 图书馆官方认证与回退入口（已实现） | 底部「图书馆」一级页、`LibrarySeatReader.tryReuseCampusSession`、`CampusLoginTarget.library`、`LibrarySeatPage` | 需要认证时点击「登录校园账号」先无弹窗静默复用 CAS 会话并立即拉取座位状态；仍需本人认证时打开自动关闭型 `CampusLoginPage`（`CampusLoginTarget.library` 在 `/ic-web/seatMenu` 就绪后立即返回），成功后通过 `showAppNotice` 明确提醒并只读刷新（0 次自动写重试）。顶栏及异常卡继续保留显式「打开学校预约网页」进入 `LibrarySeatPage` 回退 | 合成测试覆盖静默复用、官方页自动关闭、取消及中断零重发；Android 真机与模拟器核对 |
| 图书馆原生预约界面 | 内嵌一级页与今日/课表共用 `MiuixTopAppBar` 高度（`AppType.artisticHeader`）、B1艺术标题（`MacintoshHelloHeaderOverlay`，折叠后回退系统字体）及 `AppShell` 惰性加载；三级渐进空间选座组件（`ui/library_floor_overview.dart`：`LibraryFloorListView`、`LibraryFloorListSkeleton`、`LibraryFloorMiniPreview`、`LibraryFloorSchematicView`、`LibrarySpatialBreadcrumbBar`、`LibrarySpatialLocatorPill`、`LibrarySpatialLevelTransition`、`LibrarySeatViewModeTransition`）；第三级选座双视图（`LibrarySeatFloorMap`、`LibrarySeatGridRow`、`LibrarySeatPalette`、`LibrarySeatLoadingSkeleton`、`ClassroomSectionSwitch`）、三分组紧凑筛选卡与可点状态图例、选区/时段/确认与取消 `QuietSheet`（`showLibraryAreaSheet`、`showLibraryTimeSlotSheet`、`showLibraryConfirmReservationSheet`、`showLibraryConfirmCancelSheet`）、悬浮选中胶囊与“我的预约”焦点票卡（`AcrylicSurface`、`LibraryBookingFocusTicket`、`LibraryBookingHistoryRow`、`LibraryBookingsControlsCard`） | L1（楼层）仅先拉取 `/ic-web/seatMenu` 分层展示可用楼层与方位缩略图；L2（楼层平面示意图）按二层独立绘出与 3–5 层同东北方位的 `北区`（`libraryNorthZoneRect`）及周边未标明非选座轮廓，3–5 层绘出 `西A`/`西B`/连续 L 形 `西C`（双触控区 `library-zone-westC-east` 与 `library-zone-westC-south`）/`北区`/`南区` 与 `中庭`、`↑ 北` 及北侧未标明非选座轮廓；L3（区域具体座位）进入后按需拉取座位清单并采用等比映射（`schoolCanvasAspect = 1.72` 与 `computeLibraryFloorMapLayout` 保真呈现长条及混合圆桌布局、无挤压方席与统一居中缩放显号、切区复位 `1.0x`），无坐标回落可搜分段网格；顶栏 `LibrarySpatialBreadcrumbBar` 三段与分隔符统一垂直居中对齐；控制区按“空间定位与视图 / 预约日期与时段（统一 `AppRadius.small` 与 `38dp` 高度）/ 席位统计与`仅看空闲`筛选”三组以细分隔线清晰分区；`LibrarySpatialLocatorPill`、`BreadcrumbBar` 与 `PopScope` 支持逐级返回（L3→L2→L1）；`QuietSheet` 承担规则提示与防连点确认，合成示例模式下不发起学校请求 | 按[开发计划](docs/DEVELOPMENT_PLAN.md#图书馆座位预约)分别验收查询、提交、取消及阶段7A–8D |
| 周/日、录播/直播 | ScheduleModeSwitch、ClassroomSectionSwitch、AppSegmentIndicator | 共用滑动指示器；父组件保留自身标签、语义、焦点和尺寸，不复写动画坐标算法 | schedule_motion、classroom_ui_polish |
| 星期切换 | WeekdayTabs | 按文字和系统字号测量，七天可达，至少48高；窄屏横滚，禁止固定宽截断汉字 | weekday_tabs |
| 图标/设置展开 | AppIcon、AppExpansionTile、AppArrowPreference | 离线SVG、语义标签、焦点/禁用反馈；使用统一尾箭头与返回图标 | app_icons、appearance |
| 播放入口/手势 | ClassroomPlayerRoute、ClassroomSeekSurface、ClassroomSmallWindow | 权限和媒体准备先完成再扩张；主画面拖动只预览、松手单次跳转，小窗有独立手势 | classroom_player_route、classroom_slider_preview、classroom_small_window |

AppActionButton的busy/权限决定仍由调用方传onPressed。等待时禁用重试/刷新/重新匹配，保留显式“打开学校页面”恢复入口，不用一个全局busy开关封死所有操作。其他MIUIX按钮/开关沿用库的键盘、焦点和禁用语义；不要为了统一外观重写已验证的手势系统。

## 材质、动效与降级

| 角色 | 当前参数（由代码集中定义） | 降级 |
|---|---|---|
| 顶栏 | 模糊20，滚动前80逻辑像素阅读底.04→.80，负向回弹与超范围钳制 | 关闭玻璃/模糊或系统/应用提高对比度时不透明 |
| 焦点 | 圆角28、模糊10；浅色填充.26–.46，深色.16–.30；今日焦点卡、图书馆当前预约票卡和选座胶囊显式启用 `AcrylicSurface.liquidGlass` 微折射（边缘深8、折射1.5，选座胶囊沿用圆角24），列表自然高度由前景决定，背景填满实际尺寸 | 同上；正文在滤镜之后绘制；普通亚克力消费方默认保持原变体，减少动画保留静态材质；选座胶囊在字号超过1.3倍时信息与按钮上下排列，座位/时段完整换行，时段使用 `onSurface` 保证阅读对比 |
| 普通/dense卡 | 圆角默认24；浅/深普通alpha中心.78/.64，dense .90/.84，边缘±.02 | 同上；dense不加逐格滤镜 |
| 抽屉 | 顶部28、局部模糊12；浅/深.90/.92，遮罩按主题 | 同上；不增加全屏背景模糊 |
| 悬浮底栏 | 最大宽400、侧距24、底部安全留白20；模糊24，图标标签常显；选中透镜圆角32、内模糊3，公共渐变/边框/阴影从 `AppLiquidGlass` 读取，跟随同一分页时钟，并与底栏底糊以兄弟层并列而非嵌套 `BackdropFilter` | 非悬浮/关闭模糊/高对比度用不透明；仅关闭玻璃高光仍可保留普通模糊；透镜卸载并保留普通选中胶囊，高对比度附轮廓线 |
| 导航/分段 | 一级260ms；周日/录播页签220ms；换周/日内容180ms进入/120ms退出；`AppSegmentIndicator` 在周/日、录播/直播及图书馆分段复用透镜，内模糊3、边缘深8、折射2.5，圆角沿用父控件（与 `ClassroomSectionSwitch` 外层模糊同层并列，不嵌套 `BackdropFilter`） | 减少动画即时切换并保留静态材质，旧内容不能继续响应操作；高对比度或关闭玻璃/模糊使用原不透明指示器，装饰边框不挤占48dp触控区；`ScheduleModeTransition` 渐变过程中暂停内部模糊，落定即恢复 |
| 液态玻璃公共底座（阶段 1） | `LiquidGlassSurface`，圆角28、模糊10、边缘深14、折射5逻辑像素，参数集中于 `AppLiquidGlass`；限有界局部背景，前景在滤镜之后绘制，`ImageFilter.blur` 使用 `TileMode.clamp`；经 `BackdropTransitionBuilder` / `BackdropSuspensionScope` / `BackdropSuspensionAnimation` 在路由切换、Hero 飞行与局部透明渐变期间暂停背景模糊与着色器采样，保持浅透底色/边框且不嵌套 `BackdropFilter` / 重复 `ClipRRect` | 复用玻璃/模糊与对比度策略；Impeller 不支持、加载中或加载失败回落普通模糊；减少动画保留静态材质；路由或透明过渡期间暂挂光学读取、落定后恢复。`liquid_glass_test`、`course_interaction_test` 与 Android 同名合成专项验证 |
| 课程/播放路由 | 280ms进入/220ms返回；共享既有导航缓出曲线；`CourseCardHero.flightShuttleBuilder`、`QuietSliverAppBar`、`QuietSheet` 与主/设置 `MiuixTopAppBar` 在路由转场与 Hero 飞行期间暂停 `BackdropFilter` | 减少动画即时，键盘播放不做按钮扩张；保持原生返回；转场期间保留半透明底色与前景不闪白，落定后恢复模糊 |
| 图书馆空间转场 | L1↔L2 楼层景深进退（`AppMotion.routeEnter` 280ms / `AppMotion.routeExit` 220ms，`AppMotion.navigationCurve`）；L2↔L3 以选区 `libraryZoneAnchor` 为缩放枢轴推进/退回（280ms/220ms，退回 L2 时脉冲高亮刚浏览区域并在 L1 标记`刚才查看`）；L3 平面图↔网格共享轴平滑切换（`AppMotion.segment` 220ms，`AppMotion.segmentCurve`）；仅使用 GPU `Transform` + `Opacity` 并隔离旧视图交互、焦点与语义 | 减少动画下全部层级与视图切换即时完成；无坐标轮廓与过渡中旧视图均不可点击或聚焦 |
| 今日柔光/标题 | 今日页10秒环境光（跨周期单调时钟），今日/课表/图书馆自研B1标题1350ms描边；其余阅读页静态光场；3 套可选单 Pass `FragmentProgram` 背景（`backdrop_{grain_gradient,aurora,horizon_gradient}.frag`）内置程序化微粒替代 `_PaperPainter` | 前台+可见才持续运行；减少动画保留静态，高对比度关闭装饰；Shader 加载中或异常回落多色渐变与普通纸纹 |

减少动画与透明材质是不同偏好：减少动画不自动移除静态材质。抽屉在传统焦点模式下即时出现。系统字号/80%–120%整体缩放继续生效；后台/不可见页面不能靠动画维持活动。玻璃是Flutter视觉实现，不宣称系统原生折射。

## 状态与操作约定

| 状态 | 显示/可用操作 |
|---|---|
| 正常/选中 | 同一操作同一名称；选中由指示器、文字和语义共同表达，不单靠颜色 |
| 按下/拖动取消 | 普通卡缩放.98、dense .99；滚动/取消后不激活课程，不叠两次缩放 |
| 禁用/忙碌 | 无激活动作；保留原因/阶段与必要恢复入口；重复点击不重复打开路由或提交 |
| 首次空白 | 明确引导官方导入；合成示例可选且显式标记，不写本人数据 |
| 离线/缓存 | 目录/课表可读，展示实际成功更新时间；缓存存在不表示当前会话有效 |
| 未匹配/暂无/未发布 | 分别说明，不能统称网络错误；无本日回放不播放相邻日期 |
| 需要认证 | 展示官方可见页面，由本人完成；保留目标，不用动画遮盖认证，不保存凭据 |
| 网络/权限/结构错误 | 分类提示，停止无界重试，失败保留旧数据；未知状态不宣称成功 |
| 清空/退出/恢复 | 退出学校会话、清空课表、恢复备份独立确认，说明各自影响范围 |

## 页面与领域特例

- 今日：教学周、此刻/下一节、分段进度、时间轴；真实空档≥10分钟显示休息，重叠课程中不造休息。语录默认24条离线内容，在线一言默认关闭、失败回退。B1用于今日/课表/图书馆展开标题（切页可见时播放1350ms描边），折叠标题及设置用系统字体。
- 课表：默认工作日五列同屏，可选周末七列；日/今日始终能读周末数据。五个教学时段与压缩休息条保留，默认不横滚；矮屏/大字可纵向展开。密集格宽度可能小于48，保留完整语义和日视图大尺寸替代入口，不用扩大列宽破坏布局。
- 学期内找课（Pen 稿待审）：课表顶栏进入，显示当前学期；支持清空输入和返回。结果按实际日期配教学周标题，使用日视图 `CourseRow` 及其详情入口。窄屏和大字下日期与课程名可换行，结果区在系统键盘上方可滚动。未导入状态提供导入入口；无匹配状态可继续修改课名。[阶段进度](docs/DEVELOPMENT_PLAN.md#学期内找课)
- 冲突：按真实时间端点分片层叠，+N展开全部课程；相邻错色是展示分配，不代表课程身份，不写学校数据。详情保留教师、地点、周次/节次、授课分段与来源原文。
- 课堂：同学期完整名称匹配全部同名来源，教师只作标签。日期展示排序不改来源/原分页身份；统一导入任务区分未匹配、失败、取消与认证等待。录播默认、直播明确未开放。
- 播放：默认PPT主画面、教师小窗，按实际来源切换；关闭/恢复小窗独立。横屏控件闲置隐藏，右侧画面抽屉≤半屏；暂停/缓冲/错误/无障碍时保持必要操作。预览取消、后台、时长变化时不提交旧拖动值。小窗避让水印/控件，空间不足时暂不绘制，保留原生画面生命周期。
- 续播：先核对当次权限，再由本人选择继续或从头；仅本机元数据，不代表学校观看记录。具体阈值/保存生命周期由已有业务模块负责，UI不重写。
- 设置/品牌：首页按「校园账号（首行无状态 `登录校园账号` 卡）→ 课表与录播合卡（`ScheduleSyncCard` tonal 主按钮 + 同卡 `导入本学期录播`）→ 外观设置与隐私与数据合卡 → 页尾项目信息」五模块排列；图书馆座位预约统一由悬浮底栏「图书馆」直达，不在设置页重复放置快捷卡。启动图标使用design/branding/app-icon.png，离线开发者头像保留；项目信息显示实际包版本/模式/源码，外链失败可复制地址。

## 图标资源与开发使用

49个功能图标已统一为IconMCP离线outline SVG（24px、1.75描边、radius 2）；按主题/实际尺寸绘制，操作保留触控区与语义。新增图标可用已配置MCP的search_icons/get_icon检索并本地打包，不在运行时依赖MCP或下载图标。来源、摘要与许可见[ICON_SYSTEM](docs/ICON_SYSTEM.md)和[THIRD_PARTY](docs/THIRD_PARTY.md)；启动品牌图与学校网页图标不随功能图标替换。

## Pen（pen.dev）设计媒介与同步规范

本项目前端页面设计与视觉改版以 **pen.dev（Pen）** 为首要媒介，通过 `pencil` MCP 与本地项目设计稿 [bucm-campus.pen](design/bucm-campus.pen) 协作。

| 维度 | 规范要求 |
|---|---|
| 主设计稿与画布结构 | 项目主稿为 [bucm-campus.pen](design/bucm-campus.pen)，包含 `Foundations · 视觉令牌与色板`（Light/Dark 语义变量、色板、字阶、间距与圆角）、顶部公共组件区（`StatusBar`、`GlassNavigation`、`TodayQuoteBanner`、`FocusCourseCard`、`CourseRow`、`SegmentSwitch`、`SettingsRow`、`ScheduleSyncCard`、`LibrarySeatChip`）、`01`–`07` 浅色核心页面、`08`–`10` 深色核心页面及 `11 · 四套背景主题预览`。 |
| 先设计后编码 | 新增前端页面或视觉改版前，先通过 `pencil` MCP 在 Pen 中完成布局、组件复用、浅/深色与态别设计，并在 Pen 桌面客户端呈现给用户审核；审核通过后再按本文与 `mobile/lib/design` 令牌落 Flutter 代码。代码侧有视觉微调时须同步回 `.pen` 稿保持一致。 |
| 加密文件操作边界 | `.pen` 为加密设计格式，仅允许通过 `pencil` MCP 工具（`get_app_state`、`execute`、`save` 等）读写与截图自检，**严禁**使用文件读取或文本检索工具直接读取/解析 `.pen` 内容。 |
| 隐私与样本约束 | 画布与导出内容**仅允许使用合成示例数据**（如 `demo_schedule.dart` 与 `QuoteService.localQuotes`），严禁写入真实课表、学校会话、学号姓名、凭据或设备截图。 |

## Stitch 辅助设计与原型边界

Google Stitch MCP 与 `stitch-skills`（`stitch-design` / `stitch-build` / `stitch-utilities`）面向 Web HTML、React 与 React Native 生态；在当前 Flutter Android 主线中仅作为**可选视觉原型参考与独立周边展示工具**，不替代既有 Flutter 组件体系与验收流程。

| 维度 | 规范要求 |
|---|---|
| 适用场景 | 新增独立页面/模块或较大视觉改版前，可用 `stitch::generate-design`、`enhance-prompt`、`stitch::manage-design-system` 生成多套视觉变体比稿；可用 `stitch::upload-to-stitch` 上传**合成数据**渲染的模拟器截图做局部排版探索；如后续制作独立于主 App 的 Web 下载/宣传展示页或演示视频，可使用 `site-md`、`stitch-loop`、`stitch::react-components`、`shadcn-ui`、`remotion`。 |
| 不适用范围 | 主线 `mobile/lib/ui/` 不使用 `stitch-build`（React / React Native / shadcn-ui / react-vite-dashboard）生成或直译业务页面代码；不对 Flutter/Dart 源码使用 `code-to-design`、`extract-static-html`、`extract-design-md`。校园认证回跳、协议解析、状态机、无障碍、正式签名与原生播放器工程项不由 Stitch 处理。 |
| 文档隔离 | 根目录 `DESIGN.md` 是本项目唯一生效的 Flutter 界面与交互规范，**严禁**用 `design-md` 或 `taste-design` 覆盖或改写。给 Stitch 使用的语义视觉文档须隔离存放在已忽略的本地 `.stitch/DESIGN.md`，由 [app_palette.dart](mobile/lib/design/app_palette.dart)、[app_tokens.dart](mobile/lib/design/app_tokens.dart) 与本文提炼，保持克制的 MIUIX 与柔光亚克力气质，不引入 `taste-design` 中与本规范冲突的非对称排版、强制微动效或禁用系统字体规则。 |
| 落地与复用 | Stitch 产出仅作视觉参考，Flutter 落地仍须严格复用本文登记的公共组件（`AppShell`、`QuietCard`、`AcrylicSurface`、`QuietSheet`、`AppActionButton` 等）、`mobile/lib/design` 令牌、`AppVisualPolicy` 降级与离线 IconMCP 图标，并按「完成与复核」完成浅/深色、`320dp`、`1.5x/2.0x` 大字与降级验收。 |
| 隐私与样本 | 上传至 Stitch 或写入提示词上下文的截图、HTML 与样本**仅允许使用合成示例数据**，严禁包含真实课表、学校会话、学号姓名、认证页面、Cookie/令牌或设备标识。 |

## 完成与复核

1. 检索组件/令牌后再实施；涉及新交互先写状态、取消/恢复和返回行为，影响范围或认证策略有歧义时一次确认一个问题。
2. 运行受影响的模块或明确测试文件；公共主题/布局改动覆盖消费者。控件新增行为在既有测试中补边界，单纯参数搬迁不写数值镜像测试。
3. UI改动核对浅/深色、320窄屏、1.5/2倍字号、减少动画、高对比度/关闭玻璃与模糊；状态变化不得遮住关键动作。按需运行合成预览并实际目检，不能只确认Text节点存在。
4. 静态/合成/模拟器/真实学校与物理手机性能分别记录。检查、更新证据、分项提交推送后再做下一项；阶段末停审。完整课时、7天会话、物理手机性能/读屏仍是独立待验，不能由本规范或截图代替。
