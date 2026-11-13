# 测试版应用内诊断

更新：2026-11-13。用户授权在测试版本加入日志采集，随后确认未来GitHub发布同时提供debug和正常release安装包。此功能补足手机不返回Flutter系统日志时的观察能力，不抓取通用系统日志。

## 使用与保留范围

调试包入口：设置 → 项目信息 → 测试工具 → 测试诊断。页面支持查看、复制为JSON及清空记录；复制由本人主动操作，不自动上传或发送。

保留最近200条内存事件，超出丢弃最早事件，导出`dropped`记录丢弃数量。手动清空、退出学校会话或结束应用进程会清除；没有磁盘日志、后台采集或崩溃后恢复承诺。复制到系统剪贴板的内容由本人管理，应用不读取其他剪贴板内容。

采集接口只把预定义事件枚举、UTC时间、受限计数和耗时写入记录。外部错误/状态经白名单分类，未知错误仅记通用类别；不记录原始异常、账号、密码、Cookie/Token、学校课程/录播标识或名称、请求地址/参数、网页正文、设备标识或媒体URL。

## 构建隔离

- 诊断可用条件为`kDebugMode && CAMPUS_TEST_DIAGNOSTICS`，后者默认true。可用`--dart-define=CAMPUS_TEST_DIAGNOSTICS=false`关闭测试包诊断。
- release及profile不采集本项诊断、不显示测试入口；release即使误传true也不会启用。当前通过源码常量边界及禁用采集的合成检查核对，不能据此声称新的release包已完成实机验收。
- 录播直取开关`CAMPUS_DIRECT_CATALOG`与诊断独立，仍默认false；本次专用测试包显式设为true，用于核实此前实验命中情况。普通debug不因包含诊断就自动启用直取。
- [未来双包发布规范](BUILD_VARIANTS.md)已单独提交；此功能提交及本机实验构建不自动创建Release、修改版本或替换已发布附件。

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

导出额外注明schema、固定scope、诊断是否启用、直取编译开关状态，不包含认证或设备字段。日志为空可能是尚未执行相关操作或已清除；不得仅凭空记录断言网络或学校接口失败。

## 当前检查与真实验证

- 静态分析通过；完整Flutter回归159项通过、5项跳过。诊断容器覆盖上限/不可变快照、未知错误不外泄、关闭不采集；面板覆盖复制/清空及小屏深色大字。
- 开启直取开关的3项页面合成检查通过，并核对实际生成directReady/importSaved、fallbackUnsupported、permissionDenied且权限失败无保存事件。
- 本人已在校园网直连安装诊断包并复制JSON；实际安装APK摘要一致。新记录确认10组直取并保存、3组未匹配，11来源12页共78条（含空目录与10＋6跨页），无回退/错误且没有丢失记录。新包取得真机复制及直取路径证据，不补造旧包路径结论；WebVPN、认证恢复、真机清空和播放仍未由此次验证。
- 本机诊断debug包的摘要、设备复制与实际安装/验证进展见STATUS；未验证的release诊断隔离/真实媒体仍单列。

下一次本人测试时，先完成一次统一录播导入，再打开测试诊断，复制并提供记录。只按事件顺序和导入结果核对路径，不额外提取课程或认证数据；如果dropped非零，必要时清空诊断后只复测目标操作。
