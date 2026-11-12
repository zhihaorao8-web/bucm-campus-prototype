package cn.bucm.campus_schedule;

import android.app.Activity;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import io.flutter.embedding.engine.FlutterEngine;
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin;
import com.pichillilorenzo.flutter_inappwebview_android.webview.in_app_webview.FlutterWebView;
import io.flutter.plugin.common.MethodChannel;
import cn.bucm.campusprobe.ClassroomMediaTransport;
import org.json.*;
import java.util.*;

/** Android owns media descriptors, cookies and decoder lifetime. Dart receives
 * only texture IDs, display configuration and bounded playback state.
 * API/architecture references, no upstream code copied:
 * https://github.com/flutter/packages/tree/main/packages/video_player
 * https://github.com/androidx/media (Apache-2.0 dependency)
 */
final class ClassroomPlayback {
    private final Activity activity;
    private final FlutterEngine engine;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final String source;
    private final MethodChannel channel;
    private WebView preparingView;
    private String preparingRecord;
    private MethodChannel.Result pending;
    private int generation;
    private ClassroomPlayerGroup group;

    ClassroomPlayback(Activity activity,FlutterEngine engine) throws java.io.IOException {
        this.activity=activity;this.engine=engine;
        // Media3 diagnostic messages can contain media URIs. UI errors are codes.
        androidx.media3.common.util.Log.setLogLevel(androidx.media3.common.util.Log.LOG_LEVEL_OFF);
        try(java.io.InputStream in=activity.getAssets().open("classroom-player.js")) {
            java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;
            while((n=in.read(buffer))!=-1)out.write(buffer,0,n);
            source=new String(out.toByteArray(),java.nio.charset.StandardCharsets.UTF_8);
        }
        channel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cn.bucm.campus/playback");
        channel.setMethodCallHandler((call,reply)->{
            try {
                if(call.method.equals("begin")) {
                    cancelPreparation();closeGroup();
                    Object id=call.argument("view");String record=call.argument("record");
                    if(id==null||record==null||record.isEmpty()||record.length()>500)throw new IllegalArgumentException();
                    WebView view=null;
                    if(id instanceof Number) {
                        view=find(engine.getPlatformViewsControllerDelegator().getPlatformViewById(((Number)id).intValue()));
                    } else if(id instanceof String && ((String)id).length()<=100) {
                        // KeepAlive getViewId is a local plugin handle, not a platform int.
                        // The official-origin check below also applies to restored views.
                        InAppWebViewFlutterPlugin plugin=(InAppWebViewFlutterPlugin)engine.getPlugins().get(InAppWebViewFlutterPlugin.class);
                        if(plugin!=null && plugin.inAppWebViewManager!=null) {
                            FlutterWebView retained=plugin.inAppWebViewManager.keepAliveWebViews.get((String)id);
                            if(retained!=null)view=retained.webView;
                        }
                    }
                    if(view==null){reply.error("NO_VIEW","无法读取当前学校页面，请重新打开",null);return;}
                    if(!official(view.getUrl())){reply.error("UNTRUSTED_PAGE","请先进入学校课程平台",null);return;}
                    preparingView=view;preparingRecord=record;
                    final int ticket=generation;
                    evaluate(view,"install",record,data->{
                        if(ticket!=generation){reply.error("CANCELLED","已取消播放准备",null);return;}
                        if(!"installed".equals(data.optString("state"))){cancelPreparation();reply.error("PREPARE","学校播放上下文未就绪",null);}
                        else reply.success(null);
                    });
                    return;
                }
                if(call.method.equals("prepare")) {
                    if(preparingView==null||pending!=null)throw new IllegalArgumentException();
                    pending=reply;capture(generation,0);return;
                }
                if(call.method.equals("cancel")){cancelPreparation();reply.success(null);return;}
                String session=call.argument("session");
                if(group==null||!group.id.equals(session)) {reply.error("EXPIRED","播放会话已结束",null);return;}
                switch(call.method) {
                    case "state": break;
                    case "play": group.play();break;
                    case "pause": group.pause();break;
                    case "seek": {Number ms=call.argument("position");if(ms==null)throw new IllegalArgumentException();group.seek(ms.longValue());break;}
                    case "speed": {Number speed=call.argument("speed");if(speed==null||!Arrays.asList(.75,1.,1.25,1.5,2.).contains(speed.doubleValue()))throw new IllegalArgumentException();group.setSpeed(speed.floatValue());break;}
                    case "layout": group.layout(call.argument("main"),call.argument("small"));break;
                    case "dispose": closeGroup();reply.success(null);return;
                    default: reply.notImplemented();return;
                }
                reply.success(group.snapshot());
            }catch(Exception error){reply.error("PLAYBACK","未能执行播放操作",null);}
        });
    }
    private interface Answer {void accept(JSONObject object);}
    private void evaluate(WebView view,String action,String record,Answer answer) {
        try {
            JSONObject command=new JSONObject().put("action",action).put("record",record);
            view.evaluateJavascript(source.replace("__PLAYER_COMMAND__",command.toString()),value->{
                JSONObject object;
                try {Object decoded=new JSONTokener(value).nextValue();object=new JSONObject((String)decoded);}
                catch(Exception error){object=new JSONObject();}
                answer.accept(object);
            });
        }catch(Exception error){answer.accept(new JSONObject());}
    }
    private void capture(int ticket,int attempt) {
        if(ticket!=generation||pending==null)return;
        if(attempt>=50||preparingView==null||!official(preparingView.getUrl())){failPreparation("PREPARE");return;}
        WebView view=preparingView;String record=preparingRecord;
        evaluate(view,"capture",record,data->{
            if(ticket!=generation||pending==null)return;
            String state=data.optString("state");
            if(state.equals("loading")){handler.postDelayed(()->capture(ticket,attempt+1),300);return;}
            if(!state.equals("ready")){
                String code=state.equals("policy-watermark")?"WATERMARK":state.equals("policy-boundary")?"MEDIA_BOUNDARY":state.equals("policy-network")||state.equals("policy-media")?"MEDIA_NETWORK":state.equals("policy-stop")?"OFFICIAL_STOP":"SCRIPT";
                failPreparation(code);return;
            }
            try {
                ClassroomPlayerGroup prepared=createGroup(data,view.getUrl(),view.getSettings().getUserAgentString());
                group=prepared;
                MethodChannel.Result result=pending;pending=null;preparingView=null;preparingRecord=null;
                result.success(group.snapshot());
            } catch(Exception error){closeGroup();failPreparation("MEDIA");}
        });
    }
    private void failPreparation(String code){MethodChannel.Result result=pending;pending=null;cancelPreparation();if(result!=null)result.error(code,"学校媒体或水印配置未能完整读取，请重新连接后重试",null);}
    void cancelPreparation() {
        generation++;
        if(preparingView!=null&&preparingRecord!=null)evaluate(preparingView,"abort",preparingRecord,ignored->{});
        preparingView=null;preparingRecord=null;
        if(pending!=null){pending.error("CANCELLED","已取消播放准备",null);pending=null;}
    }
    void pause(){if(group!=null)group.pause();}
    private void closeGroup(){if(group!=null){group.close();group=null;}}
    void clear(){cancelPreparation();closeGroup();}
    void destroy(){clear();channel.setMethodCallHandler(null);}
    private static WebView find(View view) {
        if(view instanceof WebView)return (WebView)view;
        if(view instanceof ViewGroup){ViewGroup parent=(ViewGroup)view;for(int i=0;i<parent.getChildCount();i++){WebView found=find(parent.getChildAt(i));if(found!=null)return found;}}
        return null;
    }
    private static boolean official(String address) {
        try {
            java.net.URI uri=new java.net.URI(address);String path=uri.getPath();
            return "https".equals(uri.getScheme())&&uri.getRawUserInfo()==null&&(uri.getPort()==-1||uri.getPort()==443)&&
                (("qhz.bucm.edu.cn".equals(uri.getHost())&&path.startsWith("/coursePlatform/"))||
                 ("webvpn.bucm.edu.cn".equals(uri.getHost())&&path.startsWith("/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/coursePlatform/")));
        }catch(Exception error){return false;}
    }
    private ClassroomPlayerGroup createGroup(JSONObject data,String page,String agent)throws Exception {
            LinkedHashMap<String,String> urls=new LinkedHashMap<>();
            Uri origin=Uri.parse(page);String referer=origin.buildUpon().clearQuery().fragment(null).build().toString();
            JSONArray sources=data.getJSONArray("sources");
            if(sources.length()<1||sources.length()>3)throw new IllegalArgumentException();
            for(int i=0;i<sources.length();i++){
                JSONObject s=sources.getJSONObject(i);String kind=s.getString("kind"),url=s.getString("url");
                if(!Arrays.asList("ppt","teacher","student").contains(kind)||urls.containsKey(kind)||!ClassroomMediaTransport.allowed(url)||
                    (origin.getHost().equals("webvpn.bucm.edu.cn")&&!Uri.parse(url).getHost().equals("webvpn.bucm.edu.cn"))) {
                    throw new IllegalArgumentException();
                }
                urls.put(kind,url);
            }
            JSONObject mark=data.getJSONObject("watermark");
            String watermark=mark.getBoolean("enabled")?mark.getString("text"):"";
            if(watermark.length()>500||(mark.getBoolean("enabled")&&watermark.trim().isEmpty()))throw new IllegalArgumentException();
            return new ClassroomPlayerGroup(activity,engine.getRenderer(),urls,watermark,
                    ()->new ClassroomDataSource(referer,agent));
    }
}
