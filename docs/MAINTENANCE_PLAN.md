# 工程优化计划与审核

2026-11-15用户确认按审查方案实施；每阶段完成对应检查、提交推送后停止，用户审核通过再进入下一阶段。当前状态只在[开发进度](DEVELOPMENT_PLAN.md)维护，实际检查只在[STATUS](STATUS.md)记录。本轮不增加业务模块，版本仍由根Manifest管理。

## 阶段与交付

| 阶段 | 工作与交付 | 必要检查/完成标准 |
|---|---|---|
| A 文档入口与职责 | 统一生效需求、当前进度与证据入口；修正已确认冲突和失效链接；重写架构/复用索引，列出清理对象 | 本地Markdown目标存在、文档差异核对、描述与源码引用一致；本阶段不删运行时代码 |
| B 分层测试入口 | 扩展现有check脚本，按schedule/storage/classroom/player/ui/adapter选择；增加变更映射、dry-run和未知改动保守回退 | 模块命令执行选定测试；直取define显式处理；失败退出码、漏映射和报告可复核 |
| C 组件与交互 | 以DESIGN为唯一规范，形成场景/组件/行为/验证表；集中视觉令牌和材质/动效策略，按页面迁移 | 对应组件/手势回归及浅深色、小屏大字、减少动画、高对比度合成预览 |
| D 公共逻辑与配置 | 集中业务参数、路径/标识；抽原子文件操作；逐项拆课堂连接、导入与播放准备 | 保持存储兼容、身份/权限边界、取消和迟到回调、失败保留数据；跑受影响模块 |
| E 清理与文档精简 | 按下表解除旧引用、迁移有效测试后删旧实现；合并旧接续/专项重复内容 | 源码/资产/测试/文档引用检查；运行受影响模块；保留唯一历史证据与有效规则 |
| F 分支与发布工具 | 变更检查、预览构建、发布验证分工；完善分支规范和发布包核验脚本 | 按精确SHA检验任务选择、双包顺序构建及签名/版本/摘要；仓库规则设置另记实际状态 |

每项独立功能/UI改动完成对应检查后立即提交并普通推送，再开始下一项。阶段内未做的检查保持未测；文档通过不能替代构建、模拟器、学校验证。阶段结束不自动合入main、改版本、打标签或发布。

## 旧实现清理清单（候选，尚未删除）

| 对象 | 当前引用事实 | 删除前条件与最小验证 |
|---|---|---|
| `mobile/lib/ui/classroom_browser.dart` | 主应用无外部入口，只有自身及classroom_access_test引用 | 访问切换/旧请求取消等有效断言迁入真实课堂入口；访问/课堂连接测试通过后删页面与仅服务旧页面的测试 |
| `mobile/lib/data/classroom_links.dart` | ClassroomCoursePage仍bind，应用无lookup调用；测试有读写 | 移除无用写入、依赖注入参数和错误文案；核对旧文件兼容/隐私处置，不擅自扫描或读取真实数据；名称合并/目录/恢复测试 |
| 根`src/.../MainActivity.java`、`ReminderReceiver.java`、`RestoreReceiver.java` | 旧页面/提醒互相引用，根Manifest和build.py仍引用 | 整组解除构建、Manifest及资源依赖；保留Manifest版本唯一来源；共享Java合成检查及prepare验证 |
| 根`build.py`及旧`res/` | 原型构建入口，check.py仍从build导入EXE/java_tools | 公共JDK工具先迁出；检查入口不再依赖原型构建器，再删旧APK构建和资源 |
| 旧接续/已完成专项文档 | RESUME、QINGXIN_HANDOFF、旧UI/数据访问计划等含失效“下一步” | 逐文档提取唯一决策、协议与待验事项到对应入口，修复引用，再删重复正文/文件；保留发布与学校证据 |

保留7个Java共享核心、classroom-player.js、目录API适配器、根Manifest版本来源、图标/字形生成工具与许可。scripts/research/recording-api.cjs应考虑迁到运行时资产目录，不能按research名称删除。删除判断须同时查源码、构建复制、测试和文档；本表不等于已证明所有候选可直接删除。

## 文档定位与后续整理规则

| 入口 | 唯一职责 |
|---|---|
| [AGENTS](../AGENTS.md) | 协作、安全、阶段审核、Git同步规则 |
| [README](../README.md) | 产品、安装、开发导航 |
| [PROJECT_BRIEF](PROJECT_BRIEF.md) | 生效需求与冲突决策 |
| [DEVELOPMENT_PLAN](DEVELOPMENT_PLAN.md) / [STATUS](STATUS.md) | 当前待办 / 实际验证证据 |
| [DESIGN](../DESIGN.md) | 交互、组件与视觉；C阶段形成可执行规范 |
| [ARCHITECTURE](ARCHITECTURE.md) | 模块职责、公共能力、数据所有权 |
| [DEVELOPMENT](DEVELOPMENT.md) / [FLUTTER](FLUTTER.md) | 开发入口 / Android专项操作 |
| [VERSIONING](VERSIONING.md) / [BUILD_VARIANTS](BUILD_VARIANTS.md) | 版本与同步 / 当前双包规则；F阶段收拢重复规则 |
| [TESTING](TESTING.md) | 分层测试、改动映射、调试入口 |

当前规则不再追加阶段流水账。历史证据保持日期、源码SHA、验证对象和缺口；旧“当前/下一步”不能重新授权开发。原始提示词、第三方许可、发布说明及关键复盘继续保留。E阶段进一步删重，不为了归档再复制整套失效文档。
