# 课堂连接与目录适配

更新：2026-11-16，按当前源码核对。生效范围见[需求](PROJECT_BRIEF.md)，复用入口见[架构](ARCHITECTURE.md)，实际样本见[STATUS](STATUS.md)。本文替代旧课堂计划、接续和目录探索文档，不授权新的学校访问。

## 连接与恢复

1. 先用无凭据、固定HTTPS入口探测服务可达性；认证重定向也算路径可达，不因需要本人登录改走另一入口。自动结果与手动覆盖由ClassroomConnectionCoordinator的代次隔离。
2. 本人在可见官方WebView认证。认证等待不消耗读取次数；门户、平台初始化和目录读取分别有界，后台停止轮询并使旧请求失效。具体预算从ClassroomLimits读取。
3. 只有已识别的官方门户/精确cc入口可使用已验证的课程平台路径。cc重复导航或加载超时只作有限恢复；不携带旧查询参数，不猜隧道，不将任意文字变成跳转目标。
4. commit/history等事件可启动受限状态读取；目录已可读时结束文档加载期限。超时前仅作一次有界复核，结果仍受页面代次约束。
5. 上游CONNECTION_FAILED是服务故障，保留错误页/旧目录并停止自动读取；不视为密码错误。继续导入先识别当前阶段，门户不能调用课程内部路由。两路探测失败仍保留显式打开学校页面入口。

认证、目录可读、完整保存、实际播放是不同状态；工作页面缓存不证明会话仍有效。清除学校登录同步清理页面、目录和本机进度，离线课表/外观保留。旧单课程关联已停用，固定旧文件只在目录清除时删除，不读取或迁移。

## 目录两条路径

默认编译开关CAMPUS_DIRECT_CATALOG=false；0.3双包构建显式启用true，诊断开关独立。AppFeatures为唯一Dart开关入口，构建要求见[双包规范](BUILD_VARIANTS.md)。

| 路径 | 已实现职责 | 停止/回退边界 |
|---|---|---|
| 目录直取 | [recording-api.cjs](../assets/recording-api.cjs)在官方页面内使用学校客户端；[桥接](../assets/recording-api-bridge.js)只接受catalog、records、cancel | 仅unsupported可有限回DOM；认证、权限、结构变化、总数变化、请求失败或超时不绕路重试 |
| DOM兼容 | [classroom.js](../assets/classroom.js)读取已识别页面、按官方上下文导航和分页 | 不改变学校权限；未知结构失败，不把错误当空目录 |
| 跨路径协调 | ClassroomPageScripts负责命令编码/容量/超时，ClassroomApiReader核对完整性，ClassroomImportCoordinator负责整组提交 | UI保留WebView与可见认证、队列切换和来源恢复；不复制另一套收集或保存逻辑 |

课程名称仅整理空白与括号宽度，同学期完整名称相同的全部来源汇总，教师/班级仅展示。保存前逐来源取齐、检查页码/总数/缺条/重复；任一来源失败保留旧目录，重试只复用本轮完整来源。学校课程ID＋录播ID＋原分页共同确定播放来源，不按日期或单独录播ID覆盖。

## 受限请求契约

以下是当前适配的学校内部协议，不是公开稳定SDK。维护源在assets，prepare复制到Flutter；不要编辑生成副本。

| 请求 | 固定参数来源 |
|---|---|
| POST /cp/course/getCourseList | 当前官方学期xqCode及页面boy筛选原值（空字符串、1或2）；不切换角色 |
| POST /cp/courseInfo/ResourceList | courseCode取学校course_num，fz_id与xqCode取已校验来源；beginTime/endTime为空，page从1开始，pageSize=10 |

返回仅映射课程/录播业务字段：课程ID、名称、学期、教师/编号/班级，录播ID、标题、日期、地点、发布状态。不回传请求配置、认证头或原始异常；已发布不等于当次播放已获授权。

桥接检查精确HTTPS主机/路径、当前角色页签与学期；当前学校构建依赖webpack模块b775.a。能力缺失返回unsupported，不修改官方拦截器。认证头、可选加密及业务失效跳转仍由官方客户端处理，不能用普通fetch或导出Token替换。每轮目录任务共用递增requestId，旧分页/取消不能影响新任务；认证后旧任务不能复活。任务结束清理临时上下文，仅保留拒绝旧任务所需的数值代次。

播放详情API替换未实施：目录直取后仍按原来源恢复官方页面，重新核对发布权限、水印和实际媒体，再交[现有播放器](PLAYER.md)。不抓取通用请求头、不隐藏官方播放器补学校记录、不建立开发者凭据代理。

## 修改与排查

- 模块最小检查：`python scripts/check.py --module classroom --direct-catalog`；改存储再组合`--module storage`。纯脚本检查可使用相应Node文件，完整选择规则见[TESTING](TESTING.md)。
- 观察App中的[白名单诊断](TEST_DIAGNOSTICS.md)：selectedDirect只是选路，officialContextDirect才是请求文档类别，directReady只是完整取数，importSaved才是保存。不能据速度、离线列表或空日志推断路径。
- 学校改版先核对官方能力及结构，补合成样本；真实学校仅在新的用户授权会话手动验证。WebVPN、真实认证失效、完整学期及自然跨天仍有独立缺口。

## 研究来源与源码备份

2026-11-12研究提交cf66690记录官方公开前端及本人桌面会话；桌面12来源/13页/85条和单门9条对照归该次研究，不替代Android证据。后续真实结果统一见STATUS。

开发前基线e029530886974b6c5515c1b464e23d7a0079cff7的本机备份位于忽略的build/backups/recording-baseline-20261112T133859Z：history.bundle已verify，207个受控工作文件及差异有摘要清单。仅源码，无学校会话/密钥；恢复应在独立目录检验，不能覆盖当前工作区。

仅参考[UCAS-Sign-In](https://github.com/WXRIW/UCAS-Sign-In)的目录/缓存说明与[UCAS-Desktop](https://github.com/zhangzhendan-Berkeley/UCAS-Desktop)的模块分离思路，未复制代码或引入依赖；不视为本校协议证据，也不引入其账号保存/后台功能。端侧指南采用按目标认证、逐资源数据源、错误分类和释放原则，不采用凭据导出/持久化、全局认证头转发、默认隐藏嗅探或为此换栈。
