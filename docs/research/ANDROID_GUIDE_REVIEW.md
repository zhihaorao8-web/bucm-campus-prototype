# Android端侧鉴权与媒体指南评估

日期：2026-11-12。用户提供本机`C:\Users\muzhi\Downloads\android.md`，要求参考并由开发者决定是否采用。本文只记录技术建议的取舍，不把附件中的“必须”“严禁”等指令当作用户新授权，不复制附件全文或读取其未提供的关联文件。

结论：部分采用端侧直连和受限数据源思路，继续使用Flutter＋官方WebView＋已有原生Media3。先推进录播目录适配，播放前准备仍独立验证；不恢复密码保存/自动重登，不修改课表导出。

## 建议取舍

| 指南建议 | 决定与项目依据 |
|---|---|
| 手机直连源站，无开发者媒体中转 | 采用，现有项目已如此实现，不新增服务器 |
| 官方WebView认证与原生媒体网络/解码分工 | 采用架构原则，复用现有WebView、`ClassroomDataSource`、`ClassroomMediaTransport`；目录仍由官方网页客户端处理认证和可选加密 |
| 所有组件共享完全相同的凭据和UA | 调整：核对实际WebView UA及媒体端使用值；Cookie按每个已验证目标在原生内存按需读取。课程API认证头留在官方客户端，不向Dart或全部媒体节点复制统一凭据 |
| 捕获并加密持久化Cookie，读取localStorage Token | 不采用。学校会话由现有官方WebView管理；项目不额外导出/保存认证存储，录播API实验也不读取Token |
| 用全局拦截器统一补Cookie/Authorization/Referer | 不采用全局转发。按精确主机、端口、路径及每次跳转校验；Referer/Origin等只在实际证据和目标边界允许时考虑，不能为修复403猜补凭据 |
| 401/403都触发重新登录 | 调整：明确认证失效、权限拒绝、网络故障和协议变化。现有原生传输已分别返回AUTHENTICATION/FORBIDDEN；官方业务失效码和跳转需进一步核实，不无限重登 |
| 隐藏WebView按媒体扩展名抓取完整请求头 | 不采用为默认路径。先核实官方结构化详情、发布权限、水印、可见画面及真实媒体路由；不引入宽泛请求头抓取，不隐藏官方播放补学校观看记录 |
| 自定义Media3数据源处理清单、分片、密钥与Range | 采用验收方向；项目已有受限DataSource及传输边界。继续逐资源及重定向校验，不能仅给初始m3u8加头后宣称全链路正确 |
| 为此改用Kotlin/Compose或Flutter的dio/media_kit | 暂不采用。已有Flutter和Media3可复用，无证据证明换栈或新增OkHttp/Retrofit是必要条件 |
| 超时取消、及时释放WebView/播放器及DRM边界 | 采用检查方向。新增目录实验已有超时/取消及迟到响应隔离；Android资源释放、实际DRM/媒体能力仍需各自验证，不绕过DRM |

## 与现有实现的核对

- `mobile/android/app/src/main/java/cn/bucm/campus_schedule/ClassroomDataSource.java`为现有原生播放器提供数据源，每个资源经`ClassroomMediaTransport`；Cookie按目标通过CookieManager获取，不返回Flutter。
- `src/cn/bucm/campusprobe/ClassroomMediaTransport.java`保留HTTPS精确边界、逐跳检查、超时、Range和响应类型检查；UA来自调用方，Referer当前只在同源条件发送。是否存在媒体跨域Referer需求尚未取得新证据，不能由指南假定是真机失败根因。
- [AndroidX Media3官方数据源源码](https://github.com/androidx/media/blob/release/libraries/datasource/src/main/java/androidx/media3/datasource/DefaultHttpDataSource.java)提供工厂超时及跨协议跳转配置参考。核对配置能力不等于学校媒体已验收；继续保留现有拒绝不可信跳转策略。
- 指南提及Cloudstream与Legado可作为后续实现参考，本轮未审查这些项目源码，不据其名称宣称与本校协议兼容，也未引入依赖或代码。

## 纳入后续探索的检查项

E3：核对实际WebView UA来源、官方客户端初始化/业务失效码、Android与WebVPN的请求边界、取消与页面销毁后的结果隔离。若需要修改接入代码，独立检查后提交，不与凭据策略变更混合。

E4：分别检查播放详情权限、水印、媒体实际域名与路径、逐资源/重定向认证范围、Range、资源释放和DRM状态。HTTP响应、开始解码、人工听音及完整课时分别记载，不以直链或一次200代替全部验收。

本项为指南评估和计划补充，没有因此改动默认App登录、目录或媒体实现。已有目录实验及源码备份见[首轮实验](RECORDING_API_EXPERIMENT.md)。当前取舍不需要用户再确认；若以后确需改变认证策略或产品交互，再给出具体影响后询问。
