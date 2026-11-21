# 当前验证概览

更新：2026-11-21。当前任务见[开发进度](DEVELOPMENT_PLAN.md)，业务规则见[PROJECT_BRIEF](PROJECT_BRIEF.md)。下方按日期保留的实施记录只说明当时状态；“待审核/未合入/未发布”等历史用语不覆盖本概览。

| 对象 | 已有证据 | 未完成/限制 |
|---|---|---|
| 校园账号登录（阶段 2） | `6ac24f7` 在校内网模拟器与 5G 真机通过登录前复核。本人使用 `69e6733` 在模拟器登录后复现回跳误拦截。已修复 Android 迟到的原 HTTP 回调，宿主合成回归通过。[回跳修复](#2026-11-21-校园账号登录阶段-2-教务回跳误拦截修复) · [原测试包](#2026-11-21-校园账号登录阶段-2-测试包安装) | 待在设备复验修复后的教务回跳、课表自动恢复及图书馆新增登录路径 |
| 校园账号登录（阶段 1，已审核通过） | 2026-11-21 在 `Pixel_8_API_36` 模拟器（0.4/code13 release 包 `e6256285`）完成官方认证流程验证与公开协议核查：图书馆直连实测账号密码、手机短信与企业微信扫码三种方式均完成本人登录、官方页回跳与原生只读恢复（`0` 写入）；同 CAS 会话免密复用进入教务系统（`jw.bucm.edu.cn`）；WebVPN 扫码登录与直连会话隔离并进入 `WebVPN - 资源站点`；真实「退出学校会话」验证保留离线课表且清除学校会话 | 轻新课堂 `/cc/` 在 SSO 跳过登录后停滞于空白 `#app`；门户根路径 `https://i.bucm.edu.cn/` 明文 301 重定向受阻（`https://i.bucm.edu.cn/tp_nup/` 可直达 200）；物理真机、门户登录回跳及 WebVPN 子业务恢复留待阶段 2/3 |
| 0.4/code13 发布 | 源码 `7a73decf` 全量 `--all` 检查、精确 `main` CI `44750357261` 成功、隔离 R8 XLS `1/1`、双包签名与 release 模拟器抽查通过。`v0.4` 已预发布，四份附件的大小和 SHA-256 已核对。同一 release 包的真实退出学校会话已在上方校园账号登录阶段 1 验证。[0.4 发布说明](releases/0.4.md) | 物理真机性能/功耗与提交/取消、完整 TalkBack、预测返回及完整学期准确性仍待验 |
| 0.3/code12发布 | 729663f本地合成/静态检查、隔离R8 XLS 1/1、同源双包签名/摘要、最终release模拟器抽查及4份远端附件核对 | 精确提交的Actions因当时账户计费限制未运行；用户仅就该次发布授权例外，不作为未来跳过CI规则 |
| 当前UI | 五阶段及B1/语录分项验收；最终0.3课堂页模拟器抽查 | 物理手机性能/功耗、完整读屏与预测返回等仍待验 |
| 学校链路 | 历史分项XLS导入、直连目录、短时播放和续播样本 | 全学期独立准确性、完整课时、水印组合、WebVPN恢复、真实认证失效及7天会话待验 |
| 图书馆座位预约 | Pixel 8 API 36 与真实学校平台通过原生提交、非空查单和原生取消（阶段 1–6 已审核通过）；前端重设计阶段 7A（`4bd9329`）、7B（`9d5d2bd`）与 7C（`b4227e5`）已全部获用户审核通过；三级渐进空间选座及顶栏 B1 统一阶段 8A（`cf0189b`）、8B（`bf2e2e2`）、8C（`6c47522`）与 8D（`ff716b2`）已全部获用户审核通过，通过主机变更检查（`report-fb07fac86c6944828ac2fa41d4fb9608.json`）与 Pixel 8 API 36 真实校园会话深/浅色只读验收（0 POST 写入） | 真实退出会话已在模拟器验证，物理真机提交/取消另行验收 |

## 2026-11-21 校园账号登录阶段 2 教务回跳误拦截修复

- 本人在模拟器使用 `69e6733` 的 debug 包完成学校认证，设置入口仍停在独立登录页并显示导航拦截。隔离诊断包在同一授权会话复现：教务主框架收到同域 HTTP 跳转，应用已发起 HTTPS 替换，随后 Android 仍报告原 HTTP 的页面回调，导致登录页错误终止。诊断仅使用固定回调类别与学校域名分类。
- 登录页识别本次已经发出 HTTPS 替换的原导航，丢弃其迟到的页面和加载错误回调。HTTPS 页面仍由原域名校验、证书检查与服务就绪判定处理。合成回归在旧代码重现误拦截，修复后核对原 HTTP 回调没有执行页面脚本，仅在 HTTPS 服务就绪后返回设置并提示成功。
- `python scripts/check.py --changed --base HEAD` 覆盖 14 个受影响 Flutter 测试文件，静态分析无问题，145 项通过，报告 `build/checks/report-0815b1d5112745bfa8edd86268ff4bdb.json`。修复后的设备实测单独记录。

## 2026-11-21 校园账号登录阶段 2 测试包安装

- 在隔离干净工作树 `69e6733b12064507207d3f37834d6c92716d5910` 执行 `python scripts/prepare_flutter.py`、`flutter pub get --offline --enforce-lockfile` 和 `flutter build apk --debug --no-pub --dart-define=CAMPUS_DIRECT_CATALOG=true --dart-define=CAMPUS_TEST_DIAGNOSTICS=true`。构建退出码为 0，详情见本地 `build/checks/s2-69e6733-build.log`。
- 0.4/code13 debug APK 包名为 `cn.bucm.campus_schedule`，SHA-256 为 `1f13fcc1c55a1ab65147673bfe9bb6bad0ac889f11046908f0889c37e2366641`。复用 APK 核验工具验证签名、包内源码标识、模式、资源、许可及 Flutter 引擎，报告为 `build/checks/s2-69e6733-apk.json`。
- 模拟器与 USB 真机均使用 `adb install -r` 保留数据覆盖安装，设备端 `base.apk` 摘要与本地一致。模拟器通过 `am start -W` 冷启动。本人认证后的教务回跳、课表自动恢复及图书馆会话复用仍待设备验收。

## 2026-11-21 教务回跳与图书馆登录复用

- `5b306a1` 将教务登录后的同域 HTTP 回跳有界改写为 HTTPS。目标服务就绪后自动返回，并用公共提示组件反馈成功。图书馆先尝试复用仍有效的 CAS 会话，需要本人登录时显示官方认证页。确认楼层目录可读后返回并刷新，预约和取消均保持本人确认，认证恢复期间的自动写请求为零。保留手动打开学校预约网页的入口。
- 提交前宿主 `python scripts/check.py --changed` 通过文档检查、Flutter 静态分析、受影响的默认合成测试及直取专项。报告为 `build/checks/report-5e8c8cf2b143496a9ab6934be61dc3c7.json`。`5b306a1` 已核对为远端工作分支提交，后续设备构建另见[测试包安装记录](#2026-11-21-校园账号登录阶段-2-测试包安装)。

## 2026-11-21 校园账号登录阶段 2 设置入口

- 以 `73e11bb` 为基线实现独立登录页、设置入口与门户 HTTPS 路径。公开页面检查确认该路径引导至官方 CAS，账号密码找回链接位于同一官方域名。
- `python scripts/check.py --changed` 通过文档检查、Flutter 静态分析、受影响合成测试及直取专项 23 项，报告 `report-deeb82250a00471bbd1d2e5a149f963e.json`。设置测试覆盖深色、320dp、2 倍字号、直连默认账号密码、方式切换、目标服务仍在加载、WebVPN 回落、取消和网络超时重试。Android 新构建及真实门户登录回跳待阶段 2 联合核对。

## 2026-11-21 校园账号登录阶段 2 课表恢复

- 以 `118e103` 为基线接入课表认证恢复。合成 WebView 核对从教务入口发起自动导入或备用页面读取，取消后保留原数据，复用已有会话时直接返回，并在教务页恢复后各执行一次原操作。重复页面回调未重复恢复，再遇认证时结束本次自动恢复。
- `python scripts/check.py --changed --base 118e103` 通过文档检查、Flutter 静态分析及 135 项受影响合成测试，报告 `report-adb5b098d44e4da3a036feb0ea96bfe3.json`。真实登录和课表导出仍需在本人授权会话下验证。

## 2026-11-21 校园账号登录阶段 2 WebVPN 根路径兼容

- 首轮 Android 模拟器抽查使用源码 `023d931` 的 0.4/code13 debug APK（SHA-256 `a3d1ff973df875dec0d873c1157d330446067787a8c1ff3f7bfbf4a0e22d805e`）。设置能进入独立页、处理加载超时、重试并返回。课表自动导入可打开独立的官方 WebVPN 扫码页，系统返回可取消并回到导入页。
- 在同一模拟器中，WebVPN 从根路径可展示官方扫码页面。兼容修复用官方页标识识别该状态，让备用页面读取也进入独立认证页，并允许本人继续扫码等待。设置的门户直连和课表中的门户、教务直连在这次抽查未加载出登录表单。
- `python scripts/check.py --changed --base 023d931` 通过 Flutter 静态分析和 136 项受影响合成测试，报告 `report-1c11321631d14c488de75f2deb3dc38a.json`。新增回归核对根路径扫码识别、备用页面读取进入认证，以及等待扫码超过 25 秒仍保留官方页面。
- 使用源码 `ef39da2` 的 debug APK（SHA-256 `96eb4c89f13f7b05118fd5c743926b324c6d844aadf4c5be7011aa798eef292a`）确认备用页面读取能打开官方扫码页，但页面已可见时仍可能触发初始加载超时。补充 Android 页面可见回调，页面可见时即检查认证与目标状态。`python scripts/check.py --changed --base ef39da2` 的静态分析和 136 项合成测试通过，报告 `report-876d4da4111c4eab918544cc50e57a80.json`。
- 源码 `e68e332` 的模拟器样本仍出现扫码页已显示而加载回调迟到。到达超时时限时，增加一次有界检查。官方扫码页已可见则保留，页面不可用则提示重试。`python scripts/check.py --changed --base e68e332` 的静态分析和 136 项合成测试通过，报告 `report-e229705325d346cc9e60b275904c6aa0.json`。
- 用干净源码 `848bd68be63b08b1c2b0f0ce479736e9228b93ca` 构建正常包名 0.4/code13 debug APK，验签通过，保留数据安装后设备端 SHA-256 与本地一致（`89f004e2d68644fdf598d161fd875cd7651f5cbaca3b86914ac1c5505ff57516`）。从设置进入课表导入，点「页面读取（备用）」显示官方 WebVPN 扫码页，28 秒后扫码区仍可见。样本覆盖登录前路径，本人认证后的回跳、真实课表导出和物理真机仍待验。

## 2026-11-21 校园账号登录阶段 2 设置公网入口与完整证书链 CAS 复核

- **5G 手机与校内网模拟器差异实测**：
  - 在 5G 蜂窝网络（`8560efd2`，DNS `43.239.172.1`）直接测得：`i.bucm.edu.cn` 无公网解析（`No address associated with hostname`），解释了真机打不开 `tp_nup/` 而校园网模拟器可打开；`kjyy.bucm.edu.cn` 校外 TCP 443 超时；`jw.bucm.edu.cn`（`183.162.226.231`）、`cas.bucm.edu.cn`（`150.138.231.68`）、`qhz.bucm.edu.cn`（`202.204.46.42`）与 `webvpn.bucm.edu.cn`（`123.117.56.23`）均公网可达。
  - 在校内网使用 Java `SSLSocket` 实测服务器发送的 TLS 证书链：`jw.bucm.edu.cn`（`10.64.128.31`）仅发送 **1 张叶子证书**（缺少中级 CA `GeoTrust G2 TLS CN RSA4096 SHA256 2022 CA1`），导致冷启动 WebView 进程在未缓存该中级 CA 前报 `net_error -202`（`ERR_CERT_AUTHORITY_INVALID`）；`cas.bucm.edu.cn`、`qhz.bucm.edu.cn` 与 `webvpn.bucm.edu.cn` 均发送完整 **3 张证书链**。
- **修复范围（`1bf9096`、`6ac24f7`）**：
  - 将「设置 → 登录校园账号」目标改为 `CampusLoginTarget.teaching`（`1bf9096`），同时保留 `ImportPage` 中的 `数字北中医` 入口供校内网络使用。
  - 在 [network_policy.dart](../mobile/lib/config/network_policy.dart) 与 [campus_login_navigation.dart](../mobile/lib/platform/campus_login_navigation.dart) 新增 `SchoolEndpoints.teachingCasLogin` 与 `CampusLoginTarget.loginEntry`，使 `CampusLoginPage` 直接从公网可达且发送完整 3 证书链的 `https://cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fjw.bucm.edu.cn%2F` 进入，并在 `onReceivedServerTrustAuthRequest` 证书拒绝时立即提示失败、保持严格 TLS 校验（`6ac24f7`）。
- **宿主检查**：`python scripts/check.py --changed` 通过，报告 `build/checks/report-9cc20c31de3e47de922468357a0a56f7.json`（`docs` 268 项本地目标、`flutter-analyze` 0 问题、`flutter-default` 260 通过 / 6 条件跳过、`flutter-direct` 23 通过）。
- **构建与双端冷启动实测（未输入凭据或清除会话）**：
  - 在干净树 `6ac24f7` 执行 `python scripts/prepare_flutter.py` 并构建正常包名 0.4/code13 debug APK（SHA-256 `fee51d276cd7967d07770a50c4ce3fca4369194da719e9350db9a6402257d62e`），保留数据安装至 `emulator-5554` 与 `8560efd2`，两台设备端 `base.apk` SHA-256 核对一致。
  - **校内网模拟器冷启动（`emulator-5554`，`am start -W -S`）**：打开 `设置 → 登录校园账号`，无 TLS/网络报错，自动显示 `学校官方页面 · 教务系统` 与「账号密码（已选）/ 手机号 / 企业微信扫码」。
  - **5G 物理真机冷启动（`8560efd2`，`am start -W -S`）**：打开 `设置 → 登录校园账号`，在 5G 蜂窝网络下加载 `学校官方页面 · 教务系统`，显示三枚原生方式标签并自动选中「账号密码」，网页呈现「新教务系统」「记住账号密码」「忘记密码」「立即登录」。
- **尚未验证边界**：基于 `6ac24f7` 构建包完成本人真实登录后的教务服务就绪回跳与真机端到端自动恢复尚待本人实测核对。

## 2026-11-21 校园账号登录阶段 2 WebView 回调判等修复与登录前复核

- 根因定位：`flutter_inappwebview_android` 为 `onWebViewCreated` 与后续回调（`onLoadStart`、`onPageCommitVisible`、`onLoadStop`、`onReceivedError` 等）创建同一底层平台控制器的不同 Dart 包装实例；此前直接使用 `==` / `!=` 比较控制器，导致真实 Android 上回调全部被丢弃，表现为设置门户直连与教务独立登录页 25 秒超时、课表页返回后未感知学校页加载完成。
- 修复范围（提交 `acc5120c09faf248b0eaec2fe2bb73bbd3d0cbd7`）：新增 [webview_identity.dart](../mobile/lib/platform/webview_identity.dart)（`sameWebViewController` 比对 `identical(a.platform, b.platform)`）并在 `CampusLoginPage`、`ImportPage`、`LibrarySeatPage` 统一复用；`campus_login_navigation.dart` 兼容 `/cas//login` 路径并校验 `.active` 类；`CampusLoginPage` 区分 `onPageCommitVisible` / `onLoadStop` 并支持 `onLoadStop` 补选默认账号密码；`ImportPage` 仅在 `onLoadStop` 消费 `_waitingForSchool` 恢复原操作；测试替身 `CampusLoginTestPlatform` 同步改为 `onWebViewCreated` 传入独立包装对象并新增 2 项回归用例。
- 宿主检查：`python scripts/check.py --changed` 通过，报告 `build/checks/report-aff9e77f4b2547b998e03cc0ea9b472e.json`（`docs` 266 项本地目标、`flutter-analyze` 0 问题、`flutter-default` 260 通过 / 6 条件跳过、`flutter-direct` 23 通过）。
- 构建与设备安装：在干净树 `acc5120` 执行 `python scripts/prepare_flutter.py` 后构建正常包名 0.4/code13 debug APK（SHA-256 `3557f4f32a5ea1db441ab76210d52054b664c7176c8bd99cf563a557f54c9fbd`），保留用户数据安装至 `Pixel_8_API_36` 模拟器（`emulator-5554`）与 USB 物理真机（`8560efd2`），两台设备端 `base.apk` SHA-256 均核对一致。
- 模拟器登录前实测（`emulator-5554`，未输入凭据或清除会话）：
  - `设置 → 登录校园账号`（`CampusLoginTarget.portal`）：`https://i.bucm.edu.cn/tp_nup/` 自动跳至 CAS 并渲染三枚原生 `ChoiceChip`，自动选中「账号密码」且网页展示账号/密码表单及「记住账号密码」「忘记密码」「立即登录」，静置超过 35 秒未超时；切换「手机号」显示图形/短信验证码控件，切换「企业微信扫码」显示扫码区与提示。
  - `课表导入 → 学校 WebVPN → 页面读取（备用）`：`ImportPage` 自动识别 WebVPN 根路径需登录；独立登录页即刻显示 WebVPN 扫码区，系统返回退回课表页并提示「已取消登录，离线课表保留。」。
  - `课表导入 → 教务系统（校内） → 自动导入`：`ImportPage` 自动识别教务 CAS；独立登录页显示 `学校官方页面 · 教务系统`、选中「账号密码」并展示「新教务系统」表单，静置超过 28 秒未超时，系统返回退回课表页并提示「已取消登录，离线课表保留。」。
- 尚未验证边界：基于 `acc5120` 包在本人完成真实登录后门户 `tp_nup/` 的就绪回跳、课表与 WebVPN 端到端自动恢复及物理真机复测仍需用户本人操作核对。

## 2026-11-21 校园账号登录阶段 2 真机验证

- Android API 37 物理真机使用源码 `848bd68be63b08b1c2b0f0ce479736e9228b93ca` 的 0.4/code13 debug APK。系统拒绝 ADB 安装，经用户通过系统安装器手动安装后，已安装 APK 的 SHA-256 与已验签测试包一致（`89f004e2d68644fdf598d161fd875cd7651f5cbaca3b86914ac1c5505ff57516`）。
- 设置入口打开独立登录页，数字北中医门户在该页触发加载超时。课表选择「教务系统（校内）」时，原 WebView 显示校方扫码、账号和手机三种方式。点「自动导入」进入独立教务登录页后触发加载超时。
- 「页面读取（备用）」打开独立 WebVPN 扫码页。本人用企业微信完成扫码后，App 返回课表导入，显示正在返回学校 WebVPN。独立登录页随后再次出现，最后课表页显示「学校页面暂未恢复」。独立页返回通过，本次备用读取的端到端恢复未通过。
- 手动重选「学校 WebVPN」可复用刚才的会话，资源页显示「本科教务系统」入口。发起一次「自动导入」后，App 在真机上显示「课表已保存」。该入口使用官方 XLS 导出和整批校验流程。此次验证覆盖真实导出与本地保存，完整学期逐项准确性仍单独验收。

## 2026-11-21 校园账号登录阶段 1 官方认证流程验证

- 日期：2026-11-21
- 被测环境与包身份：工作分支 `codex/campus-account-login`（基线 `945d9b1`）；被测安装包为已安装于 **Android 模拟器 `Pixel_8_API_36`**（`emulator-5554`，`1080×2400`，浅色模式）的 0.4（`versionCode=13`）release 包（发布源码 `7a73decf7f887af4fb296ce84ed8107ec1448269`，设备端 `base.apk` SHA-256 `e6256285158bd8a215843c37168573cddce4199fb1e380786907db2aae17c4a1`，与 `dist/release-0.4/` 一致）。全程不忽略 TLS 校验、不记录任何凭据或个人数据，图书馆保持 `0` 次预约/取消写操作；尚未在物理真机验证。

### 三种直连方式与 WebVPN 分项结果

| 方式 / 入口 | 入口可见 | 本人登录 | 返回目标服务与复用结果 | 测试设备与边界 |
|---|---|---|---|---|
| 账号密码登录<br>（直连 CAS `login10.js`） | 通过（`#password_login`、`#un`、`#pd`、`#rememberName`、`#pwd_url`、`#index_login_btn` 均可见） | 通过（本人在 `LibrarySeatPage` 账号登录页提交完成） | 图书馆回跳官方首页并「返回应用」自动只读恢复 `共 4 层 · 16 个区域`；同会话下 `ImportPage → 教务系统（校内）`（`jw.bucm.edu.cn`）免密 SSO 复用直接进入教务桌面；轻新课堂（`qhz.bucm.edu.cn/cc/`）已跳过 CAS 登录表单但停滞于空白 `#app`（未自动推进到 `coursePlatform`，单列缺口） | `Pixel_8_API_36` 模拟器；`0` 次写入；未测门户 `tp_nup/` 回跳 |
| 手机号登录<br>（直连 CAS `login10.js`） | 通过（`#loginByMobile`、`#loginMobile`、`#sendConfirm`、`#codeImage`、`#phoneCode`、`#getMobileVerifyCode`、`#finishloginbymobile` 可见，软键盘弹起无重叠遮挡） | 通过（本人填写手机号、图形验证码与短信验证码并送达提交） | 回跳 `北京中医药大学图书馆预约服务平台`，点击「返回应用」后原生图书馆自动恢复 `共 4 层 · 16 个区域` | `Pixel_8_API_36` 模拟器；`0` 次写入 |
| 企业微信扫码<br>（直连 CAS `login10.js`） | 通过（默认激活 `#qrcode_login`，`#qrcode` 约 `402×415 px`；`login-qrcode.js` 本地生成并同源轮询 `/checkQRCodeScan`，不嵌入微信第三方 iframe） | 通过（本人使用绑定企业微信扫码确认） | 回跳 `北京中医药大学图书馆预约服务平台`，点击「返回应用」后原生图书馆自动恢复 `共 4 层 · 16 个区域` | `Pixel_8_API_36` 模拟器；`0` 次写入 |
| WebVPN 扫码<br>（`webvpn.bucm.edu.cn/login` 及 WebVPN CAS `login4.js`） | 通过（仅开放 `wrd_qrcode` 统一认证扫码；桌面宽视口下 `#bucm-qrcode` 约 `100×114 px` 需缩放方便扫码；且直连 CAS 已登录时 WebVPN 仍未登录，实证会话隔离） | 通过（本人扫码确认登录） | 回跳 `WebVPN - 资源站点` 门户，可见「最近访问」「本科教务系统（`jw.bucm.edu.cn`）」「智慧教学平台（`qhz.bucm.edu.cn/cc/`）」「办公系统」「业务系统」「其他资源」 | `Pixel_8_API_36` 模拟器；WebVPN 下进入教务/录播子系统待阶段 2/3 端到端验证 |

### 取消、返回与真实退出会话

- `LibrarySeatPage` 与 `ImportPage` 在未登录认证页按 Android 系统返回（`KEYCODE_BACK`）均干净退回原页面，无自动写操作或意外重发。
- 经用户授权两次在「设置 → 退出学校会话」（`SchoolAdapter.clearSession`）执行真实会话清理，核对设置页离线课表（`2026-2027-1 学期`）继续保留，切换至「图书馆」页恢复未登录提示（`学校会话已清除`），确认 WebView 会话与图书馆状态已被真实清除。

### 公开协议核查与已发现缺口

1. **门户根路径明文重定向**：公开只读请求及 `ImportPage → 数字北中医`（`https://i.bucm.edu.cn/`）实测均先返回 `301 Location: http://i.bucm.edu.cn/tp_nup`，在 Android WebView 严格禁止明文 HTTP 下直接报错 `net::ERR_CLEARTEXT_NOT_PERMITTED`；直接请求 `https://i.bucm.edu.cn/tp_nup/` 可跳过明文跳直接返回 HTTPS 200，留待阶段 2 调整并验证。
2. **轻新课堂 `/cc/` 首页初始化停滞**：在已登录 CAS 会话下打开 `统一导入录播`（`qhz.bucm.edu.cn/cc/`），虽跳过 CAS 登录页但停留在标题为 `智慧教学平台` 的空白 `#app` 页（进度条持续、`继续导入` 按钮禁用）；手动切换「数字北中医（直接访问）」除受 `i.bucm.edu.cn` 明文重定向影响外，[classroom-entry.js](../assets/classroom-entry.js) 也未将 `i.bucm.edu.cn` 识别为合法入口宿主，留待阶段 3 衔接修复。
3. **WebVPN 服务端仅开放扫码**：校方 `webvpn.bucm.edu.cn/login` 及 `cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fwebvpn.bucm.edu.cn%2Flogin%3Fcas_login%3Dtrue`（`login4.js`）均未提供账号密码与手机短信标签，仅开放统一认证扫码。
4. **教务直连 TLS 链**：Python 默认信任库对 `jw.bucm.edu.cn:443` 报 `unable to get local issuer certificate`（颁发者为 `GeoTrust G2 TLS CN RSA4096 SHA256 2022 CA1`），但 Android WebView 在正常 TLS 校验下可直接通过并跳转到三标签 CAS 页。

### 阶段 1 设计选择依据（供审核）

- **直连四业务合并与 WebVPN 独立**：门户、教务、录播、图书馆四项直连均指向同一 `cas.bucm.edu.cn` 三标签页面（`login10.js`）且共享 Android WebView `CookieManager` 会话，可合并共用统一「校园账号登录」页实现一次认证多业务免密复用，各业务保留各自回跳目标与独立恢复校验；WebVPN 因会域隔离且仅支持扫码，保留为校外独立通道。
- **方式选择器 vs 完整官方页**：`login10.js` 不支持 URL 参数直达指定标签；基于用户已授权在 CAS 加载后执行受限脚本仅 `.click()` 切换标签，直连场景下**采用原生方式选择器并默认切至「账号密码」**；检测到 WebVPN 或目标页面缺少对应标签时自动回落直接展示官方页，不呈现不可用选项。
- **白名单保持不变**：直连与 WebVPN 二维码均在页面本地绘制并轮询同源 `/checkQRCodeScan`，不嵌入微信第三方 iframe，[library_seat_navigation.dart](../mobile/lib/platform/library_seat_navigation.dart) 无需放宽域名白名单。
- **尚未验证项**：物理真机、门户 `https://i.bucm.edu.cn/tp_nup/` 实际登录回跳、WebVPN 进入教务/录播子系统的端到端恢复、独立登录页在 320px/2.0x/无障碍下的适配（留待阶段 2/3）。

## 2026-11-20 0.4（code 13）版本核验与标签发布

- 日期：2026-11-20
- 版本与精确源码：分支 `main` 快进合并 `codex/library-seat-booking` 至 `7a73decf7f887af4fb296ce84ed8107ec1448269`，根 `AndroidManifest.xml` 为 `0.4` / `versionCode 13`，`mobile/pubspec.yaml` 同步为 `0.4.0+13`（`mobile/pubspec.lock` 未改动）。
- 全量宿主检查：`python scripts/dependencies.py`、`python scripts/prepare_flutter.py`、`flutter pub get --enforce-lockfile`，以及 `python scripts/check.py --all --flutter C:\studentsAPP\build\toolchain\flutter\bin\flutter.bat` 全部通过（耗时 `67.141s`，报告 `build/checks/report-9c934563184c40b1be2ea909db89cef1.json`：`docs`、`tooling`、`icons`、`examples`、`java-compile`、5 项 Java、11 项 Node、`flutter-analyze`、`flutter-default` 351 通过 / 9 条件跳过、`flutter-direct` 23 通过）。
- 精确提交远端 CI：`main` 推送触发 GitHub Actions 运行 [`44750357261`](https://github.com/zhihaorao8-web/bucm-campus-prototype/actions/runs/44750357261)（`status: completed`, `conclusion: success`）：`quality`（`14:06:57Z`–`14:11:11Z`）与 `dual-preview`（`14:11:14Z`–`14:25:21Z`）均通过。
- 隔离 R8 二进制 XLS 测试：刷新正式插件注册表后，于 `Pixel_8_API_36` 执行 `.\gradlew.bat connectedReleaseAndroidTest -PcampusReleaseParserTest=true`（隔离包 `cn.bucm.campus_schedule.releasetest`），`cn.bucm.campus_schedule.ReleaseParserTest#optimizedBinaryXlsKeepsTeacherWeeksAndSegments` 1/1 通过。
- 可信签名双包校验：以 `pwsh -NoProfile -File ./scripts/build_flutter_previews.ps1 -Kind release`（关联 CI `44750357261`、证书 SHA-256 `4584a62b3daab61954f0842f65c4d7974f9cf9bb84155b150741b7d538faf40c`、Flutter SDK `c197ca5199e9ee5661e865596c9c07294dfab51c`）通过 `scripts/verify_apks.py` 全项检查并归档至 `dist/release-0.4/`：
  - `campus-schedule-0.4-android-release.apk`：`68,733,994` 字节，SHA-256 `e6256285158bd8a215843c37168573cddce4199fb1e380786907db2aae17c4a1`
  - `campus-schedule-0.4-android-debug.apk`：`185,220,270` 字节，SHA-256 `e2d2c5fbd5fd5e4faa6f98dd75fb390b3bd6619cf9192cd28f2fcefaf14cfefa`
  - `SHA256SUMS.txt`：`212` 字节，SHA-256 `f9e8e9852b26bf1ea9e0ac29833938143858c52ffa5bc05a197756f15011864f`
  - `build-metadata.json`：`1,715` 字节，SHA-256 `2a797a6ec3da2da20c15a9185018399a79f13c1cac9184866219b42347b067f3`
- 模拟器 release 抽查：将 `campus-schedule-0.4-android-release.apk` 覆盖安装至 `Pixel_8_API_36`（设备 `base.apk` SHA-256 与上述一致、`Night mode: no`、0 POST 写入），冷启动核对“今日”“图书馆”及“设置 → 项目信息（`发布构建 / 源码 7a73decf / 版本 0.4 (13)`）”，确认无“测试诊断”。
- 2026-11-21 核对 GitHub 预发布状态。远端 `v0.4` 解析为源码 `7a73decf7f887af4fb296ce84ed8107ec1448269`。Release API 返回 `prerelease=true`、`draft=false`，两个 APK、`SHA256SUMS.txt` 与 `build-metadata.json` 共四份附件均为 `uploaded`。逐项比对文件大小及 SHA-256，均与本地归档一致。[GitHub 预发布](https://github.com/zhihaorao8-web/bucm-campus-prototype/releases/tag/v0.4)

## 2026-11-20 图书馆顶栏统一高度与 B1 艺术标题阶段 8D

- 日期：2026-11-20
- 验证版本与安装口径：
  - 分支 `codex/library-seat-booking`（版本维持 `AndroidManifest.xml` 的 `0.3` / `code 12`，`mobile/pubspec.yaml` 为 `0.3.0+12`）。
  - `python scripts/prepare_flutter.py`（`Android 0.3, pubspec 0.3.0+12`）后执行 `flutter build apk --debug --no-pub`，生成 `mobile/build/app/outputs/flutter-apk/app-debug.apk`；`adb -s emulator-5554 install -r` 安装至 `Pixel_8_API_36` 模拟器，主机 APK 与设备端已安装 `base.apk` 的 SHA-256 一致，均为 `e9071ab1ac21a5ecf1ed51ba3f11e0c70e997e9145e5434c1c53448011e006c2`。
- 完成范围：
  - `scripts/generate_macintosh_hello_glyphs.py` 与 `mobile/lib/ui/macintosh_hello_glyphs.g.dart`：新增“图”（3 轮廓、`[32, 100, 8]` cubics、7 笔）、“书”（3 轮廓、`[87, 14, 12]` cubics、4 笔）、“馆”（3 轮廓、`[138, 13, 12]` cubics、9 笔）自研 B1 Macintosh 骨骼填充字形与笔顺，7 字全集为 `['今', '日', '课', '表', '图', '书', '馆']`。
  - `mobile/lib/ui/app_shell.dart`：`navigationHeader` 仅在 `设置`（`index == _settingsTab`）跳过 B1 覆盖，使 `图书馆`（`index == _libraryTab`）与 `今日`、`课表` 共用 `AppType.artisticHeader`（`40.0`、`height: 1.16`、`FontWeight.w400`）展开大标题高度、透明 `largeTitle` 占位与 `MacintoshHelloHeaderOverlay`（1350ms 书写动画，滚动折叠后显现居中系统标题）。
  - `mobile/test/artistic_title_test.dart` 与 `DESIGN.md`：覆盖 7 字全集、`hello-title-图书馆` 渲染、`topbar-2` 与 `topbar-0`/`topbar-1` 高度一致（`(false, 1.0, 390x844)`、`(true, 1.5, 390x844)` 与 `(false, 2.0, 320x720)` 差值 `< 0.5dp`）、`hello-title-设置` 不存在、`图书馆` 笔顺渐进推进与 `disableAnimations: true` 跳过首尾断言，并同步 `DESIGN.md` 规范说明。
- 主机检查结果（最终代码与测试编辑后）：
  - `python scripts/generate_macintosh_hello_glyphs.py`：Clean 生成 7 字 `mobile/lib/ui/macintosh_hello_glyphs.g.dart`。
  - `C:\studentsAPP\build\toolchain\flutter\bin\flutter.bat analyze --no-pub`：`No issues found! (ran in 3.6s)`。
  - `flutter test --no-pub test/artistic_title_test.dart test/atmosphere_test.dart test/library_seat_queries_test.dart`：`00:13 +55: All tests passed!`（随后追加 `320x720` 视口用例并复跑 `flutter test --no-pub test/artistic_title_test.dart`：`00:03 +2: All tests passed!`）。
  - `python scripts/check.py --changed`：退出码 `0`（耗时 `59.046s`，报告 `build/checks/report-fb07fac86c6944828ac2fa41d4fb9608.json`：`docs`、`tooling`、`icons`、`examples`、`java-compile`、5 项 Java 测试、11 项 Node 测试、`flutter-analyze`、`flutter-default` 351 passed / 9 skipped、`flutter-direct` 23 passed）。
- Android 模拟器真实校园会话只读验收（Pixel 8 API 36 / `emulator-5554`，0 POST 写入）：
  - **深色模式**：`今日` 展开大标题像素范围 `y=[214, 308]`（高 `95px`、`x=[68, 267]`），`课表` `y=[213, 311]`（高 `99px`、`x=[69, 278]`），`图书馆` 完成 1350ms 书写后 `y=[215, 309]`（高 `95px`、`x=[71, 397]`、`w=327px`），`设置` 保持纯系统字体。
  - **浅色模式**：`图书馆` 展开大标题像素范围 `y=[215, 309]`（高 `95px`、`x=[70, 397]`、`w=328px`）；进入 `图书馆五层 → 五层南区`（164 席）切换紧凑网格并上滑滚动后，B1 艺术标题平滑淡出，顶栏居中显示折叠系统标题 `图书馆`。
  - **收尾状态**：已切回 `今日` 页、确认 `cmd uimode night` 为 `no`，并清理设备 `/data/local/tmp` 临时截图与 XML。
- 未验证边界：真实物理机与真实预约提交/取消写操作未在本阶段触发，仍按既有边界单独验收。

## 2026-11-20 图书馆座位预约三级选座体验微调阶段 8C

- 日期：2026-11-20
- 验证版本与安装口径：
  - 分支 `codex/library-seat-booking`（版本维持 `AndroidManifest.xml` 的 `0.3` / `code 12`，`mobile/pubspec.yaml` 为 `0.3.0+12`）。
  - `python scripts/prepare_flutter.py`（`Android 0.3, pubspec 0.3.0+12`）后执行 `flutter build apk --debug --no-pub`，生成 `mobile/build/app/outputs/flutter-apk/app-debug.apk`；`adb -s emulator-5554 install -r` 安装至 `Pixel_8_API_36` 模拟器，主机 APK 与设备端已安装 `base.apk` 的 SHA-256 一致，均为 `62159cf983af29ef362385553b1a4c988d20f7ae02565539a82a3ce8f3a7eae1`。
- 阶段 8C 主机检查证据（合成数据与静态分析）：
  - `flutter analyze --no-pub`：无警告或错误（`No issues found!`）。
  - `flutter test --no-pub test/library_seat_queries_test.dart`：41/41 全部通过（新增阶段 8C 合成回归覆盖 `西A区`/`南区` 等比投影与方席无重叠校验、`LibrarySpatialBreadcrumbBar` 三段垂直中线对齐、`_seatControlsCard` 三分组纵序与无黑底 Chip、以及 `西A区` 1.0x/缩放显号一致性）。
  - `flutter test --no-pub test/atmosphere_test.dart`：12/12 全部通过。
  - `python scripts/check.py --changed`（退出码 `0`，耗时 `51.203s`，报告 `report-dc99e3e34ad747d49a934e21700954da.json`）：`docs`、`tooling`、`icons`、`examples`、`java-compile`、Java 单测 5/5、Node 单测 11/11、`flutter-analyze`、`flutter-default`（351 passed / 9 skipped）与 `flutter-direct`（23 passed）全部通过。
- 阶段 8C 模拟器真实只读验收（`Pixel_8_API_36`，校园会话已登录，`0` 次预约/取消 POST 写入）：
  - **深色模式**：
    - **五层西A区（1.0x 与 225% 缩放）**：索引条`全部楼层 > 图书馆五层 > 五层西A区`严格水平对齐同一中线（Bounds `y=525..620`）；控制区呈三组清晰排布（定位微标与平面/网格切换首行对齐 + 深色迷你缩略图清晰可读 -> `今天|明天` 与 `2026-11-20` 等高齐平及 `08:30–22:00 调整` -> `共 48 席` 与右侧`仅看空闲`统一样式胶囊）；两排面对面书桌呈紧凑水平带状居中、无垂直空洞、方席均一无重叠；放大至 `225%` 统一显示 `5WA015`–`5WA034` 等清晰座号。
    - **三层南区（1.0x）**：从放大状态的西A区切入后自动复位至 `1.0x`，整体保持横向厅室比例，底部靠窗密排座位为均一正方形、无细长竖条。
    - **五层南区（1.0x）**：与官方原图 1:1 比例一致，四叶圆桌簇、靠壁包厢与东侧纵列分布清晰无挤压重叠。
    - **四层西C区（1.0x）**：`全部楼层 > 图书馆四层 > 四层西C区` 索引条垂直中线对齐，倒 L 形两翼方席排布清晰。
  - **浅色模式（`外观设置 → 浅色` + `cmd uimode night no`）**：
    - `四层西C区` 面包屑、三组控制卡片、`中庭东南翼 · ↑ 北` 定位微标及 L 形平面图对比度清晰无遮挡。
  - **收尾清理**：已退回`今日`首页，确认 `Night mode: no` 并清除设备 `/data/local/tmp` 临时截图与 XML dump。
- 尚未验证边界：本轮为只读验收，未实发阶段 8 界面上的预约/取消 POST（最近真实写入记录仍为阶段 1–6）；本次真机/模拟器实测已抽查 `五层西A区`、`三层南区`、`五层南区` 与 `四层西C区`，其余未抽查子区域共享同一 `1.72:1` 等比投影管线；真实退出会话及物理真机仍待后续按需单独验证。

## 2026-11-20 图书馆座位预约三级空间选座阶段 8A 与 8B

- 日期：2026-11-20
- 验证版本与安装口径：
  - 分支 `codex/library-seat-booking`，阶段 8A 代码提交 `cf0189bad75b14bf9ae8ac9bab208d791a903ad8`（版本保持 `AndroidManifest.xml` 的 `0.3` / `code 12`，`mobile/pubspec.yaml` 为 `0.3.0+12`）。
  - `python scripts/prepare_flutter.py`（`Android 0.3, pubspec 0.3.0+12`）后执行 `flutter build apk --debug --no-pub`，生成 `mobile/build/app/outputs/flutter-apk/app-debug.apk`；`adb -s emulator-5554 install -r` 安装至 `Pixel_8_API_36` 模拟器，主机 APK 与设备端已安装 `base.apk` 的 SHA-256 一致，均为 `5a7f4071ab3ce8c93bb14273aabec6d0885a139164208b6d5704c83dfcb0b7ab`。
- 阶段 8A 主机检查证据（合成数据与静态分析）：
  - `flutter analyze --no-pub`：无警告或错误（`No issues found!`）。
  - `flutter test --no-pub test/library_seat_queries_test.dart`：39/39 全部通过（覆盖楼层分组 `groupLibraryFloors`、2F 专绘 vs 3F–5F 示意图、连续 L 形 `西C` 双触控臂、未标明轮廓隔离、按需拉取时机、面包屑/`LibrarySpatialLocatorPill`/`PopScope` 逐级回退与空间转场）。
  - `flutter test --no-pub test/atmosphere_test.dart`：12/12 全部通过（覆盖 `LibrarySpatialLevelTransition`、`LibrarySeatViewModeTransition` 动效曲线及减少动画/无障碍降级）。
  - `python scripts/check.py --changed`（退出码 `0`，耗时 `44.406s`，报告 `report-895f62e72720401e8c3b4504e2d34177.json`）：`docs`、`tooling`、`icons`、`examples`、`java-compile`、Java 单测 5/5、Node 单测 11/11、`flutter-analyze`、`flutter-default`（349 passed / 9 skipped）与 `flutter-direct`（23 passed）全部通过。
- 阶段 8B 模拟器真实只读验收（`Pixel_8_API_36`，用户在场完成 CAS 登录，`0` 次预约/取消 POST 写入）：
  - **浅色模式（`cmd uimode night no`）**：
    - **L1 楼层列表**：真实学校接口返回 `共 4 层 · 16 个区域`，展示 `图书馆二层`（`1 个区域 · 二层北区`）及 `图书馆三层`–`五层`（各 `5 个区域`）；微型平面预览 `2F` 仅点亮东北侧 `北区`，`3F–5F` 点亮全部 5 个区域。
    - **L2 楼层平面示意图**：点击 `图书馆二层` 显示专绘二层视图（`↑ 北`、`中庭`、东北方位共享 `libraryNorthZoneRect` 的 `北区` 与未标明虚线轮廓，无 `西A`/`西B`/`西C`/`南区` 标签）；返回点击 `图书馆三层` 显示 3–5 层示意图（`↑ 北`、`中庭`、北侧无标明虚线轮廓、`西A`、`西B`、统一连续 L 形 `西C` 东/南两臂、`北区`、`南区` 与`< 返回楼层`）。
    - **L3 具体区域与退回链路**：点击 `西C` 南翼拉取并展示真实 `三层西C区` 座位（`共 64 席 · 空闲 57 · 半空闲 7`），顶部显示 `中庭东南翼 · ↑ 北` 的 `LibrarySpatialLocatorPill` 与面包屑 `全部楼层 > 图书馆三层 > 三层西C区`，缩放条位于视口上方且座位节点无重叠；切入`紧凑网格`可见搜索框与 4 列席位砖块（`3WC001` 起）；切回平面图并点击方位微标准确退回 L2 `图书馆三层`，再触发系统返回准确退回 L1 并在 `图书馆三层` 卡片显示`刚才查看`微标。
  - **深色模式（应用内`外观设置 → 深色` + `cmd uimode night yes`）**：
    - L1 四层卡片（含 `图书馆三层` 的`刚才查看`微标）、L2 `图书馆三层` 五区示意图（L 形 `西C`、`中庭`、虚线非选座区、`↑ 北`）及 L3 `三层南区` 真实 145 席位（`共 145 席 · 空闲 131 · 半空闲 14`，`东南翼 · ↑ 北`微标）均对比度清晰、无重叠或截断。
  - **收尾清理**：已将模拟器调回浅色模式、导航至`今日`首页并删除 `/data/local/tmp` 临时截图与 UI dump，工作区无截留临时产物。
- 尚未验证边界：本轮为只读验收，未实发阶段 8 界面上的预约/取消 POST（最近真实写入记录仍为阶段 1–6）；本次真机/模拟器实测已覆盖 L1 四层真实目录、L2 `图书馆二层`（专绘北区）与 `图书馆三层`（五区含 L 形 `西C`）示意图，以及 L3 `三层西C区`（浅色 64 席）与 `三层南区`（深色 145 席）真实座位拉取，其余楼层及子区域共享同一 schematic 与查询管线；真实退出会话及物理真机仍待后续按需单独验证。

## 2026-11-20 图书馆座位预约前端重设计阶段 7C

- 基于已审核基线 `9d5d2bd`（阶段 7B）完成阶段 7C 收尾重设计，保持所有提交前余位复核、防连点、取消预检、fail-closed 写入与示例隔离语义不变：
  1. 扩展 [library_seat_sheets.dart](../mobile/lib/ui/library_seat_sheets.dart)：复用 `QuietSheet` 新增 `showLibraryConfirmReservationSheet`（响应式英雄摘要卡含 `AppIcons.book` 与时长胶囊、`适用规则` 列表、琥珀色`签到提示：`提醒框、越权/时段阻塞提示及防连点吸底操作区）与 `showLibraryConfirmCancelSheet`（预约标的摘要、红色释位提示框及破坏性`确认取消`防连点吸底操作区），并在窄屏大字号下自动纵向叠放按钮。
  2. 新增 [library_seat_bookings.dart](../mobile/lib/ui/library_seat_bookings.dart)：实现 `isFocusLibraryBooking`、时区无关的 `libraryBookingTimeHint`、`LibraryBookingsControlsCard`（`本周` / `近 30 天` 快捷切片 + 自定义范围 + 刷新与分页）、`LibraryBookingsLoadingSkeleton`、`LibraryBookingsEmptyCard`（`去选座` / `查看近 30 天` 快捷操作）、`LibraryBookingFocusTicket`（基于 `AcrylicSurface` 展示待生效/生效中票卡、相对倒计时、`HH:MM–HH:MM` 大号时间与操作栏）及 `LibraryBookingHistoryRow`（近期记录分组下的 `QuietCard` 历史行）。
  3. 集成 [library_seat_query_page.dart](../mobile/lib/ui/library_seat_query_page.dart)：将原 `AlertDialog` 提交与取消确认替换为 `showLibraryConfirmReservationSheet` 与 `showLibraryConfirmCancelSheet`；重构“我的预约”为聚焦票卡 + `近期记录` 分层视图并移除被替代的旧 `_bookingControlsCard` / `_bookingRow`。
  4. 扩充 [library_seat_queries_test.dart](../mobile/test/library_seat_queries_test.dart)：保留阶段 4–6 全部防超卖/防重发/取消确认断言并新增 5 项 7C 专项测试（聚焦状态与 7 天倒计时规则单元测试、`QuietSheet` 规则/释放提示与关闭零写入测试、`我的预约` 焦点 `AcrylicSurface` 票卡与历史分层及`近 30 天` / `去选座`交互测试，以及 320px `1.5x` 浅色与 `2.0x` 深色高对比关闭玻璃和动画的 7C 响应式检查）。
- **静态与合成检查通过**（与真机/学校验收分列）：
  - `mobile/` 下 `flutter analyze --no-pub`：0 问题（`No issues found!`）。
  - 靶向 `flutter test --no-pub test/library_seat_queries_test.dart test/atmosphere_test.dart test/ui_test.dart`：55 项全部通过。
  - `python scripts/check.py --changed`：退出码 0，报告 `build/checks/report-8ac94089c2414e8d875b974f450e2304.json`（49.984s：`docs`、`tooling`、`icons`、`examples`、Java 5 组、Node 11 组、`flutter-analyze`、`flutter-default` **344 项通过 / 9 项条件跳过**、`flutter-direct` **23 项通过**）；`mobile/pubspec.lock` 无改动。
- **Android 模拟器只读浅/深色视觉核对通过**（`emulator-5554` / `Pixel 8 API 36`，debug 包 `0.3/code12`，宿主机与设备 `/data/app/.../base.apk` SHA-256 校验一致：`5654e003a85d7c0408772140fbd8b7f66a6cd289ad854d802286cbc514af6baf`）：
  - 在已登录官方会话下仅执行只读查询与确认抽屉弹出核对（全程 **0 次写入请求**，未点击`确认提交预约`或`确认取消`）。
  - 浅色模式核对：`二层北区` 选中 `2N172` 呼出 `确认预约座位` `QuietSheet`（英雄摘要卡、规则列表、琥珀色 `签到提示：`、`开始时间早于当前时间` 阻断提示与禁用状态 `确认提交预约` 布局清晰，点`取消`关闭零写入）；`我的预约` 在`本周`显示空态引导卡片，切换`近 30 天`后真实加载 2 条历史记录卡片（`三层西A区 · 3WA040`、`四层北区 · 4N163`）无溢出。
  - 深色模式核对：通过应用内 `设置 → 外观设置 → 深色` 切换后核对`我的预约`（2 条历史记录卡片 + 四项底栏）与 `确认预约座位` `QuietSheet` 对比度与圆角边距均清晰无遮挡，查验后已恢复应用外观为`浅色`并切回`今日`。
- 更新 [DESIGN.md](../DESIGN.md)、[ARCHITECTURE.md](ARCHITECTURE.md) 与 [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md)；不修改应用版本，阶段 7C 已获用户审核通过（`b4227e5`），当前暂停等待后续调整指示。

## 2026-11-20 图书馆座位预约前端重设计阶段 7B

- 基于已审核基线 `4bd9329`（阶段 7A）实施并完成阶段 7B 选座体验重设计：
  1. 新增 [library_seat_map.dart](../mobile/lib/ui/library_seat_map.dart)：实现 `LibrarySeatPalette`（浅/深色与高对比度状态语义配色）、`canUseLibraryFloorMap`、`LibrarySeatFloorMap`（基于学校归一化 `coordinate` 绘制平面布局，`InteractiveViewer` 1.0x–6.0x 双指缩放与顶栏外置 `+`/`-`/`复位` 控件，`1.6dp` 最小间隔无重叠节点测距并在缩放后显现密集座位编号，筛选命中外显示轻量轮廓，手势互不遮挡/不冲突）、`LibrarySeatGridControls`（座位号实时搜索 + 80 席号段快跳）、`LibrarySeatGridRow`（自适应 2–5 列紧凑网格）及 `LibrarySeatLoadingSkeleton`（加载骨架）。
  2. 新增 [library_seat_sheets.dart](../mobile/lib/ui/library_seat_sheets.dart)：复用 `QuietSheet` 实现 `showLibraryAreaSheet`（楼层横向过滤切片 + 当前区域高亮列表）与 `showLibraryTimeSlotSheet`（`08:30–22:00` 可视时间轴刻度条、半空闲座位已约占位与可用空档切片、快捷时段、“+1/+2/+4 小时”调节及 `resvRule`/当前时间实时校验提示）。
  3. 重构 [library_seat_query_page.dart](../mobile/lib/ui/library_seat_query_page.dart)：采用 `ClassroomSectionSwitch`（`选座` / `我的预约`）、2 行紧凑筛选卡、可点击状态计数图例（`共 N 席` / `空闲` / `半空闲` / 按需显示 `使用中` 与 `不可用`）、双视图自动切换与无坐标自动回落紧凑网格、点选半空闲座位呼出空档时间轴抽屉，以及悬浮于四项底栏之上的 `AcrylicSurface` 选中操作胶囊（展示完整时长、快速清除及 `确认预约` 主按钮）。独立页顶栏补充刷新与官方网页入口。保留现有确认弹窗及“我的预约”页结构供 7C 重构。
  4. 更新与扩充 [library_seat_queries_test.dart](../mobile/test/library_seat_queries_test.dart)：迁移阶段 4–6 用例以适配新控件并保留全部零超卖/防重发/状态校验断言，新增 7 组 7B 专项用例（有坐标默认平面图/缩放与复位/切网格搜号段、无坐标回落网格+楼层筛选抽屉、半空闲空档校验与规则超限拦截、320px `1.5x` 浅色与 `2.0x` 深色高对比关闭玻璃和动画溢出检查，以及混合密集坐标零重叠与顶栏缩放控件不遮挡视口检查）。
- **静态与合成检查通过**（与真机/学校验收分列）：
  - 在 `mobile/` 下执行 `flutter analyze --no-pub`：0 问题（`No issues found!`）。
  - 执行 `python scripts/check.py --changed`：退出码 0，报告 `build/checks/report-4ff47f82cda44ae7b24d7a58764eed4d.json`（45.953s：`docs`、`tooling`、`icons`、`examples`、Java 5 组、Node 11 组、`flutter-analyze`、`flutter-default` **339 项通过 / 9 项条件跳过**、`flutter-direct` **23 项通过**）；`mobile/pubspec.lock` 无改动。
- **Android 模拟器只读视觉核对通过**（`emulator-5554` / `Pixel 8 API 36`，debug 包 `0.3/code12`，构建后宿主与设备 `/data/app/.../base.apk` SHA-256 校验一致：`cb5eeaf896c55d7dc53422a600c35daf2e245ef3a59b16d890effdf4186afb53`）：
  - 使用已登录官方会话只读加载真实学校数据（全程 **0 次写入请求**，未点击`确认提交预约`或`确认取消`）。
  - 首轮真机核对发现 `三层南区` 边缘密排座位（`3S001–3S010`、`3S049–3S061`）横向重叠、悬浮右下角缩放栏遮挡 `3S049–3S061` 及悬浮选中胶囊时长 `13 小时 30 分钟` 截断为 `13 小…`；已在上述代码中修复（外置缩放栏到视口上方标题栏、逐对 `1.6dp` 防重叠尺寸与缩放显号、胶囊副标题允许 2 行显示）。
  - 修复重装并核对最终 SHA-256 包后复查通过：真实 `二层北区`（282 席）与 `三层南区`（145 席）在 `1.0x` 均零重叠且缩放栏不遮挡座位、`225%` 放大后编号清晰、选中胶囊完整显示 `13 小时 30 分钟`、区域抽屉 / 时段轴抽屉（含半空闲 `3S006` 空档）/ `今日` 四项底栏 / `我的预约` 及深色模式切换（测后已恢复浅色模式）均视觉正常。
- 更新 [DESIGN.md](../DESIGN.md) 与 [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md)；不改应用版本号，等待用户审核 7B 后进入 7C。

## 2026-11-20 图书馆座位预约前端重设计阶段 7A

- 基于 `229f002`（阶段 6 已审核基线）与用户确认的“四项悬浮底栏（今日 / 课表 / 图书馆 / 设置）+ 阶段 7A→7B→7C 方案”实施阶段 7A：
  1. 离线从已配置 `iconmcp` 服务增补 6 个 MIT outline SVG（`book`、`map`、`grid`、`search`、`clock`、`globe`）至 [清单](../design/icons/iconmcp/manifest.json) 与 [app_icons.g.dart](../mobile/lib/ui/app_icons.g.dart)，共 49 个；原有 43 个 SVG 文件与摘要未改动。
  2. 扩展 [library-seat-read.js](../assets/library-seat-read.js)（`coordinate` 百分比提取，缺失或越界/畸形安全置 `null` 且不阻塞查询）与 [library_seats.dart](../mobile/lib/domain/library_seats.dart)（`LibrarySeat.x/y` 及 `hasCoordinates`，要求双分量均在 `[0, 100]` 有限范围）。
  3. 升级 [glass_navigation.dart](../mobile/lib/ui/glass_navigation.dart)（四项标签 `今日 / 课表 / 图书馆 / 设置`、4 等分滑块及窄屏防溢出排版）、[app_palette.dart](../mobile/lib/design/app_palette.dart)（`tab == 2` 图书馆浅/深色静谧阅览柔光，原设置移至 `tab == 3`）、[library_seat_query_page.dart](../mobile/lib/ui/library_seat_query_page.dart)（内嵌一级页壳层、`LibrarySeatTabController` 顶栏联动、仅在激活且非示例模式下惰性加载）与 [app_shell.dart](../mobile/lib/ui/app_shell.dart)（四页切换与滑过中间页不误唤醒图书馆加载；图书馆独立于本地课表状态；顶栏沿用系统字体而非 B1 艺术标题；设置页入口同步直达底部“图书馆”栏）。
  4. 同步迁改 8 组现有导航/外观/设置测试并补测 [app_icons_test.dart](../mobile/test/app_icons_test.dart)（49 图标解码）、[ui_test.dart](../mobile/test/ui_test.dart)（4 项触控区 `>= 48dp` 与 320px `1.5x/2.0x` 大字号不溢出）、[atmosphere_test.dart](../mobile/test/atmosphere_test.dart)（四页光场与顶栏模糊）与 [library_seat_queries_test.dart](../mobile/test/library_seat_queries_test.dart)（坐标校验、未激活零加载、示例隔离及设置联动跳转）。
- 同步更新 [DESIGN.md](../DESIGN.md)、[PROJECT_BRIEF.md](PROJECT_BRIEF.md)、[ICON_SYSTEM.md](ICON_SYSTEM.md)、[THIRD_PARTY.md](THIRD_PARTY.md)、[ARCHITECTURE.md](ARCHITECTURE.md) 与 [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md)。
- 本地验证通过：`python scripts/iconmcp_assets.py`（49 个本地 SVG 离线校验）、`python scripts/prepare_flutter.py`（`Android 0.3, pubspec 0.3.0+12`）与 `python scripts/check.py --changed`（报告 `build/checks/report-1ad3bf49cafd43618a066c56b5a7c72b.json`：`docs` 203 个本地目标、`tooling` 37 项、`icons`/`examples`、`java` 5 组、`node` 11 组（含 `library-seat-read-test.cjs` 8 项与 `library-seat-write-test.cjs` 9 项）、`flutter analyze --no-pub` 0 问题、`flutter-default` 333 项通过 / 9 项条件跳过、`flutter-direct` 23 项通过）。
- 本阶段未重构页内选座双视图/抽屉与票卡（留待 7B/7C），未重新打包 APK 或在模拟器/真实学校会话实机安装运行；`mobile/pubspec.lock` 未改动；等待用户审核 7A 后开展 7B。
| 工程优化A | 当前规则/进度入口、模块索引与清理清单已整理；文档检查通过，详情见A节 | 成果222ae74及状态1664bdb已推送；用户继续指令确认通过，进入B；未新增运行时验证 |
| 工程优化B | 模块/变更测试调度与分层规范已实现；本地检查通过，详情见B节 | 成果a215cb7已普通推送到origin/codex/maintenance-stage-b，用户继续指令确认通过，进入C；L3设备、构建/学校验证未运行 |
| 工程优化C | 公共视觉令牌/策略、维护与分段控件、页面参数及可执行规范已完成；对应回归、直取与合成预览通过 | eca3e55、41c26d3已推送至codex/maintenance-stage-c，用户继续指令确认通过，进入D；真机/学校验证不由本轮补齐 |
| 工程优化D | 业务配置、原子文件操作及课堂连接/导入/播放准备公共入口已完成；受影响模块检查通过，详情见D节 | 938f108、6de667e、f756644及状态8fe2a4f已推送；用户继续指令确认通过，进入E |
| 工程优化E | 旧Flutter/Java原型与关联清理，运行时资产迁移，文档按职责归并；分项检查通过 | 697de30、fdbbe82、d025f08及状态6c37980已推送；用户继续确认通过，进入F，未新增构建/设备/学校验证 |
| 工程优化F | 分层CI、精确双包构建/核验、五条复用调试场景已实现；本地及分项远端证据见F节 | e2b39fd、0c35317、d756fed、f0c449c已推送；2026-11-16用户明确审核通过，A–F全部完成审核；主线集成见下节，main保护模板未应用，未发布/安装或新增学校验证 |

## 2026-11-20 图书馆座位预约真实验收

- 用户授权在 Android 模拟器中创建、查询并取消测试预约。基线 `75c59bf`，沿用已认证官方会话，确认测试周的有效预约列表为空。选择次日上午的 30 分钟最短时段，每轮只提交一次且在上轮确认取消后才创建下一笔。
- 第一轮原生预约获学校接受并返回预约编号。原生自动回查和手动查单均失败。官方预约管理查到唯一一条座位及时段相符的记录，取消后显示「暂无预约」。第二轮的匿名结构诊断表明非空记录起止时间使用带时区的 ISO 字符串。读桥接统一换算为北京时间，取消预检按绝对时间比对，同时兼容原有本地时间字符串和毫秒时间戳。
- 第二轮原生「我的预约」与同次提交相符，显示一条待生效、审核通过的记录。学校拒绝首次原生取消。复核官方移动版及桌面版请求包装器后确认，`POST /ic-web/reserve/delete` 将 UUID 放入 JSON 请求体。修正后重新查单，核对唯一记录与确认框的座位、时段和编号，再提交一次取消。学校接受，应用显示「取消已核对」，自动回查和手动刷新均显示「暂无座位预约」，官方预约管理也显示「暂无预约」。两笔测试均已清理。[官方移动版脚本](https://kjyy.bucm.edu.cn/js/mobile_1791875373286.js)
- `node --test tests/library-seat-read-test.cjs tests/library-seat-write-test.cjs` 的 16 项合成用例通过，涵盖跨日时区换算、时段不匹配时零写入和取消 JSON 请求体。最终复测包基于 `75c59bf` 与本节修复工作区构建，普通包名 debug 0.3/code12，验签通过，APK 与设备端 SHA-256 均为 `34F7474CFAEA90270198070C3A90D0B7C8029A7FAB644A8C753C442970B641D7`。提交后的自动确认由合成测试覆盖，最终包的真实查单从「我的预约」入口复核。

## 2026-11-20 图书馆座位预约原生取消

- 基线 `550fa77`。核对官网公开发布的个人预约列表脚本和请求模块。取消控件检查预约归属及生效、结束状态，确认后调用 `POST /ic-web/reserve/delete`。UUID 的请求格式经后续真实验收修正，见上节。提前结束与签离走独立操作。
- 原生确认显示区域、座位、预约编号、起止时间和释放影响。确认后在同源 WebView 重新读取当前账号和原筛选页，匹配编号、归属、座位和时段，应用对已到起始时间或不具备已知可取消状态的记录停在预检。UUID 留在 WebView 内。收到学校接受响应后刷新预约列表，仅在完整筛选结果内确认原单已移除。响应丢失时提示查单，并抑制同会话重复操作。
- 静态分析通过，Flutter 定向 35 项及图书馆读写脚本 14 项均通过。合成用例覆盖取消确认、归属和时段变化、重复点击、超过可取消时间、认证失效和响应丢失。真实学校的有单、写入和取消样本仍待本人确认。
- 从 `550fa77` 和本阶段工作区构建普通包名 debug APK（0.3/code12），验签通过，SHA-256 为 `EB2CE7EF7C435A12FF71989C8AAC959E272E41D39F348094A896DD3A337CF7D9`。核对 APK 包内写入脚本与源码一致。Pixel 8 API 36 启动时 ADB 一度断开，恢复后重新安装并核对设备 APK 摘要。设置入口和原生「我的预约」可打开，未认证时显示登录提示。取消确认对话框的证据来自合成组件测试。

## 2026-11-20 图书馆座位预约原生预约确认与结果核对

- 基于公开 `kjyy.bucm.edu.cn` 前端脚本与公开配置接口核实提交流程：移动版选座图（`chunk-a8895e30`）点击座位仅选中并跳转，不触发锁座，`freeUseSeatLockTime` 公开配置为 `'0'`；移动提交页（`chunk-2ddf8094`）确认后发出单次 `POST /ic-web/reserve` JSON（`sysKind: 8`、`memberKind: 1`、`resvProperty: 0`、`resvDev: [devId]`，`appAccNo` 与 `resvMember` 取自同源 `/ic-web/auth/userInfo`），并由 `ResearchInfo` 展示 `openTimes`、`minResvTime`/`maxResvTime`、`earliestResvTime`/`latestResvTime`、`cancelTime` 与 `limit` 规则。公开接口 `/ic-web/sysConfig/public` 返回 `resvCode: '0'`、`needToKnow: ''`、`resvTheme: '1'`、`resvthememust: null`、`classKindMemoRequired: '0'`、`resvTimeUnit: '10'`，规则中文文案对照 `/ic-web/Language/getLanList` 核实。
- 实现阶段 5 原生确认与单次提交回查：[library-seat-read.js](../assets/library-seat-read.js) 补充数值规则字段（仅 `resvRule` 白名单）；新增独立单次写入桥接 [library-seat-write.js](../assets/library-seat-write.js)，仅在固定 `https://kjyy.bucm.edu.cn/config/config.js` 顶层文档执行，先请求 `/ic-web/sysConfig/public` 与 `/ic-web/auth/userInfo`（启用验证码/须知/必填主题或备注时 fail-closed 返回网页办理且零 POST；身份标识别留在 JS 局部并从返回消息剥离），最多发送一次 `POST /ic-web/reserve` 且禁止自动重试。[library_seats.dart](../mobile/lib/domain/library_seats.dart)、[library_seat_reader.dart](../mobile/lib/platform/library_seat_reader.dart)、[library_seat_queries.dart](../mobile/lib/application/library_seat_queries.dart) 与 [library_seat_query_page.dart](../mobile/lib/ui/library_seat_query_page.dart) 实现候选横幅规则、滚动确认对话框（本地当天过去时段与时长拦截、防双击保护）、提交前实时余位复核、提交后立即回查“我的预约”及 8 类结果卡片（含认证中断后不自动重发与结果不明查单提示）。
- 执行 `python scripts/prepare_flutter.py` 与 `python scripts/check.py --all` 全部通过（报告 `build/checks/report-338b37ae19174a0dbe0d1cde7f3be73d.json`）：`docs` 194 个本地目标、`tooling` 37 项、`icons` 与合成示例、`java` 5 组、`node` 11 组（含 `library-seat-read-test.cjs` 6 项与新增 [library-seat-write-test.cjs](../tests/library-seat-write-test.cjs) 5 项）、`flutter analyze` 0 问题、Flutter 默认 323 项通过 / 9 项条件跳过（[library_seat_queries_test.dart](../mobile/test/library_seat_queries_test.dart) 16 项覆盖规则解码/拦截、重复点击单写、余位变化、学校拒绝、需网页办理、认证中断后重登零自动重发、超时不明转查单、320px/2.0x/深色确认对话框）、直取专项 23 项通过；恢复并 `--enforce-lockfile` 验证 `mobile/pubspec.lock` 未被篡改。
- 构建普通包名（`cn.bucm.campus_schedule`，版本 `0.3` / `code 12`）Debug APK，SHA-256 为 `B66961E9C11BD73DB7576E79EB0F5EB4D41B665374DAF6C411454AC8AA60C266`，保留数据覆盖安装到 `Pixel_8_API_36` 并核对设备端 `base.apk` 摘要一致。
- 2026-11-20 00:25–00:28（北京时间）完成模拟器只读确认对话框核对：隔日空闲后旧 IC 会话失效提示“需要登录学校账号”，点击“打开学校页面登录”后原 CAS 会话自动续签回到预约首页；返回应用后成功读取 `图书馆二层 · 二层北区` `2026-11-20 08:30–22:00`（`共 282 个座位 · 空闲 279 · 半空闲 3 · 使用中 0 · 不可用 0`）。选中 `2N001` 并打开“确认预约座位”对话框，实测展示区域、座位、日期、时段及学校真实规则（`当日开放：08:30–22:00`、`允许时长：最短 30 分钟 · 最长 1 天`、`提前预约范围：最多提前 1 天`、`签到提示：预约生效后 30 分钟 内未签到即视作违约 1 次，预约不再保留`），核对无溢出后点击“取消”，未发送任何写入请求。
- 当前限制与待验：未在未获用户对真实目标座位与时段的明确确认前发出真实 `POST /ic-web/reserve`，**真实预约写入与非空个人预约回查**待用户提供明确实际需求后手动实测；真实“退出学校会话”清理需本人同意；原生取消预约属阶段 6，图形化座位图留待功能验收后优化。

## 2026-11-19 图书馆座位预约原生选座与查单

- 基于公开 `kjyy.bucm.edu.cn` 前端脚本核实查询与展示规则：PC 与移动版均按 `(devProp & 2) > 0 || onlyView === true` 筛选可见座位并按 `devSn` 升序排序（解释此前二层北区多出的 6 条设备记录），同时排除 `resvStatus & 128` 已结束预约，解析字符串与毫秒时间戳，并按官方 `resvStatus` 位掩码（`2` 待生效、`4` 生效中、`16` 违约、`64` 已签到、`128` 已结束、`256` 待审核、`512` 审核未通过、`1024` 审核通过、`2048` 暂离中、`4096` 已签离）解码个人预约状态。
- 实现阶段 4 原生只读选座与查单分层（[library-seat-read.js](../assets/library-seat-read.js)、[library_seats.dart](../mobile/lib/domain/library_seats.dart)、[library_seat_reader.dart](../mobile/lib/platform/library_seat_reader.dart)、[library_seat_queries.dart](../mobile/lib/application/library_seat_queries.dart)、[library_seat_query_page.dart](../mobile/lib/ui/library_seat_query_page.dart)），WebView 桥接脚本在出错时自动重置并严格剔除预约人身份字段，将 [library-seat-read-test.cjs](../tests/library-seat-read-test.cjs) 与 [library_seat_queries_test.dart](../mobile/test/library_seat_queries_test.dart) 登记到 `adapter` 与 `ui` 检查模块。
- 执行 `python scripts/prepare_flutter.py` 与 `python scripts/check.py --all` 全部通过（报告 `build/checks/report-9080c7dee8454abcbc5afdfdcd0d990d.json`）：`docs` 186 个本地文件目标、`tooling` 37 项、`icons` 与合成示例、`java` 5 组、`node` 10 组（含 `library-seat-read-test.cjs` 6 项）、`flutter analyze` 0 问题、Flutter 默认 318 项通过 / 9 项条件跳过、直取专项 23 项通过（合成覆盖空列表、半空闲/使用中/不开放/仅查看、失败重连、会话过期、退出/清除后迟到响应隔离、浅深色、320px 窄屏、1.5x/2.0x 大字号、高对比度与减少动画）。
- 构建普通包名（`cn.bucm.campus_schedule`，版本 `0.3` / `code 12`）Debug APK，SHA-256 为 `3383F18FB57225565C2A943B70367A680F66F54E191F10C9C8EAAADEC07B4B8D`，在 `Pixel_8_API_36` 模拟器保留数据安装并核对设备端 `base.apk` 摘要一致。
- 2026-11-19 23:46–23:51（北京时间）复用本人在可见官方页面完成的统一身份认证会话完成模拟器实机核对：`/ic-web/seatMenu` 返回 2 至 5 层全部 16 个可选区域；二层北区 `2026-11-19 08:30–22:00` 为 `共 282 个座位 · 空闲 282 · 半空闲 0 · 使用中 0 · 不可用 0`（对应官方页 `282/282`）；`2026-11-20 08:30–22:00`（`明天`）为 `共 282 个座位 · 空闲 280 · 半空闲 2 · 使用中 0 · 不可用 0`，与官方移动版同日期同时间段座位分布图逐一吻合（280 空闲、2 半空闲、0 使用中、0 不开放）；选中 `2N001` 显示“已选候选座位”横幅并支持“清除选择”，`仅看空闲` 筛选可切换恢复；`我的预约`（`2026-11-16 至 2026-11-22`）显示 `第 1 页 · 共 0 条` / `暂无座位预约`，与官方 `预约管理` 的“暂无预约”一致。
- 当前限制与待验：非空个人预约实测留待阶段 5 有真实预约时补验；真实“退出学校会话”会清除课堂本地目录与续播进度，需本人同意后验证；提交预约写入与确认流留待阶段 5，取消预约留待阶段 6，图形化座位分布图不在当前范围。

## 2026-11-19 图书馆座位预约同源查询验证

- 源码基线为 `a14c489`。查阅学校图书馆公开入口及站点检索结果，未找到公开的座位预约开发者接口文档。本次使用本人此前在 Ego Browser 完成认证的官方预约页面。先观察官网实际发出的查询，再在相同页面独立发送同源 GET。
- 2026-11-19 22:04–22:05（北京时间）核对二层北区。查询为 `GET /ic-web/reserve`，参数 `roomIds`、`resvDates`、`sysKind`。页面样本为 2026-11-20 08:30–22:00，区域 `32`、业务类型 `8`。查询按日返回，起止时间只用于本次状态核对。响应 HTTP 200、业务码 0，`data` 有 288 条设备记录。以 `devName` 对照网页座位标题首行，282 个可见座位均能匹配。280 个空闲座位与所选时段没有预约重叠，2 个半空闲座位有部分重叠。另有 6 条设备记录无对应网页标记，现有开放状态和坐标字段不足以解释，需核实后才能纳入可选座位。完全占用、不开放及仅查看状态未取得实测样本。
- 本人预约使用 `GET /ic-web/reserve/resvInfo`，查询参数为 `beginDate`、`endDate`、`needStatus`、`page`、`pageNum`、`orderKey`、`orderModel`。同会话复查官网筛选区间 2026-11-16 至 2026-11-22 的第 1 页，HTTP 200、业务码 0，`data` 与 `count` 均对应 0 条，官网显示“暂无数据”。同一查询省略 Cookie 时返回 HTTP 200、业务码 300 和登录提示。真实会话自然过期、非空预约、分页完整性及 Android WebView 取数仍待验证。
- 座位响应中的 `resvInfo` 可包含预约人身份字段。后续适配器应在 WebView 内按白名单提取业务字段，座位可用性只需座位标识和时段信息。本次仅记录字段名和聚合结果。阶段 3 只读核对结束，实际提交、取消和原生界面留待后续阶段。

## 2026-11-19 图书馆座位预约 Android 接入

- 设置 → 校园服务 → 图书馆座位预约，打开可见的官方WebView。预约站点和学校CAS使用独立的HTTPS主文档校验。页面退出时销毁WebView，认证沿用本机官方WebView会话和现有“退出学校会话”入口。
- Flutter静态分析通过，预约URL边界、既有课堂URL策略与设置页共17项定向合成检查通过。文档和工具检查通过，涵盖37项工具回归。测试注册表导致变更预选扩展为全量，日常验证按预约导航、设置、既有边界和注册表的实际改动范围定向执行。
- 以 `664ea18` 为基线的含未提交改动源码构建普通包名debug APK，版本0.3/code12，签名校验通过。SHA-256 为 `81c7fd4cc96d55e9911bcab67edb28bc241d8d8d3ab70f6ca9faa6aa7ed27329`。在Pixel 8 API 36模拟器中保留数据安装，验证从设置入口打开预约页并显示官方统一身份认证的扫码、账号和手机登录选项。
- 本人在模拟器官方页面完成认证，同一WebView回到移动版预约首页。按“座位 → 图书馆二层 → 二层北区”打开选座页，确认起止时间控件与空闲、半空闲、使用中图例。底栏“预约管理”可打开，样本显示“暂无预约”。
- 官方移动页的“首页”可从个人中心回到预约首页。二层北区和预约管理两处按Android系统返回均直接回到App设置。离开后重开入口回到官方预约首页并继续使用有效会话。真实会话清理需本人同意后验证，预约写入与取消属于后续验收。

## 2026-11-19 图书馆座位预约只读验证

源码基线为 `96213b2`。使用桌面 Ego Browser，由本人在官方页面完成统一身份认证。本次核对网页可达性、可见控件和字段。

| 步骤 | 本次证据 | 待验 |
|---|---|---|
| 进入学校平台 | [预约首页](https://kjyy.bucm.edu.cn/#/ic/home)跳转至 `https://cas.bucm.edu.cn`。认证页提供企业微信扫码、账号和手机入口。本人完成认证后回到预约首页 | Android的可见认证、有效会话复用、退出隔离及必要的扫码跳转 |
| 选楼层和区域 | 座位预约菜单展示二至五层。展开二层后，选择二层北区进入官方座位页 | 其他区域入口、移动视口中的选座可用性 |
| 核对选座控件 | 二层北区样本显示日期、开始时间和结束时间，座位图图例包括空闲中、半空闲、使用中、不开放和网站不开放但可查看。页面显示该区域开放时间为周一至周日08:30–22:00 | 实际可订日期、放号、时长限制、签到、取消期限与确认步骤需核实。点击座位是否会立即影响库存尚未确认，本次止于座位图 |
| 回查预约 | 个人中心的“个人预约”支持日期区间及多状态筛选，列表包含预约编号、预约对象、预约时间与状态。本次只核对界面和字段 | 实际订单的显示、取消入口及状态变化 |

Android构建及设备验证在后续阶段开展，真实预约和取消在本人有实际需求时手动验收。

## 2026-11-16 主线集成

- 用户明确授权“把当前进度合入main”。集成范围为已审核A–F、长期管理规范及审核记录；从main 580eac985d7dfab9da1ed00d720792e1bcfc33f5到候选e3712d1886e02a6001310a6ad193cbfb5352de82为23个提交，main为其祖先，核对时工作区干净。
- 候选精确[Actions 43791865438](https://github.com/zhihaorao8-web/bucm-campus-prototype/actions/runs/43791865438)成功：quality通过，dual-preview按工作分支规则跳过。最终候选7278b5a的PR检查43792842193成功，经[PR #1](https://github.com/zhihaorao8-web/bucm-campus-prototype/pull/1)合入6380b25a34a0ab53e229e62d8f31cab96fcd729f，保留阶段提交历史。本地main已快进同步，核对合入树与候选一致、工作区干净。
- 合入提交的[Actions 43793288471](https://github.com/zhihaorao8-web/bucm-campus-prototype/actions/runs/43793288471)全量quality通过：工具35项、静态分析、Flutter305项/9跳过及显式直取23项。debug、release均编译成功，但dual-preview在签名输出解析时报错，未上传双包；不能将编译通过写成完整核验成功。
- 本次同步集成文档仅运行文档及差异检查；不改版本、标签/发布附件或远端保护，不访问学校或安装设备。应用仍0.3/code12，既有设备/学校验证缺口保留。

## 2026-11-16 集成签名核验修复

- 用户继续确认排查。在6380b25基础上建立codex/fix-ci-apk-identity；按runner镜像清单定位37.0.0，并从Android官方下载、校验SDK压缩包，在忽略的工作区复现：相同0c35317双包用35/36读取成功，37的证书前缀由Signer #1变为V2 Signer:，旧正则因此失败。包名和源码资源读取正常，未据笼统报错推断证书损坏或更换签名。
- 核验器兼容这两种单证书格式，要求Number of signers=1及唯一证书摘要；重复/额外/未知证书、轮换格式、公钥或Source Stamp替代均拒绝，实际apksigner非零退出仍直接失败。补充真实格式的合成拒绝边界与命令失败回归，同步双包文档。
- 修复源码4e5bbde已提交推送，提交前docs/tooling检查通过（37项Python、图标/合成样本及180个本地文档目标）。37工具对既有0c35317双包完整核验通过，报告build/checks/sdk37-full-apk-recheck.json；35/36对两包身份/签名读取通过。这不是修复分支新构建，也不是新的设备/学校/发布验收。首次复核误指只含部分引擎的缓存而失败，改用实际完整缓存后通过，未放宽引擎校验。
- 修复集成在[PR #2](https://github.com/zhihaorao8-web/bucm-campus-prototype/pull/2)跟踪，最终合入SHA、候选检查及主线双包核验/上传结果以该PR的精确提交记录为准；原6380b25失败保留，不因本地复核通过改写为远端通过。

## 2026-11-16 长期项目管理规范

- 用户要求将本轮方法作为后续开发必须遵守的规则。在264ebdb基础上建立codex/project-management，仅新增[PROJECT_MANAGEMENT](PROJECT_MANAGEMENT.md)并同步AGENTS开工/阶段要求、README/开发入口、生效需求、维护台账及PR检查项。规范覆盖范围/现状核对、复用与配置集中、分项检查提交推送、阶段审核、分层测试/具名调试、文档证据维护和分支/构建/发布分工；具体标准引用现有唯一入口，不复制整套内容。
- 长期规范3968e8a已推送；该提交时F尚待审核，后续明确确认见F节。文档检查180个本地文件目标通过，差异检查通过；变更计划确认9项均为Markdown且仅选择文档检查，AGENTS/README/开发入口/PR模板均已链接长期规范。未运行应用全量、构建或设备/学校验证。

## 2026-11-16 工程优化F分项

- 用户继续确认E通过，从6c37980创建codex/maintenance-stage-f。F1实现工作分支/PR变更检查、main/发布候选全量及独立双包预览；显式dispatch分changed/full/preview。固定source/base SHA、所需工具和计划，执行复用check.Runner，失败报告保留退出码，CI归一化锁源不改变已选范围。
- F1最终22项Python工具回归、文档目标/图标/合成示例检查通过；YAML本地解析及外部Action精确SHA核对通过，日志build/checks/stage-f1-verified-tests.log。初次新增夹具将临时目录字符串当Path导致工具测试报错，已修正并完整重跑；未把初次失败计为通过。未运行新的应用构建/设备/学校验证，远端Actions状态在推送后另核对。
- F1成果e2b39fd已推送；精确SHA的[Actions 43785658318](https://github.com/zhihaorao8-web/bucm-campus-prototype/actions/runs/43785658318)成功，quality通过、dual-preview按工作分支规则跳过，未构建APK。不能沿用该结果为后续F2/F3提交通过。
- 公开GitHub API只读核对main=580eac9、protected=false、rulesets=[]；CLI无登录且连接器无保护接口，未读取凭据。已提供main保护JSON模板及职责规范，未应用远端设置，不声称主分支已受服务器规则保护。当前不创建标签/发布或合入main。

- F2实现只读双包核验与顺序构建门禁：精确源码/版本/签名/模式、资源与许可、ZIP及已知测试载荷；以固定引擎可执行段区别profile，保留符号剥离兼容。预览/发布候选分开，后者还要求干净源码、可信证书及精确SHA的完整CI成功；不发布/安装或跳过检查。
- F2初轮只读0.3双包核验发现Android已剥离引擎符号、Gradle SHA1目录省略前导0，按实际结构修正并补合成检查后，现存729663f双包身份/签名/资源/引擎核验通过（build/checks/stage-f2-historical-apks.json）。这是旧包对新工具的实证，不是新分支构建或新的release/学校验收。构建失败/无新APK两项PowerShell隔离检查及7项核验边界检查通过；初次夹具输出编码问题已显式UTF8处理，不计首次通过。新分支双包实测见下项。
- F2成果0c35317已推送；31项工具/文档/图标检查通过（report-2533354b237b4cf0bb154729919ccda7.json）。随后从干净0c353174e465e8428f976bbd99811efc744439c8顺序构建debug/release并完整核验通过，两包嵌入同一干净SHA、0.3/code12及既有可信证书；未安装/发布。debug为221496120字节、SHA256 361a936ddb731e023a8b345681878da0d0ee08ab8ea3b5eee545acc7114244ff；release为64808486字节、SHA256 144a05d51b75a155967226d4f01641f81b7ae51af5ba4fcc0999d933fbb66c93。
- 本轮预览在build/flutter-previews/0c353174-6e7d78a3c0c2423a97ea44f37dd137be/，同目录有元数据/校验文件；详细日志在build/flutter-preview-logs/0c353174-*-{debug,release}.log及build/checks/stage-f2-preview.log。kind=preview，CI字段null，不冒充发布候选验证；未重跑设备R8/原生媒体/学校链路，不替换旧0.3附件。

- F3在原check.py加入--flow，复用同一个计划/Runner/报告，不新增设备或登录入口。五条实际场景全部通过：schedule-import默认17项；classroom-import默认41项/6跳过＋直取23项；auth-recovery默认52项＋直取23项；playback-resume默认39项/1跳过；storage-recovery默认47项。各自静态分析及选定Java/Node通过；不是跨场景去重后的独立总数，不冒充全量或真实认证/解码。
- F3工具35项、文档/图标/合成示例检查通过（report-93ee144824ed4c539ad41b89ded9ba5f.json）；五条日志为build/checks/stage-f3-<flow>.log，报告分别81f1a81cc334499ebd4e31a29554af2f、55663ddacc7e452bab283c426f45cd93、8826cd08e4e54a94b313b96c26a6b41b、acbc0322c9804aa2be8278a3442fad2e、8b6795b9d916464694b9e54770dffb8d。发布/公共接口仍用--all或--changed复核影响，调试场景不替代必要验收。

- F3成果d756fed已推送。收尾将摘要读取改为Python3.10兼容的分块计算，并严格限定历史目录API路径回退，不放宽摘要/资源校验；35项工具、文档/图标/示例检查与0c35317双包只读复核通过（report-9a8137923bd24986b14374528237dabe.json、stage-f-final-apk-recheck.json）。所有Python脚本以3.10语法解析通过，实际运行解释器为3.12，未宣称已用3.10解释器实跑。

- 收尾成果f0c449ceeb17298a4427cc31c158a7b7832b7b41已推送，精确[Actions 43788910849](https://github.com/zhihaorao8-web/bucm-campus-prototype/actions/runs/43788910849)的quality成功、dual-preview按工作分支规则跳过。已读取完整任务日志：35项工具、分析无问题、默认Flutter305项通过/9跳过，显式直取23项通过；本轮跨模块/工具改动保守全量，未以F1旧CI替代。已知87b096f的真实x64 profile APK另被新核验器正确拒作release（stage-f-profile-rejection.txt）。
- F阶段代码/文档完成后按约定停止；2026-11-16用户明确表示“f阶段审核通过”，本轮A–F全部完成审核。此次仅同步审核记录，文档180个本地文件目标及差异检查通过，不重跑应用全量或重建APK。main保护JSON未应用，新版远端双包任务本轮未触发；本机0c35317双包证明顺序构建/包核验，不作为设备或发布验证。版本仍0.3/code12，未合入main、改既有标签/附件或安装设备。

## 2026-11-16 工程优化E分项

- 用户继续确认D通过，从8fe2a4f创建codex/maintenance-stage-e；只清理已核对引用的旧实现及重复文档，保留7个Java共享核心与有效协作/安全/组件规则。
- E1删除无主应用入口的ClassroomBrowser，将小屏大字手动访问/离页后迟到探测断言迁到当前课堂恢复页；保留纯探测测试。删除无读取调用的ClassroomLinks及专用测试，当前页停止无用写入/注入/保存错误提示。旧关联不读取或迁移，在显式清除学校会话/目录时连同pending删除；合成测试确认课表/外观保留。
- E1最终`--module classroom --module storage --direct`通过：静态分析、138项Flutter/7项条件跳过、直取23项、4组Node；工具调度15项通过。报告build/checks/report-1e76d7aa6f9149b29a1a3f91816b5e0e.json，日志stage-e1-passed-tests.log。初次分析发现遗漏的旧注入参数已移除；迁移测试最初沿用旧按钮/未滚动到可点击区域失败，修正夹具后单项及组合通过，失败日志/报告保留，不算首次通过。未访问学校或设备。
- E1成果697de30已提交推送。E2将JDK定位迁到scripts/java_tools.py，删除根旧Java页面/提醒接收器、build.py及专用res；根Manifest只留原版本元数据，实际Flutter宿主Manifest/包名/权限未改。保留7个共享核心；recording-api.cjs原样迁至assets，prepare、Node引用及变更选择同步更新。
- E2无参数旧离线检查（5组Java、9组Node、图标/示例）通过；docs/tooling含15项工具回归通过，报告report-80dea98dd19f4ca1aac7e761c3b4cf50.json、report-9dd351e9f0514e11bf613fe0a4ba410e.json；日志stage-e2-host.log、stage-e2-tooling.log。prepare执行通过，7个Java/8个Flutter脚本副本逐字节一致，目录API迁移前后内容一致，根版本仍0.3/code12、pubspec 0.3.0+12。未构建APK，不以复制核对替代R8/设备/学校验证。
- E2成果fdbbe82已推送。E3删除20份旧接续/专项/重复历史文档，新增CLASSROOM、PLAYER及UI_VALIDATION三个职责入口；受控Markdown从51份减至34份，正文约4260行收敛至1800行以内。STATUS按链路归并，保留真实成功/失败、构建归属、14个关键APK摘要及验收缺口；旧过程可查Git历史，不另复制失效档案。
- E3修正单来源关联、目录“未接入”、已中断B组“时间未到”、双包“仅计划”及旧原型“仍构建”等过期描述；保留原始需求/设计提示词、有效协作/组件/发布规则及许可，提取用户地点编码来源。发布说明只修复一处文档链接，不改历史结果、标签或附件。
- E3 docs/tooling（15项）及图标/合成示例检查通过，最终155个本地文档目标通过，报告build/checks/report-0a6c4fbb0efe4d2c848b2c06dda96773.json；14个APK摘要均与旧STATUS/验收原文一致，原始需求文件逐字未改，本地唯一Markdown标题锚点已核对。文档删除去向与统计仅存忽略的build/checks/stage-e3-doc-map.json、stage-e3-doc-audit.json；未校验远程链接。最终文档差异检查通过，不为纯文档重跑应用全量。
- E3成果d025f08已普通推送到origin/codex/maintenance-stage-e。E阶段完成并停止供用户审核，F未开始；版本保持0.3/code12，不合入main、不改标签/发布附件，设备/学校验证缺口保留。

## 2026-11-16 工程优化D分项

- 用户继续指令确认C通过，从3e7ab69创建codex/maintenance-stage-d。保持0.3/code12、存储格式/键、官方认证与按用途域名校验；不新增业务模块。
- D1：按职责集中StoragePolicy、ClassroomLimits、PlaybackPolicy、网络入口/探测/导入/语录策略及资源/通道/编译开关；模型与会话共用续播有效位置判断。现有数值、文件名、原始资源与通道字符串保持兼容；Java/JS独立安全校验不合并，跨语言协议仍各自校验。
- D1静态分析无问题；15个相关文件106项回归、直取专项23项通过。日志build/checks/stage-d1-analyze.log、stage-d1-tests.log及stage-d1-direct.log。D1成果938f108已提交推送。

- D2：applicationFile统一应用私有文件定位；writeAtomicText统一pending/flush/rename/finally清理，提交前同步canCommit检查阻止旧账号写回。五类存储保留各自队列、schema、备份/损坏恢复和revision，未引入全局写队列或路径迁移。
- D2 storage模块静态分析及47项回归通过（含新增5项原子文件成功、失败、取消与清理检查），工具调度15项回归通过；报告build/checks/report-9e11e98c97ce44bb90055b95adb6fc79.json，日志stage-d2-tests.log。D2成果6de667e已独立提交推送。

- D3：ClassroomConnectionCoordinator拥有连接代次、路由选择与读轮询；ClassroomImportCoordinator复用完整来源集合与API读取，统一revision约束的整组提交；ClassroomPageScripts统一脚本资产、命令及容量/超时校验；ClassroomPlaybackPreparation负责begin/play/prepare、固定错误文案及移交前原生会话释放。课堂页保留WebView、导航/认证展示、来源恢复、队列切换和播放器路由，不宣称整个页面状态机已迁出。
- D3新增12项合成边界测试，覆盖迟到路由、官方认证可达、取消轮询、部分来源/保存失败保留旧目录、账号revision、直取取消及播放会话移交/释放。已登记到独立classroom/player模块；工具测试不再硬编码player测试文件数。
- `python scripts/check.py --module classroom --module player --direct`通过：静态分析无问题；27个Flutter测试文件161项通过、8项条件跳过，显式直取23项通过；1组Java及5组Node通过。报告build/checks/report-d51b5eca27284eb3b135871a224e1916.json，日志stage-d3-tests.log；测试调度自身15项另行通过。最初分析误从仓库根目录启动，已结束该次进程并在mobile重跑通过；该次未完成的分析不作为通过证据。
- 最终补齐提交回调返回页面时的mounted检查后，静态分析及名称合并/协调器14项回归通过（stage-d3-final-analyze.log、stage-d3-final-import.log）。文档214个本地文件目标及差异检查通过；页内锚点/远程链接未校验。
- D3成果f756644已普通推送到origin/codex/maintenance-stage-d。D阶段完成并停止供用户审核，不进入E。未改版本、认证策略、原生/JS安全校验、CI或发布附件；未构建/安装APK或访问真实学校会话。

## 2026-11-15 工程优化C分项

- 用户继续指令确认B通过；从b65bd51创建codex/maintenance-stage-c。本阶段统一视觉参数、组件复用与交互规范，版本与学校业务边界不变。
- C1共享策略：新增design/app_tokens.dart及AppVisualPolicy，焦点/列表/密集/抽屉材质统一降级判断；主/课程/设置顶栏共用滚动雾化；导航、详情/播放路由、周日/周次、标题时长集中。保留底栏关闭玻璃高光后仍可普通模糊的现有独立行为。
- C1静态分析通过；11个相关UI/手势测试文件81项通过、2项条件跳过，含新增浅深色偏好/无障碍材质切换矩阵。日志build/checks/stage-c1-analyze.log及stage-c1-tests.log。分项eca3e55已提交推送。

- C2固定配色集中到AppPalette（含默认/可选强调色、课程和环境光），页面使用主题字阶、间距与圆角令牌；AppActionButton复用4个维护/恢复动作并补齐48dp最小高度，AppSegmentIndicator复用周日和课堂切换几何/时长。busy下保留打开学校页的显式恢复动作；业务取数/权限策略未改动。
- C2跨模块ui/schedule/player/classroom检查中，Java4组/Node5组及分析通过，45个Flutter文件中272项通过/9条件跳过，新增忙碌态测试因pumpAndSettle等待持续进度动画超时。只将夹具改为有界pump，组件/外观19项通过/1条件跳过；该轮未执行的直取专项另跑23项通过。失败报告report-25103503f6e749d4874cba3074f94146.json保留，不将原报告写成整体通过。
- C2最终分析无问题；现有CAPTURE_PREVIEW检查15项通过（含完整合成页面/动效采样和课堂浅深色预览）。已目检今日/课堂浅深色、周表/日视图/冲突大字，以及减少动画/关闭玻璃/高对比度共12张代表图，未见本次迁移导致的溢出、遮挡或材质回退丢失。截图/拼图仅在忽略的dist/flutter-preview下，不提交，不作为设备性能证据。
- 相关日志：build/checks/stage-c2-tests.log、stage-c2-final-analyze.log、stage-c2-target-tests.log、stage-c2-direct-tests.log、stage-c-preview.log。设计规范已改为入口/组件/状态/降级/验收表；AGENTS及架构索引同步引用。文档链接213项通过，页内锚点/远程链接不在该检查范围。
- C2成果41c26d3已提交并普通推送；C阶段完成，当前停止供用户审核。最终文档/差异检查通过；本阶段未改Android宿主、依赖锁、版本、CI或学校脚本，未构建/安装APK或新增学校会话。

## 2026-11-15 工程优化B检查

- 从已审核A阶段1664bdb建立codex/maintenance-stage-b；只修改检查工具、自身合成回归、测试规范及必要入口文档。应用/原生业务、版本、依赖锁和CI工作流未改动。
- check.py保留无参数旧离线行为，新增8个模块、组合去重、merge-base及工作区变更选择、dry-run、显式直取配置、独立JSON报告和失败即停。Dart按import/export/part传递依赖选择，未知/删除/共享配置保守扩大；新增/删除未登记测试直接报错。
- 无参数检查通过：图标/示例、5组Java、9组Node，未调用Flutter；报告build/checks/report-e5685ab84931460eb8975ca44fea52be.json。
- --all通过：文档链接、工具自身14项（当时数量）、图标/示例、5组Java/9组Node、flutter analyze零问题、48个Flutter文件默认285项通过/9项条件跳过、直取专项23项通过。普通预览文件已排除，故比旧默认集合少1项预览跳过，不代表减少业务覆盖。报告build/checks/report-c489d45bc9df4443a8b4fea71e29a49c.json，详细输出stage-b-all.log；均在忽略的build/checks内。
- 全量后补充空变更/工具无需SDK、未知Java回退、分叉base及暂存文件边界，最终15项工具回归通过；docs/tooling组合命令通过。全部8个模块dry-run通过，实际工作区--changed --base HEAD选择48文件及直取专项，dry-run未写报告。
- 最终独立player模块通过：1组Java媒体传输、1组Node播放准备、分析及8个Flutter文件64项通过/1项条件跳过；没有XLS依赖编译或目录测试。报告build/checks/report-f7e66d0324354c70bfc83339e10ed6d5.json。
- 初次沙箱--all在Flutter分析前因VM resolved_executable_name参数启动失败，报告保留failed（report-50b29dd5c74547d7a155988e2b8de9dd.json）；正常本机环境重跑后通过。不把该启动失败当业务测试失败或首次通过。
- Git差异/文档链接检查在同步前执行；本阶段不构建/安装APK，不运行L3设备专项、预览或学校会话。CI分流留到F阶段，远端本次CI结果不作为上述本地通过的依据。
- 成果提交a215cb7已普通推送，状态记录另随本分支同步；B阶段已由后续继续指令确认通过，转入C。

## 2026-11-15 工程优化A检查

- 文档成果提交222ae74已普通推送，工作分支上游跟踪已建立；该阶段已由随后用户继续指令确认通过。此条是后续状态记录，不改变成果提交、main或版本标签。
- 基于main@580eac9创建codex/maintenance-stage-a；只修改Markdown，应用代码、构建配置、Manifest与pubspec未修改，版本仍0.3/code12。
- 核对仓库Markdown中的201个本地相对文件链接目标，零缺失；检查范围不含远程URL和页内锚点。旧进度页14处失效目标随当前入口重整消除。
- 架构表列出的19个代表测试文件路径全部存在；通过源码/脚本静态核对7个共享Java维护源、prepare列表及原生媒体脚本6项预期用例。
- git diff --check通过；旧浏览页引用与关联存储读写调用核对已形成候选清单，未据此删除代码。
- 本次为文档整理，未运行应用全量回归、原生仪器测试、APK构建、模拟器或学校会话验证。上述历史发布/学校验证缺口不变。

## 历史证据：按链路归并

2026-11-16删除重复接续/旧计划和被后续覆盖的过程性待办；原文仍可从fdbbe82及之前Git历史追溯，不另复制失效档案。下列真实结果只属于所记日期、构建及样本，不能上推为当前维护分支已完成设备/学校验证。发布包摘要/签名/CI以各版发布说明为准。

### 课表与课堂

| 日期/对象 | 实际证据 | 限制 |
|---|---|---|
| 2026-11-09旧Java DOM | 当前周18、全部周次25个非空单元格；25格拆成52段候选，周次/节次与各自原文一致；52段有21项重复、31种原文/星期组合 | 单元格、排课段、课程门数不同；地点标点修正只复验含差异的前27段，不补称全52重测 |
| 2026-11-09官方XLS | 17408字节BIFF/OLE文件；修正附加区域边界后25源项/52段，首段核对通过；自动时间预检/去重后保存31条，重复导入及冷启动仍31条，10条多段/14条晚间，缺时间0 | XLS全部字段未独立逐项核对，旧DOM核对不替代；“无课表课程”只提示，地点/线上与作息的用户来源见COURSE_TIME_RULES |
| 2026-11-10桌面录播 | 本人官方认证后进入现行岐黄智；教师/学生/PPT约2秒实际解码，三份HLS清单200，样本未见加密标签 | 仅桌面短样本；不是Android、直播、长期同步/听音或所有视频无加密的证明 |
| 2026-11-11原生初期 | Android WebVPN样本PPT/教师播放超过1分钟，学生切换及暂停可用；qxkt3修正后首次/缓存/刷新分别推进超过30/19/21秒 | 水印关闭，其他节点、听音及完整课时不外推；源画面无信号不等于解码故障 |
| 2026-11-11导入恢复 | 最终普通debug包R1保留数据、关闭临时诊断并重启后，仅设置入口自动导入24/31课表项、9来源，7项待确认 | 诊断中手动切换的一轮不算无干预证据；另一设备门户复测未完成 |
| 2026-11-11同名多教师 | R2整组导入26/31课表项、11来源、5待确认；同名2来源中8条/0条均显示，有内容来源双画面推进28秒，返回目录 | 空来源不算播放通过；同ID跨来源播放分支为合成证据，非完整学期审计 |
| 2026-11-12直连认证修复 | b30f3da对应R3包保持直连认证；本人关闭系统VPN、保持校园Wi-Fi后真实统一导入13组/31项，10完成/11来源/3未匹配/0失败 | 当轮未独立取得最终文档类别；系统VPN与学校WebVPN不同，不用离线目录充当联网成功 |
| 2026-11-12桌面目录API | cf66690研究及后续相同适配模块取得12课程/13页/85条，逐来源唯一数=total；单门9条业务字段与页面逐项相同，学期列表28条 | 只对照一门；约3.2秒为该次桌面观察，非手机性能承诺；未请求媒体/观看记录 |
| 2026-11-12 Android首轮API | R4已安装摘要一致，本人反馈统一导入成功 | 系统日志没有直取/回退类别，当轮不能认定命中直取或WebVPN通过 |
| 2026-11-13目录直取确认 | R5本人确认校园网，复制白名单诊断：10组保存/3未匹配、11来源/12页/78条，含空来源与10＋6跨页，无回退/错误/丢失 | 只记录聚合，原始JSON不入Git；不是完整学期准确性、认证失效或媒体验收 |
| 2026-11-13官方文档类别 | R6自动selectedDirect；10课程响应/12目录响应均officialContextDirect，仍10组保存/3未匹配、78条 | 不据文档类别推断Wi-Fi或所有跳转。手动WebVPN上游HTTP/80拒绝未解决，真实认证异常未复现 |
| 2026-11-13任务隔离 | eacc754干净源码R7实际安装一致，单课刷新1来源/1页/9条directReady→importSaved，课程12条、响应均direct | 正常取数确认；认证先完成/旧请求迟到等竞态只经合成复现修复，真实异常恢复未测 |
| 2026-11-13节点/就绪/名称修复 | d9db911的R8包，两门qxkt1直连双画面分别00:00→00:27/00:43；fc6d911最终R9包目标括号宽度课程1来源/1页/7条导入、冷启动可读，另一个回放续播推进 | R8两门不虚增为R9逐门重测；页面未发load-stop的确定缺口有修复前失败/修复后6项时序证据，非所有随机超时唯一根因；qxkt1 VPN未观察 |

### 播放、音频与交互

| 日期/构建 | 实际证据 | 限制 |
|---|---|---|
| 2026-11-12 / 92ea6f4、R10 | WebVPN真实双流；暂停时±10秒变化10000ms且仍暂停，全屏显隐/返回先退全屏可用 | 水印关闭；该旧基线关闭短PPT会改变总时长、续播未通过，不因后来修复补写通过 |
| 2026-11-12 / 中间R11 | 时长修复中间包关闭短PPT后共同总长5986494ms保持；退出重开出现14:53续播，恢复约894243ms并推进 | 最终653b526e包的共同末尾停止/重播归4项原生合成检查，不将中间包写为最终包完整真实验收 |
| 2026-11-12原生资源/焦点 | 独立mediatest从3→4→5→6项检查，最终双流实际解码、共同时间轴、单音轨释放恢复、临时焦点暂停/归还和资源释放均通过；测试后重建正常包 | 约60秒本地合成HLS不是学校完整课时，不等于真实来电/耳机/蓝牙/人工听音 |
| 2026-11-12旧模拟器音频 | 本人本机/远程均报告底噪/卡顿/重复；绕过学校和Media3的PCM也异常，同参数Windows WAV清楚；DirectSound仅部分改善，延迟/麦克风设置未解决且已恢复 | 未确定具体根因，启动崩溃/未播放不计有效样本；旧设备不标记已修复 |
| 2026-11-12全新隔离模拟器 | 不复制旧快照/会话，30秒PCM本人确认稳定；正式播放组AAC首次太小未判通过，调音量后再次听音稳定，六项原生回归通过 | 仅新模拟器合成输出，不是另一物理手机或学校长时音频验收 |
| 2026-11-13 / R6 | 本人对短时及约5分钟播放任务反馈正常；重开同条明确出现继续/从头，恢复位置合理；白名单新增3对准备成功约1.388/1.064/1.033秒 | 实际连续时长未独立计量，准备事件不表示持续播放；没有跳转前后值，不补称精确±10秒/完整课时/水印通过 |
| 2026-11-13 / 4e2ba42、R12 | 实际安装摘要一致，本人对竖屏滑动预览/松手、横屏透明显隐、右侧半屏抽屉切换与返回反馈正常 | 横屏滑动未单独口述；精度/持续时长、所有画面/设备/网络仍未验 |
| 2026-11-13 / b538f9b、R13 | 滑块中央时间预览：分析、默认197/8跳过及相关27项、浅深色窄横屏大字预览通过，干净debug包核验 | 该交互当轮无手机安装/体验证据；不能借R12反馈补为新交互实机通过 |

完整课时、全部水印/画面组合、倍速/中断、更多网络设备仍按[验收表](research/PLAYER_ACCEPTANCE.md)留待人工验证；长期会话的旧B组已因11月12日重新认证中断，不能累计到7天，见[会话记录](research/SESSION_LONGEVITY_TEST.md)。学校观看记录未接入。

### UI与发布

- 2026-11-13：caf4b6a干净源码R14本人安装一致，底栏/设置/外观/播放器图标反馈正常；43个SVG及许可/摘要核验、178项默认/8跳过、14项可选检查通过，不外推全部页面/字号。
- 2026-11-13–14：柔光五阶段及审核修订已获用户通过。模拟器profile独有样本与性能边界保存在[UI验证](research/UI_VALIDATION.md)，物理手机功耗/FrameTiming、完整TalkBack/预测返回/反向键盘仍未完成。
- 2026-11-14：e64f85d的B1标题/语录普通debug构建并保留数据安装，模拟器抽查正常、用户明确验收；最终0.3 release另抽查新版课堂页。移除旧字体，不能用早期字体检查描述最终资源。
- 发布0.1/0.2/0.25/0.27/0.3的精确SHA、CI和签名/附件证据归各[发布说明](releases/0.3.md)及[复盘](releases/0.1-retrospective.md)，不重写标签/附件。0.26本地标签保留；旧记录中的发布准备不能替代远端附件核验。

### 上表本机测试包身份

这些均为当时正常包名测试包，未替换对应版本GitHub附件；R4–R6等开发中构建不补造干净源码SHA。摘要是APK身份，不是课程或设备标识。

| 编号 | 版本/来源 | APK SHA-256 |
|---|---|---|
| R1 | 0.25导入恢复最终包 | 3ef06b8708382295bb639f0018b7c8f899bfca367efab9400113f165296c5e78 |
| R2 | 0.25同名合并 | 077e9905f5f242cbc973db023b22354f3a926fc9ee80dad1de78dfe84c5a9698 |
| R3 | 0.25路由修复，含修改 | 0c778b844dd87077946da1574054eddbee133076d67d11ae98fd9c353fb62378 |
| R4 | 0.26首轮API，含修改 | efbd2dc6c72b96d04ebd053211ff42b2f821901cd84f7384718efb35c281a525 |
| R5 | 0.26诊断，含修改 | fd917128efe3c3f74131ddcef489033cddc10170fd0713d98a8d18359e1df3e9 |
| R6 | 0.26路径类别，含修改 | 9185851d09ae46be190ab59cb0ebb095556d4df131284ab4bdd1ad7676f9bb04 |
| R7 | 0.26 / eacc7548e871ab32420d700a1f8ba4f78e09d729 | 28c331ba4aff679db998ca4e4a3d0cd83fd7d571725454f928c86c7bfbf8b280 |
| R8 | 0.27 / d9db911 | bfdcd4ec035b4bd9687fa42e6ce8ab896342a5571608519e7d48a4dc2be89f20 |
| R9 | 0.27 / fc6d911dcaf8300dbd4805c2488e83fb83fdc8d4 | 17332306d24793ebff5834b65514f39e95a3a0bdef462d70a76a72e8ad2a41b3 |
| R10 | 0.25 / 92ea6f49b86e4a6a8177999ce4bb8df333eb0d92 | 1277176b6358af5e38008053d1ce4f9ea55aa2f1817ae8641309239ac8f0a659 |
| R11 | 0.25时长中间包，含修改 | ee2f6723a7f2c2045c624a36fae6988c171ada9d6692e29d7e3ebbeccb97b580 |
| R12 | 0.26 / 4e2ba42 | 8560dbefc6f16dc4e5024e96a5d5cfeb17d45dea6a23f51ef21859e5526b4213 |
| R13 | 0.27 / b538f9b9071aeb5ea37c8801e2da2d8382a4a939 | 3458a28503fddf94c67cc2789f727eca7c22b791ddc55ed3a57297327f439d74 |
| R14 | 0.26 / caf4b6afd5659f67f33c6af34c75b8dfe082ad61 | d20c1dc5bd4540d3cf8c05e9b8841f96473b4783c936313c4b57e72c851092db |
