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

[scripts/build_flutter_previews.ps1](../scripts/build_flutter_previews.ps1)在同一源码顺序构建debug/release，分别传入直取true及诊断true/false；保留成功/失败详细日志和退出码。不可并发刷新插件注册表。CI已分quality检查与受门禁控制的dual-preview任务；普通工作分支/PR不默认构建APK，main/发布候选或显式preview才顺序构建双包。构建后使用verify_apks.py核验，远端运行结果另记STATUS。

预览输出每次使用新的build/flutter-previews/<源码前8位>-<随机ID>/，日志在build/flutter-preview-logs/；避免旧包/旧成功元数据冒充本次产物。文件名沿用已发布规则：

- campus-schedule-<版本>-android-debug.apk
- campus-schedule-<版本>-android-release.apk
- SHA256SUMS.txt和build-metadata.json

CI锁文件源地址归一化可能使包内源码带modified，必须如实保留；这种预览不冒充干净发布附件。最终附件从同一干净提交、可信本机签名重建并按VERSIONING核验版本、模式、资产/许可、测试数据排除、签名和摘要；隔离测试后重建正常包名。

普通用户下载指向release，debug明确测试用途。诊断只记[白名单事件](TEST_DIAGNOSTICS.md)，不抓通用logcat/凭据/真实课程或自动上传。精确提交CI、双包检查、标签和上传后的远端摘要均须各自有证据，0.3的CI例外不延续为后续规则。

## 可复用的双包与只读核验

本地先按FLUTTER准备环境，从已提交源码执行（PowerShell）：

```powershell
$source = git rev-parse HEAD
./scripts/build_flutter_previews.ps1 -Flutter ./build/toolchain/flutter/bin/flutter.bat -ExpectedSourceSha $source
```

脚本检查固定HEAD，顺序debug/release，每次构建前删除限定输出目录中的旧目标APK；失败保留本轮日志与原退出码，缺少新APK直接失败。两包均核验后才生成本轮build-metadata.json和SHA256SUMS.txt，不签发新密钥、不安装、不打标签或上传Release。

独立只读核验已有APK（路径替换为本机文件）：

```powershell
python scripts/verify_apks.py --debug <debug.apk> --release <release.apk> --source <完整40位SHA> --build-tools <Android-build-tools目录> --flutter-sdk <固定Flutter-SDK目录> --gradle-cache <Gradle缓存目录> --output build/checks/<新的结果名>.json
```

检查源提交Manifest版本/code、包名、debug标志/kernel/AOT、嵌入源码标识、apksigner实际验证和双包证书、ZIP完整性/重复条目、已知测试/私有缓存载荷排除，以及公开脚本/品牌/图标/许可与源提交逐字一致。对照固定Flutter SDK对应Gradle引擎JAR的可执行段，允许Android剥离符号/重写ELF节表，防止profile混作release；校验缓存JAR摘要。默认读取GRADLE_USER_HOME或用户.gradle，历史两包缓存不同可重复--gradle-cache，不会下载或修改缓存。

发布候选改用`-Kind release -SignerSha256 <已确认的证书SHA256> -CiRunId <运行ID>`。构建前后必须干净且HEAD不变；提前查询固定仓库公开Actions API，要求精确SHA成功且quality/dual-preview都成功，构建后再次核对。单独verify_apks.py也支持`--kind release --signer-sha256 ... --ci-run-id ...`。预览允许如实标记source-modified；发布候选拒绝modified或未知标识，两包必须同源同证书。网络/CI不可读或失败即拒绝，不提供跳过开关。

静态核验不能证明诊断页面运行效果、Dart编译开关实际体验、压缩XLS解析、音画或学校链路已通过；这些仍按VERSIONING、FLUTTER及人工验收单独完成。JSON的kind=release也不自动发布或授予上传权限。
