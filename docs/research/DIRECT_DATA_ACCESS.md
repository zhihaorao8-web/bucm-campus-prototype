# 学校数据直接读取探索

日期：2026-11-12。范围：课表与已授权的录播目录取数流程简化。此文记录本轮静态研究和本人授权桌面会话验证，不代表 Android 新取数链路已实现或发布。

## 结论

录播目录可以在官方课程平台初始化一次后，复用其请求客户端取得课程和分页目录，无需逐课程设置前端状态、切换路由、等待组件或点击翻页。本轮真实桌面会话已验证这一点。

现阶段不需要自建账号密码登录。应用已有可见官方 WebView；本人在学校页面认证后，由学校网页客户端管理认证和可选加密。不可把“普通 fetch 携带 Cookie”视为等价方案，学校客户端另有认证头处理。

推荐的下一实施分项仅为受限录播目录数据源，保留现有播放及课表导出。Android、WebVPN、冷启动和认证失效仍需独立验证后才能替换默认路径。

## 本轮授权与操作边界

- 用户明确要求借助技能探索简化流程，必要时考虑应用内登录。本人在新建的 Ego 浏览器任务空间完成官方扫码/登录，确认后继续研究。
- Scrapling MCP 用于无凭据的公开 HTML、JS 和运行配置分析；登录后的验证在同一官方浏览器页面上下文内进行。
- 未读取或导出 Cookie、令牌、密码、验证码、认证存储或请求头；未导出 HAR、真实课程/录播 JSON、截图或媒体地址。仅报告结构、数量和比较布尔结果。
- 请求使用正常 TLS；没有开发者凭据代理，没有新增登录服务、凭据保存、自动重登或后台任务，没有改变学校权限或发布状态。
- 本轮不启动视频，不调用观看记录接口，不替换学校水印或当次播放权限检查。

## 当前实现的依赖

| 模块 | 当前实现 | 可简化之处 |
|---|---|---|
| 录播课程/目录 | `assets/classroom.js` 遍历 Vue 组件，写官方课程上下文、切换路由、调用分页方法并读数组；Flutter 定时识别状态 | 认证和平台初始化后，以课程标识和页码请求目录，直接映射现有模型 |
| 课表 | `assets/export-nav.js` 进入菜单、选择全部周次、触发官方 XLS；原生 `SchoolExport` 已直接下载二进制 | 待核实导出地址、参数和全部周次证据后，简化导出发现；不重写已工作的 XLS 解析器 |
| 播放 | 原生播放器已实现，播放信息、官方水印、媒体实际路由仍由受限页面和原生适配器协调 | 本轮保留；目录 API 成功不证明播放详情可等价替换 |

## 公开前端证据

本轮通过 Scrapling 正常 HTTPS 无凭据读取以下资源，均返回 200；资源名仅代表本次观察，不视为稳定接口契约。

