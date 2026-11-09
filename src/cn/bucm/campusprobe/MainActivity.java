package cn.bucm.campusprobe;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.*;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import org.json.*;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class MainActivity extends Activity {
    static final String VPN="https://webvpn.bucm.edu.cn/", PORTAL="https://i.bucm.edu.cn/", JW="https://jw.bucm.edu.cn/";
    final int INK=Color.rgb(25,49,45), GREEN=Color.rgb(26,100,80), BG=Color.rgb(244,247,242);
    LinearLayout root,body; TextView status;WebView web; JSONArray lessons=new JSONArray();
    ArrayList<ScheduleParser.Candidate> candidates=new ArrayList<>(); int candidateIndex,editingIndex=-1;String source="",probe="本次启动尚未重新读取学校页面";
    LocalDate term=LocalDate.now().with(java.time.temporal.TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    boolean browser=false,agendaVisible=false;
    boolean exportDownloading=false;
    boolean exportFlow=false,exportRequested=false;int exportSteps=0;
    String exportSemester="";
    String appVersion(){try{return getPackageManager().getPackageInfo(getPackageName(),0).versionName;}catch(PackageManager.NameNotFoundException e){return "unknown";}}
    @Override public void onCreate(Bundle b){super.onCreate(b);load();ReminderReceiver.reschedule(this);home();}
    void load(){try{lessons=new JSONArray(getPreferences(0).getString("lessons","[]"));term=LocalDate.parse(getPreferences(0).getString("term",term.toString()));}catch(Exception e){probe="本地缓存读取失败，请重新导入";}}
    int dp(int v){return (int)(v*getResources().getDisplayMetrics().density+.5f);}
    TextView text(String s,int size){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(INK);v.setPadding(0,dp(6),0,dp(6));return v;}
    void shell(String title){
        if(web!=null){web.onPause();CookieManager.getInstance().flush();}
        browser=false;agendaVisible=false;root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(BG);root.setPadding(dp(18),dp(12),dp(18),dp(12));
        root.setOnApplyWindowInsetsListener((v,i)->{v.setPadding(dp(18),i.getSystemWindowInsetTop()+dp(8),dp(18),i.getSystemWindowInsetBottom()+dp(8));return i;});
        root.addView(text("BUCM  /  校园连接实验",12));root.addView(text(title,26));setContentView(root);
    }
    void scroll(){ScrollView s=new ScrollView(this);body=new LinearLayout(this);body.setOrientation(1);s.addView(body);root.addView(s,new LinearLayout.LayoutParams(-1,0,1));}
    void button(LinearLayout box,String label,Runnable action){Button b=new Button(this);b.setText(label);b.setAllCaps(false);b.setTextColor(GREEN);box.addView(b,new LinearLayout.LayoutParams(-1,-2));b.setOnClickListener(v->action.run());}
    void note(String s){new AlertDialog.Builder(this).setMessage(s).setPositiveButton("知道了",null).show();}
    void home(){
        stopExport();
        shell("把课表留在手机里");scroll();
        body.addView(text("官方页面认证 → 自动导入课表 → 离线查看",15));
        body.addView(text(lessons.length()==0?"尚无已导入课程":"已保存 "+lessons.length()+" 条排课规则 · 支持离线",18));
        body.addView(text("导入状态："+getPreferences(0).getString("savedStatus","未导入")+"\n"+probe,13));
        button(body,"1  打开官方认证 / WebVPN",()->open(VPN));
        button(body,"自动进入课表并读取官方导出",()->beginExport(true));
        button(body,"2  数字北中医门户",()->open(PORTAL));
        button(body,"3  本地课表与提醒",()->agenda());
        button(body,"诊断（不含账号、Cookie 或课表原文）",()->diagnostics());
        button(body,"退出学校会话",()->new AlertDialog.Builder(this).setMessage("将删除本应用的学校 Cookie、网页存储和浏览缓存。本地课表继续保留；学校服务端的会话可能仍存在。")
            .setPositiveButton("清除本机会话",(d,w)->{CookieManager.getInstance().removeAllCookies(null);CookieManager.getInstance().flush();WebStorage.getInstance().deleteAllData();if(web!=null){web.clearCache(true);web.clearHistory();web.loadUrl("about:blank");}probe="已清除本应用的学校会话";home();}).setNegativeButton("取消",null).show());
        body.addView(text("验证版 "+appVersion()+" · Android 8+\n本人在学校页面登录，按已配置学期和作息自动导入。数据仅存本机。新学期首次设置一次起点。",12));
    }
    boolean school(Uri u){String h=u.getHost();return "https".equals(u.getScheme())&&h!=null&&(h.equals("bucm.edu.cn")||h.endsWith(".bucm.edu.cn"));}
    boolean trusted(Uri u){String h=u.getHost();return school(u)||("https".equals(u.getScheme())&&h!=null&&(h.equals("open.weixin.qq.com")||h.equals("work.weixin.qq.com")||h.equals("login.work.weixin.qq.com")||h.equals("open.work.weixin.qq.com")));}
    void open(String url){
        shell("学校官方页面");browser=true;
        status=text("请本人完成认证，再从学校导航进入课表。",12);root.addView(status);
        LinearLayout nav=new LinearLayout(this);root.addView(nav);
        Button back=new Button(this);back.setText("返回");nav.addView(back);back.setOnClickListener(v->{stopExport();if(web.canGoBack())web.goBack();else home();});
        Button menu=new Button(this);menu.setText("入口");nav.addView(menu);menu.setOnClickListener(v->new AlertDialog.Builder(this).setItems(new String[]{"WebVPN","数字北中医","教务（校内直连）"},(d,n)->web.loadUrl(new String[]{VPN,PORTAL,JW}[n])).show());
        Button read=new Button(this);read.setText("读取课表");nav.addView(read);read.setOnClickListener(v->extract());
        Button export=new Button(this);export.setText("自动导入");nav.addView(export);export.setOnClickListener(v->beginExport(false));
        if(web==null){
            web=new WebView(this);WebView.setWebContentsDebuggingEnabled(false);
            web.setDownloadListener((downloadUrl,agent,disposition,mime,length)->receiveExport(downloadUrl,agent));
            web.getSettings().setJavaScriptEnabled(true);web.getSettings().setDomStorageEnabled(true);web.getSettings().setAllowFileAccess(false);web.getSettings().setAllowContentAccess(false);
            web.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);web.getSettings().setSupportZoom(true);web.getSettings().setBuiltInZoomControls(true);web.getSettings().setDisplayZoomControls(false);
            web.getSettings().setSupportMultipleWindows(true);
            web.setWebChromeClient(new WebChromeClient(){
                @Override public boolean onCreateWindow(WebView origin,boolean dialog,boolean userGesture,Message message){
                    if(!userGesture&&!exportFlow)return false;
                    WebView child=new WebView(MainActivity.this);
                    child.setWebViewClient(new WebViewClient(){
                        boolean handled=false;
                        void follow(String target){if(handled||target==null||target.equals("about:blank"))return;handled=true;Uri u=Uri.parse(target);if(trusted(u))web.loadUrl(target);else note("新窗口目标不在学校认证范围内，未打开。");child.post(()->child.destroy());}
                        @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){follow(r.getUrl().toString());return true;}
                        @Override public void onPageStarted(WebView v,String u,android.graphics.Bitmap icon){follow(u);}
                    });
                    ((WebView.WebViewTransport)message.obj).setWebView(child);message.sendToTarget();return true;
                }
            });
            CookieManager.getInstance().setAcceptCookie(true);CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);
            web.setWebViewClient(new WebViewClient(){
                @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest req){Uri u=req.getUrl();if(trusted(u))return false;
                    if(req.isForMainFrame()&&(u.getScheme().equals("weixin")||u.getScheme().equals("wxwork"))){
                        new AlertDialog.Builder(MainActivity.this).setMessage("打开微信 / 企业微信完成学校认证？").setPositiveButton("打开",(d,w)->{try{startActivity(new Intent(Intent.ACTION_VIEW,u));}catch(Exception e){note("未找到对应应用，请使用学校支持的扫码方式。");}}).setNegativeButton("取消",null).show();
                    }else if(req.isForMainFrame())note("未打开此链接。验证版仅支持学校及指定微信 HTTPS 认证页面；不支持明文 HTTP、文件或未知应用跳转。");return true;
                }
                @Override public void onPageFinished(WebView view,String u){CookieManager.getInstance().flush();if(status!=null)status.setText("当前站点："+Uri.parse(u).getHost()+"\n进入本人课表后，点击“读取课表”。");}
                @Override public void onReceivedError(WebView v,WebResourceRequest r,WebResourceError e){if(r.isForMainFrame()){probe="网页错误 "+e.getErrorCode();status.setText(probe+"；可返回入口重试。尚未导入课表。");}}
                @Override public void onReceivedSslError(WebView v,android.webkit.SslErrorHandler h,android.net.http.SslError e){h.cancel();probe="TLS证书校验失败";note("连接的证书未通过系统验证，已停止加载。可尝试学校 WebVPN 入口；本原型不会忽略证书错误。");}
            });
        }
        if(web.getParent()!=null)((android.view.ViewGroup)web.getParent()).removeView(web);
        root.addView(web,new LinearLayout.LayoutParams(-1,0,1));web.onResume();
        if(!url.isEmpty())web.loadUrl(url);
    }
    void stopExport(){exportFlow=false;if(web!=null)web.getSettings().setJavaScriptCanOpenWindowsAutomatically(false);}
    void beginExport(boolean openPage){exportFlow=true;exportRequested=false;exportSteps=0;exportSemester="";if(openPage)open(web!=null&&web.getUrl()!=null&&school(Uri.parse(web.getUrl()))?"":VPN);exportStep();}
    void exportStep(){
        if(!exportFlow||web==null||exportRequested||exportDownloading)return;
        web.getSettings().setJavaScriptCanOpenWindowsAutomatically(true);
        if(++exportSteps>120){stopExport();status.setText("自动导航已暂停，请完成学校登录后点击“自动导出”继续。");return;}
        if(web.getUrl()==null||!school(Uri.parse(web.getUrl()))){stopExport();return;}
        try{
            java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();try(java.io.InputStream in=getAssets().open("export-nav.js")){byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1)out.write(b,0,n);}
            web.evaluateJavascript(new String(out.toByteArray(),java.nio.charset.StandardCharsets.UTF_8),value->{
                if(!exportFlow)return;
                try{
                    JSONObject result=new JSONObject((String)new JSONTokener(value).nextValue());String state=result.getString("state");
                    if(state.equals("exportClicked")){exportSemester=result.optString("semester");exportRequested=true;status.setText("已点击学校官方导出，正在等待文件……");web.postDelayed(()->{if(exportFlow&&!exportDownloading){stopExport();status.setText("尚未收到导出文件，请检查学校页面或手动点击学校“导出”。");}},15000);return;}
                    if(state.equals("blocked")||state.equals("ambiguous")||state.equals("filterMissing")){stopExport();status.setText("无法唯一确认学校导出入口或全部周次，请手动进入学期理论课表后重试。");return;}
                    status.setText(state.equals("login")?"请本人完成学校认证，完成后自动继续。":state.equals("waiting")?"正在等待学校页面加载，完成认证后将继续……":"正在从学校导航进入学期课表……");
                    web.postDelayed(()->exportStep(),1500);
                }catch(Exception e){stopExport();status.setText("自动导航未成功，请手动打开学期课表后重试。");}
            });
        }catch(Exception e){stopExport();note("自动导出脚本加载失败。");}
    }
    void receiveExport(String url,String agent){
        if(exportDownloading)return;
        if(!SchoolExport.allowed(url)){note("导出地址不在学校HTTPS范围内，已停止。");return;}
        exportDownloading=true;status.setText("正在接收学校导出文件，仅在内存中处理……");
        String pageSemester=exportFlow?exportSemester:"";
        new Thread(()->{
            try{
                byte[] bytes=SchoolExport.download(url,agent,value->CookieManager.getInstance().getCookie(value));
                ExportWorkbook.Result result=ExportWorkbook.read(bytes);
                runOnUiThread(()->{exportDownloading=false;stopExport();if(!browser)return;source=Uri.parse(url).getHost();try{String semester=result.semesterId;if(!semester.isEmpty()&&!pageSemester.isEmpty()&&!semester.equals(pageSemester))throw new IllegalArgumentException("页面与导出文件学期不一致");if(semester.isEmpty())semester=pageSemester;importCourses(result.candidates,semester,result.hasUnscheduledSection);}catch(Exception e){note("未自动保存："+e.getMessage());}});
            }catch(Exception|LinkageError e){String kind=e.getClass().getSimpleName();runOnUiThread(()->{exportDownloading=false;stopExport();probe="官方导出未读取成功（"+kind+"）";status.setText(probe+"，未保存课程；可重试或使用页面读取。");});}
        },"school-course-export").start();
    }
    void importCourses(List<ScheduleParser.Candidate> imported,String semester,boolean hasUnscheduled){
        try{
            String id=AcademicTerm.find(semester);
            if(id.isEmpty()){configureSemester(imported,"",hasUnscheduled);return;}
            JSONObject starts=new JSONObject(getPreferences(0).getString("semesterStarts","{}"));
            LocalDate monday=starts.has(id)?LocalDate.parse(starts.getString(id)):AcademicTerm.knownStart(id);
            if(monday==null){configureSemester(imported,id,hasUnscheduled);return;}
            CourseImportPlan plan=CourseImportPlan.create(imported,monday);
            JSONArray next=new JSONArray();
            for(int i=0;i<lessons.length();i++){
                JSONObject old=new JSONObject(lessons.getJSONObject(i).toString());
                if(old.optBoolean("automaticImport")&&id.equals(old.optString("semesterId")))continue;
                if(!old.has("termStart")){
                    if(!getPreferences(0).getBoolean("termVerified",false))throw new IllegalArgumentException("旧课表尚未绑定学期起点，请先设置旧课表学期");
                    old.put("termStart",term.toString());
                }
                next.put(old);
            }
            for(CourseImportPlan.Entry entry:plan.entries){
                ScheduleParser.Candidate c=entry.course;CourseTimes.Timing time=entry.timing;
                JSONObject o=new JSONObject();o.put("name",c.name);o.put("place",c.place);o.put("day",c.day);o.put("weeks",c.weeks);o.put("start",time.start());o.put("end",time.end());o.put("source",source);
                o.put("semesterId",id);o.put("termStart",monday.toString());o.put("automaticImport",true);o.put("importKey",entry.key);o.put("sourceOccurrences",entry.occurrences);o.put("timeRuleSource","user-2026-11-09");o.put("teachingMinutes",time.teachingMinutes());
                o.put("deliveryMode",c.day>=6?"online":"unspecified");o.put("deliveryModeSource",c.day>=6?"user-weekend-rule":"school-page");
                JSONArray periods=new JSONArray();for(int p:time.periods)periods.put(p);o.put("periods",periods);
                JSONArray segments=new JSONArray();for(CourseTimes.Segment segment:time.segments){JSONObject part=new JSONObject();part.put("start",segment.start);part.put("end",segment.end);segments.put(part);}o.put("segments",segments);next.put(o);
            }
            starts.put(id,monday.toString());
            String summary="已自动导入 "+plan.entries.size()+" 条排课规则（"+plan.sourceCount+" 段来源，合并 "+plan.duplicates+" 项完全重复）\n学期："+id+"；第1周周一："+monday+"\n时间按用户提供的学校作息识别，无需逐门确认。"+(hasUnscheduled?"\n另有无课表课程区域，因无排课时间未排入日历。":"");
            boolean saved=getPreferences(0).edit().putString("lessons",next.toString()).putString("term",monday.toString()).putBoolean("termVerified",true).putString("semesterStarts",starts.toString()).putString("savedStatus","自动识别导入 · "+LocalDate.now()).putString("autoImportSummary",summary).commit();
            if(!saved)throw new IllegalArgumentException("本机写入失败，请重试");
            lessons=next;term=monday;probe=summary;ReminderReceiver.reschedule(this);home();
        }catch(Exception e){probe="自动导入未完成";note("未自动保存本批课程："+e.getMessage());}
    }
    void configureSemester(List<ScheduleParser.Candidate> imported,String detected,boolean hasUnscheduled){
        LinearLayout box=new LinearLayout(this);box.setOrientation(1);box.setPadding(dp(20),dp(8),dp(20),dp(8));
        box.addView(text(detected.isEmpty()?"学校文件未明确标识学期，请设置一次学期信息。":"这个学期首次导入，请设置一次第1周周一。",14));
        EditText id=new EditText(this);id.setHint("学期，如2027-2028-1");id.setText(detected);id.setEnabled(detected.isEmpty());box.addView(id);
        EditText date=new EditText(this);date.setHint("第1周周一，YYYY-MM-DD");box.addView(date);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("设置学期起点（每学期一次）").setView(box).setPositiveButton("保存设置并自动导入",null).setNegativeButton("稍后设置",null).create();
        dialog.setOnShowListener(v->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(w->{try{
            String semester=AcademicTerm.find(id.getText().toString().trim());if(semester.isEmpty())throw new IllegalArgumentException("请填写有效学期");
            LocalDate monday=LocalDate.parse(date.getText().toString().trim());if(monday.getDayOfWeek()!=DayOfWeek.MONDAY)throw new IllegalArgumentException("起点必须为周一");
            JSONObject starts=new JSONObject(getPreferences(0).getString("semesterStarts","{}"));starts.put(semester,monday.toString());
            if(!getPreferences(0).edit().putString("semesterStarts",starts.toString()).commit())throw new IllegalArgumentException("设置保存失败");
            dialog.dismiss();importCourses(imported,semester,hasUnscheduled);
        }catch(Exception e){date.setError("请核对学期和日期："+e.getMessage());}}));dialog.show();
    }
    void extract(){
        stopExport();
        if(web==null||web.getUrl()==null||!school(Uri.parse(web.getUrl()))){note("请先进入学校域名内的本人课表页面。");return;}
        {
            try{java.io.ByteArrayOutputStream scriptBytes=new java.io.ByteArrayOutputStream();try(java.io.InputStream in=getAssets().open("extract.js")){byte[] buf=new byte[4096];int count;while((count=in.read(buf))!=-1)scriptBytes.write(buf,0,count);}String js=new String(scriptBytes.toByteArray(),java.nio.charset.StandardCharsets.UTF_8);
                source=Uri.parse(web.getUrl()).getHost();web.evaluateJavascript(js,value->{
                    try{Object decoded=new JSONTokener(value).nextValue();JSONObject result=new JSONObject((String)decoded);JSONArray tables=result.getJSONArray("tables");
                        if(tables.length()==0){probe="未识别课表；跨域框架数："+result.optInt("blockedFrames");note("没有发现可识别的周课表。可能尚未登录、页面不是课表、使用跨域框架或采用不同布局。旧课表未改动。\n请打开具体课表页面再试；此结果不代表接口已打通。");return;}
                        String semester=result.optString("semester");if(tables.length()>1){new AlertDialog.Builder(this).setTitle("发现多份课表，请指定导入来源").setItems(tableLabels(tables),(dialog,n)->selectTable(tables,n,semester)).show();}else selectTable(tables,0,semester);
                    }catch(Exception e){probe="课表结构读取失败";note("未读取成功，旧课表未改动。请确认当前页为周课表。");}
                });
            }catch(Exception e){note("读取器加载失败");}
        }
    }
    String[] tableLabels(JSONArray tables){String[] a=new String[tables.length()];for(int i=0;i<a.length;i++)a[i]="表格 "+(i+1)+" · "+tables.optJSONObject(i).optJSONArray("candidates").length()+" 个候选单元格";return a;}
    void selectTable(JSONArray tables,int n,String semester){
        try{candidates.clear();JSONArray a=tables.getJSONObject(n).getJSONArray("candidates");for(int i=0;i<a.length();i++){JSONObject o=a.getJSONObject(i);candidates.addAll(ScheduleParser.parseAll(o.getString("text"),o.getInt("day"),o.optString("rowLabel")));}
            editingIndex=-1;candidateIndex=0;importCourses(new ArrayList<>(candidates),semester,false);
        }catch(Exception e){note("表格读取失败，旧课表未改动。");}
    }
    EditText field(String label,String value){body.addView(text(label,13));EditText e=new EditText(this);e.setText(value);e.setTextColor(INK);e.setSingleLine(true);body.addView(e,new LinearLayout.LayoutParams(-1,-2));return e;}
    void review(){
        if(candidateIndex>=candidates.size()){probe="候选核对结束";home();return;}
        ScheduleParser.Candidate c=candidates.get(candidateIndex);shell("核对课程 "+(candidateIndex+1)+" / "+candidates.size());scroll();
        body.addView(text("每个候选是一段排课，同名课程可能有多段。周次、时间与学期起点须与学校课表核对。",13));
        body.addView(text("原单元格：\n"+c.raw+"\n行标题 / 节次："+c.periods,13));
        EditText name=field("课程名称",c.name),place=field("地点",c.place),day=field("星期（1=周一，7=周日）",String.valueOf(c.day)),weeks=field("上课周次，例如 1-16单、1-8,10-16",c.weeks);
        EditText first=field("本地课表的第1周周一（YYYY-MM-DD，必须核对）",getPreferences(0).getBoolean("termVerified",false)?term.toString():"");
        String[] times=c.time.split("-");EditText start=field("开始时间 HH:mm（不猜测学校节次时间）",times.length==2?times[0]:""),end=field("结束时间 HH:mm",times.length==2?times[1]:"");
        button(body,"确认并保存这一门",()->{try{
            String title=name.getText().toString().trim();if(title.isEmpty())throw new IllegalArgumentException("课程名称不能为空");
            int dow=Integer.parseInt(day.getText().toString());if(dow<1||dow>7)throw new IllegalArgumentException("星期应为1至7");
            String w=weeks.getText().toString().trim();ScheduleParser.weeks(w);LocalDate t=LocalDate.parse(first.getText().toString().trim());if(t.getDayOfWeek()!=DayOfWeek.MONDAY)throw new IllegalArgumentException("第1周起始日期必须为周一");
            if(lessons.length()>0&&!term.equals(t)&&editingIndex<0)throw new IllegalArgumentException("已保存课程使用不同的学期起点。请先通过“校正已有课程”校正日期。");
            String s=start.getText().toString().trim(),e=end.getText().toString().trim();if(ScheduleParser.minutes(s)>=ScheduleParser.minutes(e))throw new IllegalArgumentException("结束时间必须晚于开始时间");
            JSONObject o=new JSONObject();o.put("name",title);o.put("place",place.getText().toString().trim());o.put("day",dow);o.put("weeks",w);o.put("start",s);o.put("end",e);o.put("source",source);
            for(int i=0;i<lessons.length();i++){if(i==editingIndex)continue;JSONObject old=lessons.getJSONObject(i);if(old.getString("name").equals(title)&&old.getInt("day")==dow&&old.getString("start").equals(s)&&old.getString("weeks").equals(w))throw new IllegalArgumentException("这一门已保存，请跳过重复候选");}
            term=t;if(editingIndex>=0)lessons.put(editingIndex,o);else lessons.put(o);getPreferences(0).edit().putString("lessons",lessons.toString()).putString("term",term.toString()).putBoolean("termVerified",true).putString("savedStatus","学校页面提取，经用户核对 · "+LocalDate.now()).apply();
            ReminderReceiver.reschedule(this);if(editingIndex>=0){editingIndex=-1;agenda();}else{candidateIndex++;review();}
        }catch(Exception e){note(e.getMessage()==null?"请检查课程信息":e.getMessage());}});
        button(body,"跳过此候选",()->{candidateIndex++;review();});button(body,"结束核对，返回首页",()->home());
    }
    void agenda(){
        shell("本地课表");agendaVisible=true;scroll();boolean verified=getPreferences(0).getBoolean("termVerified",false);body.addView(text("第1周周一："+(verified?term.toString():"待核对（旧值 "+term+"）")+"\n已保存 "+lessons.length()+" 条课程规则；断网可查看。",14));
        if(!verified)body.addView(text("学期起点未核对：以下日期仅为预览，暂不安排真实课程提醒。测试通知仍可使用。",14));
        button(body,"校正已有课程",()->editExisting());
        Switch sw=new Switch(this);sw.setText("课前10分钟提醒");sw.setChecked(getPreferences(0).getBoolean("remind",false));body.addView(sw);
        sw.setOnCheckedChangeListener((v,on)->{if(on&&android.os.Build.VERSION.SDK_INT>=33&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED){sw.setChecked(false);requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},10);return;}getPreferences(0).edit().putBoolean("remind",on).apply();ReminderReceiver.reschedule(this);});
        body.addView(text(ReminderReceiver.exactAllowed(this)?"定时方式：已获准时提醒授权":"定时方式：未获准时提醒授权，系统可能延迟一小时或更久。",13));
        button(body,"设置准时提醒权限",()->{
            if(Build.VERSION.SDK_INT<31||ReminderReceiver.exactAllowed(this)){note("已具备准时提醒权限。");return;}
            new AlertDialog.Builder(this).setMessage("课前提醒需要在指定时间送达。请在接下来的系统页面允许本应用设置闹钟和提醒。").setPositiveButton("前往设置",(d,w)->{try{startActivity(new Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:"+getPackageName())));}catch(Exception e){note("无法打开授权页面，请在系统设置中查找本应用的闹钟和提醒权限。");}}).setNegativeButton("取消",null).show();
        });
        button(body,"测试即时通知",()->{if(!getPreferences(0).getBoolean("remind",false)){note("请先开启提醒。");return;}ReminderReceiver.testNow(this);note("已尝试发送即时通知，可在通知栏检查。");});
        button(body,"测试提醒（约1分钟后）",()->{
            if(!getPreferences(0).getBoolean("remind",false)){note("请先开启课前提醒，并允许通知权限。");return;}
            if(!ReminderReceiver.exactAllowed(this)){note("请先允许准时提醒权限，再进行一分钟测试。");return;}
            ReminderReceiver.test(this);note("已登记测试提醒。请返回桌面并等待约1分钟；系统省电可能造成延迟。测试不修改课程，关闭提醒会取消此次测试。");
        });
        ArrayList<ReminderReceiver.Occurrence> events=ReminderReceiver.occurrences(this);long now=System.currentTimeMillis();int shown=0;
        for(ReminderReceiver.Occurrence o:events)if(o.end>now&&shown++<50){body.addView(text(o.label,17));body.addView(text(o.place+"\n"+Instant.ofEpochMilli(o.start).atZone(ZoneId.of("Asia/Shanghai")).format(DateTimeFormatter.ofPattern("MM-dd E HH:mm",Locale.CHINA))+" — "+Instant.ofEpochMilli(o.end).atZone(ZoneId.of("Asia/Shanghai")).format(DateTimeFormatter.ofPattern("HH:mm"))+(o.teachingTimes.isEmpty()?"":"\n实际授课："+o.teachingTimes),14));}
        if(shown==0)body.addView(text("没有未来课程。请核对学期起点和周次。",15));
        button(body,"查看全部课程规则",()->{StringBuilder s=new StringBuilder();for(int i=0;i<lessons.length();i++){JSONObject o=lessons.optJSONObject(i);s.append(o.optString("name")).append(" · 周").append(o.optInt("day")).append(" · ").append(o.optString("weeks")).append("周 · ").append(o.optString("start")).append("\n");}note(s.length()==0?"暂无课程":s.toString());});
        button(body,"清空本地课表",()->new AlertDialog.Builder(this).setMessage("删除全部本地课程并取消其提醒？").setPositiveButton("删除",(d,w)->{lessons=new JSONArray();getPreferences(0).edit().putString("lessons","[]").putString("savedStatus","未导入").apply();ReminderReceiver.reschedule(this);agenda();}).setNegativeButton("取消",null).show());
        button(body,"返回首页",()->home());
    }
    void diagnostics(){
        int automatic=0,multipleSegments=0,evening=0,missingTimes=0;for(int i=0;i<lessons.length();i++){JSONObject o=lessons.optJSONObject(i);if(o==null||!o.optBoolean("automaticImport"))continue;automatic++;JSONArray parts=o.optJSONArray("segments");if(parts!=null&&parts.length()>1)multipleSegments++;if(o.optString("start").equals("18:00")&&o.optString("end").equals("20:25"))evening++;if(parts==null||parts.length()==0||o.optString("start").isEmpty()||o.optString("end").isEmpty())missingTimes++;}
        String host=web==null||web.getUrl()==null?"未打开":String.valueOf(Uri.parse(web.getUrl()).getHost());
        String report="版本："+appVersion()+"\nAndroid API："+Build.VERSION.SDK_INT+"\nWebView："+(WebView.getCurrentWebViewPackage()==null?"未知":WebView.getCurrentWebViewPackage().versionName)+"\n当前站点："+host+"\n读取状态："+probe+"\n保存规则："+lessons.length()+"\n通知权限："+(Build.VERSION.SDK_INT<33||checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED)+"\n准时提醒权限："+ReminderReceiver.exactAllowed(this)+"\n学期起点已核对："+getPreferences(0).getBoolean("termVerified",false)+"\n已登记课程提醒："+getPreferences(0).getInt("alarmCount",0)+"\n测试登记："+getPreferences(0).getLong("testScheduledAt",0)+"\n接收器执行："+getPreferences(0).getLong("lastAlarmReceivedAt",0)+"\n通知提交："+getPreferences(0).getLong("lastNotificationSentAt",0)+"\n提醒错误："+getPreferences(0).getString("lastReminderError","")+"\n说明：未记录账号、URL查询参数、Cookie、令牌或课程原文。";
        report+="\n自动导入规则："+automatic+"\n多段授课规则："+multipleSegments+"\n晚间统一时段规则："+evening+"\n自动导入缺少时间字段："+missingTimes;final String diagnosticReport=report;
        new AlertDialog.Builder(this).setTitle("脱敏诊断").setMessage(diagnosticReport).setPositiveButton("复制",(d,w)->{((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("课表验证诊断",diagnosticReport));}).setNegativeButton("关闭",null).show();
    }
    @Override public void onBackPressed(){stopExport();if(browser&&web!=null&&web.canGoBack())web.goBack();else home();}
    @Override protected void onPause(){super.onPause();CookieManager.getInstance().flush();if(web!=null)web.onPause();}
    void editExisting(){
        if(lessons.length()==0){note("暂无已保存课程。");return;}
        String[] labels=new String[lessons.length()];for(int i=0;i<labels.length;i++)labels[i]=lessons.optJSONObject(i).optString("name");
        new AlertDialog.Builder(this).setTitle("选择要校正的课程").setItems(labels,(d,index)->{
            JSONObject o=lessons.optJSONObject(index);ScheduleParser.Candidate c=ScheduleParser.parse(o.optString("name"),o.optInt("day"),"");c.raw=o.optString("name");if(!o.optString("place").isEmpty())c.place=o.optString("place");c.weeks=o.optString("weeks");c.time=o.optString("start")+"-"+o.optString("end");source=o.optString("source");candidates.clear();candidates.add(c);candidateIndex=0;editingIndex=index;review();
        }).show();
    }
    @Override protected void onResume(){super.onResume();if(browser&&web!=null)web.onResume();ReminderReceiver.reschedule(this);if(agendaVisible)agenda();}
    @Override public void onRequestPermissionsResult(int request,String[] p,int[] g){super.onRequestPermissionsResult(request,p,g);if(request==10)note(g.length>0&&g[0]==PackageManager.PERMISSION_GRANTED?"通知已允许，请重新打开课前提醒开关。":"未获得通知权限，课前提醒未启用。");}
}
