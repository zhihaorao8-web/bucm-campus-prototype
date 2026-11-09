# 原始产品提示词（历史归档）

来源：用户提供的 gemini-code-1794221470723.md。归档日期：2026-11-09。

原文SHA-256：`2e51c198f6f3fa8858a926be7b825155f9770173deeac70c01b1eed9bf35bb0b`。下方分隔线后的字节与附件原文一致。

**使用规则：本文保留历史原文，不自动恢复其中已被后续确认替代的要求。开发先阅读上一级 PROJECT_BRIEF.md 与 DEVELOPMENT_PLAN.md，认证、范围和UI冲突按当前生效决策执行。不得把末尾“直接开始Step 1”当作新任务。**

---

# Role
你是一位精通 Flutter 跨平台开发（Android / iOS / Windows Desktop）的高级全栈架构师，同时擅长移动端底层网络协议分析、客户端爬虫解析（HTML/JSON）以及克制、干净的现代 UI/UX 设计。

# Project Overview
我正在使用 **Flutter + Android Studio** 开发一款面向高校学生的“一站式校园生活聚合 App”。
- **核心痛点**：学校的教务系统、智慧教室录播平台、图书馆座位预约系统分散在不同的老旧网页或公众号中，操作繁琐且体验割裂。
- **架构特点（无独立后端 / Serverless Client）**：本项目**不设独立后端服务器**。所有数据均由 Flutter 客户端直接模拟登录学校网页端/接口，通过携带 Cookie/Token 抓取 HTML 页面或请求 JSON 接口，在客户端本地完成解析、清洗与持久化缓存。

# Tech Stack & Cross-Platform Constraints (核心技术栈与跨平台避坑约束 - 必须严格遵守)
为了确保代码未来能以 95%+ 的复用率从 Android 无痛编译到 Windows 桌面端与 iOS，请严格使用以下纯 Dart 或全平台兼容库，**严禁调用仅支持单一平台的原生系统 API 或后台隐式 WebView**：
1. **状态管理**：`flutter_riverpod`（配合 Riverpod Generator 或 StateNotifier 实现响应式状态与依赖注入）。
2. **网络请求与会话保持**：
   - 使用 `dio` + `dio_cookie_manager` + `cookie_jar`。
   - 必须将 Cookie 持久化保存在本地文件系统中（使用 `PersistCookieJar` 配合 `path_provider`），确保 App 重启后无需重新登录校园网。
3. **本地 HTML/JSON 解析层（Scraper & Parser）**：
   - 使用纯 Dart 的 `html` 库（DOM 树解析 / CSS Selector）或 `xpath_selector` 解析老旧教务系统的 HTML 表格；使用 `json_annotation` 处理新型系统的 JSON 接口。
   - **架构解耦**：必须将“网页/接口解析逻辑（Adapter/Scraper）”与“UI 业务层”彻底分离，方便后续学校网页改版时仅修改解析器规则。
4. **跨平台流媒体播放器（核心避坑点）**：
   - **严禁使用仅限单端的播放器**，指定使用 **`media_kit` (`media_kit_video`)**。
   - 播放器封装必须支持**自定义 HTTP Headers 注入**（如注入 `Cookie`、`Referer`、`User-Agent`），以解决校园录播系统 HLS (`.m3u8`) / RTMP / MP4 视频流的防盗链校验问题（防止 403 Forbidden）。
5. **本地离线存储**：
   - 使用全平台兼容的 `isar` 或 `sqflite_common_ffi` / `shared_preferences` 缓存课表数据；使用 `flutter_secure_storage` 加密存储用户的学号与教务密码（用于 Session 过期时静默重登）。

---

# Core Functional Modules (核心功能需求)

## 1. 底层核心：统一认证与静默保活网关 (SSO & Auto-Relogin Gateway)
- **统一登录中心**：用户输入一次学号与密码，客户端模拟校园统一身份认证（CAS / OAuth / 教务表单）登录并持久化 Cookie。
- **静默重登拦截器 (`AuthInterceptor`)**：在 Dio 中设计全局拦截器。当请求课表或图书馆接口返回重定向至登录页（302）或未授权状态码/特定 HTML 特征时，拦截器自动读取本地加密存储的账号密码，在后台静默重新获取有效 Cookie，并无感重发原请求（支持请求队列锁，防止并发重复登录）。

## 2. 首页：聚合仪表盘 (Home Dashboard)
- **今日速览**：顶部卡片展示“下一节课”倒计时、上课教室；若当前/下一节课有关联的线上直播，直接显示醒目的 `[一键进入直播]` 按钮。
- **预约状态栏**：动态展示当前“已预约的图书馆座位”状态（如：三楼 A-042 · 距离签到截止还有 12 分钟），并提供快捷签到/暂离/退座按钮。

