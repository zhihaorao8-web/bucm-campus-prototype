package cn.bucm.campus_schedule;

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
import cn.bucm.campusprobe.*;

/** Visible Flutter WebView owns authentication. This adapter never returns cookies. */
public class MainActivity extends FlutterActivity {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    @Override public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        android.webkit.WebView.setWebContentsDebuggingEnabled(false);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cn.bucm.campus/school")
            .setMethodCallHandler((call,reply)->{
                if(call.method.equals("clearSession")) {
                    CookieManager.getInstance().removeAllCookies(done->{
                        CookieManager.getInstance().flush();WebStorage.getInstance().deleteAllData();reply.success(null);
                    });return;
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
    @Override protected void onDestroy(){worker.shutdown();super.onDestroy();}
}
