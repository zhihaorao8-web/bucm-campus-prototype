# 两类Android安装包

更新：2026-11-16。2026-11-12用户确认双包发布，0.27/0.3已执行；本页说明当前模式差异，发布前顺序/审批与版本规则统一见[VERSIONING](VERSIONING.md)，实际证据见[STATUS](STATUS.md)。不因此授权新发布。

| 项目 | debug测试包 | 正常使用包 |
|---|---|---|
| Flutter模式 | --debug | --release，保留R8压缩 |
| 诊断 | kDebugMode且CAMPUS_TEST_DIAGNOSTICS=true时可采集/复制/清空；默认true | 不采集/不显示测试入口，即使误传true也硬关闭 |
| 目录直取 | 源码默认false；0.3构建显式true | 0.3获确认后同样显式true，不随debug实验自动启用其他功能 |
| 身份 | 与同次release相同精确源码、版本/code、正常包名及可信签名 | 日常使用；仍为预发布 |

包名为cn.bucm.campus_schedule；同次双包便于覆盖切换并保留数据，但必须实际核对证书和升级路径，不能只凭版本相同保证可升级。当前兼容开发签名不是正式生产签名，CI临时签名预览不能替代可升级发布附件。源码开关与运行时实际访问路径类别不同。

## 当前构建入口

[scripts/build_flutter_previews.ps1](../scripts/build_flutter_previews.ps1)在同一源码顺序构建debug/release，分别传入直取true及诊断true/false；保留成功/失败详细日志和退出码。不可并发刷新插件注册表。CI已分quality检查与受门禁控制的dual-preview任务；普通工作分支/PR不默认构建APK，main/发布候选或显式preview才顺序构建双包。F2补充包核验工具，远端运行结果另记STATUS。

预览输出为build/flutter-previews/，日志为build/flutter-preview-logs/；文件名沿用已发布规则：

- campus-schedule-<版本>-android-debug.apk
- campus-schedule-<版本>-android-release.apk
- SHA256SUMS.txt和build-metadata.json

CI锁文件源地址归一化可能使包内源码带modified，必须如实保留；这种预览不冒充干净发布附件。最终附件从同一干净提交、可信本机签名重建并按VERSIONING核验版本、模式、资产/许可、测试数据排除、签名和摘要；隔离测试后重建正常包名。

普通用户下载指向release，debug明确测试用途。诊断只记[白名单事件](TEST_DIAGNOSTICS.md)，不抓通用logcat/凭据/真实课程或自动上传。精确提交CI、双包检查、标签和上传后的远端摘要均须各自有证据，0.3的CI例外不延续为后续规则。
