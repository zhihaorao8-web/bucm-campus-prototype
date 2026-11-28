package cn.bucm.campus_schedule;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.webkit.CookieManager;
import android.webkit.WebStorage;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import org.json.*;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import cn.bucm.campusprobe.*;

/** Visible Flutter WebView owns authentication. This adapter never returns cookies. */
public class MainActivity extends FlutterActivity {
    private static final int REQUEST_CODE_SAVE_QR = 4102;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final AtomicLong credentialGeneration=new AtomicLong(0);
    private ClassroomPlayback playback;
    private byte[] pendingQrBytes;
    private MethodChannel.Result pendingQrReply;
    @Override public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        android.webkit.WebView.setWebContentsDebuggingEnabled(false);
        CampusCredentialStore credentials = new CampusCredentialStore(this);
        try { playback=new ClassroomPlayback(this,engine); }
        catch(java.io.IOException error) { throw new IllegalStateException("Missing public player adapter asset"); }
        // Read-only app/theme metadata, separate from school authentication.
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cn.bucm.campus/app")
            .setMethodCallHandler((call,reply)->{
                if(call.method.equals("info")) {
                    try {
                        android.content.pm.PackageInfo info=getPackageManager().getPackageInfo(getPackageName(),0);
                        Map<String,Object> data=new HashMap<>();
                        data.put("name",getApplicationInfo().loadLabel(getPackageManager()).toString());
                        data.put("version",info.versionName);
                        data.put("build",android.os.Build.VERSION.SDK_INT>=28?info.getLongVersionCode():info.versionCode);
                        data.put("sdk",android.os.Build.VERSION.SDK_INT);
                        data.put("source",getString(R.string.build_source_identity));
                        if(android.os.Build.VERSION.SDK_INT>=31)
                            data.put("accent",((long)getResources().getColor(android.R.color.system_accent1_500,getTheme()))&0xffffffffL);
                        reply.success(data);
                    }catch(Exception error){reply.error("APP_INFO","无法读取应用信息",null);}
                } else if(call.method.equals("openProjectLink")) {
                    String target=String.valueOf(call.arguments);
                    if(!target.equals("repository")&&!target.equals("developer")){reply.error("UNTRUSTED_LINK","未知项目链接",null);return;}
                    String url="https://github.com/zhihaorao8-web"+(target.equals("repository")?"/bucm-campus-prototype":"");
                    try {startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW,android.net.Uri.parse(url)));reply.success(null);}
                    catch(android.content.ActivityNotFoundException error){reply.error("NO_BROWSER","未找到可用浏览器，可复制地址",null);}
                } else reply.notImplemented();
            });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "cn.bucm.campus/credentials")
            .setMethodCallHandler((call, reply) -> {
                switch (call.method) {
                    case "save" -> {
                        final long generation = credentialGeneration.get();
                        final String account = call.argument("account");
                        final String password = call.argument("password");
                        worker.execute(() -> {
                            if (generation != credentialGeneration.get()) {
                                runOnUiThread(() -> reply.error("CREDENTIAL_STALE", "登录状态已变更，未保存校园账号密码", null));
                                return;
                            }
                            try {
                                credentials.save(account, password);
                                if (generation != credentialGeneration.get()) {
                                    try {
                                        credentials.clear();
                                    } catch (Exception ignored) {
                                    }
                                    runOnUiThread(() -> reply.error("CREDENTIAL_STALE", "登录状态已变更，未保存校园账号密码", null));
                                    return;
                                }
                                runOnUiThread(() -> reply.success(null));
                            } catch (Exception ignored) {
                                runOnUiThread(() -> reply.error("CREDENTIAL_SAVE", "无法保存校园账号密码", null));
                            }
                        });
                    }
                    case "clear" -> {
                        credentialGeneration.incrementAndGet();
                        worker.execute(() -> {
                            try {
                                credentials.clear();
                                runOnUiThread(() -> reply.success(null));
                            } catch (Exception ignored) {
                                runOnUiThread(() -> reply.error("CREDENTIAL_CLEAR", "无法清除保存的校园账号密码", null));
                            }
                        });
                    }
                    case "hasSaved" -> worker.execute(() -> {
                        boolean saved = credentials.hasSaved();
                        runOnUiThread(() -> reply.success(saved));
                    });
                    default -> reply.notImplemented();
                }
            });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "cn.bucm.campus/login_actions")
            .setMethodCallHandler((call, reply) -> {
                switch (call.method) {
                    case "saveQrImage" -> {
                        Object rawBytes = call.argument("bytes");
                        byte[] bytes = rawBytes instanceof byte[] ? (byte[]) rawBytes : null;
                        try {
                            CampusLoginActions.validatePng(bytes);
                        } catch (IllegalArgumentException ignored) {
                            reply.error("QR_INVALID", "当前二维码无效，请刷新后重试", null);
                            return;
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                                || checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                                        == PackageManager.PERMISSION_GRANTED) {
                            saveQrToGallery(bytes, reply);
                        } else if (pendingQrReply != null) {
                            reply.error("QR_SAVE_BUSY", "正在保存二维码，请稍候", null);
                        } else {
                            pendingQrBytes = bytes;
                            pendingQrReply = reply;
                            requestPermissions(
                                new String[] {Manifest.permission.WRITE_EXTERNAL_STORAGE},
                                REQUEST_CODE_SAVE_QR
                            );
                        }
                    }
                    case "availableScanClients" ->
                        reply.success(CampusLoginActions.availableScanClients(getPackageManager()));
                    case "launchScanClient" -> {
                        Object rawClient = call.argument("client");
                        String client = rawClient instanceof String ? (String) rawClient : null;
                        try {
                            reply.success(CampusLoginActions.launchScanClient(this, client));
                        } catch (IllegalArgumentException ignored) {
                            reply.error("UNTRUSTED_CLIENT", "不支持拉起该应用", null);
                        }
                    }
                    default -> reply.notImplemented();
                }
            });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cn.bucm.campus/school")
            .setMethodCallHandler((call,reply)->{
                if(call.method.equals("clearSession")) {
                    credentialGeneration.incrementAndGet();
                    if(playback!=null)playback.clear();
                    worker.execute(() -> {
                        boolean cleared;
                        try {
                            credentials.clear();
                            cleared = true;
                        } catch (Exception ignored) {
                            cleared = false;
                        }
                        boolean credentialsCleared = cleared;
                        runOnUiThread(() -> CookieManager.getInstance().removeAllCookies(done -> {
                            CookieManager.getInstance().flush();
                            WebStorage.getInstance().deleteAllData();
                            if (credentialsCleared) reply.success(null);
                            else reply.error("CREDENTIAL_CLEAR", "无法清除保存的校园账号密码", null);
                        }));
                    });
                    return;
                }
                final String method=call.method;
                final Map<String,Object> args=call.arguments();
                if(!Arrays.asList("download","parseDom","validate").contains(method)){reply.notImplemented();return;}
                worker.execute(()->{
                    try {
                        String answer;
                        if(method.equals("download")) {
                            String url=string(args,"url"),agent=string(args,"userAgent");
                            if(!SchoolExport.allowed(url))throw new IllegalArgumentException("UNTRUSTED");
                            byte[] bytes=SchoolExport.download(url,agent,value->CookieManager.getInstance().getCookie(value));
                            ExportWorkbook.Result parsed=ExportWorkbook.read(bytes);
                            String page=AcademicTerm.find(string(args,"semester")),term=parsed.semesterId;
                            if(!page.isEmpty()&&!term.isEmpty()&&!page.equals(term))throw new IllegalArgumentException("SEMESTER_MISMATCH");
                            answer=batch(parsed.candidates,term.isEmpty()?page:term,parsed.hasUnscheduledSection,parsed.sourceCells).put("dataSource","official-xls").toString();
                        } else if(method.equals("parseDom")) {
                            JSONObject table=new JSONObject(string(args,"table"));
                            JSONArray cells=table.getJSONArray("candidates");
                            if(cells.length()>600)throw new IllegalArgumentException("TOO_MANY_CELLS");
                            List<ScheduleParser.Candidate> candidates=new ArrayList<>();
                            for(int i=0;i<cells.length();i++) {
                                JSONObject cell=cells.getJSONObject(i);String text=cell.getString("text");
                                if(text.length()>6000)throw new IllegalArgumentException("TOO_LONG");
                                candidates.addAll(ScheduleParser.parseAll(text,cell.getInt("day"),cell.optString("rowLabel")));
                            }
                            answer=batch(candidates,AcademicTerm.find(string(args,"semester")),false,cells.length()).put("dataSource","dom").toString();
                        } else answer=validate(args).toString();
                        runOnUiThread(()->reply.success(answer));
                    }catch(Exception|LinkageError error) {
                        // Don't forward URLs, raw page content or exception payloads to logs/Dart.
                        runOnUiThread(()->reply.error("IMPORT_FAILED","未能完整校验本批课表；请核对页面、学期与作息规则，旧课表未改动。",null));
                    }
                });
            });
    }
    private static String string(Map<String,Object> args,String key) {
        Object value=args.get(key);String text=value instanceof String?(String)value:"";
        if(text.length()>4*1024*1024)throw new IllegalArgumentException("TOO_LONG");return text;
    }
    private static JSONObject batch(List<ScheduleParser.Candidate> candidates,String term,boolean unscheduled,int sourceCells) throws JSONException {
        if(candidates.isEmpty()||candidates.size()>1200)throw new IllegalArgumentException("NO_VALID_COURSES");
        JSONArray rows=new JSONArray();
        for(ScheduleParser.Candidate c:candidates)rows.put(new JSONObject()
            .put("name",c.name).put("teacher",c.teacher).put("place",c.place).put("raw",c.raw)
            .put("weeks",c.weeks).put("periods",c.periods).put("time",c.time).put("day",c.day));
        return new JSONObject().put("semester",term).put("hasUnscheduled",unscheduled)
            .put("sourceCells",sourceCells).put("candidates",rows);
    }
    private static JSONArray validate(Map<String,Object> args) throws Exception {
        JSONObject payload=new JSONObject(string(args,"payload"));
        String term=AcademicTerm.find(string(args,"semester"));
        String sourceTerm=AcademicTerm.find(payload.optString("semester"));
        if(term.isEmpty()||(!sourceTerm.isEmpty()&&!sourceTerm.equals(term)))throw new IllegalArgumentException("INVALID_TERM");
        LocalDate monday=LocalDate.parse(string(args,"monday"));
        JSONArray rows=payload.getJSONArray("candidates");
        if(rows.length()>1200)throw new IllegalArgumentException("TOO_MANY");
        List<ScheduleParser.Candidate> candidates=new ArrayList<>();
        for(int i=0;i<rows.length();i++) {
            JSONObject row=rows.getJSONObject(i);
            // Reparse the source; Dart cannot accidentally replace validated fields.
            candidates.addAll(ScheduleParser.parseAll(row.getString("raw"),row.getInt("day"),row.getString("periods")));
        }
        CourseImportPlan plan=CourseImportPlan.create(candidates,monday);JSONArray out=new JSONArray();
        for(CourseImportPlan.Entry entry:plan.entries) {
            ScheduleParser.Candidate c=entry.course;JSONArray parts=new JSONArray();
            for(CourseTimes.Segment segment:entry.timing.segments)parts.put(new JSONObject().put("start",segment.start).put("end",segment.end));
            out.put(new JSONObject().put("dataSource",payload.optString("dataSource","unknown")).put("id",entry.key).put("name",c.name).put("teacher",c.teacher)
                .put("place",c.place).put("day",c.day).put("weeks",c.weeks).put("periods",new JSONArray(entry.timing.periods))
                .put("segments",parts).put("semester",term).put("termStart",monday.toString())
                .put("sourceCount",entry.occurrences).put("online",c.day>=6)
                .put("deliverySource",c.day>=6?"user-weekend-rule":"school-page").put("timeSource","user-2026-11-09"));
        }
        return out;
    }
    private void saveQrToGallery(byte[] bytes, MethodChannel.Result reply) {
        worker.execute(() -> {
            try {
                CampusLoginActions.savePng(this, bytes);
                runOnUiThread(() -> reply.success(true));
            } catch (Exception ignored) {
                runOnUiThread(() -> reply.error("QR_SAVE_FAILED", "无法保存二维码到系统相册", null));
            }
        });
    }
    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            @NonNull String[] permissions,
            @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQUEST_CODE_SAVE_QR) {
            return;
        }
        final byte[] bytes = pendingQrBytes;
        final MethodChannel.Result reply = pendingQrReply;
        pendingQrBytes = null;
        pendingQrReply = null;
        if (reply == null) {
            return;
        }
        boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED
                && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                        == PackageManager.PERMISSION_GRANTED;
        if (!granted || bytes == null) {
            reply.error(
                "QR_PERMISSION_DENIED",
                "未获得相册写入权限，无法保存二维码；也可使用另一台设备直接扫码。",
                null
            );
            return;
        }
        saveQrToGallery(bytes, reply);
    }
    @Override protected void onPause(){if(playback!=null)playback.pause();super.onPause();}
    @Override protected void onDestroy(){pendingQrBytes=null;pendingQrReply=null;if(playback!=null)playback.destroy();worker.shutdown();super.onDestroy();}
}
