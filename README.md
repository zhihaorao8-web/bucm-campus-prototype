# BUCM Campus Prototype

## Flutter 第一版 0.1（预发布）

当前Flutter版本按用户指定为`0.1`（Android内部版本号7），下载见[GitHub预发布](https://github.com/zhihaorao8-web/bucm-campus-prototype/releases/tag/v0.1)。release模式APK沿用本机开发签名，不代表已建立生产签名流程。已有`v0.1.4`、`v0.1.5`历史标签保持不变。

用户已确认迁移至Flutter，优先Android，只做课表与今日速览。新工程位于`mobile/`：官方页面登录、官方XLS自动导入与DOM备用读取、离线缓存、周/日课表、冲突并排、课程详情、下一节课和深浅色界面。应用不保存密码；会话失效需本人重新登录。不包含直播、图书馆、提醒或社区。

新包名与旧原型并存，需重新登录导入，不自动读取旧应用数据。Android复用已有Java XLS与作息解析器；iOS/Windows接入尚未完成。**原型真实学校验证不等于Flutter新应用通过验证。** 构建、架构和限制见[Flutter开发说明](docs/FLUTTER.md)，界面规范见[DESIGN.md](DESIGN.md)。下文记录保留的Java原型。

北京中医药大学校园数据提取可行性验证原型。当前重点是：用户在学校官方页面完成认证后，手机通过WebVPN进入本科教务页面，在本机读取本人课表数据。无需开发者自建服务器。

这是非官方研究原型，不代表学校提供了第三方开放API或正式单点登录接入授权。

## 进度

已在Android真机上读取当前周课表和学期理论课表；2026-11-09在Android 16 AVD中复现官方认证后的读取路径，并通过官方XLS自动导入。25个源单元格拆为52段排课来源，合并21项完全重复，保存31条排课规则。**单元格数、排课段数均不是课程门数；完整学期准确导出尚未验证。**

已验证可读字段：课程名、教师原文、星期、周次表达式、节次和地点。按用户规则的HH:mm映射和自动保存已有合成与AVD验证；不代表学校官方作息已独立认证，也不代表完整学期全部课程逐条核验完成。其他校园系统、独立HTTP JSON接口和后台提醒仍未验证完成。

详细记录见[验证状态与下一步](docs/STATUS.md)、[架构说明](docs/ARCHITECTURE.md)。真实课表、截图和认证信息只保留在本地，不上传；仓库中的[示例](examples/course-sample.synthetic.json)完全合成。

## 目录

```text
AndroidManifest.xml          应用标识和版本
assets/extract.js            WebView内的DOM读取逻辑
src/cn/bucm/campusprobe/      Android界面、解析与早期试验代码
tests/                       不访问学校系统的合成测试
examples/                    合成字段示例
docs/                        架构、验证状态和维护记录
build.py                     轻量APK构建脚本
```

“自动进入课表并读取官方导出”入口：本人完成学校认证后，脚本进入本科教务的学期理论课表、选择全部周次、触发官方导出，在本机内存中读取二进制XLS，按用户作息自动映射精确时间、整批校验并去重保存，无需逐门确认。重复导入不累加，重启后保留。页面DOM读取保留为备用路径，也使用同一自动导入逻辑。文件中的“无课表课程”区域单独提示，尚未排入日历。

时间按[用户提供并补充的规则](docs/COURSE_TIME_RULES.md)：白天保留授课分段，所有晚间组合统一18:00–20:25，第12节不额外延长。当前学期起点为用户确认的2026-09-07，其他学期首次设置一次；未知/冲突规则停止本批保存，不猜测缺失时间。

当前保留早期本地课表与提醒试验，后续功能开发已暂停。源码中存在这些入口，不表示它们已通过完整验证。

## 本地构建

需要Python 3.10+、JDK 17+、Android SDK Platform 35和Build Tools 35.0.0，支持Windows与Linux。脚本测试另需Node.js。当前不是Gradle工程；XLS读取使用固定版本Apache POI HSSF及其依赖，不需要安装Maven。首次准备依赖需联网到公开Maven Central，之后检查和构建验证本地SHA-256锁定的JAR。

```powershell
python scripts/dependencies.py
python scripts/check.py
python build.py --sdk C:\path\to\Android\Sdk --work .\build\local --output .\dist
```

构建会运行Java解析检查、生成并签署开发APK、验证签名。后续覆盖安装需沿用相同的本地开发密钥；密钥位于指定work目录且被Git忽略，不用于正式发布。

GitHub Actions自动执行离线检查与APK构建，并保留临时开发签名的产物。CI不登录学校，不使用真实课程。详见[开发和CI说明](docs/DEVELOPMENT.md)。

## 真机验证

1. 安装本地构建的APK，打开学校官方认证/WebVPN入口。
2. 用户本人完成认证，从学校资源导航进入本科教务系统。
3. 打开“个人课表信息 → 学期理论课表”，确认学期与周次筛选。
4. 点击“自动导入”读取学校官方XLS，或使用“读取课表”备用DOM路径，按已配置规则自动保存。也可从首页的自动导出入口开始导航；认证仍需本人完成，新学期首次设置一次起点。

CI或自动测试不得使用真实账号，亦不应保存认证会话。

## 版本

当前Flutter维护版：`0.1`；此前Java原型维护版：`v0.1.5`；首个Git验证基线：`v0.1.4`。历史变化见[CHANGELOG](CHANGELOG.md)，分支、标签和发布规范见[版本管理](docs/VERSIONING.md)。Java原型0.1.0–0.1.3仅有此前本地迭代，不补造其Git历史。

源码独立编写，参考过THUInfo与ZZUPocket的接入思路，未复制其应用源码。
