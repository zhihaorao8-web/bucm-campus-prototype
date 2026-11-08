# BUCM Campus Prototype

北京中医药大学校园数据提取可行性验证原型。当前重点是：用户在学校官方页面完成认证后，手机通过WebVPN进入本科教务页面，在本机读取本人课表数据。无需开发者自建服务器。

这是非官方研究原型，不代表学校提供了第三方开放API或正式单点登录接入授权。

## 进度

2026-11-08已在Android真机上读取当前周课表和学期理论课表；学期页面识别出25个候选单元格，并对一个单元格中的三段排课完成结构化样本核对。**单元格数不是课程门数；完整学期准确导出尚未验证。**

已验证字段：课程名、教师、星期、周次表达式、节次和地点。节次到HH:mm的映射、其他校园系统、独立HTTP接口和后台提醒均未验证完成。

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

当前保留早期本地课表与提醒试验，后续功能开发已暂停。源码中存在这些入口，不表示它们已通过完整验证。

## 本地构建

需要Python 3.10+、JDK 17+、Android SDK Platform 35和Build Tools 35.0.0，支持Windows与Linux。DOM测试另需Node.js。当前不是Gradle工程，不依赖Maven或第三方Java库。

```powershell
python scripts/check.py
python build.py --sdk C:\path\to\Android\Sdk --work .\build\local --output .\dist
```

构建会运行Java解析检查、生成并签署开发APK、验证签名。后续覆盖安装需沿用相同的本地开发密钥；密钥位于指定work目录且被Git忽略，不用于正式发布。

GitHub Actions自动执行离线检查与APK构建，并保留临时开发签名的产物。CI不登录学校，不使用真实课程。详见[开发和CI说明](docs/DEVELOPMENT.md)。

## 真机验证

1. 安装本地构建的APK，打开学校官方认证/WebVPN入口。
2. 用户本人完成认证，从学校资源导航进入本科教务系统。
3. 打开“个人课表信息 → 学期理论课表”，确认学期与周次筛选。
4. 点击“读取课表”，与原网页核对候选内容；不要将原型输入框中的默认值当作学校数据。

CI或自动测试不得使用真实账号，亦不应保存认证会话。

## 版本

当前维护版：`v0.1.5`；首个Git验证基线：`v0.1.4`。历史变化见[CHANGELOG](CHANGELOG.md)，分支、标签和发布规范见[版本管理](docs/VERSIONING.md)。0.1.0–0.1.3仅有此前本地迭代，不补造其Git历史。

源码独立编写，参考过THUInfo与ZZUPocket的接入思路，未复制其应用源码。