- [平台 HTML](https://qhz.bucm.edu.cn/coursePlatform/)
- [主包 app.d786e056.js](https://qhz.bucm.edu.cn/coursePlatform/static/js/app.d786e056.js)
- [运行配置 config.json](https://qhz.bucm.edu.cn/coursePlatform/config.json)
- [课程页 chunk-3d317dd5.b0ff06bd.js](https://qhz.bucm.edu.cn/coursePlatform/static/js/chunk-3d317dd5.b0ff06bd.js)
- [录播目录 chunk-9375ca56.6bfc561d.js](https://qhz.bucm.edu.cn/coursePlatform/static/js/chunk-9375ca56.6bfc561d.js)
- [录播详情 chunk-0fada180.9cec7759.js](https://qhz.bucm.edu.cn/coursePlatform/static/js/chunk-0fada180.9cec7759.js)

| 用途 | 方法及路径 | 参数和成功业务数据 |
|---|---|---|
| 学期 | GET `/cp/teacher/calendar/getTermNum` | 数组；页面使用 `xqCode`、`CNAME` |
| 本人课程 | POST `/cp/course/getCourseList` | `{xqCode,boy}`，成功数组；另一身份页签额外传 `role:"3"`，不擅自切换角色 |
| 录播分页 | POST `/cp/courseInfo/ResourceList` | `{courseCode,fz_id,beginTime:"",endTime:"",xqCode,page,pageSize}`，成功 `{total,list}` |
| 录播详情 | POST `/cp/courseInfo/getCourseSchedDetail` | `{courseSchedId,resId,courseId,timeTableId,rpLookType:2,description:2}`；前端取成功数组 `[0].res.courseSched` 和 `streamMap`，本轮只静态研究 |

课程列表参数使用当前页面的学期与 `boy` 原值；`boy` 初始空字符串，官方选择器另有数值 1、2。目录 `courseCode` 来自 `course_num`，`fz_id` 来自同名字段，`xqCode` 来自课程 `xq_code`；不能把本地课程 ID 当作这些参数。默认每页 10 条，下一页无需另开路由。

录播业务白名单沿用已有模型：`rpId`、`rpName`、`date_time`、`roomName`、`shareType`；后续播放来源核对还涉及 `courseSchedId`、`course_id`、`timeTableId`。`shareType=1` 表示已发布，不据此跳过播放时的服务端权限校验。

### 认证与请求客户端

当前主包统一请求模块为 webpack `b775` 的导出 `a`，API 包装模块 `71e2.n`、`1fa1.a` 分别调用它取得课程、录播目录。

- 客户端会附加 `X-Token`，由官方代码处理，研究代码不读取其值。
- 客户端读取运行配置。本轮配置 `encryption_config.enabled=false`；源码支持启用后包装请求数据并附加 `X-Encrypted`，不能写死当前未加密行为。
- 成功封套 `meta.code === "0"` 后直接返回业务 `data`。客户端收到 `-555` / `-502` 会执行官方退出与登录跳转；不能把此结果当作空目录保存。
- 未发现稳定公开的 `window.axios` 或 Vue `$http/$axios/$request`。本轮在官方页面临时借 webpack runtime 取得客户端，清理临时模块定义/缓存；没有改动官方请求拦截器。模块号随学校构建可能变化，生产适配必须检测能力并可回退。

本轮实际成功调用的通用形态如下；`request` 是仍留在官方页面内的客户端引用，不向 Flutter 返回它或其上下文。

```javascript
const courses = await request({
  url: '/cp/course/getCourseList',
  method: 'post',
  data: {xqCode: currentSemester, boy: currentOfficialFilter},
  timeout: 10000
});
const page = await request({
  url: '/cp/courseInfo/ResourceList',
  method: 'post',
  data: {
    courseCode: course.course_num, fz_id: course.fz_id,
    beginTime: '', endTime: '', xqCode: course.xq_code,
    page: pageNumber, pageSize: 10
  },
  timeout: 8000
});
```

### 本轮需要经官方入口完成初始化

本轮直接打开 `/coursePlatform/` 会进入官方 CAS，认证后先落到 `/cc/#/portal`。仅再次直接打开课程平台根地址，未取得课程列表。经门户中可见的“课程平台”入口进入后，官方初始化完成并打开课程首页，后续直接 API 请求成功。

因此快捷取数应从已初始化的官方上下文开始；首次连接、会话恢复仍须保留官方门户/认证导航，不能承诺无网页冷启动或仅靠复制课程页面 URL 即可登录。

## 真实会话证据与边界

| 检查 | 本轮结果 | 限制 |
|---|---|---|
| 课程列表 | API 返回 12 条，与当前官方首页课程 ID 集合一致，所需字段存在 | 仅当前所选学期、本人桌面会话；条目数不是课表课程门数 |
| 学期列表 | 返回数组，共 28 条 | 未逐学期导入或核验历史学期完整性 |
| 全部当前来源的录播分页 | 12 个课程条目，13 次目录请求，取得 85 条目录记录；一门共 16 条、分两页；每门唯一 ID 数等于其 `total`，页间总数稳定 | 以本次 API 总数为完整性基准；不是完整学期所有实际录制内容或发布时间的独立审计 |
| 无逐课程导航 | 上述 13 次请求全程停留课程首页，约 3.2 秒完成（含请求间约 120ms 间隔） | 单次桌面观察，不是手机或其他网络的性能承诺 |
| 页面抽样对照 | 经原有受限路径进入一门官方录播列表；9 条记录的 ID、名称、日期、地点、发布状态及播放关联字段与直接 API 逐项一致 | 只有一门样本作页面对照，未把全部 85 条逐条人工核验 |
| Android / WebVPN | 未验证新直接目录请求 | 不沿用旧页面路径真机通过来声称新链路通过 |
| 课表导出 / 详情播放 / 失效恢复 | 本轮未做新路径真实验证 | 现有功能继续保留，不能以目录成功代替这些验收 |

## 建议下一实施分项与验收

仅替换录播课程和目录的数据获取；不同时改播放器、课表解析器或认证策略。此分项在范围和可复核结果给出后由用户确认，再进入应用开发。

1. 新建独立受限目录适配器，只开放学期、本人课程、指定课程分页三类动作。端点固定，不接受任意 URL、脚本、请求头或角色；认证信息始终由官方代码在网页内部处理。
2. 验证精确 HTTPS 主机、路径和当前访问方式；WebVPN 只复用已核实的官方映射/客户端行为。能力不匹配时回退原页面流程，禁止尝试关闭 TLS、跨域放行或另造凭据代理。
3. 只返回业务白名单字段，检查类型、学期、总数、页码、重复、空页、总数变化、超时和取消。复用现有同名多来源收集器和整组原子保存规则，失败保留旧目录。
4. 认证失效回到可见官方页面，由本人完成后恢复原任务；不得无限重试、把错误当空列表、读取令牌补认证或保存密码。
5. 使用合成数据覆盖请求白名单、异常返回、客户端缺失/变更、分页完整性、取消后迟到响应及回退边界；对应 DOM/脚本修改运行项目合成检查。
6. 本人授权 Android 分别核验直连和 WebVPN、冷启动/已有会话/过期、同名多来源、两页及空列表；比较保存结果与既有路径，播放仍走原权限/水印链路。

本轮研究脚本仅在被忽略的 `build/api-exploration-20261112/` 下运行，未加入应用资产或 CI；现有应用代码和版本不变。研究文档检查与 Git 同步另见提交记录，不把文档提交视为功能发布。
