# 本地开发与检查入口

更新：2026-11-16。当前主工程是mobile/，根src/只保留7个共享Java核心，日常开发使用Flutter/Gradle。先读[需求](PROJECT_BRIEF.md)、[进度](DEVELOPMENT_PLAN.md)、[证据](STATUS.md)；定位已有能力用[架构索引](ARCHITECTURE.md)，UI同时读[DESIGN](../DESIGN.md)。文档职责见[工程优化计划](MAINTENANCE_PLAN.md)。

## 工具与准备

- Flutter固定3.47.9及SHA c197ca5199e9ee5661e865596c9c07294dfab51c；依赖以pubspec.lock和dependencies.lock.json为准。
- Python 3.10+、Node.js 22；Java核心检查使用JDK 17+，当前Flutter CI配置Temurin 25/Python 3.12，不再按旧原型文档认作JDK17 runner。
- Android宿主、SDK、同盘pub缓存、本机环境和隔离验证命令见[FLUTTER](FLUTTER.md)。本机路径是配置示例，不是其他机器必需路径。
- 根src/和assets/是共享维护源；prepare复制到被忽略目录，不能编辑副本或将真实学校数据作为夹具。

首次或共享资源变更后，从根目录执行：

```powershell
python scripts/dependencies.py
python scripts/prepare_flutter.py
cd mobile
flutter pub get --enforce-lockfile
```

公开依赖均校验锁定摘要；不通过删除锁文件、SHA或关闭TLS解决下载失败。Windows依赖源码与工程同盘，CI使用官方源。版本只从根AndroidManifest.xml同步。

## 当前可用检查

```powershell
# 根目录：Java/XLS/DOM/目录桥/媒体传输与图标资产合成检查
python scripts/check.py
```

```powershell
# mobile目录：静态检查及按文件选择现有测试
flutter analyze --no-pub
flutter test --no-pub test/schedule_test.dart
flutter test --no-pub --dart-define=CAMPUS_DIRECT_CATALOG=true test/classroom_api_reader_test.dart test/classroom_direct_import_test.dart
# 全量回归
flutter test --no-pub
```

统一模块入口和变更映射已加入check.py：`python scripts/check.py --module player`、`python scripts/check.py --changed --base origin/main --dry-run`。完整分层、选择边界和报告见[TESTING](TESTING.md)。无参数保持旧离线行为，CI分流尚未实施；文档用--module docs，跨模块改动先预览--changed，发布候选用--all并按版本规范补独立构建验证。

普通默认回归会条件跳过直取和预览场景；直取相关变更须显式开启define，可选合成预览见FLUTTER。Android方法通道、R8 XLS和原生媒体属于独立检查，不能由Dart组件测试替代。真实学校验证只在本人授权会话下执行，不进入CI。

## 构建与同步

开发安装、正常包名、隔离测试与签名边界见[FLUTTER](FLUTTER.md)。双包构建见[BUILD_VARIANTS](BUILD_VARIANTS.md)，版本/发布检查见[VERSIONING](VERSIONING.md)及[发布复盘](releases/0.1-retrospective.md)。顺序构建，保留真实退出码和详细日志。

每个独立功能/UI分项检查后更新证据、仅暂存相关文件、提交并普通推送工作分支。阶段完成停止审核；不把Git同步等同于main合入或发布。失败保留改动/提交并如实报告。check.py使用scripts/java_tools.py定位JDK；旧原型构建入口已移除。
