# 测试版应用内诊断

更新：2026-11-16。用户授权在测试版本加入日志采集，随后确认未来GitHub发布同时提供debug和正常release安装包。此功能补足手机不返回Flutter系统日志时的观察能力，不抓取通用系统日志。

## 使用与保留范围

调试包入口：设置 → 项目信息 → 测试工具 → 测试诊断。页面支持查看、复制为JSON及清空记录；复制由本人主动操作，不自动上传或发送。

保留最近200条内存事件，超出丢弃最早事件，导出`dropped`记录丢弃数量。手动清空、退出学校会话或结束应用进程会清除；没有磁盘日志、后台采集或崩溃后恢复承诺。复制到系统剪贴板的内容由本人管理，应用不读取其他剪贴板内容。

采集接口只把预定义事件枚举、UTC时间、受限计数和耗时写入记录。外部错误/状态经白名单分类，未知错误仅记通用类别；不记录原始异常、账号、密码、Cookie/Token、学校课程/录播标识或名称、请求地址/参数、网页正文、设备标识或媒体URL。

## 构建隔离

- 诊断可用条件为`kDebugMode && CAMPUS_TEST_DIAGNOSTICS`，后者默认true。可用`--dart-define=CAMPUS_TEST_DIAGNOSTICS=false`关闭测试包诊断。
- release及profile不采集本项诊断、不显示测试入口；release即使误传true也不会启用。源码常量边界及禁用采集有合成检查；发布包实测范围另见STATUS，不泛化到新的维护提交。
- 录播直取开关`CAMPUS_DIRECT_CATALOG`与诊断独立，仍默认false；0.3双包构建显式设为true。普通debug不因包含诊断就自动启用直取。
- [双包发布规范](BUILD_VARIANTS.md)已单独提交；此功能提交及本机实验构建不自动创建Release、修改版本或替换已发布附件。

## 事件解读

| 事件 | 含义与限制 |
|---|---|
| directoryStart / catalogRequest / catalogReady | 进入目录直取及课程请求；仅记课程条目数/耗时，无个人课程字段 |
| pageRequest / pageReady | 请求一页及通过该页校验；计数是本页记录条数，不是完整学期证明 |
| directReady | 本组直接请求返回完整校验结果；仍需后续importSaved确认本地保存成功 |
| fallbackUnsupported | 客户端能力不支持，进入原页面路径；不能标作直取成功 |
| importSaved / importSaveFailed | 同名来源组保存结果；不等于所有组导入完成，需结合导入面板 |
| authenticationNeeded / permissionDenied | 官方认证需求与权限拒绝，分别处理，不据权限拒绝自动重登 |
| requestTimeout / requestFailed / bridgeFailed / invalidResponse / cancelled | 受限请求、桥接、结构或取消类别；原始错误不进入导出 |
| mediaPrepare / mediaReady | 开始或取得原生播放准备结果；不等于已听到声音、持续播放或完整课时通过 |
| mediaNetwork / mediaBoundary / mediaWatermark / mediaFailed | 原有播放准备错误的白名单类别，不输出地址或完整错误 |
| unmatched | 当前同名任务未匹配；不当作网络故障 |
| accessAutomatic / accessDirect / accessWebVpn | 本次请求的访问方式，不代表探测或连接已经成功 |
| selectedDirect / selectedWebVpn | 访问探测/手动选择最终决定的入口类别，不代表已完成认证 |
| officialContextDirect / officialContextWebVpn / officialContextUnknown | 实际目录请求所在的官方文档类别，由桥接按白名单主机计算；不输出地址，也不据此推断Wi-Fi、校园网、系统VPN或全部网络跳转 |
| upstreamConnectionFailed | 学校WebVPN已加载的上游连接错误页，不混作密码错误或TLS错误 |

2026-11-13后续：旧记录中的directReady只表示接口直取，不等于网络直连。新路径类别的JS/页面合成及历史手机直连样本已通过，真实认证异常恢复仍未验证。正常桥接超时记requestTimeout；若期间已进入认证或读取代次失效，则迟到错误记cancelled，不覆盖正在等待认证的界面。

导出额外注明schema、固定scope、诊断是否启用、直取编译开关状态，不包含认证或设备字段。日志为空可能是尚未执行相关操作或已清除；不得仅凭空记录断言网络或学校接口失败。

## 验证与使用边界

实现的合成检查覆盖上限/不可变快照、未知错误不外泄、关闭不采集、复制/清空及小屏深色大字；直取成功、unsupported回退和权限失败分别有断言。0.27/0.3发布包隔离及历史手机路径/播放反馈统一见[STATUS](STATUS.md)，不在本页重复流水账。

后续按待验证项选择最小操作，已通过的正常取数无需重复统一导入；自然出现认证或失败时结合提示及该轮事件判断。dropped非零可在本人同意后清空，仅复测目标动作。诊断没有持续播放时长、跳转位置或续播选择，mediaReady不能证明声音、完整课时或恢复位置。
