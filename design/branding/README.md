# 应用图标

`app-icon.png`为用户于2026-11-09提供的原图：蓝紫色叠层玻璃卡片与白色学士帽。仅用于当前Flutter Android应用；根目录历史Java原型保持原样。

运行`python scripts/prepare_icons.py`（需要Pillow）生成5档传统图标与108dp自适应图标画布。保留原图构图，不预裁成圆形；Android启动器负责圆形、圆角方形等遮罩，主体位于中央安全区域。

生成文件随源码保存，正常构建无需安装Pillow。修改图标不自动增加版本号。
