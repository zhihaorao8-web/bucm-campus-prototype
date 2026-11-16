# 版本与协作规范

更新：2026-11-16。当前版本为0.3/code12，pubspec为0.3.0+12；唯一版本来源为根AndroidManifest.xml。历史发布证据见[0.3](releases/0.3.md)、[0.27](releases/0.27.md)与[STATUS](STATUS.md)。

## 当前协作规则

- main保存已经检查的主线，日常工作使用独立codex/分支，通过PR说明变更和验证后按授权合入。旧原型固定保留在codex/legacy-java-prototype（611ec8e）；不在日常分支重启旧产品范围。
- 提交使用fix/feat/docs/test/chore等前缀；一个提交围绕一个目的。每个独立功能/UI分项检查后立即提交并普通推送，再开始下一项，只暂存相关内容。
- 推送失败保留本地提交、报告未同步；不强推、不自动合并main、不改写发布标签或附件。同步不等于发布。
- 工程优化阶段完成后停审。F1已实现下表分工，CI选择复用本地check_plan；实际运行结果记录精确SHA，不能把源码配置写成远端已通过。
- 真正合入main、修改版本及创建Release依照用户对应授权；旧版本的一次授权不自动用于下一版本。

## 分支与CI分工

| 分支/触发 | 检查与构建 | 职责 |
|---|---|---|
| codex/feature-*、fix-*、docs-*等工作分支push | 与origin/main的共同祖先比较整条分支；按变更检查，默认不构建APK | 单项开发/修复/文档，不在main堆未验改动；前次运行被取消也不漏掉较早改动 |
| PR | 按PR基线SHA选择；检查精确head SHA，不构建APK | 评审功能与验证；此检查不是merge提交的集成验证 |
| main push | 全量宿主检查通过后，独立dual-preview任务顺序双包 | 经授权合入的稳定集成线；预览仍不是发布附件 |
| codex/release/<版本> push | 全量宿主检查及双包预览 | 冻结候选、只做发布修复，不自动创建标签/Release |
| workflow_dispatch | changed（默认）/full（全量无APK）/preview（全量＋双包） | 显式复核当前选择ref的精确提交，不复用旧提交CI |
| codex/legacy-java-prototype | 历史保留，不主动触发新工作 | 不在该分支推进Flutter功能或修改已发布历史 |

quality固定为唯一质量任务名；先保存source/base精确SHA及测试计划，再安装所需工具，避免CI锁文件源地址归一化使测试选择误扩大。纯文档无需Flutter/JDK；未知共享配置保守全量。分流不跳过必要L3设备或发布验证；检查/详细构建日志在失败时仍上传，工作流仅contents:read，无自动发布权限。

2026-11-16公开API核对：main仍580eac9、protected=false，规则集为空。[main保护模板](../.github/main-protection.json)可复核：要求PR、最新quality、讨论解决，禁止强推/删除并约束管理员；当前单人协作不强制另一账号批准（review count=0），用户审核/合入授权仍必须遵守。**模板未应用，远端保护未开启**；需有仓库管理权限的操作者在确认后应用，不能将文件存在写成服务端已保护。模板结构依据[GitHub保护API](https://docs.github.com/en/rest/branches/branch-protection)。

## 版本与包身份

- versionName按用户指定使用两段或三段数字；pubspec由prepare规范化为三段SemVer加code。Android versionCode每次可安装发布严格递增，同次debug/release共用一个code。
- 页面从实际包信息读取版本、构建类型和源码标识；含未提交修改必须明确显示，未知Git身份不补造。
- 新标签为v加Android版本名；已有标签和附件不可移动、覆盖。早于Git基线的本地迭代不伪造历史。
- GitHub Release继续标记Pre-release。正常包与debug测试包的模式、开关、包名、兼容签名及附件要求见[BUILD_VARIANTS](BUILD_VARIANTS.md)。
- 当前使用兼容开发签名，正式生产签名尚未建立。CI临时签名只用于预览，不能替代可信本机的可升级附件。
- 真实课程、学校会话、截图/HAR、设备标识和密钥不进入任何分支或Git历史；误提交时先停止推送并评估处置。

## 发布前检查

下次发布或工具链改动先读[发布复盘](releases/0.1-retrospective.md)，核对Windows长路径、pub源码与项目同盘、官方CI依赖源、锁文件完整性和精确SDK SHA。

1. 完成对应合成检查及必要的release压缩后解析/媒体验证，核对待提交内容并同步。
2. 对精确候选SHA等待CI结果；旧提交通过不能替代候选提交。新修复须重新核对身份。
3. 从同一干净源码顺序构建debug与release，不并发刷新插件注册表；隔离测试后重建正常包名最终附件。
4. 核对根Manifest版本、包名、构建模式、签名、ZIP完整性、许可、测试夹具排除、SHA-256及构建元数据。
5. 更新CHANGELOG、验证状态和发布说明；经对应发布授权才新增标签/Pre-release，上传后核对远端大小与摘要。后续文档提交不移动标签。

构建无新输出先查详细日志末行与时间戳；API不能下载运行中日志则看网页实时日志。保留真实退出码与失败日志，区分已确认原因、推测与未测，不能凭耗时盲目重启。

0.3的729663f远端Actions因当时账户计费限制未执行，用户明确授权以本地核验发布，详见STATUS和发布说明。这只是该次例外，不构成未来跳过CI的默认规则。
