package cn.bucm.campus_schedule;

import android.app.Activity;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import androidx.media3.common.*;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
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
    private Group group;

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
                    Number id=call.argument("view");String record=call.argument("record");
                    if(id==null||record==null||record.isEmpty()||record.length()>500)throw new IllegalArgumentException();
                    WebView view=find(engine.getPlatformViewsControllerDelegator().getPlatformViewById(id.intValue()));
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
                    case "play": group.want=true;if(group.ended())group.seek(0);break;
                    case "pause": group.pause();break;
                    case "seek": {Number ms=call.argument("position");if(ms==null)throw new IllegalArgumentException();group.seek(ms.longValue());break;}
                    case "speed": {Number speed=call.argument("speed");if(speed==null||!Arrays.asList(.75,1.,1.25,1.5,2.).contains(speed.doubleValue()))throw new IllegalArgumentException();group.speed=speed.floatValue();for(Stream s:group.streams.values())s.player.setPlaybackSpeed(group.speed);break;}
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
                Group prepared=new Group(data,view.getUrl(),view.getSettings().getUserAgentString());
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
    private final class Group {
        final String id=UUID.randomUUID().toString(),referer,agent,watermark;
        final LinkedHashMap<String,String> urls=new LinkedHashMap<>();
        final LinkedHashMap<String,Stream> streams=new LinkedHashMap<>();
        String main,small,error;
        boolean want;
        float speed=1;
        Group(JSONObject data,String page,String agent)throws Exception {
            Uri origin=Uri.parse(page);referer=origin.buildUpon().clearQuery().fragment(null).build().toString();this.agent=agent;
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
            watermark=mark.getBoolean("enabled")?mark.getString("text"):"";
            if(watermark.length()>500||(mark.getBoolean("enabled")&&watermark.trim().isEmpty()))throw new IllegalArgumentException();
            main=urls.containsKey("ppt")?"ppt":urls.keySet().iterator().next();
            small=urls.containsKey("teacher")&&!main.equals("teacher")?"teacher":null;
            try {layout(main,small);}catch(Exception failure){close();throw failure;}
        }
        void layout(String nextMain,String nextSmall) {
            if(!urls.containsKey(nextMain)||(nextSmall!=null&&(!urls.containsKey(nextSmall)||nextMain.equals(nextSmall))))throw new IllegalArgumentException();
            long position=master()==null?0:master().player.getCurrentPosition();
            main=nextMain;small=nextSmall;
            for(String kind:new ArrayList<>(streams.keySet()))if(!kind.equals(main)&&!kind.equals(small)){streams.remove(kind).close();}
            for(String kind:Arrays.asList(main,small))if(kind!=null&&!streams.containsKey(kind))streams.put(kind,new Stream(this,kind,position));
            for(Stream s:streams.values()) {
                boolean audible=s==master();
                s.player.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),audible);
                s.player.setVolume(audible?1:0);
            }
        }
        Stream master(){return streams.containsKey("teacher")?streams.get("teacher"):streams.containsKey("student")?streams.get("student"):streams.get(main);}
        void pause(){want=false;activity.getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);for(Stream s:streams.values())s.player.pause();}
        void seek(long ms){long end=duration();long target=Math.max(0,end>0?Math.min(ms,end):ms);for(Stream s:streams.values())s.player.seekTo(target);}
        long duration(){long result=Long.MAX_VALUE;for(Stream s:streams.values()){long d=s.player.getDuration();if(d>0)result=Math.min(result,d);}return result==Long.MAX_VALUE?0:result;}
        boolean ended(){for(Stream s:streams.values())if(s.player.getPlaybackState()==Player.STATE_ENDED)return true;return false;}
        Map<String,Object> snapshot() {
            boolean ready=error==null&&!streams.isEmpty();
            for(Stream s:streams.values())ready&=s.player.getPlaybackState()==Player.STATE_READY;
            Stream clock=master();
            if(clock!=null&&ready&&want)for(Stream s:streams.values())if(s!=clock&&Math.abs(s.player.getCurrentPosition()-clock.player.getCurrentPosition())>400)s.player.seekTo(clock.player.getCurrentPosition());
            for(Stream s:streams.values())s.player.setPlayWhenReady(ready&&want);
            if(ready&&want)activity.getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            else activity.getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            Map<String,Object> result=new HashMap<>();
            result.put("session",id);result.put("main",main);result.put("small",small);result.put("available",new ArrayList<>(urls.keySet()));
            result.put("playing",ready&&want);result.put("wanted",want);result.put("buffering",!ready&&error==null&&!ended());
            result.put("position",clock==null?0:clock.player.getCurrentPosition());result.put("duration",duration());result.put("speed",(double)speed);
            result.put("watermark",watermark);result.put("error",error);
            List<Map<String,Object>> textures=new ArrayList<>();
            for(Stream s:streams.values()){
                VideoSize size=s.player.getVideoSize();Map<String,Object> item=new HashMap<>();
                item.put("kind",s.kind);item.put("texture",s.surface.id());item.put("width",size.width);item.put("height",size.height);item.put("ratio",size.height>0?(double)size.width*size.pixelWidthHeightRatio/size.height:16./9.);textures.add(item);
            }
            result.put("textures",textures);return result;
        }
        void close(){pause();for(Stream s:streams.values())s.close();streams.clear();urls.clear();}
    }
    private final class Stream {
        final String kind;
        final ExoPlayer player;
        final TextureRegistry.SurfaceProducer surface;
        Stream(Group owner,String kind,long position) {
            this.kind=kind;
            surface=engine.getRenderer().createSurfaceProducer();surface.setSize(1280,720);
            try {player=new ExoPlayer.Builder(activity).build();}
            catch(RuntimeException failure){surface.release();throw failure;}
            try {
            player.setVideoSurface(surface.getSurface());
            surface.setCallback(new TextureRegistry.SurfaceProducer.Callback(){
                @Override public void onSurfaceAvailable(){player.setVideoSurface(surface.getSurface());}
                @Override public void onSurfaceCleanup(){owner.pause();player.clearVideoSurface();}
            });
            player.addListener(new Player.Listener(){
                @Override public void onPlaybackStateChanged(int state){if(state==Player.STATE_ENDED)owner.pause();}
                @Override public void onPlayWhenReadyChanged(boolean playing,int reason){
                    if(!playing&&reason==Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS)owner.pause();
                }
                @Override public void onVideoSizeChanged(VideoSize size){if(size.width>0&&size.height>0)surface.setSize(size.width,size.height);}
                @Override public void onPlayerError(PlaybackException failure){
                    owner.error="PLAYBACK";
                    Throwable reason=failure;
                    for(int i=0;i<8&&reason!=null;i++,reason=reason.getCause())if(reason instanceof ClassroomMediaTransport.Failure)owner.error=((ClassroomMediaTransport.Failure)reason).code;
                    owner.pause();
                }
            });
            player.setMediaSource(new HlsMediaSource.Factory(()->new ClassroomDataSource(owner.referer,owner.agent)).createMediaSource(MediaItem.fromUri(owner.urls.get(kind))));
            player.setPlaybackSpeed(owner.speed);player.seekTo(position);player.prepare();
            }catch(RuntimeException failure){surface.setCallback(null);player.release();surface.release();throw failure;}
        }
        void close(){surface.setCallback(null);player.release();surface.release();}
    }
}
