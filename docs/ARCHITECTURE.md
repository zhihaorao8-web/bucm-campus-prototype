# 当前架构

```text
MainActivity
  ├─ WebView：官方认证、WebVPN、教务页面及会话
  ├─ assets/extract.js：读取表格、星期列和同源框架
  ├─ ScheduleParser：将候选文本转为待核对字段
  └─ 早期本地课表 / 提醒试验（当前暂停）
```

`MainActivity.java`目前同时承担页面导航和验证界面。网站地址以HTTPS域名白名单校验；跳转新窗口转到主WebView；不忽略TLS证书错误，不开放JavaScript原生桥或WebView调试。

`extract.js`仅在用户点击读取时执行，返回课表候选文本与星期、行标题。它不读取输入框、Cookie或认证令牌。跨域框架不可直接读取，错误以计数返回。为控制资源使用，表格、行、候选、文本长度和递归深度均有限制，不能把截断结果视为完整导出。

`ScheduleParser.java`提供基础周次、单双周和时间校验。学校特定格式仍有已知适配缺口，详见[验证状态](STATUS.md)。

`ReminderReceiver.java`和`RestoreReceiver.java`为早期试验保留；其存在不代表后台提醒已通过验证。

会话存放在Android应用自己的WebView存储中。应用私有存储可能包含个人课程；它们不应进入Git、日志、CI或测试固定样本。