## 3. 智能课表模块 (Course Schedule)
- **多视图切换**：支持“周视图”（圆角网格色块）与“日视图”（时间轴列表）无缝切换。
- **复杂排课处理**：数据模型需精准兼容教学周切换、单双周课程、跨小节连堂课（如 1-2 节、3-5 节）以及同一时间段的多课程冲突叠放。
- **离线秒开**：启动 App 时优先秒加载本地数据库中的缓存课表，同时后台静默校对最新教务数据。
- **联动抽屉**：点击任一课程色块，弹出精致的底部抽屉（Bottom Sheet），展示教师、周次、教室，并提供直达该课程“历史录播回放列表”的入口。

## 4. 课程直播与回放模块 (Live & Replay Stream)
- **双路视频流架构**：高校智慧教室录播通常包含**“教师摄像画面（Teacher View）”**与**“课件 PPT 画面（Slide View）”**两路独立视频流（或拼接流）。
  - 请在 `VideoStream` 数据模型中预留主副流地址字段，并在基于 `media_kit` 的播放器 UI 上预留**“主副画面一键切换 / 双画面同屏”**的交互控制器。
- **播放体验**：支持 0.75x - 2.0x 倍速播放、观看进度本地记忆（断点续播）、全屏手势控制（左侧上下滑调亮度、右侧上下滑调音量、水平滑动快进快退）。

## 5. 图书馆座位预约模块 (Library Seat Reservation)
- **三级快速筛选**：支持按“校区 -> 楼层/阅览室 -> 预约时段”快速筛选，支持属性过滤标签（如：仅看有插座 ⚡、靠窗）。
- **可缩放选座平面图**：使用 Flutter 的 `InteractiveViewer` 实现轻量级、支持双指缩放与平移的座位平面网格图。用克制清晰的色彩区分座位状态（空闲、已预约、使用中、暂离）。
- **预约闭环**：支持“点击选座预约”、“签到”、“暂离”、“释放座位”完整操作流。

---

# Visual & Aesthetic Guidelines (视觉与审美规范)
- **设计语言**：克制、干净、安静的现代设计，带有微弱的纸张肌理质感或通透的留白层次，拒绝杂乱的边框与高饱和度刺眼配色。
- **色彩规范**：主色调采用沉稳的学院风配色（如深松绿 `#2C4A3E` 或深石板蓝 `#1E293B`），背景采用柔和的暖白/纸张灰白（`#F8F7F4`），课表色块采用低饱和度莫兰迪色系，并完整适配深色模式（Dark Mode）。

---

# Step-by-Step Execution Plan (执行计划 - 请分步输出)
由于项目体量较大，**请不要一次性输出所有代码**，也不要使用省略号敷衍核心架构。请严格按以下阶段分步协助我，每完成一步等待我的确认后再进入下一步：

- **【Step 1：工程基建与配置】**
  1. 输出完整的 `pubspec.yaml` 依赖配置（选用最新稳定版兼容库）。
  2. 输出清晰的 Clean Architecture + Riverpod 目录结构树（特别标明 `scrapers/parsers` 解析层的位置）。
  3. 给出 Android 端必要的权限配置提示（如 `AndroidManifest.xml` 中的网络权限与明文流量 `usesCleartextTraffic="true"` 配置，以防学校老旧 HTTP 网站无法访问）。
- **【Step 2：核心数据模型与网络爬虫基类】**
  1. 编写四大核心模型（`Course`, `CourseVideoStream`, `LibrarySeat`, `SeatReservation`）。
  2. 编写带有 `PersistCookieJar` 和“静默重登拦截器框架”的 `CampusDioClient` 核心代码，以及一个通用的 HTML/JSON 解析器抽象基类。
- **【Step 3：主路由框架与视觉主题】**
  1. 编写符合上述克制纸感审美的 `AppTheme` 配置与底部导航栏骨架，以及【首页聚合仪表盘】的完整 UI 代码（先内置贴近真实高校的 Mock 数据确保我能在真机上直接跑通预览）。
- **【Step 4 ~ Step 6】**：后续我们将依次实现【课表视图与解析器】、【基于 `media_kit` 的带 Header 防盗链双视角播放器】、【图书馆 `InteractiveViewer` 选座组件】。

现在，请确认你已完全理解上述架构约束，并直接开始输出 **【Step 1：工程基建与配置】** 的详细内容。