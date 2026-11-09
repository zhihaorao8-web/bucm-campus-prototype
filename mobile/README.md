# 校园课表 Flutter Android

第一版范围、构建准备、验证边界与迁移说明见[开发文档](../docs/FLUTTER.md)，界面规范见[DESIGN.md](../DESIGN.md)。

首次从仓库根目录运行`python scripts/dependencies.py`和`python scripts/prepare_flutter.py`，再在本目录运行`flutter pub get`、`flutter analyze`、`flutter test`、`flutter build apk --debug`。

只在学校官方页面登录，不保存密码。合成示例不会写入本人课表。Android XLS解析使用独立的过渡适配层，其他平台待接入。完整学期准确性需要本人授权会话下独立核验。
