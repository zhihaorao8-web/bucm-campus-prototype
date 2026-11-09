# XLS读取依赖

根目录原型仍使用轻量Java构建；新增mobile/使用Flutter/Gradle，并通过过渡适配层复用这些依赖。学校实际导出为BIFF/OLE二进制XLS，使用Apache POI的HSSF读取，不包含POI的OOXML模块。固定的5.5.1版本支持现有Java 8目标；不自动升级依赖。Flutter依赖版本和摘要见mobile/pubspec.lock，插件许可由Flutter许可注册提供；HSSF原始许可同样打包到Flutter APK。

公开依赖从Maven Central获取，版本和SHA-256锁定在`dependencies.lock.json`，缓存于`build/deps/`，不提交二进制JAR。构建与离线检查每次验证摘要。CI只获取公开依赖和使用合成工作簿，不访问学校。

| 组件 | 版本 | 许可 |
|---|---|---|
| Apache POI | 5.5.1 | Apache-2.0 |
| Apache Commons Codec | 1.20.0 | Apache-2.0 |
| Apache Commons Collections | 4.5.0 | Apache-2.0 |
| Apache Commons Math | 3.6.1 | Apache-2.0 |
| Apache Commons IO | 2.21.0 | Apache-2.0 |
| SparseBitSet | 1.3 | Apache-2.0 |
| Apache Log4j API（不包含Core） | 2.24.3 | Apache-2.0 |

JAR中的原始LICENSE/NOTICE随构建加入APK的`assets/third-party/`。SparseBitSet的JAR没有附许可文件，因此单独保留[上游LICENSE](https://github.com/brettwooldridge/SparseBitSet/blob/master/LICENSE)。

参考：[POI HSSF说明](https://poi.apache.org/components/spreadsheet/)、[POI依赖说明](https://poi.apache.org/components/index.html)、[Maven Central](https://repo.maven.apache.org/maven2/)。
