# 应用内IconMCP图标

2026-11-13用户要求通过新接入IconMCP全面替换应用内功能图标。保留既有品牌启动图标和开发者头像，学校官方网页不属于应用自绘图标范围。用户指定服务为素材来源，不以另一图标库冒充。

## 来源与离线资产

- 本会话未动态加载IconMCP工具，插件目录也无同名条目；直接通过已配置的公开HTTPS MCP入口`https://iconmcp.com/mcp`完成初始化、只读search_icons/list_sets/get_icon。没有读取配置凭据，也没有调用request_icon/report_icon/fix_icon等写操作。
- 43个已检索确认的SVG，统一outline、24px、1.75px描边、radius 2，原始viewBox为16单位。源名、分类、下载参数、业务别名与SHA256见[清单](../design/icons/iconmcp/manifest.json)，SVG随源码保留，本机构建复制到Flutter assets，应用运行不请求服务。
- [官方许可证](https://iconmcp.com/licence)为MIT，Copyright (c) 2026 UI8；原文从该页公开前端资源核对并保留。页面说明少数手形参考Phosphor/Tabler/Lucide，手势图标连同这些上游MIT/ISC许可证一并随包保存，并注册到Flutter许可列表。
- `python scripts/iconmcp_assets.py --fetch`为显式开发时更新，会校验全部响应后写文件；正常`python scripts/iconmcp_assets.py`、检查和prepare仅校验本地摘要/SVG独立性，不联网。新源名及许可变更须重新审查，不自动更新现有包。

## Flutter接入

`AppIcons`为受控业务目录，`AppIcon`显示本地SVG，继承IconTheme的尺寸、颜色、禁用透明度与阴影，方向图标按RTL翻转，保留语义。使用官方维护的`flutter_svg 2.4.0`，锁文件仅新增它与10项所需依赖，原锁定依赖版本不变；不加入运行时图标搜索、下载或账户能力。

当前资产/适配基础已实现：3项合成检查逐个解码绘制全部43个SVG并核对主题/语义/RTL；静态分析与完整离线Java/JS检查通过。接下来替换页面显式图标、默认返回/更多/展开箭头及设置尾箭头，再做全量回归和合成视觉核对；此段不代表页面替换已完成。
