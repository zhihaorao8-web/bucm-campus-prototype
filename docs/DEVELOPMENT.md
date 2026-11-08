# 本地开发与CI

## 环境

- Python 3.10+、JDK 17+；CI固定使用Python 3.12及JDK 17。
- Node.js 22运行DOM合成测试。
- 构建APK另需Android SDK Platform 35和Build Tools 35.0.0。
- 支持Windows与Linux构建脚本；不依赖Gradle。Android Studio的AVD可用于安装APK和手动验证，但当前目录不是可直接Gradle同步的Android Studio工程。

SDK安装示例：

```text
sdkmanager "platforms;android-35" "build-tools;35.0.0"
```

## 离线检查

```text
python scripts/check.py
```

检查Java周次与时间校验、DOM星期列/合并单元格/登录表格排除/框架处理，以及示例数据的合成标记。它不访问学校，不要求Android SDK，不证明学校实时接口仍有效。

## 构建

Windows：

```powershell
python build.py --sdk C:\path\to\Android\Sdk --work .\build\local --output .\dist
```

Linux：

```bash
python build.py --sdk "$ANDROID_HOME" --work build/local --output dist
```

版本从`AndroidManifest.xml`读取，APK放在`dist/`。每次编译使用独立run目录，避免混入上次遗留的class或DEX。`build/`与`dist/`均不进入Git。

## 签名与覆盖安装

`--work`目录下的`prototype.keystore`是本地开发密钥，首次不存在时才生成。开发口令`android`不是生产密钥管理方案。不要上传密钥。

此前手机验证使用的密钥保留在原本机工作目录；后续覆盖更新应继续给`--work`传同一目录。更换工作目录会生成新签名，不能直接覆盖同包名旧安装。

CI每次生成临时开发签名，产物仅供独立安装检查，不保证能覆盖手机或前次CI产物。发布前需另行设计正式签名流程；当前不配置生产密钥或账号Secrets。

## 自动化边界

GitHub Actions在push、PR和手动触发时运行离线检查和APK构建，上传临时开发APK。CI不运行学校认证，不包含账号、会话、真机截图、真实课表或root调试脚本。

本机检查通过、CI通过、AVD通过和学校真实数据核对是独立证据。维护时不要混为同一状态。
